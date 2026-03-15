#!/bin/bash
# ============================================================
# Z + Z Anniversary Website — Photo Manager
# ============================================================
# Usage:
#   ./update-photos.sh          Scan folders, convert HEIC, update index.html
#   ./update-photos.sh --dry    Preview changes without modifying index.html
#
# Workflow:
#   1. Add/remove photos in any numbered folder (e.g., "01. Apr 2023")
#   2. Add new month folders (e.g., "36. Mar 2026")
#   3. Run this script — it handles everything automatically
# ============================================================

set -euo pipefail
cd "$(dirname "$0")"

DRY_RUN=false
[[ "${1:-}" == "--dry" ]] && DRY_RUN=true

HTML_FILE="index.html"

if [[ ! -f "$HTML_FILE" ]]; then
  echo "Error: $HTML_FILE not found in $(pwd)"
  exit 1
fi

echo "========================================"
echo "  Z + Z Photo Manager"
echo "========================================"
echo ""

# --- Step 1: Convert any new HEIC files to JPEG ---
echo "[1/3] Checking for HEIC files to convert..."
heic_count=0
converted_count=0

while IFS= read -r -d '' f; do
  heic_count=$((heic_count + 1))
  dir=$(dirname "$f")
  base=$(basename "$f" | sed 's/\.[hH][eE][iI][cC]$//')
  output="$dir/${base}.jpg"
  if [[ ! -f "$output" ]]; then
    if $DRY_RUN; then
      echo "  Would convert: $f → $output"
    else
      sips -s format jpeg -s formatOptions 85 "$f" --out "$output" > /dev/null 2>&1
    fi
    converted_count=$((converted_count + 1))
  fi
done < <(find . -maxdepth 2 -type f -iname "*.heic" -print0)

if [[ $converted_count -gt 0 ]]; then
  echo "  Converted $converted_count new HEIC file(s) to JPEG"
else
  echo "  No new HEIC files to convert"
fi

# --- Step 2: Build the new manifest ---
echo ""
echo "[2/3] Scanning folders for images..."

total_photos=0
manifest_lines=()

for dir in */; do
  # Only process numbered folders like "01. Apr 2023"
  [[ "$dir" =~ ^[0-9]+\. ]] || continue

  dirname=$(basename "$dir")

  # Collect web-compatible image files (sorted)
  files=()
  while IFS= read -r -d '' img; do
    files+=("$(basename "$img")")
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0 | sort -z)

  count=${#files[@]}
  total_photos=$((total_photos + count))

  # Build JSON array for this folder
  json_files=""
  for f in "${files[@]}"; do
    [[ -n "$json_files" ]] && json_files+=","
    json_files+="\"$f\""
  done

  manifest_lines+=("  \"$dirname\": [$json_files]")
  echo "  $dirname: $count photos"
done

echo ""
echo "  Total: $total_photos photos across ${#manifest_lines[@]} months"

# --- Step 3: Update index.html ---
echo ""
echo "[3/3] Updating $HTML_FILE..."

# Build the full manifest block
new_manifest="const IMAGE_MANIFEST = {\n"
for i in "${!manifest_lines[@]}"; do
  if [[ $i -lt $((${#manifest_lines[@]} - 1)) ]]; then
    new_manifest+="${manifest_lines[$i]},\n"
  else
    new_manifest+="${manifest_lines[$i]}\n"
  fi
done
new_manifest+="};"

if $DRY_RUN; then
  echo "  [DRY RUN] Would update manifest with ${#manifest_lines[@]} months, $total_photos photos"
  echo ""
  echo "Run without --dry to apply changes."
  exit 0
fi

# Use perl to replace the manifest block in-place
# Matches from "const IMAGE_MANIFEST = {" to the closing "};"
perl -0777 -i -pe "
  s{const IMAGE_MANIFEST = \{.*?\};}
   {$(echo -e "$new_manifest")}s
" "$HTML_FILE"

echo "  Done! Manifest updated with ${#manifest_lines[@]} months and $total_photos photos."
echo ""
echo "========================================"
echo "  Open index.html in your browser to see the changes!"
echo "========================================"
