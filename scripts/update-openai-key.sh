#!/usr/bin/env bash
# Retired during local recovery: this script previously mixed production
# operations with client credential writes or an all-subscriber push test.
set -euo pipefail
printf '%s\n' 'This legacy command is retired. No credentials or services were changed.' >&2
printf '%s\n' 'Use Docs/LaunchReadinessChecklist.md for the reviewed provisioning and release plan.' >&2
printf '%s\n' 'Server API keys must never be written into the iOS app. Production actions require separate approval.' >&2
exit 2
