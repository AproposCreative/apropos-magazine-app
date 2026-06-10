#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/functions"

echo "→ Deployer sendTestArticleNotification + webflowWebhook …"
npx -y firebase-tools@latest deploy \
  --only functions:sendTestArticleNotification,functions:webflowWebhook \
  --project apropos-magazine-6004a

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if [[ -z "${PODCAST_NOTIFY_SECRET:-}" ]]; then
  echo "⚠️  PODCAST_NOTIFY_SECRET mangler i .env — springer curl-test over."
  exit 0
fi

echo "→ Sender test artikel-push til emnet new_articles …"
curl -sS -X POST \
  "https://us-central1-apropos-magazine-6004a.cloudfunctions.net/sendTestArticleNotification" \
  -H "Content-Type: application/json" \
  -H "X-Apropos-Podcast-Secret: ${PODCAST_NOTIFY_SECRET}" \
  -d '{"title":"Test artikel","body":"Team push-test"}'
echo ""
