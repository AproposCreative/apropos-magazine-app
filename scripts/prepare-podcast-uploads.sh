#!/usr/bin/env bash
# Download current Firebase podcast files, re-encode for streaming, report size savings.
# Does NOT upload — run Firebase Console upload manually after review.
#
# Usage: ./scripts/prepare-podcast-uploads.sh
# Requires: ffmpeg (brew install ffmpeg), curl

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTERS="$ROOT/podcast-audio/masters"
OPTIMIZED="$ROOT/podcast-audio/optimized"
SCRIPT="$ROOT/scripts/reencode-podcast-audio.sh"

mkdir -p "$MASTERS" "$OPTIMIZED"

# name|url pairs (portable — no bash 4 associative arrays)
PAIRS=(
  "backrooms.m4a|https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fbackrooms-anmeldelse%2FR%C3%A6dslen_i_de_uendelige_gule_Backrooms.m4a?alt=media&token=8ddc2183-3a7a-4452-826b-360bbd6d2757"
  "tomodachi-life-living-the-dream.m4a|https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Ftomodachi-life-living-the-dream%2Ftomodachi-life-living-the-dream.m4a?alt=media&token=e5f05391-ea5b-4235-877d-35391fc899ba"
  "copenhell---den-store-apropos-guide.m4a|https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fcopenhell---den-store-apropos-guide%2Fcopenhell---den-store-apropos-guide.m4a?alt=media&token=e8e5cf79-e629-41ee-8a51-5448cb5f6f15"
  "farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a|https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Ffarveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse%2Ffarveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a?alt=media&token=803255d5-a8c1-4d0c-95fe-e43f3f6682df"
)

echo "=== Downloading current Firebase masters ==="
for pair in "${PAIRS[@]}"; do
  name="${pair%%|*}"
  url="${pair#*|}"
  dest="$MASTERS/$name"
  if [[ -f "$dest" ]]; then
    echo "Skip (exists): $name"
  else
    echo "Downloading: $name"
    if ! curl -fsSL "$url" -o "$dest"; then
      echo "  Warning: download failed (403 = expired token?). Place master manually at: $dest" >&2
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
Upload optimized files to Firebase Storage (replace same paths):
  podcast-audio/optimized/*.m4a

Firebase paths (keep filenames):
  podcasts/articles/backrooms-anmeldelse/Rædslen_i_de_uendelige_gule_Backrooms.m4a
  podcasts/articles/tomodachi-life-living-the-dream/tomodachi-life-living-the-dream.m4a
  podcasts/articles/copenhell---den-store-apropos-guide/copenhell---den-store-apropos-guide.m4a
  podcasts/articles/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a

After replace-in-place, existing PodcastLinks.swift URLs still work (same token/path).
EOF
