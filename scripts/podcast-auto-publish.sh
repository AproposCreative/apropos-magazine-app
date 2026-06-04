#!/usr/bin/env bash
# One command after uploading raw podcast(s) to Firebase.
# See: Docs/PODCAST_UPLOAD.md
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
node scripts/podcast-auto-publish.mjs "$@"
