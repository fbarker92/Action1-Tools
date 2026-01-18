#!/bin/zsh
set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Action1 Software Repository uploader (zsh)
#
# Flow per scope:
#   find/create package -> find/create version (must include os) ->
#   init resumable upload (expects HTTP 308 + X-Upload-Location) ->
#   upload chunks via PUT with Content-Range
#
# Scopes:
#   enterprise : orgId=all
#   orgs       : choose orgs interactively
#   all-orgs   : loop all orgs
#
# Requires: curl, jq, python3, mktemp, split, stat, sed, tr, awk
###############################################################################

# Ensure basic tools are reachable regardless of weird environments
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
hash -r 2>/dev/null || true

#############################################
# Logging
#############################################
typeset -A _LV
_LV=(TRACE 0 DEBUG 1 INFO 2 WARN 3 ERROR 4)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

_log_ok() {
  local want="${_LV[$1]:-2}"
  local cur="${_LV[$LOG_LEVEL]:-2}"
  (( want >= cur ))
}
log() { local lvl="$1"; shift; _log_ok "$lvl" && print -r -- "[$lvl] $*" >&2 || true; }
die() { log ERROR "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  print -r -- "$s"
}

#############################################
# Globals used by API helper (must exist under set -u)
#############################################
typeset -g API_BASE=""
typeset -g TOKEN=""
typeset -g REQ_CODE=""
typeset -g REQ_HDR=""
typeset -g REQ_BODY=""

#############################################
# Prompts
#############################################
prompt_required() {
  local var="$1" label="$2" def="${3:-}"
  local cur="${(P)var:-}"
  cur="$(trim "$cur")"
  if [[ -n "$cur" ]]; then
    typeset -g "$var=$cur"
    return 0
  fi

  local ans=""
  while true; do
    if [[ -n "$def" ]]; then
      vared -p "${label} [${def}]: " ans
      ans="$(trim "${ans:-$def}")"
    else
      vared -p "${label}: " ans
      ans="$(trim "$ans")"
    fi
    [[ -n "$ans" ]] && break
    print -r -- "Value is required." >&2
  done
  typeset -g "$var=$ans"
}

prompt_secret() {
  local var="$1" label="$2"
  local cur="${(P)var:-}"
  cur="$(trim "$cur")"
  if [[ -n "$cur" ]]; then
    typeset -g "$var=$cur"
    return 0
  fi

  local ans=""
  while true; do
    print -n -- "${label}: " >&2
    stty -echo
    IFS= read -r ans
    stty echo
    print -r -- "" >&2
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] && break
    print -r -- "Value is required." >&2
  done
  typeset -g "$var=$ans"
}

prompt_menu() {
  local var="$1" title="$2" opts="$3" def="${4:-1}"
  local -a arr
  arr=("${(@s:|:)opts}")

  print -r -- "" >&2
  print -r -- "$title" >&2
  local i=1
  for o in "${arr[@]}"; do
    print -r -- "  $i) $o" >&2
    ((i++))
  done

  local pick=""
  while true; do
    vared -p "Select (1-${#arr[@]}) [${def}]: " pick
    pick="$(trim "${pick:-$def}")"
    [[ "$pick" == <-> ]] || { print -r -- "Enter a number." >&2; continue; }
    (( pick>=1 && pick<=${#arr[@]} )) || { print -r -- "Out of range." >&2; continue; }
    typeset -g "$var=${arr[$pick]}"
    return 0
  done
}

#############################################
# .env loader (safe)
# - supports "export KEY=VALUE"
# - strips wrapping quotes
# - skips PATH
#############################################
dotenv_load() {
  local file="${1:-.env}"
  [[ -f "$file" ]] || die "Missing env file: $file"
  log DEBUG "Loading .env from: $file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
      line="$(trim "$line")"
    fi

    [[ "$line" == *"="* ]] || continue

    local key="${line%%=*}"
    local val="${line#*=}"
    key="$(trim "$key")"
    val="$(trim "$val")"

    if [[ "$key" == "PATH" ]]; then
      log DEBUG "Skipping PATH from .env"
      continue
    fi

    # strip wrapping quotes
    if [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val#\'}"; val="${val%\'}"
    elif [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val#\"}"; val="${val%\"}"
    fi

    export "$key=$val"
  done < "$file"
}

#############################################
# Region/base URL
#############################################
derive_api_base() {
  if [[ -n "${ACTION1_BASE_URL:-}" ]]; then
    print -r -- "${ACTION1_BASE_URL}"
    return 0
  fi
  local r="${ACTION1_REGION:-Europe}"
  case "${r:l}" in
    europe|eu) print -r -- "https://app.eu.action1.com/api/3.0" ;;
    northamerica|north_america|na|us|global) print -r -- "https://app.action1.com/api/3.0" ;;
    australia|au) print -r -- "https://app.au.action1.com/api/3.0" ;;
    *) print -r -- "" ;;
  esac
}

#############################################
# Utils
#############################################
urlencode() {
  python3 - <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))
