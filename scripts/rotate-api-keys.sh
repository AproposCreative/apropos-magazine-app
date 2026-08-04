#!/usr/bin/env bash
# Rotate Google API key via gcloud, prompt for new OpenAI key, update local secrets.
# Prereq: gcloud auth login && gcloud config set project apropos-magazine-6004a
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/AproposMagazinev2/Resources/Secrets.plist"
GSI_PLIST="$ROOT/AproposMagazinev2/AproposMagazinev2/GoogleService-Info.plist"
ENV_FILE="$ROOT/.env"
PROJECT="${GCP_PROJECT:-apropos-magazine-6004a}"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.frederikkragh.aproposmagazinev2}"
KEY_DISPLAY_NAME="Apropos Magazine iOS $(date +%Y-%m-%d)"

read_old_google() {
  if [[ -f "$PLIST" ]]; then
    plutil -extract GOOGLE_API_KEY raw "$PLIST" 2>/dev/null || true
  fi
}

read_old_openai() {
  if [[ -f "$PLIST" ]]; then
    plutil -extract OPENAI_API_KEY raw "$PLIST" 2>/dev/null || true
  fi
}

update_plist_key() {
  local key="$1" value="$2"
  if plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1; then
    plutil -replace "$key" -string "$value" "$PLIST"
  else
    plutil -insert "$key" -string "$value" "$PLIST"
  fi
}

update_gsi_api_key() {
  local value="$1"
  if [[ -f "$GSI_PLIST" ]] && plutil -extract API_KEY raw "$GSI_PLIST" >/dev/null 2>&1; then
    plutil -replace API_KEY -string "$value" "$GSI_PLIST"
  fi
}

update_env_key() {
  local name="$1" value="$2"
  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi
  if grep -q "^${name}=" "$ENV_FILE"; then
    sed -i '' "s|^${name}=.*|${name}=${value}|" "$ENV_FILE"
  else
    echo "${name}=${value}" >> "$ENV_FILE"
  fi
}

update_keychain() {
  local service="$1" value="$2"
  security delete-generic-password -s "$service" -a api_key 2>/dev/null || true
  security add-generic-password -s "$service" -a api_key -w "$value" -U
}

echo "=== Google API key rotation (project: $PROJECT) ==="
gcloud config set project "$PROJECT" >/dev/null
OLD_GOOGLE="$(read_old_google || true)"
echo "Current Google key prefix: ${OLD_GOOGLE:0:12}..."

NEW_GOOGLE="$(gcloud services api-keys create \
  --display-name="$KEY_DISPLAY_NAME" \
  --api-target=service=firebase.googleapis.com \
  --api-target=service=identitytoolkit.googleapis.com \
  --format='value(keyString)' 2>/dev/null || true)"

if [[ -z "$NEW_GOOGLE" ]]; then
  echo "Creating unrestricted key (add iOS restriction in Console if needed)..."
  NEW_GOOGLE="$(gcloud alpha services api-keys create \
    --display-name="$KEY_DISPLAY_NAME" \
    --format='value(keyString)')"
fi

echo "New Google key created."

if [[ -n "$OLD_GOOGLE" && "$OLD_GOOGLE" != "$NEW_GOOGLE" ]]; then
  OLD_UID="$(gcloud services api-keys list --filter="restrictions.api_targets:firebase OR displayName~Apropos" --format='value(uid)' 2>/dev/null | head -1 || true)"
  if [[ -z "$OLD_UID" ]]; then
    echo "List keys in Console and delete the old key manually:"
    echo "  https://console.cloud.google.com/apis/credentials?project=$PROJECT"
  else
    echo "Delete old keys manually in Console after verifying the app works."
  fi
fi

echo "=== OpenAI API key ==="
echo "Create a new key at https://platform.openai.com/api-keys and revoke the old one."
read -r -s -p "Paste new OPENAI_API_KEY: " NEW_OPENAI
echo

[[ -f "$PLIST" ]] || { echo "Missing $PLIST"; exit 1; }

update_plist_key GOOGLE_API_KEY "$NEW_GOOGLE"
update_plist_key OPENAI_API_KEY "$NEW_OPENAI"
update_gsi_api_key "$NEW_GOOGLE"
update_env_key GOOGLE_API_KEY "$NEW_GOOGLE"
update_env_key FIREBASE_API_KEY "$NEW_GOOGLE"
update_env_key OPENAI_API_KEY "$NEW_OPENAI"
update_keychain google "$NEW_GOOGLE"
update_keychain openai "$NEW_OPENAI"

echo "Updated Secrets.plist, GoogleService-Info.plist (if present), .env, and Keychain."
echo "Rebuild the app and test Firebase + OpenAI features."
