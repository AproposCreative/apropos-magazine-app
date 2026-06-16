#!/usr/bin/env bash
# Download current Firebase podcast files, re-encode for streaming, report size savings.
# Does NOT upload — run podcast-auto-publish or Firebase Console after review.
#
# Usage: ./scripts/prepare-podcast-uploads.sh
# Requires: ffmpeg (brew install ffmpeg), gcloud or gsutil with application-default auth

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTERS="$ROOT/podcast-audio/masters"
OPTIMIZED="$ROOT/podcast-audio/optimized"
SCRIPT="$ROOT/scripts/reencode-podcast-audio.sh"
BUCKET="apropos-magazine-6004a.firebasestorage.app"
GS_URI="gs://${BUCKET}"

mkdir -p "$MASTERS" "$OPTIMIZED"

# local filename|storage path (no download tokens — uses gcloud/gsutil auth)
PAIRS=(
  "backrooms.m4a|podcasts/articles/backrooms-anmeldelse/Rædslen_i_de_uendelige_gule_Backrooms.m4a"
  "tomodachi-life-living-the-dream.m4a|podcasts/articles/tomodachi-life-living-the-dream/tomodachi-life-living-the-dream.m4a"
  "copenhell---den-store-apropos-guide.m4a|podcasts/articles/copenhell---den-store-apropos-guide/copenhell---den-store-apropos-guide.m4a"
  "farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a|podcasts/articles/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a"
)

copy_from_storage() {
  local src="$1"
  local dest="$2"
  if command -v gcloud >/dev/null 2>&1; then
    gcloud storage cp "$src" "$dest"
  elif command -v gsutil >/dev/null 2>&1; then
    gsutil cp "$src" "$dest"
  else
    echo "Install Google Cloud SDK (gcloud or gsutil) and run: gcloud auth application-default login" >&2
    return 1
  fi
}

echo "=== Downloading current Firebase masters ==="
for pair in "${PAIRS[@]}"; do
  name="${pair%%|*}"
  storage_path="${pair#*|}"
  dest="$MASTERS/$name"
  if [[ -f "$dest" ]]; then
    echo "Skip (exists): $name"
  else
    echo "Downloading: $name"
    if ! copy_from_storage "${GS_URI}/${storage_path}" "$dest"; then
      echo "  Warning: download failed. Place master manually at: $dest" >&2
      rm -f "$dest"
    fi
  fi
done

echo
echo "=== Re-encoding to AAC-LC 96k mono, -16 LUFS ==="
PODCAST_MONO=1 "$SCRIPT" "$MASTERS" "$OPTIMIZED"

echo "=== Size comparison ==="
printf "%-55s %12s %12s %8s\n" "File" "Master" "Optimized" "Saved"
printf "%-55s %12s %12s %8s\n" "----" "------" "---------" "-----"
total_in=0
total_out=0
for f in "$MASTERS"/*; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  out="$OPTIMIZED/$base"
  [[ -f "$out" ]] || continue
  in_size=$(stat -f%z "$f")
  out_size=$(stat -f%z "$out")
  total_in=$((total_in + in_size))
  total_out=$((total_out + out_size))
  pct=$((100 - (out_size * 100 / in_size)))
  printf "%-55s %10dB %10dB %6d%%\n" "$base" "$in_size" "$out_size" "$pct"
done
echo
if [[ "$total_in" -gt 0 ]]; then
  echo "Total: ${total_in}B -> ${total_out}B (~$((100 - (total_out * 100 / total_in)))% smaller)"
fi
echo
cat <<'EOF'
Upload optimized files:
  node scripts/upload-podcasts-to-firebase.mjs
  # or preferred:
  node scripts/podcast-auto-publish.mjs

Then refresh manifest:
  node scripts/podcast-auto-publish.mjs --manifest-only
EOF