PY
}

file_size_bytes() {
  local f="$1"
  if stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    stat -c%s "$f"
  fi
}

origin_from_base() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
u=urllib.parse.urlparse(sys.argv[1])
print(f"{u.scheme}://{u.netloc}")
PY
}

normalize_upload_location() {
  local base="$1" loc="$2"
  if [[ "$loc" == http* ]]; then
    print -r -- "$loc"
    return 0
  fi
  local origin; origin="$(origin_from_base "$base")"
  if [[ "$loc" == /API/* ]]; then
    loc="/api/3.0${loc#/API}"
  fi
  if [[ "$loc" == /* ]]; then
    print -r -- "${origin}${loc}"
  else
    print -r -- "${origin}/${loc}"
  fi
}

#############################################
# OpenAPI enum extraction (OSMac / OSWindows)
#############################################
typeset -g OPENAPI_PATH=""

find_openapi() {
  local script_dir="${0:A:h}"
  local -a candidates
  candidates=(
    "${OPENAPI_PATH_ARG:-}"
    "${script_dir}/_api/docs/action1_openapi.json"
    "${script_dir}/docs/action1_openapi.json"
    "${PWD}/_api/docs/action1_openapi.json"
    "${PWD}/docs/action1_openapi.json"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -n "$p" && -f "$p" ]] && { print -r -- "$p"; return 0; }
  done

  local d="$script_dir"
  local i=0
  while (( i < 6 )); do
    p="${d}/_api/docs/action1_openapi.json"
    [[ -f "$p" ]] && { print -r -- "$p"; return 0; }
    p="${d}/docs/action1_openapi.json"
    [[ -f "$p" ]] && { print -r -- "$p"; return 0; }
    d="${d:h}"
    ((i++))
  done
  print -r -- ""
  return 1
}

openapi_enum_list() {
  local schema="$1"
  python3 - "$OPENAPI_PATH" "$schema" <<'PY'
import sys, json
path=sys.argv[1]
schema_name=sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
  doc=json.load(f)
schemas=(doc.get("components") or {}).get("schemas") or {}
def resolve_ref(ref):
  if not ref.startswith("#/"): return {}
  cur=doc
  for part in ref[2:].split("/"):
    if not isinstance(cur, dict): return {}
    cur=cur.get(part)
    if cur is None: return {}
  return cur if isinstance(cur, dict) else {}
def find_enum(obj):
  if not isinstance(obj, dict): return None
  if isinstance(obj.get("enum"), list): return obj["enum"]
  if "$ref" in obj: return find_enum(resolve_ref(obj["$ref"]))
  for key in ("allOf","oneOf","anyOf"):
    if isinstance(obj.get(key), list):
      for part in obj[key]:
        e=find_enum(part)
        if e: return e
  return None
sch=schemas.get(schema_name) or {}
enum=find_enum(sch) or []
for v in enum: print(v)
PY
}

prompt_os_list_json() {
  local schema="$1"
  local -a opts
  opts=()
  local line=""
  if [[ -n "$OPENAPI_PATH" && -f "$OPENAPI_PATH" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && opts+=("$line")
    done < <(openapi_enum_list "$schema" 2>/dev/null || true)
  fi

  if (( ${#opts[@]} > 0 )); then
    print -r -- "" >&2
    print -r -- "Supported OS options ($schema):" >&2
    local i=1
    for line in "${opts[@]}"; do
      print -r -- "  $i) $line" >&2
      ((i++))
    done
    local sel=""
    while true; do
      vared -p "Select OS entries (e.g. 1,3,5): " sel
      sel="$(trim "${sel// /}")"
      [[ "$sel" =~ '^[0-9]+(,[0-9]+)*$' ]] || { print -r -- "Use comma-separated numbers." >&2; continue; }
      OS_LIST_JSON="$(python3 - "$sel" "${opts[@]}" <<'PY'
import sys, json
sel=sys.argv[1]
opts=sys.argv[2:]
idxs=[int(x) for x in sel.split(",") if x]
vals=[]
for i in idxs:
  if 1<=i<=len(opts): vals.append(opts[i-1])
print(json.dumps(vals))
PY
)"
      [[ "$OS_LIST_JSON" != "[]" ]] && break
      print -r -- "OS list cannot be empty." >&2
    done
  else
    log WARN "OpenAPI enum not available; OS list will be manual."
    local raw=""
    while true; do
      vared -p "Supported OS list (comma-separated, required): " raw
      raw="$(trim "$raw")"
      [[ -n "$raw" ]] || { print -r -- "OS list is required." >&2; continue; }
      OS_LIST_JSON="$(
        print -r -- "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
          | jq -R -s 'split("\n") | map(select(length>0))'
      )"
      [[ "$OS_LIST_JSON" != "[]" ]] && break
      print -r -- "OS list cannot be empty." >&2
    done
  fi
}

#############################################
# API helper (NO command substitution!)
# writes: REQ_CODE, REQ_HDR, REQ_BODY
#############################################
api_json() {
  local method="$1"
  local api_path="$2"
  local body="${3:-}"
  local url="${API_BASE}${api_path}"

  if [[ -n "${REQ_HDR:-}" && -f "${REQ_HDR:-}" ]]; then
    rm -f "$REQ_HDR" 2>/dev/null || true
  fi

  local hdr out code
  hdr="$(mktemp)"
  out="$(mktemp)"
  code=""

  if [[ -n "$body" ]]; then
    if [[ -n "${TOKEN:-}" ]]; then
      code="$(curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        --data "$body" \
        -D "$hdr" -o "$out" -w "%{http_code}")" || true
    else
      code="$(curl -sS -X "$method" "$url" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        --data "$body" \
        -D "$hdr" -o "$out" -w "%{http_code}")" || true
    fi
  else
    if [[ -n "${TOKEN:-}" ]]; then
      code="$(curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/json" \
        -D "$hdr" -o "$out" -w "%{http_code}")" || true
    else
      code="$(curl -sS -X "$method" "$url" \
        -H "Accept: application/json" \
        -D "$hdr" -o "$out" -w "%{http_code}")" || true
    fi
  fi

  typeset -g REQ_CODE="$code"
  typeset -g REQ_HDR="$hdr"
  typeset -g REQ_BODY
  REQ_BODY="$(cat "$out")"
  rm -f "$out"
}

header_get() {
  local hdr_file="$1" header="$2"
  awk -v IGNORECASE=1 -v h="$header" '
    BEGIN{FS=": "}
    tolower($1)==tolower(h){sub("\r$","",$2); print $2; exit}
  ' "$hdr_file"
}

auth() {
  # Only uses ACTION1_* vars (as you requested)
  prompt_required ACTION1_CLIENT_ID "ACTION1_CLIENT_ID (Client ID)"
  prompt_secret   ACTION1_CLIENT_SECRET "ACTION1_CLIENT_SECRET (Client Secret)"

  local payload
  payload="$(jq -nc --arg id "$ACTION1_CLIENT_ID" --arg sec "$ACTION1_CLIENT_SECRET" \
    '{client_id:$id, client_secret:$sec}')"

  log INFO "Authenticating (client_credentials)…"
  TOKEN=""
  api_json POST "/oauth2/token" "$payload"

  log DEBUG "Auth HTTP code: '${REQ_CODE:-<unset>}'"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Auth failed (HTTP ${REQ_CODE:-<unset>}). Body: $REQ_BODY"

  TOKEN="$(print -r -- "$REQ_BODY" | jq -r '.access_token // empty')"
  [[ -n "$TOKEN" ]] || die "Auth failed: access_token missing. Body: $REQ_BODY"
}

#############################################
# Organizations
#############################################
get_orgs() {
  api_json GET "/organizations"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Failed to list orgs (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"
}

choose_targets() {
  TARGETS=()

  if [[ "$MODE" == "enterprise" ]]; then
    TARGETS=("all")
    return 0
  fi

  get_orgs
  local count
  count="$(print -r -- "$REQ_BODY" | jq -r '.items | length')"
  (( count > 0 )) || die "No orgs returned."

  if [[ "$MODE" == "all-orgs" ]]; then
    TARGETS=("${(@f)$(print -r -- "$REQ_BODY" | jq -r '.items[].id')}")
    return 0
  fi

  print -r -- "" >&2
  print -r -- "Organizations:" >&2
  local i=1
  print -r -- "$REQ_BODY" | jq -r '.items[] | "\(.name)\t\(.id)"' | while IFS=$'\t' read -r name id; do
    print -r -- "  $i) $name ($id)" >&2
    ((i++))
  done

  local sel=""
  while true; do
    vared -p "Select orgs (e.g. 1,3,5) or type 'all': " sel
    sel="$(trim "${sel// /}")"
    [[ -n "$sel" ]] || { print -r -- "Selection is required." >&2; continue; }
    if [[ "${sel:l}" == "all" ]]; then
      TARGETS=("${(@f)$(print -r -- "$REQ_BODY" | jq -r '.items[].id')}")
      return 0
    fi
    [[ "$sel" =~ '^[0-9]+(,[0-9]+)*$' ]] || { print -r -- "Use comma-separated numbers or 'all'." >&2; continue; }

    TARGETS=("${(@f)$(python3 - "$sel" <<'PY' <<<"$REQ_BODY"
import sys, json
sel=sys.argv[1]
d=json.load(sys.stdin)
items=d.get("items") or []
idxs=[int(x) for x in sel.split(",") if x]
out=[]
for i in idxs:
  if 1<=i<=len(items):
    oid=items[i-1].get("id")
    if oid: out.append(oid)
print("\n".join(out))
PY
)}")
    (( ${#TARGETS[@]} > 0 )) && return 0
    print -r -- "No valid orgs selected." >&2
  done
}

#############################################
# Software repository
#############################################
find_package_id() {
  local org_id="$1" app="$2" platform="$3"
  local app_q; app_q="$(print -r -- "$app" | urlencode)"
  api_json GET "/software-repository/${org_id}?custom=yes&builtin=no&limit=100&match_name=${app_q}&platform=${platform}"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Package list failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  local items_len
  items_len="$(print -r -- "$REQ_BODY" | jq -r '(.items // []) | length')"
  (( items_len > 0 )) || { print -r -- ""; return 0; }

  local exact
  exact="$(print -r -- "$REQ_BODY" | jq -r --arg n "$app" '
    (.items // []) as $it
    | ($it | map(select((.name // "") | ascii_downcase == ($n|ascii_downcase))) | .[0].id) // empty
  ')"
  [[ -n "$exact" ]] && { print -r -- "$exact"; return 0; }

  print -r -- "$(print -r -- "$REQ_BODY" | jq -r '.items[0].id // empty')"
}

create_package() {
  local org_id="$1"
  local payload
  payload="$(jq -nc \
    --arg name "$APP_NAME" \
    --arg vendor "$VENDOR" \
    --arg desc "$DESCRIPTION" \
    --arg platform "$PLATFORM" \
    '{name:$name, vendor:$vendor, description:$desc, platform:$platform}')"

  api_json POST "/software-repository/${org_id}" "$payload"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Package create failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  local id; id="$(print -r -- "$REQ_BODY" | jq -r '.id // empty')"
  [[ -n "$id" ]] || die "Package create returned no id. Body: $REQ_BODY"
  print -r -- "$id"
}

get_package_with_versions() {
  local org_id="$1" pkg_id="$2"
  api_json GET "/software-repository/${org_id}/${pkg_id}?fields=versions"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Get package failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"
}

find_version_id() {
  local version_str="$1"
  print -r -- "$REQ_BODY" | jq -r --arg v "$version_str" '
    ((.versions.items // .versions // []) | map(select(.version == $v)) | .[0].id) // empty
  '
}

create_version() {
  local org_id="$1" pkg_id="$2" file_name="$3"

  local payload
  payload="$(jq -nc \
    --arg ver "$APP_VERSION" \
    --arg match "$APP_NAME_MATCH" \
    --arg date "$RELEASE_DATE" \
    --arg up "$UPLOAD_PLATFORM" \
    --arg fn "$file_name" \
    --argjson os "$OS_LIST_JSON" \
    '{
      version:$ver,
      app_name_match:$match,
      release_date:$date,
      os:$os,
      OS:$os,
      file_name: {($up): {name:$fn}}
    }')"

  api_json POST "/software-repository/${org_id}/${pkg_id}/versions" "$payload"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Version create failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  local id; id="$(print -r -- "$REQ_BODY" | jq -r '.id // empty')"
  [[ -n "$id" ]] || die "Version create returned no id. Body: $REQ_BODY"
  print -r -- "$id"
}

#############################################
# Upload init + chunks
#############################################
upload_init() {
  local org_id="$1" pkg_id="$2" ver_id="$3"
  local size="$FILE_SIZE"
  local url="${API_BASE}/software-repository/${org_id}/${pkg_id}/versions/${ver_id}/upload?platform=${UPLOAD_PLATFORM}"

  local hdr out code
  hdr="$(mktemp)"
  out="$(mktemp)"
  code=""

  code="$(curl -sS -X POST "$url" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -H "X-Upload-Content-Type: application/octet-stream" \
    -H "X-Upload-Content-Length: ${size}" \
    -D "$hdr" -o "$out" -w "%{http_code}")" || true

  if [[ "$code" != "308" ]]; then
    log ERROR "Upload init failed (expected 308). Got: $code"
    log ERROR "Body: $(cat "$out" 2>/dev/null || true)"
    rm -f "$hdr" "$out"
    return 1
  fi

  local loc; loc="$(header_get "$hdr" "X-Upload-Location")"
  rm -f "$hdr" "$out"
  [[ -n "$loc" ]] || die "Upload init succeeded but X-Upload-Location missing."
  normalize_upload_location "$API_BASE" "$loc"
}

upload_chunks() {
  local upload_url="$1"
  local chunk_mb="$CHUNK_MB"
  [[ "$chunk_mb" == <-> ]] || die "Chunk MB must be numeric (got '$chunk_mb')"
  (( chunk_mb >= 5 )) || die "Chunk size must be >= 5MB"
  local chunk_bytes=$(( chunk_mb * 1024 * 1024 ))
  local total="$FILE_SIZE"

  log INFO "Uploading ${total} bytes in ${chunk_mb}MB chunks…"

  local tmpdir; tmpdir="$(mktemp -d)"
  split -b "$chunk_bytes" -d -a 4 "$FILE_PATH" "${tmpdir}/chunk_"

  local offset=0
  local part
  for part in "${tmpdir}"/chunk_*; do
    [[ -f "$part" ]] || continue
    local part_size; part_size="$(file_size_bytes "$part")"
    local start="$offset"
    local end=$(( offset + part_size - 1 ))
    offset=$(( end + 1 ))

    local hdr out code
    hdr="$(mktemp)"
    out="$(mktemp)"
    code=""

    code="$(curl -sS -X PUT "$upload_url" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/octet-stream" \
      -H "Content-Length: ${part_size}" \
      -H "Content-Range: bytes ${start}-${end}/${total}" \
      --data-binary "@${part}" \
      -D "$hdr" -o "$out" -w "%{http_code}")" || true

    if [[ "$code" == "308" ]]; then
      log DEBUG "Chunk ${start}-${end} OK (308)"
      rm -f "$hdr" "$out"
      continue
    fi

    if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
      log INFO "Final chunk ${start}-${end} OK (HTTP ${code})"
      rm -f "$hdr" "$out"
      break
    fi

    log ERROR "Chunk upload failed HTTP ${code} at ${start}-${end}"
    log ERROR "Body: $(cat "$out" 2>/dev/null || true)"
    rm -f "$hdr" "$out"
    rm -rf "$tmpdir"
    return 1
  done

  rm -rf "$tmpdir"
  log INFO "Upload complete."
}

#############################################
# CLI args + defaults
#############################################
ENV_FILE=".env"
FILE_PATH=""
MODE=""
OPENAPI_PATH_ARG=""
FORCE_REUPLOAD="no"

typeset -g APP_NAME="${APP_NAME:-}"
typeset -g APP_VERSION="${APP_VERSION:-}"
typeset -g PLATFORM="${PLATFORM:-}"
typeset -g UPLOAD_PLATFORM="${UPLOAD_PLATFORM:-}"
typeset -g VENDOR="${VENDOR:-}"
typeset -g DESCRIPTION="${DESCRIPTION:-}"
typeset -g APP_NAME_MATCH="${APP_NAME_MATCH:-}"
typeset -g RELEASE_DATE="${RELEASE_DATE:-}"
typeset -g OS_LIST_JSON="${OS_LIST_JSON:-}"
typeset -g CHUNK_MB="${CHUNK_MB:-${UPLOAD_CHUNK_MB:-24}}"

usage() {
  cat >&2 <<EOF
Usage:
  $0 --env .env --file-path /path/to/file.zip [options]

Options:
  --log-level TRACE|DEBUG|INFO|WARN|ERROR
  --mode enterprise|orgs|all-orgs
  --openapi-path /path/to/action1_openapi.json
  --chunk-mb N            (>=5)
  --force-reupload

Notes:
  - enterprise uses orgId=all ("My Enterprise")
  - Mac uploads require .zip
EOF
}

while (( $# )); do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --file-path) FILE_PATH="$2"; shift 2 ;;
    --log-level) LOG_LEVEL="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --openapi-path) OPENAPI_PATH_ARG="$2"; shift 2 ;;
    --chunk-mb) CHUNK_MB="$2"; shift 2 ;;
    --force-reupload) FORCE_REUPLOAD="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

#############################################
# Main
#############################################
need_cmd curl
need_cmd jq
need_cmd python3
need_cmd mktemp
need_cmd split
need_cmd stat
need_cmd awk
need_cmd sed
need_cmd tr

[[ -n "$FILE_PATH" ]] || prompt_required FILE_PATH "Installer file path"
FILE_PATH="$(trim "$FILE_PATH")"
[[ -f "$FILE_PATH" ]] || die "File not found: $FILE_PATH"

dotenv_load "$ENV_FILE"

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
hash -r 2>/dev/null || true
log DEBUG "PATH after dotenv: '$PATH'"

# Base URL
API_BASE="$(derive_api_base)"
if [[ -z "$API_BASE" ]]; then
  prompt_required ACTION1_BASE_URL "Action1 API base URL (e.g. https://app.eu.action1.com/api/3.0)"
  API_BASE="$ACTION1_BASE_URL"
fi

# OpenAPI path
OPENAPI_PATH="$(find_openapi || true)"
if [[ -n "$OPENAPI_PATH" ]]; then
  log DEBUG "Using OpenAPI file: $OPENAPI_PATH"
else
  log WARN "OpenAPI file not found; OS list will be manual."
fi

# Infer from filename: Name-1.2.3.ext
FILE_BASENAME="$(basename -- "$FILE_PATH")"
FILE_EXT="${FILE_BASENAME##*.}"
FILE_EXT="${FILE_EXT:l}"
typeset -g FILE_SIZE; FILE_SIZE="$(file_size_bytes "$FILE_PATH")"

if [[ -z "$APP_NAME" || -z "$APP_VERSION" ]]; then
  local stem maybe_ver maybe_name
  stem="${FILE_BASENAME%.*}"
  if [[ "$stem" == *-* ]]; then
    maybe_ver="${stem##*-}"
    maybe_name="${stem%-${maybe_ver}}"
    [[ -z "$APP_NAME" && -n "$maybe_name" && "$maybe_name" != "$stem" ]] && APP_NAME="$maybe_name"
    [[ -z "$APP_VERSION" && -n "$maybe_ver" ]] && APP_VERSION="$maybe_ver"
  fi
fi

# Mode
if [[ -z "$MODE" ]]; then
  prompt_menu MODE "Choose scope mode" "enterprise|orgs|all-orgs" 1
fi
MODE="$(trim "$MODE")"
[[ "$MODE" == "enterprise" || "$MODE" == "orgs" || "$MODE" == "all-orgs" ]] || die "Invalid --mode: $MODE"

# Platform
if [[ -z "$PLATFORM" ]]; then
  if [[ "$FILE_EXT" == "msi" || "$FILE_EXT" == "exe" || "$FILE_EXT" == "msix" ]]; then
    PLATFORM="Windows"
  else
    PLATFORM="Mac"
  fi
fi
PLATFORM="$(trim "$PLATFORM")"
if [[ "$PLATFORM" != "Windows" && "$PLATFORM" != "Mac" ]]; then
  prompt_menu PLATFORM "Choose package platform" "Windows|Mac" 2
fi

if [[ "$PLATFORM" == "Mac" && "$FILE_EXT" != "zip" ]]; then
  die "For Mac packages, Action1 requires .zip (you provided .$FILE_EXT)"
fi

# Upload platform
if [[ -z "$UPLOAD_PLATFORM" ]]; then
  if [[ "$PLATFORM" == "Mac" ]]; then
    prompt_menu UPLOAD_PLATFORM "Choose upload platform" "Mac_AppleSilicon|Mac_IntelCPU" 1
  else
    prompt_menu UPLOAD_PLATFORM "Choose upload platform" "Windows_64|Windows_32|Windows_ARM64" 1
  fi
fi

# Required fields
prompt_required APP_NAME "App name" "$APP_NAME"
prompt_required APP_VERSION "Version" "$APP_VERSION"
prompt_required VENDOR "Vendor (required for package create)" "${VENDOR:-$APP_NAME}"
prompt_required DESCRIPTION "Description (required for package create)" "${DESCRIPTION:-$APP_NAME $APP_VERSION}"
prompt_required RELEASE_DATE "Release date (YYYY-MM-DD)" "${RELEASE_DATE:-$(date +%F)}"
prompt_required APP_NAME_MATCH "app_name_match (required)" "${APP_NAME_MATCH:-$APP_NAME}"

if [[ -z "$OS_LIST_JSON" ]]; then
  if [[ "$PLATFORM" == "Mac" ]]; then
    prompt_os_list_json "OSMac"
  else
    prompt_os_list_json "OSWindows"
  fi
fi

log INFO "API base:      $API_BASE"
log INFO "Mode:          $MODE"
log INFO "App:           $APP_NAME"
log INFO "Version:       $APP_VERSION"
log INFO "Platform:      $PLATFORM"
log INFO "Upload plat:   $UPLOAD_PLATFORM"
log INFO "Release date:  $RELEASE_DATE"
log INFO "File:          $FILE_PATH"
log DEBUG "OS list JSON:  $OS_LIST_JSON"
log DEBUG "Chunk MB:      $CHUNK_MB"

# Auth (from ACTION1_* only)
auth

# Targets
typeset -a TARGETS
choose_targets
log INFO "Target scope count: ${#TARGETS[@]}"

# Process
for org_id in "${TARGETS[@]}"; do
  print -r -- "" >&2
  log INFO "---- Scope: ${org_id} ----"

  log INFO "Looking for custom package '${APP_NAME}'…"
  pkg_id="$(find_package_id "$org_id" "$APP_NAME" "$PLATFORM")"

  if [[ -z "$pkg_id" ]]; then
    log WARN "Not found. Creating package…"
    pkg_id="$(create_package "$org_id")"
    log INFO "Created package id: $pkg_id"
  else
    log INFO "Found package id: $pkg_id"
  fi

  get_package_with_versions "$org_id" "$pkg_id"
  existing_ver_id="$(find_version_id "$APP_VERSION")"

  if [[ -n "$existing_ver_id" && "$FORCE_REUPLOAD" != "yes" ]]; then
    print -r -- "" >&2
    print -r -- "Version '${APP_VERSION}' already exists (id=${existing_ver_id})." >&2
    local yn=""
    vared -p "Upload to the existing version? (y/N): " yn
    yn="$(trim "${yn:l}")"
    if [[ "$yn" != "y" ]]; then
      die "Refusing to overwrite existing version. Use a new version number or re-run with --force-reupload."
    fi
    ver_id="$existing_ver_id"
    log WARN "Reusing existing version id: $ver_id"
  elif [[ -n "$existing_ver_id" && "$FORCE_REUPLOAD" == "yes" ]]; then
    ver_id="$existing_ver_id"
    log WARN "Reusing existing version id due to --force-reupload: $ver_id"
  else
    log INFO "Creating version '${APP_VERSION}'…"
    ver_id="$(create_version "$org_id" "$pkg_id" "$FILE_BASENAME")"
    log INFO "Created version id: $ver_id"
  fi

  upload_url="$(upload_init "$org_id" "$pkg_id" "$ver_id")" || die "Upload init failed."
  log DEBUG "Upload URL: $upload_url"

  upload_chunks "$upload_url" || die "Upload failed."
  log INFO "Done for scope: $org_id"
done

log INFO "All done."
