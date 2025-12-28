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
  if [[ -z "$VER" ]]; then
    read -e -rp "Version (e.g. 2.1): " VER
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
    "$run_root/mac/$APP/$VER"
    "$repo_root/mac/$APP/$VER"
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
          echo " [$i] $d (parent: $(basename "$(dirname "$d")"))"
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

(
  cd "$src"
  zip -r -q "$outfile" . -x "*.DS_Store" "local_mnt/*" "*/local_mnt/*"
)

echo "Created: $outfile"
exit 0
