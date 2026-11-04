#!/usr/bin/env bash
# The same unsigned, hermetic native test entry point locally and on CI.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export npm_config_ignore_scripts=true
export APROPOS_CRASHLYTICS_UPLOAD=NO

# Missing/changed pins and wrong tools fail before any test/build SDK work.
LOCK_BEFORE="$(python3 scripts/ios-ci-preflight.py lock)"
DESTINATION="$(python3 scripts/ios-ci-preflight.py)"
node scripts/native-diagnostics-check.mjs

RUN_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/apropos-native-ci.XXXXXX")"
DERIVED_DATA_PATH="$RUN_DIRECTORY/DerivedData"
if [[ -n "${APROPOS_XCRESULT_PATH:-}" ]]; then
  RESULT_PATH="$APROPOS_XCRESULT_PATH"
else
  RESULT_PATH="$RUN_DIRECTORY/Tests.xcresult"
fi
if [[ -e "$RESULT_PATH" ]]; then
  echo "Refusing to overwrite an existing test result: $RESULT_PATH" >&2
  exit 1
fi

set +e
xcodebuild \
  -project AproposMagazinev2.xcodeproj \
  -scheme AproposMagazinev2 \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -parallel-testing-enabled NO -only-testing:AproposMagazineTests -collect-test-diagnostics never \
  -test-timeouts-enabled YES \
  -resultBundlePath "$RESULT_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  'EXCLUDED_SOURCE_FILE_NAMES=Secrets.plist GoogleService-Info.plist' \
  test
TEST_STATUS=$?
set -e

# Check even on failure. A package rewrite must never become a green job.
LOCK_AFTER="$(python3 scripts/ios-ci-preflight.py lock)"
if [[ "$LOCK_BEFORE" != "$LOCK_AFTER" ]]; then
  echo "Package lock changed during verification" >&2
  exit 1
fi
if [[ "$TEST_STATUS" -eq 0 ]]; then
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Apropos.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "The tested app bundle is missing" >&2
    exit 1
  fi
  if [[ -n "$(find "$APP_PATH" -type f \( -name Secrets.plist -o -name GoogleService-Info.plist \) -print -quit)" ]]; then
    echo "Private configuration unexpectedly reached the unit-test app" >&2
    exit 1
  fi
  xcrun xcresulttool get test-results summary --path "$RESULT_PATH" --format json > "$RESULT_PATH.summary.json"
  python3 scripts/ios-ci-preflight.py result "$RESULT_PATH.summary.json"
fi
echo "Native results: $RESULT_PATH"
exit "$TEST_STATUS"
