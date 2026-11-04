#!/usr/bin/env bash
# Native UI tests with local fixtures. No installs of packages, signing or services.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
SIMULATOR_ID="${APROPOS_SMOKE_SIMULATOR_ID:-C78009BF-2E7B-4E23-B977-8AA22B98FB45}"
RESULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apropos-smoke.XXXXXX")"
export npm_config_ignore_scripts=true
echo "Simulator: $SIMULATOR_ID"
echo "Resultater: $RESULT_DIR"
# An explicit existing simulator avoids accidental physical-device runs or resets.
xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
if not any(d["udid"] == sys.argv[1] for values in devices.values() for d in values):
    sys.exit("Den valgte simulator skal være startet. Ingen enhed er oprettet eller slettet.")
' "$SIMULATOR_ID"
xcodebuild \
  -project AproposMagazinev2.xcodeproj -scheme AproposSmoke \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 180 \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$RESULT_DIR/AccountSmoke.xcresult" \
  CODE_SIGNING_ALLOWED=NO test > "$RESULT_DIR/xcodebuild.log" 2>&1 || {
    tail -n 60 "$RESULT_DIR/xcodebuild.log"
    exit 1
  }
xcrun xcresulttool get test-results summary --path "$RESULT_DIR/AccountSmoke.xcresult"
