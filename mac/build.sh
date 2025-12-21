# ...existing code...
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

usage() {
  echo "Usage: $0 -a APP -v VER [-s SRC_DIR] [-o OUT_DIR]"
  echo "  -a APP      Application name (e.g. VirtualBuddy)"
  echo "  -v VER      Version (e.g. 2.1)"
  echo "  -s SRC_DIR  Optional explicit source folder (overrides auto-detect)"
  echo "  -o OUT_DIR  Optional output folder (default: ./dist)"
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
    h|*) usage ;;
  esac
done

if [[ -z "$APP" || -z "$VER" ]]; then usage; fi

# Resolve source directory
if [[ -n "$SRC_DIR" ]]; then
  src="$SRC_DIR"
else
  # common layout: mac/<App>/<ver> or <App>/<ver>
  candidates=(
    "$repo_root/mac/$APP/$VER"
    "$repo_root/$APP/$VER"
  )
  src=""
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then src="$c"; break; fi
  done
  if [[ -z "$src" ]]; then
    # fallback: find first matching path anywhere under repo
    src="$(find "$repo_root" -type d -path "*/$APP/$VER" -print -quit || true)"
  fi
fi

if [[ -z "$src" || ! -d "$src" ]]; then
  echo "Error: source folder for ${APP}/${VER} not found." >&2
  exit 2
fi

outdir="${OUT_DIR:-$repo_root/dist}"
mkdir -p "$outdir"
outfile="$outdir/${APP}-${VER}.zip"

# Create zip with the contents of the version folder at the zip root
(
  cd "$src"
  # -q quiet, -r recursive, include hidden files; exclude .DS_Store and any local_mnt folders
  zip -r -q "$outfile" . -x "*.DS_Store" "local_mnt/*" "*/local_mnt/*"
)

echo "Created: $outfile"
