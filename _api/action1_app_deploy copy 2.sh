#!/usr/bin/env bash
# Action1 Software Repository uploader (macOS native: bash/zsh + curl + osascript)
# - Reads defaults from .env
# - CLI args override .env
# - Detects APPNAME + VERSION from APPNAME-VERSION.zip
# - Fetches orgs; interactive select one/many/all
# - For each org: find or create Software Repository package, then upload a new version
#
# IMPORTANT:
# - Uses Action1 endpoints:
#     POST /software-repository/{orgId}
#     POST /software-repository/{orgId}/{packageId}/versions
# - JSON parsing is done via osascript (JXA), writing to stdout (safe for command substitution)

set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Logging
# -------------------------
LOG_LEVEL="${LOG_LEVEL:-INFO}" # ERROR|WARN|INFO|DEBUG|TRACE
lvl_num() {
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
  local cur; cur="$(lvl_num "$LOG_LEVEL")"
  local want; want="$(lvl_num "$lvl")"
  if (( want <= cur )); then
    printf '[%s] %s\n' "$lvl" "$*" >&2
  fi
}
die() { log ERROR "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then printf '%s' "$p"; else printf '%s/%s' "$(pwd)" "$p"; fi
}

# -------------------------
# .env loader (supports inline comments and quoted values)
# -------------------------
strip_quotes() {
  local s; s="$(trim "$1")"
  if [[ "$s" =~ ^\".*\"$ ]]; then s="${s:1:${#s}-2}"; fi
  if [[ "$s" =~ ^\'.*\'$ ]]; then s="${s:1:${#s}-2}"; fi
  printf '%s' "$s"
}

load_env_file() {
  local env_path="$1"
  [[ -f "$env_path" ]] || return 0
  log DEBUG "Loading .env from: $env_path"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local k="${BASH_REMATCH[1]}"
      local v="${BASH_REMATCH[2]}"

      # If unquoted, strip inline comments
      if [[ ! "$v" =~ ^[\"\'] ]]; then
        v="${v%%\#*}"
      fi

      v="$(strip_quotes "$v")"
      export "$k=$v"
    fi
  done <"$env_path"
}

# -------------------------
# JXA JSON helpers (stdout-safe via NSFileHandle)
# -------------------------
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

// last 2 args are payload + path
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

orgs_to_tsv() {
  # Usage: orgs_to_tsv "<json>"
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

function pickArray(obj) {
  if (Array.isArray(obj)) return obj;
  if (Array.isArray(obj.items)) return obj.items;
  if (Array.isArray(obj.data)) return obj.data;
  if (Array.isArray(obj.organizations)) return obj.organizations;
  if (Array.isArray(obj.orgs)) return obj.orgs;
  return [];
}

function pickId(o) {
  return o.orgId || o.organizationId || o.organizationID || o.orgID ||
         o.id || o.organization_id || o.org_id || '';
}

function pickName(o) {
  return o.name || o.orgName || o.organizationName || o.organization_name ||
         o.title || o.displayName || o.display_name || '';
}

try {
  const obj = JSON.parse(input);
  const arr = pickArray(obj);
  for (const o of arr) {
    const id = pickId(o);
    const name = pickName(o);
    if (id && name) writeln(id + "\t" + name);
  }
} catch (e) {}
JSCODE
}

packages_find_id_by_name() {
  # Usage: packages_find_id_by_name "<json>" "<app_name>"
  local json="$1"
  local app_name="$2"

  /usr/bin/osascript -l JavaScript - "$json" "$app_name" <<'JSCODE'
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
const want  = ObjC.unwrap(args.objectAtIndex(argc - 1));

function pickArray(obj) {
  if (Array.isArray(obj)) return obj;
  if (Array.isArray(obj.items)) return obj.items;
  if (Array.isArray(obj.data)) return obj.data;
  if (Array.isArray(obj.packages)) return obj.packages;
  return [];
}

function pickId(o) {
  return o.packageId || o.id || o.pkg_id || o.package_id || '';
}
function pickName(o) {
  return o.name || o.title || o.displayName || o.display_name || '';
}

try {
  const obj = JSON.parse(input);
  const arr = pickArray(obj);
  const hit = arr.find(p => (pickName(p) === want));
  writeln(hit ? pickId(hit) : '');
} catch (e) {
  writeln('');
}
JSCODE
}

# -------------------------
# Region → base URL
# -------------------------
region_to_api_base() {
  case "$1" in
    Europe)       echo "https://app.eu.action1.com/api/3.0" ;;
    NorthAmerica) echo "https://app.action1.com/api/3.0" ;;
    Australia)    echo "https://app.au.action1.com/api/3.0" ;;
    *) return 1 ;;
  esac
}

# -------------------------
# HTTP helpers
# -------------------------
curl_json() {
  # curl_json METHOD URL [DATA]
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"

  if [[ -n "$data" ]]; then
    curl -sS -L -X "$method" "$url" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -sS -L -X "$method" "$url" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Accept: application/json"
  fi
}

curl_multipart() {
  # curl_multipart URL zip_path version
  local url="$1"
  local zip_path="$2"
  local version="$3"

  curl -sS -L -X POST "$url" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/json" \
    -F "version=${version}" \
    -F "file=@${zip_path};type=application/zip"
}

# -------------------------
# Args + env
# -------------------------
ENV_FILE=".env"

ACTION1_REGION="${ACTION1_REGION:-}"
CLIENT_ID="${CLIENT_ID:-}"
CLIENT_SECRET="${CLIENT_SECRET:-}"

UPLOAD_CHUNK_MB="${UPLOAD_CHUNK_MB:-24}"
MAC_PLATFORM_INTEL="${MAC_PLATFORM_INTEL:-Mac_Intel}"
MAC_PLATFORM_ARM="${MAC_PLATFORM_ARM:-Mac_AppleSilicon}"

ZIP_PATH=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") \\
    --client-id <id> \\
    --client-secret <secret> \\
    --action1-region <Europe|NorthAmerica|Australia> \\
    --zip-path <APPNAME-VERSION.zip> \\
    [--env <path-to-.env>] \\
    [--log-level <ERROR|WARN|INFO|DEBUG|TRACE>]

Notes:
- CLI args override .env values.
- Package create: POST /software-repository/{orgId}
- Upload version: POST /software-repository/{orgId}/{packageId}/versions
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --client-secret) CLIENT_SECRET="$2"; shift 2 ;;
    --action1-region) ACTION1_REGION="$2"; shift 2 ;;
    --zip-path) ZIP_PATH="$2"; shift 2 ;;
    --log-level) LOG_LEVEL="${2^^}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

load_env_file "$ENV_FILE"

# CLI overrides env (already set above). Validate required:
[[ -n "${CLIENT_ID:-}" ]] || die "--client-id is mandatory"
[[ -n "${CLIENT_SECRET:-}" ]] || die "--client-secret is mandatory"
[[ -n "${ACTION1_REGION:-}" ]] || die "--action1-region is mandatory"
[[ -n "${ZIP_PATH:-}" ]] || die "--zip-path is mandatory"

need_cmd curl
need_cmd osascript

ZIP_PATH="$(abs_path "$ZIP_PATH")"
[[ -f "$ZIP_PATH" ]] || die "Zip file not found: $ZIP_PATH"
[[ "${ZIP_PATH##*.}" == "zip" ]] || die "zip-path must point to a .zip file"

API_BASE="$(region_to_api_base "$ACTION1_REGION")" || die "Invalid ACTION1_REGION: $ACTION1_REGION"

log INFO "Region: $ACTION1_REGION"
log INFO "API base: $API_BASE"

# Detect APPNAME-VERSION.zip
zip_file="$(basename "$ZIP_PATH")"
zip_stem="${zip_file%.zip}"
version="${zip_stem##*-}"
app_name="${zip_stem%-${version}}"
[[ -n "$app_name" && -n "$version" && "$app_name" != "$zip_stem" ]] || die "Zip name must be APPNAME-VERSION.zip (got: $zip_file)"

log INFO "Detected app: '$app_name'"
log INFO "Detected version: '$version'"

# -------------------------
# Auth
# -------------------------
TOKEN_URL="${API_BASE}/oauth2/token"
log INFO "Authenticating (OAuth2 client_credentials)…"
log DEBUG "Token URL: $TOKEN_URL"

token_raw="$(
  curl -sS -L -w $'\n%{http_code}' -X POST "$TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "grant_type=client_credentials"
)"
token_http="$(tail -n 1 <<< "$token_raw")"
token_body="$(sed '$d' <<< "$token_raw")"
log TRACE "Token HTTP: $token_http"
log TRACE "Token body: $token_body"
[[ "$token_http" =~ ^2 ]] || die "Token request failed (HTTP $token_http). Body: $token_body"

