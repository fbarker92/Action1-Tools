#!/usr/bin/env bash
set -euo pipefail

# =========================
# Logging
# =========================
LOG_LEVEL="INFO" # ERROR, WARN, INFO, DEBUG, TRACE

_level_to_num() {
  case "${1^^}" in
    ERROR) echo 0 ;;
    WARN)  echo 1 ;;
    INFO)  echo 2 ;;
    DEBUG) echo 3 ;;
    TRACE) echo 4 ;;
    *)     echo 2 ;;
  esac
}

log() {
  local lvl="${1^^}"; shift
  local want="$(_level_to_num "$LOG_LEVEL")"
  local have="$(_level_to_num "$lvl")"
  if [[ "$have" -le "$want" ]]; then
    printf '[%s] %s\n' "$lvl" "$*" >&2
  fi
}

die() { log ERROR "$*"; exit 1; }

# =========================
# Helpers (macOS-safe)
# =========================
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

trim_quotes() {
  # Removes surrounding single/double quotes if present.
  local s="$1"
  s="${s#\'}"; s="${s%\'}"
  s="${s#\"}"; s="${s%\"}"
  printf '%s' "$s"
}

file_size_bytes() {
  # macOS stat
  stat -f%z "$1"
}

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s' "$p"
  else
    printf '%s/%s' "$(pwd)" "$p"
  fi
}

# =========================
# JSON parsing via osascript (JavaScriptCore)
# =========================
json_get() {
  # Usage: json_get "<json>" "<path>"
  local json="$1"
  local path="$2"

  /usr/bin/osascript -l JavaScript - "$json" "$path" <<'JSCODE'
ObjC.import('Foundation');

function writeln(s) {
  s = (s === null || s === undefined) ? '' : String(s);
  const ns = $.NSString.alloc.initWithUTF8String(s + "\n");
  const data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

const args = $.NSProcessInfo.processInfo.arguments;
const argc = args.count;

// last 2 args are our payload + path
const input = ObjC.unwrap(args.objectAtIndex(argc - 2));
const path  = ObjC.unwrap(args.objectAtIndex(argc - 1));

function getByPath(obj, p) {
  try {
    const parts = p.split('.').flatMap(seg => {
      const out = [];
      let s = seg;
      while (true) {
        const m = s.match(/^([^\[]+)\[(\d+)\](.*)$/);
        if (!m) { out.push(s); break; }
        out.push(m[1]); out.push(Number(m[2])); s = m[3];
        if (!s) break;
      }
      return out.filter(x => x !== '');
    });

    let cur = obj;
    for (const part of parts) {
      if (cur == null) return '';
      cur = cur[part];
    }
    if (cur == null) return '';
    if (typeof cur === 'object') return JSON.stringify(cur);
    return String(cur);
  } catch (e) {
    return '';
  }
}

try {
  const obj = JSON.parse(input);
  const v = getByPath(obj, path);
  writeln(v ?? '');
} catch (e) {
  writeln('');
}
JSCODE
}

## DEBUGGING: test json_get
if [[ "${TEST_JSON_GET:-0}" == "1" ]]; then
  body='{"access_token":"abc"}'
  tok="$(json_get "$body" "access_token")"
  echo "tok=$tok"
  exit 0
fi

orgs_to_tsv() {
  local json="$1"

  /usr/bin/osascript -l JavaScript - "$json" <<'JSCODE'
ObjC.import('Foundation');

function writeln(s) {
  s = (s === null || s === undefined) ? '' : String(s);
  const ns = $.NSString.alloc.initWithUTF8String(s + "\n");
  const data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

const args = $.NSProcessInfo.processInfo.arguments;
const argc = args.count;
const input = ObjC.unwrap(args.objectAtIndex(argc - 1));

function pickName(o){
  return o.name || o.title || o.display_name || o.displayName || o.organization_name || o.org_name || '';
}

try {
  const obj = JSON.parse(input);
  const arr = Array.isArray(obj) ? obj : (obj.items || obj.data || obj.organizations || []);
  for (const o of arr) {
    const id = o.id || o.organization_id || o.org_id || '';
    const name = pickName(o);
    if (id && name) writeln(id + "\t" + name);
  }
} catch (e) {}
JSCODE
}

packages_find_match() {
  local json="$1"
  local app_lower="$2"

  /usr/bin/osascript -l JavaScript - "$json" "$app_lower" <<'JSCODE'
ObjC.import('Foundation');

function writeln(s) {
  s = (s === null || s === undefined) ? '' : String(s);
  const ns = $.NSString.alloc.initWithUTF8String(s + "\n");
  const data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

const args = $.NSProcessInfo.processInfo.arguments;
const argc = args.count;

const input = ObjC.unwrap(args.objectAtIndex(argc - 2));
const want  = ObjC.unwrap(args.objectAtIndex(argc - 1)).toLowerCase();

function pickName(o){
  return (o.name || o.title || o.display_name || o.displayName || '').toString();
}

try {
  const obj = JSON.parse(input);
  const arr = Array.isArray(obj) ? obj : (obj.items || obj.data || obj.packages || []);
  for (const p of arr) {
    const nm = pickName(p);
    const id = p.id || p.package_id || p.pkg_id || '';
    if (id && nm && nm.toLowerCase() === want) {
      writeln(id + "\t" + nm);
      break;
    }
  }
} catch (e) {}
JSCODE
}

# =========================
# .env loader
# =========================
load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0
  log DEBUG "Loading .env from: $env_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # ignore comments/blank
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # KEY=VALUE
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      val="$(trim_quotes "$val")"
      # only set if not already set in environment
      if [[ -z "${!key:-}" ]]; then
        export "$key=$val"
      fi
    fi
  done < "$env_file"
}

# =========================
# Region → host
# =========================
region_to_host() {
  case "${1}" in
    Europe)        echo "app.eu.action1.com" ;;
    NorthAmerica)  echo "app.action1.com" ;;
    Australia)     echo "app.au.action1.com" ;;
    *)             return 1 ;;
  esac
}

