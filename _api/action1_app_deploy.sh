#!/bin/zsh
set -eo pipefail
IFS=$'\n\t'
set +x
set +v

###############################################################################
# Action1 Software Repository Uploader
###############################################################################

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

#############################################
# Logging
#############################################
typeset -A _LV
_LV=(TRACE 0 DEBUG 1 INFO 2 WARN 3 ERROR 4 SILENT 5)
LOG_LEVEL="${LOG_LEVEL:-SILENT}"

_log_ok() {
  local want="${_LV[$1]:-2}"
  local cur="${_LV[$LOG_LEVEL]:-5}"
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
# Globals
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
  local var="$1" title="$2"
  shift 2
  local -a opts=("$@")

  print -r -- "" >&2
  print -r -- "$title" >&2
  local i=1
  for o in "${opts[@]}"; do
    print -r -- "  $i) $o" >&2
    ((i++))
  done

  local pick=""
  while true; do
    vared -p "Select (1-${#opts[@]}): " pick
    pick="$(trim "$pick")"
    [[ "$pick" == <-> ]] || { print -r -- "Enter a number." >&2; continue; }
    (( pick>=1 && pick<=${#opts[@]} )) || { print -r -- "Out of range." >&2; continue; }
    typeset -g "$var=${opts[$pick]}"
    return 0
  done
}

#############################################
# .env loader
#############################################
dotenv_load() {
  local file="${1:-.env}"
  [[ -f "$file" ]] || return 0
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

    [[ "$key" == "PATH" ]] && continue

    if [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val#\'}"; val="${val%\'}"
    elif [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val#\"}"; val="${val%\"}"
    fi

    export "$key=$val"
  done < "$file"
}

#############################################
# Utils
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
# API helper
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

#############################################
# Authentication
#############################################
auth() {
  prompt_required ACTION1_CLIENT_ID "ACTION1_CLIENT_ID (Client ID)"
  prompt_secret   ACTION1_CLIENT_SECRET "ACTION1_CLIENT_SECRET (Client Secret)"

  local payload
  payload="$(jq -nc --arg id "$ACTION1_CLIENT_ID" --arg sec "$ACTION1_CLIENT_SECRET" \
    '{client_id:$id, client_secret:$sec}')"

  log INFO "Authenticating..."
  TOKEN=""
  api_json POST "/oauth2/token" "$payload"

  log DEBUG "Auth HTTP code: ${REQ_CODE:-}"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Auth failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  TOKEN="$(print -r -- "$REQ_BODY" | jq -r '.access_token // empty')"
  [[ -n "$TOKEN" ]] || die "Auth failed: access_token missing. Body: $REQ_BODY"
  log INFO "Authentication successful"
}

#############################################
# Organizations
#############################################
get_orgs() {
  api_json GET "/organizations"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Failed to list orgs (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"
}

choose_org() {
  get_orgs
  local count
  count="$(print -r -- "$REQ_BODY" | jq -r '.items | length')"
  (( count > 0 )) || die "No organizations found."

  if (( count == 1 )); then
    ORG_ID="$(print -r -- "$REQ_BODY" | jq -r '.items[0].id')"
    ORG_NAME="$(print -r -- "$REQ_BODY" | jq -r '.items[0].name')"
    log INFO "Using organization: $ORG_NAME"
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
    vared -p "Select organization: " sel
    sel="$(trim "$sel")"
    [[ "$sel" == <-> ]] || { print -r -- "Enter a number." >&2; continue; }
    
    local result
    result="$(print -r -- "$REQ_BODY" | jq -r --arg idx "$sel" '.items[($idx|tonumber)-1] | "\(.id)\t\(.name)"')"
    [[ "$result" != "null" && -n "$result" ]] || { print -r -- "Invalid selection." >&2; continue; }
    
    ORG_ID="${result%%$'\t'*}"
    ORG_NAME="${result#*$'\t'}"
    break
  done
}

#############################################
# Software Repository
#############################################
list_custom_repos() {
  local org_id="$1"
  log INFO "Fetching custom software repositories..."
  api_json GET "/software-repository/${org_id}?custom=yes&builtin=no&limit=100"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Failed to list repos (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"
}

create_repo() {
  local org_id="$1"
  
  print -r -- "" >&2
  log INFO "Creating new software repository..."
  
  prompt_required REPO_NAME "Repository name"
  prompt_required REPO_VENDOR "Vendor name"
  prompt_required REPO_DESC "Description"
  prompt_required REPO_NOTES "Internal notes" ""
  
  local platform_choice
  prompt_menu platform_choice "Select platform" "Mac" "Windows" "Linux"
  
  local payload
  payload="$(jq -nc \
    --arg name "$REPO_NAME" \
    --arg vendor "$REPO_VENDOR" \
    --arg desc "$REPO_DESC" \
    --arg notes "$REPO_NOTES" \
    --arg platform "$platform_choice" \
    '{name:$name, vendor:$vendor, description:$desc, internal_notes:$notes, platform:$platform}')"

  api_json POST "/software-repository/${org_id}" "$payload"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Repo create failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  local id; id="$(print -r -- "$REQ_BODY" | jq -r '.id // empty')"
  [[ -n "$id" ]] || die "Repo create returned no id. Body: $REQ_BODY"
  log INFO "Created repository: $REPO_NAME (ID: $id)"
  print -r -- "$id"
}

select_or_create_repo() {
  local org_id="$1"
  
  list_custom_repos "$org_id"
  
  local count
  count="$(print -r -- "$REQ_BODY" | jq -r '.items | length')"
  
  if (( count == 0 )); then
    log WARN "No custom repositories found."
    REPO_ID="$(create_repo "$org_id")"
    return 0
  fi
  
  print -r -- "" >&2
  print -r -- "Existing Custom Repositories:" >&2
  local i=1
  print -r -- "$REQ_BODY" | jq -r '.items[] | "\(.name) (\(.vendor)) - \(.platform)\t\(.id)"' | while IFS=$'\t' read -r name id; do
    print -r -- "  $i) $name" >&2
    ((i++))
  done
  print -r -- "  $((count+1))) Create new repository" >&2
  
  local sel=""
  while true; do
    vared -p "Select option (1-$((count+1))): " sel
    sel="$(trim "$sel")"
    [[ "$sel" == <-> ]] || { print -r -- "Enter a number." >&2; continue; }
    (( sel>=1 && sel<=$((count+1)) )) || { print -r -- "Out of range." >&2; continue; }
    
    if (( sel == count+1 )); then
      REPO_ID="$(create_repo "$org_id")"
      return 0
    else
      REPO_ID="$(print -r -- "$REQ_BODY" | jq -r --arg idx "$sel" '.items[($idx|tonumber)-1].id')"
      [[ -n "$REPO_ID" && "$REPO_ID" != "null" ]] || { print -r -- "Invalid selection." >&2; continue; }
      local repo_name
      repo_name="$(print -r -- "$REQ_BODY" | jq -r --arg idx "$sel" '.items[($idx|tonumber)-1].name')"
      log INFO "Selected repository: $repo_name (ID: $REPO_ID)"
      break
    fi
  done
}

#############################################
# Version Management (UPDATED)
#############################################
create_version() {
  local org_id="$1" pkg_id="$2" file_name="$3"
  
  print -r -- "" >&2
  log INFO "Creating new version..."
  
  # Required fields
  prompt_required VERSION_NUM "Version number"
  prompt_required APP_NAME_MATCH "App name match (regex)" "^AppName$"
  
  local release_date
  release_date="$(date +%F)"
  prompt_required RELEASE_DATE "Release date (YYYY-MM-DD)" "$release_date"
  
  # Determine platform and install_type based on file extension
  local upload_platform install_type
  if [[ "$file_name" == *.zip ]]; then
    prompt_menu upload_platform "Select Mac platform" "Mac_AppleSilicon" "Mac_IntelCPU"
    install_type="macOS"
  elif [[ "$file_name" == *.msi ]]; then
    prompt_menu upload_platform "Select Windows platform" "Windows_64" "Windows_32" "Windows_ARM64"
    install_type="MSI"
  elif [[ "$file_name" == *.exe ]]; then
    prompt_menu upload_platform "Select Windows platform" "Windows_64" "Windows_32" "Windows_ARM64"
    install_type="EXE"
  else
    die "Unsupported file type. Use .zip for Mac or .msi/.exe for Windows"
  fi
  
  # Operating systems (required array)
  local os_input os_list
  if [[ "$install_type" == "macOS" ]]; then
    local default_os="macOS Tahoe,macOS Sequoia,macOS Sonoma,macOS Ventura,macOS Monterey,macOS"
    prompt_required os_input "Supported OS (comma-separated)" "$default_os"
  else
    local default_os="Windows 11,Windows 10,Windows"
    prompt_required os_input "Supported OS (comma-separated)" "$default_os"
  fi
  os_list="$(print -r -- "$os_input" | python3 -c "import sys,json; print(json.dumps([x.strip() for x in sys.stdin.read().split(',') if x.strip()]))")"

  # Exit codes
  prompt_required SUCCESS_EXIT_CODES "Success exit codes (comma-separated)" "0"
  prompt_required REBOOT_EXIT_CODES "Reboot exit codes (comma-separated)" "1641,3010"
  
  # Optional fields
  local notes
  vared -p "Release notes (optional): " notes
  notes="$(trim "${notes:-}")"
  
  local update_type
  prompt_menu update_type "Update type" "Regular Updates" "Security Updates" "Critical Updates"
  
  local security_severity
  prompt_menu security_severity "Security severity" "Unspecified" "Low" "Medium" "High" "Critical"
  
  # Status and approval (using version_status to avoid zsh reserved variable)
  local version_status
  prompt_menu version_status "Version status" "Published" "Draft"
  
  local approval_status
  prompt_menu approval_status "Approval status" "New" "Approved" "Declined"
  
  # EULA
  local eula_accepted
  prompt_menu eula_accepted "EULA acceptance required" "no" "yes"

  # Build the JSON payload
  local payload
  payload="$(jq -nc \
    --arg ver "$VERSION_NUM" \
    --arg match "$APP_NAME_MATCH" \
    --arg date "$RELEASE_DATE" \
    --arg up "$upload_platform" \
    --arg fn "$file_name" \
    --arg itype "$install_type" \
    --argjson os "$os_list" \
    --arg success_codes "$SUCCESS_EXIT_CODES" \
    --arg reboot_codes "$REBOOT_EXIT_CODES" \
    --arg notes "$notes" \
    --arg update_type "$update_type" \
    --arg severity "$security_severity" \
    --arg vstatus "$version_status" \
    --arg approval_status "$approval_status" \
    --arg eula "$eula_accepted" \
    '{
      version: $ver,
      app_name_match: $match,
      release_date: $date,
      os: $os,
      install_type: $itype,
      success_exit_codes: $success_codes,
      reboot_exit_codes: $reboot_codes,
      notes: $notes,
      update_type: $update_type,
      security_severity: $severity,
      status: $vstatus,
      approval_status: $approval_status,
      EULA_accepted: $eula,
      file_name: {($up): {name: $fn, type: "cloud"}}
    }')"

  api_json POST "/software-repository/${org_id}/${pkg_id}/versions" "$payload"
  [[ "${REQ_CODE:-}" == "200" ]] || die "Version create failed (HTTP ${REQ_CODE:-}). Body: $REQ_BODY"

  local id; id="$(print -r -- "$REQ_BODY" | jq -r '.id // empty')"
  [[ -n "$id" ]] || die "Version create returned no id. Body: $REQ_BODY"
  log INFO "Created version: $VERSION_NUM (ID: $id)"
  print -r -- "$id"
}

check_conflicts() {
  local org_id="$1" pkg_id="$2" ver_id="$3"
  
  log INFO "Checking for conflicts..."
  api_json POST "/software-repository/${org_id}/${pkg_id}/versions/${ver_id}/match-conflicts" ""
  
  if [[ "${REQ_CODE:-}" == "200" ]]; then
    local conflicts
    conflicts="$(print -r -- "$REQ_BODY" | jq -r '.conflicts // [] | length')"
    if (( conflicts > 0 )); then
      log WARN "Found $conflicts potential conflicts:"
      print -r -- "$REQ_BODY" | jq -r '.conflicts[] | "  - \(.name) (\(.version))"' >&2
    else
      log INFO "No conflicts found"
    fi
  else
    log WARN "Conflict check returned HTTP ${REQ_CODE:-}, proceeding anyway"
  fi
}

#############################################
# Upload
#############################################
upload_init() {
  local org_id="$1" pkg_id="$2" ver_id="$3" platform="$4"
  local size="$FILE_SIZE"
  local url="${API_BASE}/software-repository/${org_id}/${pkg_id}/versions/${ver_id}/upload?platform=${platform}"

  local hdr out code
  hdr="$(mktemp)"
  out="$(mktemp)"

  log INFO "Initializing upload..."
  code="$(curl -sS -X POST "$url" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
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
  local chunk_mb="${CHUNK_MB:-24}"
  [[ "$chunk_mb" == <-> ]] || die "Chunk MB must be numeric"
  (( chunk_mb >= 5 )) || die "Chunk size must be >= 5MB"
  
  local chunk_bytes=$(( chunk_mb * 1024 * 1024 ))
  local total="$FILE_SIZE"

  log INFO "Uploading ${total} bytes in ${chunk_mb}MB chunks..."
  print -r -- "" >&2

  local tmpdir
  tmpdir="$(mktemp -d)"
  split -b "$chunk_bytes" -d -a 4 "$FILE_PATH" "${tmpdir}/chunk_" 2>/dev/null

  python3 -u - "$tmpdir" "$upload_url" "$TOKEN" "$total" "$chunk_mb" <<'PYEND'
import sys, os, time, glob, subprocess, select

tmpdir = sys.argv[1]
upload_url = sys.argv[2]
token = sys.argv[3]
total_size = int(sys.argv[4])
chunk_mb = int(sys.argv[5])

chunks = sorted(glob.glob(os.path.join(tmpdir, "chunk_*")))
total_chunks = len(chunks)
spinner = ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷']

def draw_bar(pct):
    filled = int(pct * 30 / 100)
    empty = 30 - filled
    return f"[\033[32m{'█' * filled}\033[0m{'░' * empty}]"

def update_progress(chunk_num, total_chunks, chunk_pct, speed_mbps, spin_idx=0):
    overall_pct = ((chunk_num - 1) * 100 + chunk_pct) // total_chunks
    sys.stderr.write('\033[3A\r\033[J')
    sys.stderr.write(f'\033[36m{spinner[spin_idx]}\033[0m Uploading chunk {chunk_num}/{total_chunks} - {speed_mbps} Mbps\n')
    sys.stderr.write(f'Overall:       {draw_bar(overall_pct)} {overall_pct:3d}%\n')
    sys.stderr.write(f'Current Chunk: {draw_bar(chunk_pct)} {chunk_pct:3d}%')
    sys.stderr.flush()

offset = 0
for chunk_idx, chunk_path in enumerate(chunks, 1):
    chunk_size = os.path.getsize(chunk_path)
    chunk_mb_size = chunk_size // (1024 * 1024)
    start_byte = offset
    end_byte = offset + chunk_size - 1
    offset = end_byte + 1
    
    if chunk_idx == 1:
        sys.stderr.write('\n\n\n\033[3A')
    
    spin_idx = 0
    update_progress(chunk_idx, total_chunks, 0, 0, spin_idx)
    
    start_time = time.time()
    cmd = ['curl', '-X', 'PUT', upload_url,
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/octet-stream',
        '-H', f'Content-Length: {chunk_size}',
        '-H', f'Content-Range: bytes {start_byte}-{end_byte}/{total_size}',
        '--data-binary', f'@{chunk_path}',
        '-w', '%{http_code}', '-o', '/dev/null', '-#']
    
    proc = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    last_pct = 0
    last_update = time.time()
    
    while proc.poll() is None:
        ready, _, _ = select.select([proc.stderr], [], [], 0.15)
        current_time = time.time()
        
        if ready:
            line = proc.stderr.readline()
            if '#' in line or '%' in line:
                parts = line.split()
                for part in parts:
                    if '%' in part or '.' in part:
                        try:
                            pct = int(float(part.replace('%', '')))
                            if 0 <= pct <= 100:
                                elapsed = max(1, current_time - start_time)
                                speed = int((chunk_mb_size * pct * 8) / (elapsed * 100)) if pct > 0 else 0
                                update_progress(chunk_idx, total_chunks, pct, speed, spin_idx)
                                last_pct = pct
                                last_update = current_time
                                spin_idx = (spin_idx + 1) % len(spinner)
                                break
                        except:
                            pass
        
        if current_time - last_update >= 0.15:
            elapsed = max(1, current_time - start_time)
            speed = int((chunk_mb_size * last_pct * 8) / (elapsed * 100)) if last_pct > 0 else 0
            update_progress(chunk_idx, total_chunks, last_pct, speed, spin_idx)
            last_update = current_time
            spin_idx = (spin_idx + 1) % len(spinner)
    
    stdout, _ = proc.communicate()
    http_code = stdout.strip()[-3:] if stdout else ""
    elapsed = time.time() - start_time
    final_speed = int((chunk_mb_size * 8) / elapsed) if elapsed > 0 else 0
    overall_pct = chunk_idx * 100 // total_chunks
    
    sys.stderr.write('\033[3A\r\033[J')
    if http_code == "308":
        sys.stderr.write(f'\033[32m✓\033[0m Uploaded chunk {chunk_idx}/{total_chunks} - {final_speed} Mbps\n')
        sys.stderr.write(f'Overall:       {draw_bar(overall_pct)} {overall_pct:3d}%\n')
        sys.stderr.write(f'Current Chunk: {draw_bar(100)} 100%')
        sys.stderr.flush()
    elif http_code in ["200", "201", "204"]:
        sys.stderr.write(f'\033[32m✓\033[0m Uploaded chunk {chunk_idx}/{total_chunks} - {final_speed} Mbps - Complete!\n')
        sys.stderr.write(f'Overall:       {draw_bar(100)} 100%\n')
        sys.stderr.write(f'Current Chunk: {draw_bar(100)} 100%')
        sys.stderr.flush()
        break
    else:
        sys.stderr.write(f'\033[31m✗\033[0m Chunk upload failed (HTTP {http_code})\n\n\n')
        sys.exit(1)

sys.exit(0)
PYEND

  local pyresult=$?
  rm -rf "$tmpdir" 2>/dev/null
  
  if [[ $pyresult -eq 0 ]]; then
    log INFO "Upload complete!"
    return 0
  else
    die "Upload failed"
  fi
}

#############################################
# CLI args
#############################################
ENV_FILE=".env"
FILE_PATH=""
typeset -g CHUNK_MB="${CHUNK_MB:-24}"

usage() {
  cat >&2 <<EOF
Usage:
  $0 --file-path /path/to/file.zip [options]

Options:
  --env FILE              Environment file (default: .env)
  --file-path FILE        Path to installation file (required)
  --log-level LEVEL       Log level: SILENT|INFO|DEBUG|TRACE (default: SILENT)
  --chunk-mb N            Upload chunk size in MB (default: 24, min: 5)
  -h, --help              Show this help

Environment Variables:
  ACTION1_CLIENT_ID       API Client ID
  ACTION1_CLIENT_SECRET   API Client Secret
  ACTION1_REGION          Region (Europe, NorthAmerica, Australia)
  ACTION1_BASE_URL        Custom API base URL
EOF
}

while (( $# )); do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --file-path) FILE_PATH="$2"; shift 2 ;;
    --log-level) LOG_LEVEL="$2"; shift 2 ;;
    --chunk-mb) CHUNK_MB="$2"; shift 2 ;;
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

[[ -n "$FILE_PATH" ]] || die "Missing required argument: --file-path"
FILE_PATH="$(trim "$FILE_PATH")"
[[ -f "$FILE_PATH" ]] || die "File not found: $FILE_PATH"

dotenv_load "$ENV_FILE"

typeset -g FILE_SIZE; FILE_SIZE="$(file_size_bytes "$FILE_PATH")"
typeset -g FILE_BASENAME; FILE_BASENAME="$(basename -- "$FILE_PATH")"

log INFO "File: $FILE_PATH"
log INFO "Size: $FILE_SIZE bytes"

API_BASE="$(derive_api_base)"
[[ -n "$API_BASE" ]] || die "Could not determine API base URL. Set ACTION1_REGION or ACTION1_BASE_URL"
log INFO "API Base: $API_BASE"

auth

typeset -g ORG_ID ORG_NAME
choose_org

typeset -g REPO_ID
select_or_create_repo "$ORG_ID"

typeset -g VERSION_ID VERSION_NUM APP_NAME_MATCH RELEASE_DATE
VERSION_ID="$(create_version "$ORG_ID" "$REPO_ID" "$FILE_BASENAME")"

check_conflicts "$ORG_ID" "$REPO_ID" "$VERSION_ID"

typeset -g UPLOAD_PLATFORM
if [[ "$FILE_BASENAME" == *.zip ]]; then
  UPLOAD_PLATFORM="${UPLOAD_PLATFORM:-Mac_AppleSilicon}"
else
  UPLOAD_PLATFORM="${UPLOAD_PLATFORM:-Windows_64}"
fi

typeset -g UPLOAD_URL
UPLOAD_URL="$(upload_init "$ORG_ID" "$REPO_ID" "$VERSION_ID" "$UPLOAD_PLATFORM")" || die "Upload init failed"
log DEBUG "Upload URL: $UPLOAD_URL"

upload_chunks "$UPLOAD_URL" || die "Upload failed"

log INFO "Successfully deployed to Action1!"
log INFO "Organization: $ORG_NAME"
log INFO "Repository: $REPO_ID"
log INFO "Version: $VERSION_NUM"