ACCESS_TOKEN="$(json_get "$token_body" "access_token")"
[[ -n "$ACCESS_TOKEN" ]] || die "Failed to obtain access_token. Body: $token_body"
log DEBUG "Access token acquired."

# -------------------------
# Fetch orgs + interactive selection
# -------------------------
log INFO "Fetching organizations…"
org_raw="$(
  curl -sS -L -w $'\n%{http_code}' -X GET "${API_BASE}/organizations" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/json"
)"
org_code="$(tail -n 1 <<< "$org_raw")"
org_resp="$(sed '$d' <<< "$org_raw")"
log TRACE "Organizations HTTP: $org_code"
log TRACE "Organizations body: $org_resp"
[[ "$org_code" =~ ^2 ]] || die "Failed to fetch organizations (HTTP $org_code). Body: $org_resp"

org_tsv="$(orgs_to_tsv "$org_resp")"
[[ -n "$org_tsv" ]] || die "No orgs parsed from /organizations response. Raw response: $org_resp"

# Build arrays
ids=()
names=()
while IFS=$'\t' read -r oid oname; do
  ids+=("$oid")
  names+=("$oname")
done <<< "$org_tsv"
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

SELECTED_ORG_IDS=()
if [[ "$choice" == "0" || "${choice,,}" == "all" ]]; then
  SELECTED_ORG_IDS=("${ids[@]}")