# =========================
# HTTP wrapper
# =========================
API_HOST=""
API_BASE=""
TOKEN_URL=""
ACCESS_TOKEN=""

api_call() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"; shift || true
  local content_type="${1:-application/json}"; shift || true

  local url="${API_BASE}${path}"
  log TRACE "HTTP $method $url"

  local tmp_body; tmp_body="$(mktemp)"
  local tmp_hdr;  tmp_hdr="$(mktemp)"
  local code=""

  if [[ -n "$data" ]]; then
    code="$(curl -sS -D "$tmp_hdr" -o "$tmp_body" \
      -X "$method" "$url" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: ${content_type}" \
      --data "$data" \
      -w "%{http_code}")"
  else
    code="$(curl -sS -D "$tmp_hdr" -o "$tmp_body" \
      -X "$method" "$url" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -w "%{http_code}")"
  fi

  local body; body="$(cat "$tmp_body")"
  rm -f "$tmp_body" "$tmp_hdr"

  printf '%s\n' "$code"
  printf '%s' "$body"
}

# Multipart upload attempt helper
api_upload_multipart() {
  local path="$1"
  local zip_path="$2"
  local version="$3"

  local url="${API_BASE}${path}"
  log DEBUG "Trying upload endpoint: POST $url"

  local tmp_body; tmp_body="$(mktemp)"
  local tmp_hdr;  tmp_hdr="$(mktemp)"

  local code
  code="$(curl -sS -D "$tmp_hdr" -o "$tmp_body" \
    -X POST "$url" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -F "file=@${zip_path}" \
    -F "version=${version}" \
    -w "%{http_code}")"

  local body; body="$(cat "$tmp_body")"
  rm -f "$tmp_body" "$tmp_hdr"

  printf '%s\n' "$code"
  printf '%s' "$body"
}

