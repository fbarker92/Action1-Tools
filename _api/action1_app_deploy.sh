#!/bin/zsh
set -euo pipefail

#############################################
# action1_app_deploy.sh - clean consolidated
#############################################

# Load .env (simple parser)
dotenv_load() {
  local file="${1:-.env}"
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    local key="${line%%=*}"
    local val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    export "${key}=${val}"
  done < "$file"
}

# Evaluate JS expression against JSON using osascript (macOS)
json_eval() {
  local json="$1" expr="$2"
  /usr/bin/osascript -l JavaScript <<JSC
  const obj = JSON.parse(\`${json//`/\\`}\`);
  const out = (${expr});
  if (typeof out === 'string') console.log(out); else console.log(JSON.stringify(out));
JSC
}

# Minimal in-memory logging
action1_log=""
log_level="${log_level:-INFO}"
get_loglevel(){ case "$1" in ERR) echo 1;; WARN) echo 2;; INFO) echo 3;; DBG) echo 4;; DBG2) echo 5;; *) echo 3;; esac }
log(){ local OPTSTRING="m:n:" opt mesg msg_lev="INFO" time_stamp mesg_out; while getopts ${OPTSTRING} opt; do case ${opt} in m) mesg="${OPTARG}";; n) msg_lev="${OPTARG}";; esac; done; [[ -z "$log_level" ]] && log_level=INFO; if (( $(get_loglevel "$msg_lev") <= $(get_loglevel "$log_level") )); then time_stamp=$(date "+%Y/%m/%d %H:%M:%S%z"); mesg_out=$(printf '%s [%-4s]: %s(): %s' "$time_stamp" "$msg_lev" "${FUNCNAME[1]}" "$mesg"); action1_log=$(printf '%s\n%s' "$action1_log" "$mesg_out"); fi }
print_revision(){ log -m "script revision: 1.0" -n INFO; }
print_diskspace(){ local disksize_Kb freespace_Kb; disksize_Kb=$(df -k / | awk 'NR==2 {print $2}'); freespace_Kb=$(df -k / | awk 'NR==2 {print $4}'); log -m "$(echo "scale=2; $freespace_Kb / 1024 / 1024" | bc) GB free" -n INFO; }
log_started(){ log -m "bash $1 $2" -n INFO; print_revision; print_diskspace; }
log_finished(){ log -m "\"$1\" script finished (exit $2)" -n INFO; }

show_usage(){ cat <<USAGE
Usage: $0 [options] /path/to/APP-version.zip

Options:
  --action1-region REGION   Set ACTION1_REGION (Europe, NorthAmerica, Australia)
  --action1-base-url URL    Set ACTION1_BASE_URL directly
  --zip PATH                Path to APP-version.zip (alternative to positional arg)
  --client-id ID            Set CLIENT_ID
  --client-secret SECRET    Set CLIENT_SECRET
  --upload-chunk-mb N       Set UPLOAD_CHUNK_MB (overrides env)
  --release-date DATE       Set release date (YYYY-MM-DD)
  --notes TEXT             Set release notes
  --update-type TYPE       Set update type
  --cve CVE                Set CVE identifier
  --org-ids IDS            Comma-separated org ids to target
  -h, --help                Show this help
USAGE
}

# CLI parsing
parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action1-region) ACTION1_REGION="$2"; shift 2;;
      --action1-base-url) ACTION1_BASE_URL="$2"; shift 2;;
      --client-id) CLIENT_ID="$2"; shift 2;;
      --client-secret) CLIENT_SECRET="$2"; shift 2;;
      --upload-chunk-mb) UPLOAD_CHUNK_MB="$2"; shift 2;;
      --release-date) RELEASE_DATE="$2"; shift 2;;
      --notes) NOTES="$2"; shift 2;;
      --update-type) UPDATE_TYPE="$2"; shift 2;;
      --cve) CVE="$2"; shift 2;;
      --org-ids) ORG_IDS="$2"; shift 2;;
      --zip) ZIP_PATH="$2"; shift 2;;
      -h|--help) show_usage; exit 0;;
      --) shift; break;;
      -*) echo "Unknown option: $1" >&2; show_usage; exit 2;;
      *) [[ -z "${ZIP_PATH:-}" ]] && ZIP_PATH="$1"; shift;;
    esac
  done
}

require_env(){ [[ -n "${(P)1:-}" ]] || { echo "Missing env var: $1" >&2; exit 1; } }

# API helpers
api_token(){ curl -sS -X POST -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=${CLIENT_ID}" --data-urlencode "client_secret=${CLIENT_SECRET}" "${ACTION1_BASE_URL}/api/3.0/oauth2/token"; }
api_get(){ local path="$1"; curl -sS -X GET -H "Authorization: Bearer ${ACCESS_TOKEN}" "${ACTION1_BASE_URL}${path}"; }
api_post_json(){ local path="$1" json="$2"; curl -sS -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d "$json" "${ACTION1_BASE_URL}${path}"; }

# Orgs
list_orgs(){ api_get "/api/3.0/organizations?per_page=1000"; }
choose_org_ids(){
  local orgs_json="$1" count
  count="$(json_eval "$orgs_json" 'obj.items.length')"
  echo ""; echo "Available organisations:"
  for ((i=0;i<count;i++)); do
    local name id
    name="$(json_eval "$orgs_json" "obj.items[$i].name")"
    id="$(json_eval "$orgs_json" "obj.items[$i].id")"
    echo "[$((i+1))] $name ($id)"
  done
  if [[ -n "${ORG_IDS:-}" ]]; then echo "$ORG_IDS" | tr ',' '\n'; return 0; fi
  if [[ ! -t 0 ]]; then
    if (( count == 1 )); then json_eval "$orgs_json" 'obj.items[0].id'; else json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'; fi
    return 0
  fi
  echo ""; echo "Select org(s): comma-separated numbers, or ALL:"; read -r choice
  if [[ "${choice:u}" == "ALL" ]]; then json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'; return 0; fi
  local -a picks; IFS=',' read -r -A picks <<< "$choice"
  for p in "${picks[@]}"; do p="${p// /}"; local idx=$((p-1)); json_eval "$orgs_json" "obj.items[$idx].id"; done
}

# ZIP parse
parse_zip(){ local zip="$1" base="${zip:t}"; if [[ ! "$base" =~ ^(.+)-([^-]+)\.zip$ ]]; then echo "ZIP must be named APP-version.zip (e.g. Chrome-121.0.0.zip)" >&2; exit 2; fi; APP_NAME="${match[1]}"; APP_VER="${match[2]}"; }

prompt_optional(){ local label="$1" preset="${2:-}"; if [[ -n "$preset" ]]; then echo "$preset"; return 0; fi; if [[ ! -t 0 ]]; then echo ""; return 0; fi; echo -n "${label} (optional, Enter to skip): "; read -r val; echo "$val"; }

# Repo placeholders
repo_find_package_id(){ echo ""; }
repo_create_package(){ echo "TODO_CREATE_PACKAGE_ID"; }
repo_create_version(){ echo "TODO_VERSION_ID"; }
repo_upload_init(){ echo "TODO_UPLOAD_URL"; }

repo_upload_chunks(){
  local upload_url="$1" zip_path="$2" chunk_mb="${UPLOAD_CHUNK_MB:-24}" chunk_bytes=$((chunk_mb*1024*1024)) total_bytes start=0
  total_bytes="$(stat -f%z "$zip_path")"
  while (( start < total_bytes )); do
    local remaining=$((total_bytes-start)) this_chunk=$(( remaining < chunk_bytes ? remaining : chunk_bytes )) end=$((start+this_chunk-1)) tmpfile
    tmpfile="$(mktemp)"
    dd if="$zip_path" of="$tmpfile" bs=1 skip="$start" count="$this_chunk" 2>/dev/null
    curl -sS -X PUT -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/octet-stream" -H "Content-Range: bytes ${start}-${end}/${total_bytes}" --data-binary "@${tmpfile}" "${upload_url}" >/dev/null
    rm -f "$tmpfile"
    start=$((end+1))
  done
}

# MAIN
parse_args "$@"
if [[ -f ".env" ]]; then dotenv_load ".env"; fi
if [[ -z "${ACTION1_BASE_URL:-}" ]]; then
  if [[ -z "${ACTION1_REGION:-}" ]]; then echo "Missing ACTION1_REGION (or set ACTION1_BASE_URL directly or pass via --action1-base-url)" >&2; exit 1; fi
  reg="${ACTION1_REGION//[[:space:]]/}"; reg="${reg:l}"
  case "$reg" in
    europe|eu) ACTION1_BASE_URL="https://app.eu.action1.com/api/3.0";;
    northamerica|north-america|north_america|northameria|na) ACTION1_BASE_URL="https://app.action1.com/api/3.0";;
    australia|austrailia|au) ACTION1_BASE_URL="https://app.au.action1.com/api/3.0";;
    *) echo "Unknown ACTION1_REGION: $ACTION1_REGION" >&2; exit 1;;
  esac
fi
require_env ACTION1_BASE_URL; require_env CLIENT_ID; require_env CLIENT_SECRET
ACTION1_BASE_URL="${ACTION1_BASE_URL%/}"; if [[ "${ACTION1_BASE_URL}" == */api/3.0 ]]; then ACTION1_BASE_URL="${ACTION1_BASE_URL%/api/3.0}"; fi
ZIP_PATH="${ZIP_PATH:-${1:-}}"; [[ -f "$ZIP_PATH" ]] || { echo "Usage: $0 /path/to/APP-version.zip" >&2; exit 2; }
parse_zip "$ZIP_PATH"
printf "Detected:\n  App:     %s\n  Version: %s\n" "$APP_NAME" "$APP_VER"
RELEASE_DATE="$(prompt_optional "Release date (YYYY-MM-DD)" "${RELEASE_DATE:-}")"
NOTES="$(prompt_optional "Notes" "${NOTES:-}")"
UPDATE_TYPE="$(prompt_optional "Update Type" "${UPDATE_TYPE:-}")"
CVE="$(prompt_optional "CVE" "${CVE:-}")"
inv_script="$0"; script_opts="$*"; log_started "$inv_script" "$script_opts"; trap 'rc=$?; log_finished "$inv_script" "$rc"; echo "$action1_log"' EXIT

token_json="$(api_token)"
ACCESS_TOKEN="$(json_eval "$token_json" 'obj.access_token')"
[[ -n "$ACCESS_TOKEN" ]] || { echo "Failed to get access token" >&2; exit 1; }

orgs_json="$(list_orgs)"
org_ids="$(choose_org_ids "$orgs_json")"

printf "\nProcessing organisations...\n"
org_id_list=("${(@f)org_ids}")
for ORG_ID in "${org_id_list[@]}"; do
  [[ -n "$ORG_ID" ]] || continue
  printf "\n== Org: %s ==\n" "$ORG_ID"
  pkg_id="$(repo_find_package_id "$ORG_ID" "$APP_NAME")"
  if [[ -z "$pkg_id" ]]; then
    echo "No repo match for '${APP_NAME}'. Creating…"
    echo -n "Name [${APP_NAME}]: "; read -r NAME; [[ -n "$NAME" ]] || NAME="$APP_NAME"
    echo -n "Vendor: "; read -r VENDOR
    echo -n "Description: "; read -r DESC
    echo -n "Scope: "; read -r SCOPE
    pkg_id="$(repo_create_package "$ORG_ID" "$NAME" "$VENDOR" "$DESC" "$SCOPE")"
  else
    echo "Found package id: $pkg_id"
  fi
  ver_id="$(repo_create_version "$ORG_ID" "$pkg_id" "$APP_VER" "$RELEASE_DATE" "$NOTES" "$UPDATE_TYPE" "$CVE")"
  echo "Created/selected version id: $ver_id"
  total_bytes="$(stat -f%z "$ZIP_PATH")"
  platform="${MAC_PLATFORM:-macos}"
  upload_url="$(repo_upload_init "$pkg_id" "$ver_id" "$total_bytes" "$platform")"
  echo "Upload URL: $upload_url"
  repo_upload_chunks "$upload_url" "$ZIP_PATH"
  echo "Upload complete for org $ORG_ID"
done

echo "\nDone."
#!/bin/zsh
set -euo pipefail
#!/bin/zsh
#!/bin/zsh
set -euo pipefail

#############################################
# action1_app_deploy.sh - consolidated
#############################################

dotenv_load() {
  local file="${1:-.env}"
  #!/bin/zsh
  set -euo pipefail

  #############################################
  # action1_app_deploy.sh - cleaned single-file
  #############################################

  dotenv_load() {
    local file="${1:-.env}"
    [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
    while IFS= read -r line; do
      line="${line#${line%%[![:space:]]*}}"
      line="${line%${line##*[![:space:]]}}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      local key="${line%%=*}"
      local val="${line#*=}"
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      export "${key}=${val}"
    done < "$file"
  }

  json_eval() {
    local json="$1" expr="$2"
    /usr/bin/osascript -l JavaScript <<JSC
    const obj = JSON.parse(\`${json//`/\\`}\`);
    const out = (${expr});
    if (typeof out === 'string') console.log(out); else console.log(JSON.stringify(out));
  JSC
  }

  # Logging helpers
  action1_log=""
  log_level="${log_level:-INFO}"
  get_loglevel(){ case "$1" in ERR) echo 1;; WARN) echo 2;; INFO) echo 3;; DBG) echo 4;; DBG2) echo 5;; *) echo 3;; esac }
  log(){ local OPTSTRING="m:n:" opt mesg msg_lev="INFO" time_stamp mesg_out; while getopts ${OPTSTRING} opt; do case ${opt} in m) mesg="${OPTARG}";; n) msg_lev="${OPTARG}";; esac; done; [[ -z "$log_level" ]] && log_level=INFO; if (( $(get_loglevel "$msg_lev") <= $(get_loglevel "$log_level") )); then time_stamp=$(date "+%Y/%m/%d %H:%M:%S%z"); mesg_out=$(printf '%s [%-4s]: %s(): %s' "$time_stamp" "$msg_lev" "${FUNCNAME[1]}" "$mesg"); action1_log=$(printf '%s\n%s' "$action1_log" "$mesg_out"); fi }
  print_revision(){ log -m "script revision: 1.0" -n INFO; }
  print_diskspace(){ local disksize_Kb freespace_Kb; disksize_Kb=$(df -k / | awk 'NR==2 {print $2}'); freespace_Kb=$(df -k / | awk 'NR==2 {print $4}'); log -m "$(echo "scale=2; $freespace_Kb / 1024 / 1024" | bc) GB free" -n INFO; }
  log_started(){ log -m "bash $1 $2" -n INFO; print_revision; print_diskspace; }
  log_finished(){ log -m "\"$1\" script finished (exit $2)" -n INFO; }

  show_usage(){ cat <<USAGE
  Usage: $0 [options] /path/to/APP-version.zip

  Options:
    --action1-region REGION   Set ACTION1_REGION (Europe, NorthAmerica, Australia)
    --action1-base-url URL    Set ACTION1_BASE_URL directly
    --zip PATH                Path to APP-version.zip (alternative to positional arg)
    --client-id ID            Set CLIENT_ID
    --client-secret SECRET    Set CLIENT_SECRET
    --upload-chunk-mb N       Set UPLOAD_CHUNK_MB (overrides env)
    --release-date DATE       Set release date (YYYY-MM-DD)
    --notes TEXT             Set release notes
    --update-type TYPE       Set update type
    --cve CVE                Set CVE identifier
    --org-ids IDS            Comma-separated org ids to target
    -h, --help                Show this help
  USAGE
  }

  parse_args(){
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --action1-region) ACTION1_REGION="$2"; shift 2;;
        --action1-base-url) ACTION1_BASE_URL="$2"; shift 2;;
        --client-id) CLIENT_ID="$2"; shift 2;;
        --client-secret) CLIENT_SECRET="$2"; shift 2;;
        --upload-chunk-mb) UPLOAD_CHUNK_MB="$2"; shift 2;;
        --release-date) RELEASE_DATE="$2"; shift 2;;
        --notes) NOTES="$2"; shift 2;;
        --update-type) UPDATE_TYPE="$2"; shift 2;;
        --cve) CVE="$2"; shift 2;;
        --org-ids) ORG_IDS="$2"; shift 2;;
        --zip) ZIP_PATH="$2"; shift 2;;
        -h|--help) show_usage; exit 0;;
        --) shift; break;;
        -*) echo "Unknown option: $1" >&2; show_usage; exit 2;;
        *) [[ -z "${ZIP_PATH:-}" ]] && ZIP_PATH="$1"; shift;;
      esac
    done
  }

  require_env(){ [[ -n "${(P)1:-}" ]] || { echo "Missing env var: $1" >&2; exit 1; } }

  api_token(){
    curl -sS -X POST -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=${CLIENT_ID}" --data-urlencode "client_secret=${CLIENT_SECRET}" "${ACTION1_BASE_URL}/api/3.0/oauth2/token"
  }
  api_get(){ local path="$1"; curl -sS -X GET -H "Authorization: Bearer ${ACCESS_TOKEN}" "${ACTION1_BASE_URL}${path}"; }
  api_post_json(){ local path="$1" json="$2"; curl -sS -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d "$json" "${ACTION1_BASE_URL}${path}"; }

  list_orgs(){ api_get "/api/3.0/organizations?per_page=1000"; }

  choose_org_ids(){
    local orgs_json="$1" count
    count="$(json_eval "$orgs_json" 'obj.items.length')"
    echo ""; echo "Available organisations:"
    for ((i=0;i<count;i++)); do
      local name id
      name="$(json_eval "$orgs_json" "obj.items[$i].name")"
      id="$(json_eval "$orgs_json" "obj.items[$i].id")"
      echo "[$((i+1))] $name ($id)"
    done
    if [[ -n "${ORG_IDS:-}" ]]; then echo "$ORG_IDS" | tr ',' '\n'; return 0; fi
    if [[ ! -t 0 ]]; then
      if (( count == 1 )); then json_eval "$orgs_json" 'obj.items[0].id'; else json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'; fi
      return 0
    fi
    echo ""; echo "Select org(s): comma-separated numbers, or ALL:"; read -r choice
    if [[ "${choice:u}" == "ALL" ]]; then json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'; return 0; fi
    local -a picks; IFS=',' read -r -A picks <<< "$choice"
    for p in "${picks[@]}"; do p="${p// /}"; local idx=$((p-1)); json_eval "$orgs_json" "obj.items[$idx].id"; done
  }

  parse_zip(){ local zip="$1" base="${zip:t}"; if [[ ! "$base" =~ ^(.+)-([^-]+)\.zip$ ]]; then echo "ZIP must be named APP-version.zip (e.g. Chrome-121.0.0.zip)" >&2; exit 2; fi; APP_NAME="${match[1]}"; APP_VER="${match[2]}"; }

  prompt_optional(){ local label="$1" preset="${2:-}"; if [[ -n "$preset" ]]; then echo "$preset"; return 0; fi; if [[ ! -t 0 ]]; then echo ""; return 0; fi; echo -n "${label} (optional, Enter to skip): "; read -r val; echo "$val"; }

  # Repo placeholders
  repo_find_package_id(){ echo ""; }
  repo_create_package(){ echo "TODO_CREATE_PACKAGE_ID"; }
  repo_create_version(){ echo "TODO_VERSION_ID"; }
  repo_upload_init(){ echo "TODO_UPLOAD_URL"; }

  repo_upload_chunks(){
    local upload_url="$1" zip_path="$2" chunk_mb="${UPLOAD_CHUNK_MB:-24}" chunk_bytes=$((chunk_mb*1024*1024)) total_bytes start=0
    total_bytes="$(stat -f%z "$zip_path")"
    while (( start < total_bytes )); do
      local remaining=$((total_bytes-start)) this_chunk=$(( remaining < chunk_bytes ? remaining : chunk_bytes )) end=$((start+this_chunk-1)) tmpfile
      tmpfile="$(mktemp)"
      dd if="$zip_path" of="$tmpfile" bs=1 skip="$start" count="$this_chunk" 2>/dev/null
      curl -sS -X PUT -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/octet-stream" -H "Content-Range: bytes ${start}-${end}/${total_bytes}" --data-binary "@${tmpfile}" "${upload_url}" >/dev/null
      rm -f "$tmpfile"
      start=$((end+1))
    done
  }

  # MAIN
  parse_args "$@"
  if [[ -f ".env" ]]; then dotenv_load ".env"; fi
  if [[ -z "${ACTION1_BASE_URL:-}" ]]; then
    if [[ -z "${ACTION1_REGION:-}" ]]; then echo "Missing ACTION1_REGION (or set ACTION1_BASE_URL directly or pass via --action1-base-url)" >&2; exit 1; fi
    reg="${ACTION1_REGION//[[:space:]]/}"; reg="${reg:l}"
    case "$reg" in
      europe|eu) ACTION1_BASE_URL="https://app.eu.action1.com/api/3.0";;
      northamerica|north-america|north_america|northameria|na) ACTION1_BASE_URL="https://app.action1.com/api/3.0";;
      australia|austrailia|au) ACTION1_BASE_URL="https://app.au.action1.com/api/3.0";;
      *) echo "Unknown ACTION1_REGION: $ACTION1_REGION" >&2; exit 1;;
    esac
  fi

  require_env ACTION1_BASE_URL; require_env CLIENT_ID; require_env CLIENT_SECRET
  ACTION1_BASE_URL="${ACTION1_BASE_URL%/}"; if [[ "${ACTION1_BASE_URL}" == */api/3.0 ]]; then ACTION1_BASE_URL="${ACTION1_BASE_URL%/api/3.0}"; fi

  ZIP_PATH="${ZIP_PATH:-${1:-}}"; [[ -f "$ZIP_PATH" ]] || { echo "Usage: $0 /path/to/APP-version.zip" >&2; exit 2; }
  parse_zip "$ZIP_PATH"
  printf "Detected:\n  App:     %s\n  Version: %s\n" "$APP_NAME" "$APP_VER"

  RELEASE_DATE="$(prompt_optional "Release date (YYYY-MM-DD)" "${RELEASE_DATE:-}")"
  NOTES="$(prompt_optional "Notes" "${NOTES:-}")"
  UPDATE_TYPE="$(prompt_optional "Update Type" "${UPDATE_TYPE:-}")"
  CVE="$(prompt_optional "CVE" "${CVE:-}")"

  inv_script="$0"; script_opts="$*"; log_started "$inv_script" "$script_opts"; trap 'rc=$?; log_finished "$inv_script" "$rc"; echo "$action1_log"' EXIT

  token_json="$(api_token)"
  ACCESS_TOKEN="$(json_eval "$token_json" 'obj.access_token')"
  [[ -n "$ACCESS_TOKEN" ]] || { echo "Failed to get access token" >&2; exit 1; }

  orgs_json="$(list_orgs)"
  org_ids="$(choose_org_ids "$orgs_json")"

  printf "\nProcessing organisations...\n"
  org_id_list=("${(@f)org_ids}")
  for ORG_ID in "${org_id_list[@]}"; do
    [[ -n "$ORG_ID" ]] || continue
    printf "\n== Org: %s ==\n" "$ORG_ID"
    pkg_id="$(repo_find_package_id "$ORG_ID" "$APP_NAME")"
    if [[ -z "$pkg_id" ]]; then
      echo "No repo match for '${APP_NAME}'. Creating…"
      echo -n "Name [${APP_NAME}]: "; read -r NAME; [[ -n "$NAME" ]] || NAME="$APP_NAME"
      echo -n "Vendor: "; read -r VENDOR
      echo -n "Description: "; read -r DESC
      echo -n "Scope: "; read -r SCOPE
      pkg_id="$(repo_create_package "$ORG_ID" "$NAME" "$VENDOR" "$DESC" "$SCOPE")"
    else
      echo "Found package id: $pkg_id"
    fi
    ver_id="$(repo_create_version "$ORG_ID" "$pkg_id" "$APP_VER" "$RELEASE_DATE" "$NOTES" "$UPDATE_TYPE" "$CVE")"
    echo "Created/selected version id: $ver_id"
    total_bytes="$(stat -f%z "$ZIP_PATH")"
    platform="${MAC_PLATFORM:-macos}"
    upload_url="$(repo_upload_init "$pkg_id" "$ver_id" "$total_bytes" "$platform")"
    echo "Upload URL: $upload_url"
    repo_upload_chunks "$upload_url" "$ZIP_PATH"
    echo "Upload complete for org $ORG_ID"
  done

  echo "\nDone."

    val="${val%\'}"; val="${val#\'}"
    export "${key}=${val}"
  done < "$file"
}

# Evaluate a JS expression against JSON and print result.
# Usage: json_eval "$json" 'obj.items.length'
json_eval() {
  local json="$1"
  local expr="$2"
  /usr/bin/osascript -l JavaScript <<JSC
  const obj = JSON.parse(\`${json//`/\\`}\`);
  const out = (${expr});
  if (typeof out === "string") console.log(out);
  else console.log(JSON.stringify(out));
JSC
}

show_usage() {
  cat <<USAGE
Usage: $0 [options] /path/to/APP-version.zip

Options:
  --action1-region REGION   Set ACTION1_REGION (Europe, NorthAmerica, Australia)
  --action1-base-url URL    Set ACTION1_BASE_URL directly
  --zip PATH                Path to APP-version.zip (alternative to positional arg)
  --client-id ID            Set CLIENT_ID
  --client-secret SECRET    Set CLIENT_SECRET
  --upload-chunk-mb N       Set UPLOAD_CHUNK_MB (overrides env)
  -h, --help                Show this help
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action1-region)
        ACTION1_REGION="$2"; shift 2 ;;
      --action1-base-url)
        ACTION1_BASE_URL="$2"; shift 2 ;;
      --client-id)
        CLIENT_ID="$2"; shift 2 ;;
      --client-secret)
        CLIENT_SECRET="$2"; shift 2 ;;
      --upload-chunk-mb)
        UPLOAD_CHUNK_MB="$2"; shift 2 ;;
      --zip)
        ZIP_PATH="$2"; shift 2 ;;
      -h|--help)
        show_usage; exit 0 ;;
      --)
        shift; break ;;
      -*)
        echo "Unknown option: $1" >&2; show_usage; exit 2 ;;
      *)
        if [[ -z "${ZIP_PATH:-}" ]]; then
          ZIP_PATH="$1"
        fi
        shift ;;
    esac
  done
}

#############################################
# HTTP helpers
#############################################

require_env() { [[ -n "${(P)1:-}" ]] || { echo "Missing env var: $1" >&2; exit 1; } }

api_token() {
  curl -sS -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    "${ACTION1_BASE_URL}/oauth2/token"
}

api_get() {
  local path="$1"
  curl -sS -X GET \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${ACTION1_BASE_URL}${path}"
}

api_post_json() {
  local path="$1"
  local json="$2"
  curl -sS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$json" \
    "${ACTION1_BASE_URL}${path}"
}

#############################################
# Org selection
#############################################

list_orgs() {
  api_get "/api/3.0/organizations"
}

choose_org_ids() {
  local orgs_json="$1"
  local count
  count="$(json_eval "$orgs_json" 'obj.items.length')"

  # If ORG_IDS provided (env or CLI), use it. Accept comma-separated IDs.
  if [[ -n "${ORG_IDS:-}" ]]; then
    echo "$ORG_IDS" | tr ',' '\n'
    return 0
  fi

  echo ""
  echo "Available organisations:"
  for ((i=0; i<count; i++)); do
    local name id
    name="$(json_eval "$orgs_json" "obj.items[$i].name")"
    id="$(json_eval "$orgs_json" "obj.items[$i].id")"
    echo "[$((i+1))] $name ($id)"
  done

  # If non-interactive, auto-select: single org -> that id, multiple -> ALL
  if [[ ! -t 0 ]]; then
    if (( count == 1 )); then
      json_eval "$orgs_json" 'obj.items[0].id'
    else
      json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'
    fi
    return 0
  fi

  echo ""
  echo "Select org(s): comma-separated numbers, or ALL:"
  read -r choice

  if [[ "${choice:u}" == "ALL" ]]; then
    json_eval "$orgs_json" 'obj.items.map(x => x.id).join("\n")'
    return
  fi

  local -a picks
  IFS=',' read -r -A picks <<< "$choice"
  for p in "${picks[@]}"; do
    p="${p// /}"
    local idx=$((p-1))
    json_eval "$orgs_json" "obj.items[$idx].id"
  done
}

#############################################
# ZIP parsing (APP-version.zip)
#############################################

parse_zip() {
  local zip="$1"
  local base="${zip:t}"
  if [[ ! "$base" =~ ^(.+)-([^-]+)\.zip$ ]]; then
    echo "ZIP must be named APP-version.zip (e.g. Chrome-121.0.0.zip)" >&2
    exit 2
  fi
  APP_NAME="${match[1]}"
  APP_VER="${match[2]}"
}

prompt_optional() {
  local label="$1"
  echo -n "${label} (optional, Enter to skip): "
  read -r val
  echo "$val"
}

#############################################
# Software repo / version / upload hooks
#############################################

# Return package id if found, else empty
repo_find_package_id() {
  local org_id="$1"
  local app_name="$2"
  echo ""
}

# Create repository package and echo new package_id
repo_create_package() {
  local org_id="$1"
  local name="$2"
  local vendor="$3"
  local desc="$4"
  local scope="$5"
  echo "TODO_CREATE_PACKAGE_ID"
}

# Create a version and echo new version_id
repo_create_version() {
  local org_id="$1"
  local package_id="$2"
  local version="$3"
  local release_date="$4"
  local notes="$5"
  local update_type="$6"
  local cve="$7"

  local payload
  payload="$(/usr/bin/osascript -l JavaScript <<JSC
  const obj = { version: ${version:json} };
  const add = (k,v)=>{ if (v && String(v).trim()!="") obj[k]=v; };
  add("release_date", ${release_date:json});
  add("notes", ${notes:json});
  add("update_type", ${update_type:json});
  add("cve", ${cve:json});
  console.log(JSON.stringify(obj));
JSC
)"

  echo "TODO_VERSION_ID"
}

# Start upload; echo upload URL/location
repo_upload_init() {
  local package_id="$1"
  local version_id="$2"
  local total_bytes="$3"
  local platform="$4"
  echo "TODO_UPLOAD_URL"
}

# Upload in chunks using Content-Range
repo_upload_chunks() {
  local upload_url="$1"
  local zip_path="$2"

  local chunk_mb="${UPLOAD_CHUNK_MB:-24}"
  local chunk_bytes=$((chunk_mb * 1024 * 1024))
  local total_bytes
  total_bytes="$(stat -f%z "$zip_path")"

  local start=0
  while (( start < total_bytes )); do
    local remaining=$((total_bytes - start))
    local this_chunk=$(( remaining < chunk_bytes ? remaining : chunk_bytes ))
    local end=$((start + this_chunk - 1))

    local tmpfile
    tmpfile="$(mktemp)"
    dd if="$zip_path" of="$tmpfile" bs=1 skip="$start" count="$this_chunk" 2>/dev/null

    curl -sS -X PUT \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/octet-stream" \
      -H "Content-Range: bytes ${start}-${end}/${total_bytes}" \
      --data-binary "@${tmpfile}" \
      "${upload_url}" >/dev/null

    rm -f "$tmpfile"
    start=$((end + 1))
  done
}

#############################################
# MAIN
#############################################

# parse CLI args first (so CLI can override .env)
parse_args "$@"

# Load .env if present (do not fail if it's missing; CLI args may provide needed values)
if [[ -f ".env" ]]; then
  dotenv_load ".env"
fi

# Derive ACTION1_BASE_URL from ACTION1_REGION if not already set.
if [[ -z "${ACTION1_BASE_URL:-}" ]]; then
  if [[ -z "${ACTION1_REGION:-}" ]]; then
    echo "Missing ACTION1_REGION (or set ACTION1_BASE_URL directly or pass via --action1-base-url)" >&2
    exit 1
  fi
  reg="${ACTION1_REGION//[[:space:]]/}"
  reg="${reg:l}"
  case "$reg" in
    europe|eu)
      ACTION1_BASE_URL="https://app.eu.action1.com/api/3.0" ;;
    northamerica|north-america|north_america|northameria|na)
      ACTION1_BASE_URL="https://app.action1.com/api/3.0" ;;
    australia|austrailia|au)
      ACTION1_BASE_URL="https://app.au.action1.com/api/3.0" ;;
    *)
      echo "Unknown ACTION1_REGION: $ACTION1_REGION" >&2
      exit 1 ;;
  esac
fi

require_env ACTION1_BASE_URL
require_env CLIENT_ID
require_env CLIENT_SECRET

# Normalize ACTION1_BASE_URL: remove trailing slash and optional /api/3.0 suffix
ACTION1_BASE_URL="${ACTION1_BASE_URL%/}"
if [[ "${ACTION1_BASE_URL}" == */api/3.0 ]]; then
  ACTION1_BASE_URL="${ACTION1_BASE_URL%/api/3.0}"
fi

# ZIP path: prefer explicit flag/var, then positional
ZIP_PATH="${ZIP_PATH:-${1:-}}"
[[ -f "$ZIP_PATH" ]] || { echo "Usage: $0 /path/to/APP-version.zip" >&2; exit 2; }

parse_zip "$ZIP_PATH"
echo "Detected:"
echo "  App:     $APP_NAME"
echo "  Version: $APP_VER"

RELEASE_DATE="$(prompt_optional "Release date (YYYY-MM-DD)")"
NOTES="$(prompt_optional "Notes")"
UPDATE_TYPE="$(prompt_optional "Update Type")"
CVE="$(prompt_optional "CVE")"

# Initialize logging and register exit handler
inv_script="$0"
script_opts="$*"
log_started "$inv_script" "$script_opts"
trap 'rc=$?; log_finished "$inv_script" "$rc"; echo "$action1_log"' EXIT

# Token
token_json="$(api_token)"
ACCESS_TOKEN="$(json_eval "$token_json" 'obj.access_token')"
[[ -n "$ACCESS_TOKEN" ]] || { echo "Failed to get access token" >&2; exit 1; }

# Orgs
orgs_json="$(list_orgs)"
org_ids="$(choose_org_ids "$orgs_json")"

# Process each org
echo ""
echo "Processing organisations..."
echo "$org_ids" | while IFS= read -r ORG_ID; do
  [[ -n "$ORG_ID" ]] || continue
  echo ""
  echo "== Org: $ORG_ID =="

  pkg_id="$(repo_find_package_id "$ORG_ID" "$APP_NAME")"
  if [[ -z "$pkg_id" ]]; then
    echo "No repo match for '${APP_NAME}'. Creating…"
    if [[ -t 0 ]]; then
      echo -n "Name [${APP_NAME}]: "; read -r NAME; [[ -n "$NAME" ]] || NAME="$APP_NAME"
      echo -n "Vendor: "; read -r VENDOR
      echo -n "Description: "; read -r DESC
      echo -n "Scope: "; read -r SCOPE
    else
      NAME="$APP_NAME"
      VENDOR=""
      DESC=""
      SCOPE=""
    fi

    pkg_id="$(repo_create_package "$ORG_ID" "$NAME" "$VENDOR" "$DESC" "$SCOPE")"
  else
    echo "Found package id: $pkg_id"
  fi

  ver_id="$(repo_create_version "$ORG_ID" "$pkg_id" "$APP_VER" "$RELEASE_DATE" "$NOTES" "$UPDATE_TYPE" "$CVE")"
  echo "Created/selected version id: $ver_id"

  total_bytes="$(stat -f%z "$ZIP_PATH")"
  platform="${MAC_PLATFORM:-macos}"

  upload_url="$(repo_upload_init "$pkg_id" "$ver_id" "$total_bytes" "$platform")"
  echo "Upload URL: $upload_url"
  repo_upload_chunks "$upload_url" "$ZIP_PATH"

  echo "Upload complete for org $ORG_ID"
done

echo ""
echo "Done."
