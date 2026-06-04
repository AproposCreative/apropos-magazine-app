#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./Scripts/profile-device.sh <DEVICE_UDID> [DURATION_SECONDS] [PROCESS_NAME]
#
# Example:
# ./Scripts/profile-device.sh 00008110-000131A01431401E 25 "Apropos Magazine"

DEVICE_UDID="${1:-}"
DURATION="${2:-25}"
PROCESS_NAME="${3:-Apropos Magazine}"
OUT_DIR="${PWD}/profiling-results"

if [[ -z "${DEVICE_UDID}" ]]; then
  echo "Missing device udid."
  echo "Run: xcrun xctrace list devices"
  echo "Then: ./Scripts/profile-device.sh <DEVICE_UDID> [DURATION_SECONDS]"
  exit 1
fi

mkdir -p "${OUT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "Recording Time Profiler (${DURATION}s) on ${DEVICE_UDID}..."
xcrun xctrace record \
  --template "Time Profiler" \
  --device "${DEVICE_UDID}" \
  --attach "${PROCESS_NAME}" \
  --time-limit "${DURATION}s" \
  --output "${OUT_DIR}/time-profiler-${STAMP}.trace"

echo "Recording Core Animation (${DURATION}s) on ${DEVICE_UDID}..."
xcrun xctrace record \
  --template "Core Animation" \
  --device "${DEVICE_UDID}" \
  --attach "${PROCESS_NAME}" \
  --time-limit "${DURATION}s" \
  --output "${OUT_DIR}/core-animation-${STAMP}.trace"

echo "Done. Traces saved in: ${OUT_DIR}"