# =========================
# Auth
# =========================
get_token() {
  local client_id="$1"
  local client_secret="$2"

  log INFO "Authenticating (OAuth2 client_credentials)…"
  log DEBUG "Token URL: $TOKEN_URL"

  # Capture body + HTTP code (last line)
  local resp http_code body
  resp="$(
    curl -sS -w $'\n%{http_code}' -X POST "$TOKEN_URL" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "client_id=${client_id}" \
      --data-urlencode "client_secret=${client_secret}" \
      --data-urlencode "grant_type=client_credentials"
  )"

  http_code="$(tail -n 1 <<< "$resp")"
  body="$(sed '$d' <<< "$resp")"

  log TRACE "Token HTTP: $http_code"
  log TRACE "Token body: $body"

  [[ "$http_code" =~ ^2 ]] || die "Token request failed (HTTP $http_code). Body: $body"

  local tok
  tok="$(json_get "$body" "access_token")"
  [[ -n "$tok" ]] || die "Failed to obtain access_token. Body: $body"

  ACCESS_TOKEN="$tok"
  log DEBUG "Access token acquired."
}


# =========================
# Interactive org selection
# =========================
select_orgs_interactive() {
  local tsv="$1"

  local ids=()
  local names=()

  while IFS=$'\t' read -r oid oname; do
    ids+=("$oid")
    names+=("$oname")
  done <<< "$tsv"

  ((${#ids[@]} > 0)) || die "No organizations returned by API."

  echo
  echo "Organizations:"
  echo "  0) ALL organizations"
  for i in "${!ids[@]}"; do
    printf "  %d) %s (%s)\n" "$((i+1))" "${names[$i]}" "${ids[$i]}"
  done
  echo
  read -r -p "Select orgs (e.g. 1,3,5 or 0 for ALL): " choice

  choice="${choice//[[:space:]]/}"
  [[ -n "$choice" ]] || die "No selection made."

  if [[ "$choice" == "0" || "${choice,,}" == "all" ]]; then
    printf '%s\n' "${ids[@]}"
    return 0
  fi

  IFS=',' read -r -a picks <<< "$choice"
  local out=()
  for p in "${picks[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid selection token: $p"
    local idx=$((p-1))
    (( idx >= 0 && idx < ${#ids[@]} )) || die "Selection out of range: $p"
    out+=("${ids[$idx]}")
  done

  # de-dupe
  local uniq=()
  local seen="|"
  for x in "${out[@]}"; do
    if [[ "$seen" != *"|$x|"* ]]; then
      uniq+=("$x")
      seen="${seen}${x}|"
    fi
  done

  printf '%s\n' "${uniq[@]}"
}

# =========================
# Main
# =========================
usage() {
  cat <<EOF
Usage:
  $(basename "$0") \\
    --client-id <id> \\
    --client-secret <secret> \\
    --action1-region <Europe|NorthAmerica|Australia> \\
    --zip-path <APPNAME-VERSION.zip> \\
    [--log-level <ERROR|WARN|INFO|DEBUG|TRACE>] \\
    [--env <path-to-.env>]

Notes:
- CLI args override .env values.
EOF
}

ENV_FILE=".env"
CLIENT_ID="${CLIENT_ID:-}"
CLIENT_SECRET="${CLIENT_SECRET:-}"
ACTION1_REGION="${ACTION1_REGION:-}"
ZIP_PATH=""
UPLOAD_CHUNK_MB="${UPLOAD_CHUNK_MB:-24}"
MAC_PLATFORM_INTEL="${MAC_PLATFORM_INTEL:-Mac_Intel}"
MAC_PLATFORM_ARM="${MAC_PLATFORM_ARM:-Mac_AppleSilicon}"

# Optional endpoint overrides (because exact upload/create paths are defined in Swagger for your tenant)
PACKAGE_CREATE_PATH_TEMPLATE="${PACKAGE_CREATE_PATH_TEMPLATE:-/packages/{org_id}}"
PACKAGE_UPLOAD_PATH_TEMPLATE="${PACKAGE_UPLOAD_PATH_TEMPLATE:-}"  # if empty, try a set of common candidates

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --client-secret) CLIENT_SECRET="$2"; shift 2 ;;
    --action1-region) ACTION1_REGION="$2"; shift 2 ;;
    --zip-path) ZIP_PATH="$2"; shift 2 ;;
    --log-level) LOG_LEVEL="${2^^}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use --help)" ;;
  esac
done

# Load env (only fills missing vars)
load_env_file "$ENV_FILE"

# Validate required
[[ -n "${CLIENT_ID:-}" ]] || die "--client-id is mandatory"
[[ -n "${CLIENT_SECRET:-}" ]] || die "--client-secret is mandatory"
[[ -n "${ACTION1_REGION:-}" ]] || die "--action1-region is mandatory"
[[ -n "${ZIP_PATH:-}" ]] || die "--zip-path is mandatory"

need_cmd curl
need_cmd osascript

ZIP_PATH="$(abs_path "$ZIP_PATH")"
[[ -f "$ZIP_PATH" ]] || die "Zip file not found: $ZIP_PATH"
[[ "${ZIP_PATH##*.}" == "zip" ]] || die "zip-path must point to a .zip file"

API_HOST="$(region_to_host "$ACTION1_REGION")" || die "Invalid ACTION1_REGION: $ACTION1_REGION"
API_BASE="https://${API_HOST}/api/3.0"
TOKEN_URL="${API_BASE}/oauth2/token"

log INFO "Region: $ACTION1_REGION"
log INFO "API base: $API_BASE"

# Parse APPNAME-VERSION.zip
zip_file="$(basename "$ZIP_PATH")"
zip_stem="${zip_file%.zip}"
version="${zip_stem##*-}"
app_name="${zip_stem%-${version}}"
[[ -n "$app_name" && -n "$version" && "$app_name" != "$zip_stem" ]] || die "Zip name must be APPNAME-VERSION.zip (got: $zip_file)"

log INFO "Detected app: '$app_name'"
log INFO "Detected version: '$version'"

# Auth
get_token "$CLIENT_ID" "$CLIENT_SECRET"

# Get orgs
log INFO "Fetching organizations…"
org_raw="$(
  curl -sS -w $'\n%{http_code}' -X GET "${API_BASE}/organizations" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"
)"
org_code="$(tail -n 1 <<< "$org_raw")"
org_resp="$(sed '$d' <<< "$org_raw")"
log TRACE "Organizations HTTP: $org_code"
log TRACE "Organizations body: $org_resp"
[[ "$org_code" =~ ^2 ]] || die "Failed to fetch organizations (HTTP $org_code). Body: $org_resp"

org_tsv="$(orgs_to_tsv "$org_resp")"
[[ -n "$org_tsv" ]] || die "No orgs parsed from /organizations response. Raw response: $org_resp"

mapfile -t SELECTED_ORG_IDS < <(select_orgs_interactive "$org_tsv")
((${#SELECTED_ORG_IDS[@]} > 0)) || die "No organizations selected."

log INFO "Selected org count: ${#SELECTED_ORG_IDS[@]}"

# Process each org
for org_id in "${SELECTED_ORG_IDS[@]}"; do
  echo
  log INFO "---- Org: $org_id ----"

  # List packages in org (try with extended fields)
  log INFO "Checking existing software repositories/packages for '$app_name'…"
  pkg_resp="$(curl -sS -X GET "${API_BASE}/packages/${org_id}?fields=versions" -H "Authorization: Bearer ${ACCESS_TOKEN}")"

  match="$(packages_find_match "$pkg_resp" "${app_name,,}" || true)"
  pkg_id=""
  pkg_display_name="$app_name"

  if [[ -n "$match" ]]; then
    pkg_id="$(cut -f1 <<< "$match")"
    pkg_display_name="$(cut -f2- <<< "$match")"
    log INFO "Found existing package: '$pkg_display_name' (id: $pkg_id)"
  else
    log WARN "No existing package named '$app_name' found in org $org_id."
    echo
    read -r -p "Create a new repository/package for '$app_name' in this org? [y/N]: " yn
    yn="${yn,,}"
    if [[ "$yn" != "y" && "$yn" != "yes" ]]; then
      log WARN "Skipping org $org_id (no package to upload into)."
      continue
    fi

    # Prompt for minimal metadata
    read -r -p "Publisher/Vendor (optional): " publisher
    read -r -p "Description (optional): " description
    echo "Platform:"
    echo "  1) Intel (${MAC_PLATFORM_INTEL})"
    echo "  2) Apple Silicon (${MAC_PLATFORM_ARM})"
    read -r -p "Choose platform [2]: " plat_choice
    plat_choice="${plat_choice:-2}"
    platform="$MAC_PLATFORM_ARM"
    [[ "$plat_choice" == "1" ]] && platform="$MAC_PLATFORM_INTEL"

    # Best-effort create (endpoint shape may vary by tenant; override via PACKAGE_CREATE_PATH_TEMPLATE if needed)
    create_path="${PACKAGE_CREATE_PATH_TEMPLATE//\{org_id\}/$org_id}"

    # Best-effort body (your Swagger may require additional fields; if so, API will return details)
    create_body="$(cat <<JSON
{
  "name": "$(printf '%s' "$app_name" | /usr/bin/sed 's/"/\\"/g')",
  "publisher": "$(printf '%s' "$publisher" | /usr/bin/sed 's/"/\\"/g')",
  "description": "$(printf '%s' "$description" | /usr/bin/sed 's/"/\\"/g')",
  "platform": "$(printf '%s' "$platform" | /usr/bin/sed 's/"/\\"/g')"
}
JSON
)"

    log INFO "Creating package via POST ${create_path} …"
    # Use curl directly so we can show the raw response if it fails
    create_resp="$(curl -sS -X POST "${API_BASE}${create_path}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$create_body")"

    pkg_id="$(json_get "$create_resp" "id")"
    if [[ -z "$pkg_id" ]]; then
      # Try alternative field names
      pkg_id="$(json_get "$create_resp" "package_id")"
    fi

    [[ -n "$pkg_id" ]] || die "Package create did not return an id. Response: $create_resp"
    log INFO "Created package id: $pkg_id"
  fi

  # Upload new version (best-effort; override via PACKAGE_UPLOAD_PATH_TEMPLATE if your Swagger differs)
  log INFO "Uploading '${zip_file}' as version '${version}' …"

  tried_any=false
  success=false

  if [[ -n "$PACKAGE_UPLOAD_PATH_TEMPLATE" ]]; then
    up_path="$PACKAGE_UPLOAD_PATH_TEMPLATE"
    up_path="${up_path//\{org_id\}/$org_id}"
    up_path="${up_path//\{package_id\}/$pkg_id}"
    up_path="${up_path//\{version\}/$version}"

    tried_any=true
    up_out="$(api_upload_multipart "$up_path" "$ZIP_PATH" "$version")"
    up_code="$(head -n1 <<< "$up_out")"
    up_body="$(tail -n +2 <<< "$up_out")"

    if [[ "$up_code" =~ ^2 ]]; then
      log INFO "Upload succeeded (HTTP $up_code) via $up_path"
      success=true
    else
      log WARN "Upload failed (HTTP $up_code) via $up_path"
      log DEBUG "Response: $up_body"
    fi
  else
    # Try a small set of common candidates (you can add more once you confirm Swagger paths)
    candidates=(
      "/packages/${org_id}/${pkg_id}/versions"
      "/packages/${org_id}/${pkg_id}/versions/${version}"
      "/packages/${org_id}/${pkg_id}/versions/${version}/upload"
      "/packages/${org_id}/${pkg_id}/upload"
      "/packages/${org_id}/${pkg_id}/files"
    )

    for c in "${candidates[@]}"; do
      tried_any=true
      up_out="$(api_upload_multipart "$c" "$ZIP_PATH" "$version")"
      up_code="$(head -n1 <<< "$up_out")"
      up_body="$(tail -n +2 <<< "$up_out")"

      if [[ "$up_code" =~ ^2 ]]; then
        log INFO "Upload succeeded (HTTP $up_code) via $c"
        success=true
        break
      else
        log DEBUG "Upload attempt failed (HTTP $up_code) via $c"
        log TRACE "Response: $up_body"
      fi
    done
  fi

  $tried_any || die "No upload attempts were made (unexpected)."
  $success || die "Upload failed for org $org_id. Check your Swagger paths and set PACKAGE_UPLOAD_PATH_TEMPLATE in .env."
done

log INFO "Done."