else
  IFS=',' read -r -a picks <<< "$choice"
  for p in "${picks[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || die "Invalid selection token: $p"
    idx=$((p-1))
    (( idx >= 0 && idx < ${#ids[@]} )) || die "Selection out of range: $p"
    SELECTED_ORG_IDS+=("${ids[$idx]}")
  done
fi

# De-dupe + sanity check
uniq=()
seen="|"
for x in "${SELECTED_ORG_IDS[@]}"; do
  [[ -n "$x" ]] || die "Selected org id is blank (org parsing issue)."
  if [[ "$seen" != *"|$x|"* ]]; then
    uniq+=("$x")
    seen="${seen}${x}|"
  fi
done
SELECTED_ORG_IDS=("${uniq[@]}")

log INFO "Selected org count: ${#SELECTED_ORG_IDS[@]}"

# -------------------------
# Per org: find/create package then upload version
# -------------------------
for org_id in "${SELECTED_ORG_IDS[@]}"; do
  echo
  log INFO "---- Org: $org_id ----"

  # List packages in software repository for org
  log INFO "Checking existing software repository packages for '$app_name'…"
  pkgs_resp="$(curl_json GET "${API_BASE}/software-repository/${org_id}")"
  pkg_id="$(packages_find_id_by_name "$pkgs_resp" "$app_name")"

  if [[ -n "$pkg_id" ]]; then
    log INFO "Found existing package '$app_name' (id: $pkg_id)"
  else
    log WARN "No existing package named '$app_name' found in org $org_id."
    echo
    read -r -p "Create a new repository/package for '$app_name' in this org? [y/N]: " yn
    yn="${yn,,}"
    if [[ "$yn" != "y" && "$yn" != "yes" ]]; then
      log WARN "Skipping org $org_id (no package to upload into)."
      continue
    fi

    read -r -p "Publisher/Vendor (optional): " publisher
    read -r -p "Description (optional): " description

    echo "Platform:"
    echo "  1) Intel (${MAC_PLATFORM_INTEL})"
    echo "  2) Apple Silicon (${MAC_PLATFORM_ARM})"
    read -r -p "Choose platform [2]: " plat_choice
    plat_choice="${plat_choice:-2}"
    platform="$MAC_PLATFORM_ARM"
    [[ "$plat_choice" == "1" ]] && platform="$MAC_PLATFORM_INTEL"

    create_body="$(cat <<JSON
{
  "name": "$(printf '%s' "$app_name" | sed 's/"/\\"/g')",
  "publisher": "$(printf '%s' "$publisher" | sed 's/"/\\"/g')",
  "description": "$(printf '%s' "$description" | sed 's/"/\\"/g')",
  "platform": "$(printf '%s' "$platform" | sed 's/"/\\"/g')"
}
JSON
)"

    log INFO "Creating package via POST /software-repository/{orgId} …"
    create_resp="$(curl_json POST "${API_BASE}/software-repository/${org_id}" "$create_body")"
    log TRACE "Create package response: $create_resp"

    # Try likely id keys
    pkg_id="$(json_get "$create_resp" "packageId")"
    [[ -n "$pkg_id" ]] || pkg_id="$(json_get "$create_resp" "id")"

    [[ -n "$pkg_id" ]] || die "Package create did not return an id. Response: $create_resp"
    log INFO "Created package id: $pkg_id"
  fi

  # Upload version
  log INFO "Uploading '${zip_file}' as version '${version}' …"
  upload_url="${API_BASE}/software-repository/${org_id}/${pkg_id}/versions"
  log DEBUG "Upload URL: $upload_url"

  upload_resp="$(curl_multipart "$upload_url" "$ZIP_PATH" "$version")"
  log TRACE "Upload response: $upload_resp"

  # Try likely version id keys (may vary)
  ver_id="$(json_get "$upload_resp" "versionId")"
  [[ -n "$ver_id" ]] || ver_id="$(json_get "$upload_resp" "id")"

  if [[ -n "$ver_id" ]]; then
    log INFO "Uploaded new version successfully (version id: $ver_id)"
  else
    log WARN "Upload response did not include a version id. Response: $upload_resp"
    log WARN "If your tenant requires an upload-session/chunked workflow, paste this response and I’ll tailor the upload step."
  fi
done

log INFO "Done."
