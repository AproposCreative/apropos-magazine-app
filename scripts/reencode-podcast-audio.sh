#!/usr/bin/env bash
# Re-encode podcast audio for faster streaming in Apropos Magazine app.
# Target: AAC-LC 96 kbps, ~-16 LUFS, .m4a (speech/podcast optimized)
#
# Usage:
#   ./scripts/reencode-podcast-audio.sh input.m4a output.m4a
#   ./scripts/reencode-podcast-audio.sh ./masters ./optimized
#
# Requires: ffmpeg (brew install ffmpeg)

set -euo pipefail

TARGET_LUFS="-16"
TARGET_BITRATE="96k"
AUDIO_CODEC="aac"

usage() {
  cat <<'EOF'
Re-encode podcast audio for streaming.

Single file:
  ./scripts/reencode-podcast-audio.sh input.m4a output.m4a

Batch (all audio in a folder):
  ./scripts/reencode-podcast-audio.sh ./masters ./optimized

Options via env:
  PODCAST_BITRATE=128k   Override bitrate (default 96k)
  PODCAST_MONO=1         Force mono output (default: keep channels)
EOF
}

require_ffmpeg() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg not found. Install with: brew install ffmpeg" >&2
    exit 1
  fi
}

encode_one() {
  local input="$1"
  local output="$2"
  local bitrate="${PODCAST_BITRATE:-$TARGET_BITRATE}"
  local mono_filter=""

  mkdir -p "$(dirname "$output")"

  if [[ "${PODCAST_MONO:-0}" == "1" ]]; then
    mono_filter=",pan=mono|c0=0.5*c0+0.5*c1"
  fi

  echo "Encoding: $input"
  echo "      ->: $output (${bitrate}, LUFS ${TARGET_LUFS})"

  # Two-pass loudness normalize to ~-16 LUFS (EBU R128), then AAC encode.
  ffmpeg -hide_banner -loglevel error -y -i "$input" \
    -af "loudnorm=I=${TARGET_LUFS}:TP=-1.5:LRA=11${mono_filter}" \
    -c:a "$AUDIO_CODEC" -b:a "$bitrate" -movflags +faststart \
    "$output"

  local in_size out_size
  in_size=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input")
  out_size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output")
  local pct=$((100 - (out_size * 100 / in_size)))
  echo "Done: $(numfmt --to=iec-i --suffix=B "$in_size" 2>/dev/null || echo "${in_size}B") -> $(numfmt --to=iec-i --suffix=B "$out_size" 2>/dev/null || echo "${out_size}B") (~${pct}% smaller)"
  echo
}

encode_batch() {
  local input_dir="$1"
  local output_dir="$2"
  shopt -s nullglob
  local files=("$input_dir"/*.{m4a,mp3,aac,wav,mp4,M4A,MP3,AAC,WAV,MP4})
  if (( ${#files[@]} == 0 )); then
    echo "No audio files found in: $input_dir" >&2
    exit 1
  fi
  for input in "${files[@]}"; do
    local base
    base=$(basename "$input")
    base="${base%.*}"
    encode_one "$input" "$output_dir/${base}.m4a"
  done
}

require_ffmpeg

if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 2 && -f "$1" ]]; then
  encode_one "$1" "$2"
elif [[ $# -eq 2 && -d "$1" ]]; then
  encode_batch "$1" "$2"
else
  echo "Invalid arguments." >&2
  usage
  exit 1
fi

cat <<'EOF'

Next steps (Firebase Storage):
1. Upload optimized .m4a files to the SAME paths in Firebase Storage
   (replace in place) so existing PodcastLinks.swift URLs keep working.
2. Or upload as new files and update tokens/URLs in PodcastLinks.swift.
3. Test in app: timeToFirstAudio should drop sharply (check Xcode console in DEBUG).

Current Firebase sizes (approx, May 2026):
- Backrooms: ~38 MB  <- highest priority to re-encode
- Copenhell:   ~11 MB
- Farveblind:  ~11 MB
EOF
