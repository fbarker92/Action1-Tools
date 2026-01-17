#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
run_root="$PWD"

usage() {
  cat <<EOF
Usage: $0 -a APP -v VER [-s SRC_DIR] [-o OUT_DIR]
  -a APP      Application name (e.g. VirtualBuddy)
  -v VER      Version (e.g. 2.1)
  -s SRC_DIR  Optional explicit source folder (overrides auto-detect)
  -o OUT_DIR  Optional output folder (default: ./dist)
  -h          Show this help message
EOF
  exit 1
}

APP=""
VER=""
SRC_DIR=""
OUT_DIR=""

while getopts "a:v:s:o:h" opt; do
  case "$opt" in
    a) APP="$OPTARG" ;;
    v) VER="$OPTARG" ;;
    s) SRC_DIR="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Interactive prompts (use readline so tab completion works)
if [[ -t 0 ]]; then
  if [[ -z "$APP" ]]; then
    read -e -rp "Application name (e.g. VirtualBuddy): " APP
  fi
  # If interactive and the entered app folder doesn't exist, offer fuzzy matches
  if [[ -n "$APP" && -t 0 ]]; then
    found_exact=false
    bases=("$run_root" "$repo_root" "$repo_root/_mac" "$run_root/_mac")
    for base in "${bases[@]}"; do
      if [[ -d "$base/$APP" ]]; then found_exact=true; break; fi
    done

    if ! $found_exact; then
      # gather candidate app basenames under the bases
      mapfile -t raw_paths < <(find "${bases[@]}" -mindepth 1 -maxdepth 2 -type d 2>/dev/null || true)
      declare -A seen_apps
      app_names=()
      for p in "${raw_paths[@]:-}"; do
        b=$(basename "$p")
        # skip empty or current dir
        [[ -z "$b" || "$b" = "." ]] && continue
        if [[ -z "${seen_apps[$b]:-}" ]]; then
          seen_apps[$b]=1
          app_names+=("$b")
        fi
      done

      if [[ ${#app_names[@]} -gt 0 ]]; then
        # compute Levenshtein distances using awk and sort
        distances=()
        for name in "${app_names[@]}"; do
          dist=$(awk -v s="$APP" -v t="$name" 'BEGIN{
            n=length(s); m=length(t);
            for(i=0;i<=n;i++) d[i,0]=i;
            for(j=0;j<=m;j++) d[0,j]=j;
            for(i=1;i<=n;i++){ si=substr(s,i,1);
              for(j=1;j<=m;j++){ tj=substr(t,j,1); cost=(si==tj)?0:1;
                a=d[i-1,j]+1; b=d[i,j-1]+1; c=d[i-1,j-1]+cost;
                v=a; if(b<v) v=b; if(c<v) v=c; d[i,j]=v }
            }
            print d[n,m]
          }')
          distances+=("$dist|$name")
        done
        IFS=$'\n' sorted_matches=($(printf '%s\n' "${distances[@]}" | sort -t'|' -k1,1n))
        # present top 5 matches
        choices=()
        for s in "${sorted_matches[@]}"; do
          choices+=("${s#*|}")
          [[ ${#choices[@]} -ge 5 ]] && break
        done

        if [[ ${#choices[@]} -gt 0 ]]; then
          echo "No exact app folder named '$APP' found. Close matches:"
          i=1
          for c in "${choices[@]}"; do
            echo " [$i] $c"
            ((i++))
          done
          echo " [0] Keep original / enter manual name"
          read -e -rp "Choose number to use (or 0 to keep '$APP'): " ch
          if [[ "$ch" =~ ^[0-9]+$ ]] && (( ch >= 1 && ch <= ${#choices[@]} )); then
            APP="${choices[$((ch-1))]}"
            echo "Using app name: $APP"
          fi
        fi
      fi
    fi
  fi
  if [[ -z "$VER" ]]; then
    # Find candidate version folders for this APP (look in sensible roots)
    candidates=()
    for base in "$run_root" "$repo_root" "$repo_root/_mac" "$run_root/_mac"; do
      if [[ -d "$base/$APP" ]]; then
        for d in "$base/$APP"/*; do
          [[ -d "$d" ]] && candidates+=("$d")
        done
      fi
    done

    # also do a wider find (limited depth) if nothing found yet
    if [[ ${#candidates[@]} -eq 0 ]]; then
      mapfile -t found < <(find "$run_root" "$repo_root" -type d -path "*/$APP/*" -maxdepth 4 2>/dev/null || true)
      for d in "${found[@]:-}"; do
        candidates+=("$d")
      done
    fi

    # dedupe
    if [[ ${#candidates[@]} -gt 1 ]]; then
      readarray -t candidates < <(printf '%s\n' "${candidates[@]}" | awk '!seen[$0]++')
    fi

    # remove empty entries and ensure candidates are directories
    if [[ ${#candidates[@]} -gt 0 ]]; then
      _tmp_candidates=()
      for p in "${candidates[@]}"; do
        if [[ -n "$p" && -d "$p" ]]; then
          _tmp_candidates+=("$p")
        fi
      done
      candidates=("${_tmp_candidates[@]}")
      unset _tmp_candidates
    fi

    # sort by version (highest first) if any candidates
    if [[ ${#candidates[@]} -gt 0 ]]; then
      ver_key() {
        local v="$1"
        v="${v//_/\.}"
        v="${v//-/.}"
        # strip non-digit and non-dot characters
        v="$(printf '%s' "$v" | sed 's/[^0-9.]/./g')"
        IFS='.' read -ra parts <<< "$v"
        # support up to 4 components; pad with zeros
        printf '%08d%08d%08d%08d' "${parts[0]:-0}" "${parts[1]:-0}" "${parts[2]:-0}" "${parts[3]:-0}"
      }

      mlist=()
      for p in "${candidates[@]}"; do
        vname=$(basename "$p")
        key=$(ver_key "$vname")
        mlist+=("$key|$vname|$p")
      done

      IFS=$'\n' sorted=($(printf '%s\n' "${mlist[@]}" | sort -t'|' -k1,1nr))
      candidates=()
      for s in "${sorted[@]}"; do
        # field 3 is the path
        candidates+=("$(printf '%s' "$s" | cut -d'|' -f3-)")
      done

      if [[ -t 0 ]]; then
        echo "Found candidate version folders for '$APP':"
        i=1
        for d in "${candidates[@]}"; do
          vername=$(basename "$d")
          if [[ "$d" == "$repo_root"* ]]; then
            disp="${d#$repo_root}"
            disp="~${disp}"
          elif [[ "$d" == "$run_root"* ]]; then
            disp="${d#$run_root}"
            # show as relative to current dir when different from repo_root
            disp=".${disp}"
          else
            disp="$d"
          fi
          echo " [$i] $vername -> $disp"
          ((i++))
        done
        echo " [m] Enter manual path"
        read -e -rp "Choose number (default 1) or type path (leave blank for default): " choice
        if [[ -z "$choice" ]]; then
          sel=1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
          sel=$choice
        elif [[ "$choice" = "m" || "$choice" = "M" ]]; then
          read -e -rp "Enter explicit source path: " input_src
          if [[ -n "$input_src" ]]; then
            if [[ "${input_src:0:1}" = "/" ]]; then
              candidate="$input_src"
            else
              candidate="$run_root/$input_src"
            fi
            if [[ -d "$candidate" ]]; then
              SRC_DIR="$candidate"
              VER=$(basename "$candidate")
              sel=0
            else
              echo "Invalid path provided." >&2
              exit 2
            fi
          else
            echo "No path entered. Aborting." >&2
            exit 2
          fi
        else
          # treat non-numeric input as a path or version name
          if [[ "${choice:0:1}" = "/" || -d "$run_root/$choice" ]]; then
            if [[ "${choice:0:1}" = "/" ]]; then
              candidate="$choice"
            else
              candidate="$run_root/$choice"
            fi
            if [[ -d "$candidate" ]]; then
              SRC_DIR="$candidate"
              VER=$(basename "$candidate")
              sel=0
            fi
          else
            # look for a candidate with this version basename
            idx=0
            for d in "${candidates[@]}"; do
              ((idx++))
              if [[ "$(basename "$d")" = "$choice" ]]; then
                sel=$idx
                break
              fi
            done
          fi
        fi

        if [[ -n "${sel:-}" && "$sel" != 0 ]]; then
          SRC_DIR="${candidates[$((sel-1))]}"
          VER=$(basename "$SRC_DIR")
        fi
      else
        # non-interactive fallback: pick most recent
        SRC_DIR="${candidates[0]}"
        VER=$(basename "$SRC_DIR")
      fi
    else
      # no candidates found, fall back to simple prompt
      read -e -rp "Version (e.g. 2.1): " VER
    fi
  fi
else
  if [[ -z "$APP" || -z "$VER" ]]; then usage; fi
fi

if [[ -z "$APP" || -z "$VER" ]]; then
  echo "Error: Application name and version are required." >&2
  usage
fi

# Resolve source directory: prefer explicit, then run_root, then repo_root, then search
if [[ -n "${SRC_DIR:-}" ]]; then
  if [[ "${SRC_DIR:0:1}" = "/" ]]; then
    src="$SRC_DIR"
  else
    src="$run_root/$SRC_DIR"
  fi
else
  candidates=(
    "$run_root/$APP/$VER"
    "$run_root/$APP"
    "$run_root/_mac/$APP/$VER"
    "$repo_root/_mac/$APP/$VER"
    "$repo_root/$APP/$VER"
  )
  src=""
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      src="$c"
      break
    fi
  done

  if [[ -z "$src" ]]; then
    src="$(find "$run_root" -type d -path "*/$APP/$VER" -print -quit 2>/dev/null || true)"
    if [[ -z "$src" ]]; then
      src="$(find "$repo_root" -type d -path "*/$APP/$VER" -print -quit 2>/dev/null || true)"
    fi
  fi
  
# Fuzzy-ish fallback without Python: look for directories named VER and match parent names
if [[ -z "$src" ]]; then
  mapfile -t ver_dirs < <(find "$run_root" "$repo_root" -type d -name "$VER" 2>/dev/null || true)

  # dedupe while preserving order
  if [[ ${#ver_dirs[@]} -gt 1 ]]; then
    readarray -t ver_dirs < <(printf '%s\n' "${ver_dirs[@]}" | awk '!seen[$0]++')
  fi

  if [[ ${#ver_dirs[@]} -gt 0 ]]; then
    lc_app="$(printf '%s' "$APP" | tr '[:upper:]' '[:lower:]')"
    exact=()
    contains=()
    for d in "${ver_dirs[@]}"; do
      parent="$(basename "$(dirname "$d")")"
      lp="$(printf '%s' "$parent" | tr '[:upper:]' '[:lower:]')"
      if [[ "$lp" = "$lc_app" ]]; then
        exact+=("$d")
      elif [[ "$lp" = *"$lc_app"* ]]; then
        contains+=("$d")
      fi
    done

      if [[ ${#exact[@]} -gt 0 ]]; then
        src="${exact[0]}"
      elif [[ ${#contains[@]} -gt 0 ]]; then
        src="${contains[0]}"
      elif [[ ${#ver_dirs[@]} -eq 1 ]]; then
        src="${ver_dirs[0]}"
      elif [[ ${#ver_dirs[@]} -gt 1 && -t 0 ]]; then
        echo "Multiple candidate version folders found:"
        i=1
        for d in "${ver_dirs[@]}"; do
          if [[ "$d" == "$repo_root"* ]]; then
            disp="${d#$repo_root}"
            disp="~${disp}"
          elif [[ "$d" == "$run_root"* ]]; then
            disp="${d#$run_root}"
            disp=".${disp}"
          else
            disp="$d"
          fi
          echo " [$i] $disp (parent: $(basename "$(dirname "$d")"))"
          ((i++))
        done
        read -e -rp "Choose number or enter a path (leave blank to abort): " choice
        if [[ -z "$choice" ]]; then
          echo "Aborting." >&2
          exit 2
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ver_dirs[@]} )); then
          src="${ver_dirs[$((choice-1))]}"
        else
          # accept absolute or relative to run_root
          if [[ "$choice" = /* ]]; then candidate="$choice"; else candidate="$run_root/$choice"; fi
          if [[ -d "$candidate" ]]; then src="$candidate"; else echo "Invalid selection. Aborting." >&2; exit 2; fi
        fi
      fi
    fi
  fi

  # interactive fallback to let user type a path (tab completion enabled)
  if [[ -z "$src" && -t 0 ]]; then
    read -e -rp "Source folder for ${APP}/${VER} not found automatically. Enter explicit source path (or leave blank to abort): " input_src
    if [[ -n "$input_src" ]]; then
      if [[ "${input_src:0:1}" = "/" ]]; then
        candidate="$input_src"
      else
        candidate="$run_root/$input_src"
      fi
      if [[ -d "$candidate" ]]; then
        src="$candidate"
      else
        echo "No valid source folder provided. Aborting." >&2
        exit 2
      fi
    else
      echo "No valid source folder provided. Aborting." >&2
      exit 2
    fi
  fi
fi

if [[ -z "${src:-}" || ! -d "$src" ]]; then
  echo "Error: source folder for ${APP}/${VER} not found." >&2
  exit 2
fi

outdir="${OUT_DIR:-$repo_root/dist}"
mkdir -p "$outdir"
outfile="$outdir/${APP}-${VER}.zip"

create_zip_with_spinner() {
  local srcdir="$1" out="$2"

  (cd "$srcdir" && zip -r -q "$out" . -x "*.DS_Store" "local_mnt/*" "*/local_mnt/*") &
  zip_pid=$!

  spinner() {
    local pid=$1
    local delay=0.12
    local spin_chars=( '⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷' )
    local idx=0
    # color codes (green)
    local green=$'\033[32m'
    local reset=$'\033[0m'
    while kill -0 "$pid" 2>/dev/null; do
      # print the path and a green spinner glyph
      printf '\rCreating: %s %s%s%s' "$out" "$green" "${spin_chars[idx]}" "$reset"
      idx=$(( (idx + 1) % ${#spin_chars[@]} ))
      sleep "$delay"
    done
    # clear the line (carriage return + erase to end of line)
    printf '\r\033[K'
  }

  spinner "$zip_pid" &
  spin_pid=$!

  wait "$zip_pid"
  zip_rc=$?

  kill "$spin_pid" 2>/dev/null || true
  wait "$spin_pid" 2>/dev/null || true
  # ensure spinner output is cleared before printing result
  printf '\r\033[K'

  if [[ $zip_rc -ne 0 ]]; then
    echo "zip failed with code $zip_rc" >&2
    exit $zip_rc
  fi

  echo "Created: $out"
}

create_zip_with_spinner "$src" "$outfile"
exit 0
