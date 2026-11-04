#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./Scripts/profile-device.sh <DEVICE_UDID> [DURATION_SECONDS] [PROCESS_NAME]
#
# Example:
# ./Scripts/profile-device.sh 00008150-000548A10ADB401C 25 "Apropos"

DEVICE_UDID="${1:-}"
DURATION="${2:-25}"
PROCESS_NAME="${3:-Apropos}"
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

echo "Recording Animation Hitches (${DURATION}s) on ${DEVICE_UDID}..."
xcrun xctrace record \
  --template "Animation Hitches" \
  --device "${DEVICE_UDID}" \
  --attach "${PROCESS_NAME}" \
  --time-limit "${DURATION}s" \
  --output "${OUT_DIR}/animation-hitches-${STAMP}.trace"

echo "Done. Traces saved in: ${OUT_DIR}"
