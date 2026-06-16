#!/usr/bin/env bash
# Update OpenAI API key locally after creating one at platform.openai.com/api-keys
set -euo pipefail
NEW="${1:-}"
if [[ -z "$NEW" || "$NEW" != sk-* ]]; then
  echo "Usage: $0 sk-..."
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/AproposMagazinev2/Resources/Secrets.plist"
ENV="$ROOT/.env"
plutil -replace OPENAI_API_KEY -string "$NEW" "$PLIST"
[[ -f "$ENV" ]] && sed -i '' "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$NEW|" "$ENV"
security delete-generic-password -s openai -a api_key 2>/dev/null || true
security add-generic-password -s openai -a api_key -w "$NEW" -U
echo "OpenAI key updated in Secrets.plist, .env, and Keychain."
