#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-AproposMagazinev2}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro}"
WORKSPACE="${WORKSPACE:-AproposMagazinev2.xcodeproj}"

echo "Running tests for scheme '${SCHEME}' on ${DESTINATION}"

if command -v xcpretty >/dev/null 2>&1; then
  xcodebuild \
    -project "${WORKSPACE}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    clean test | xcpretty
else
  xcodebuild \
    -project "${WORKSPACE}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    clean test
fi
