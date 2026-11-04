#!/usr/bin/env bash
# Local checks only. Never install dependencies, contact app services, or sign.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
MODE="${1:-checks}"

case "$MODE" in
  checks|build|test|release) ;;
  *) echo "Usage: bash scripts/verify-local.sh [checks|build|test|release]" >&2; exit 2 ;;
esac

export npm_config_ignore_scripts=true
node --check functions/index.js
node --check functions/narration.js
for script in functions/*.js scripts/*.mjs scripts/lib/*.mjs scripts/tests/*.mjs; do
  node --check "$script"
done
for script in scripts/*.sh; do
  bash -n "$script"
done
node --test functions/*.test.js scripts/tests/*.test.mjs
node scripts/native-diagnostics-check.mjs
git diff --check

if [[ "$MODE" == checks ]]; then
  exit 0
fi

BUILD_CONFIGURATION=Debug
BUILD_ACTION=build
BUILD_DESTINATION='generic/platform=iOS Simulator'
if [[ "$MODE" == release ]]; then
  BUILD_CONFIGURATION=Release
elif [[ "$MODE" == test ]]; then
  BUILD_ACTION=test
  # Override when using a different installed simulator; no device is created.
  BUILD_DESTINATION="${APROPOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
fi


# Keep unit execution serial and retain XCTest results without a lengthy
# system-wide simulator diagnosis after a local assertion failure.
if [[ "$MODE" == test ]]; then
  set -- -parallel-testing-enabled NO -only-testing:AproposMagazineTests -collect-test-diagnostics never
else
  set --
fi

xcodebuild \
  -project AproposMagazinev2.xcodeproj \
  -scheme AproposMagazinev2 \
  -configuration "$BUILD_CONFIGURATION" \
  -destination "$BUILD_DESTINATION" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  "$@" CODE_SIGNING_ALLOWED=NO "$BUILD_ACTION"
