# Security

## Secret handling

| Secret | Where it lives | In git? |
|--------|----------------|---------|
| Google API key | `Secrets.plist`, Keychain, `GOOGLE_API_KEY` env | No |
| OpenAI API key | `Secrets.plist`, Keychain | No |
| Push notify secret | `Secrets.plist`, Firebase Functions env | No |
| Podcast manifest URL (optional) | `Secrets.plist` `PODCAST_MANIFEST_URL` | No |
| Firebase download tokens | Storage metadata + `manifest.json` at runtime | No |

Copy `AproposMagazinev2/Resources/Secrets.example.plist` → `Secrets.plist` and fill in values locally.

## GitGuardian

- Pre-commit: `ggshield install -m local` (blocks new secrets)
- Cursor MCP: GitGuardian workspace **AproposCreative**
- Config: `.ggshield.yaml` ignores local plist copies

Scan before push:

```bash
ggshield secret scan path .
```

## Rotate these keys (manual)

If keys were ever committed or flagged as **Valid** in GitGuardian:

1. **Google API key** — [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → create new key → restrict by iOS bundle ID → update `Secrets.plist` / Keychain → delete old key.
2. **OpenAI API key** — [OpenAI dashboard](https://platform.openai.com/api-keys) → revoke old → update `Secrets.plist`.
3. **Firebase Storage tokens** — rotate by re-uploading files with new tokens via `node scripts/podcast-auto-publish.mjs`, or deploy public-read rules (see below).

## Git history

Incident **#21857556** (Google API key in old `SecureConfig.swift`) remains in history until you:

- rotate the key (required either way), and optionally
- rewrite history with `git filter-repo` (coordinate with anyone else using the repo).

Current `SecureConfig.swift` does not embed keys.

## Podcast URLs

The app loads episodes from `podcasts/manifest.json` (no hardcoded tokens in Swift).

1. Publish manifest: `node scripts/podcast-auto-publish.mjs --manifest-only`
2. **Option A (recommended):** deploy storage rules so manifest works without `token=`:

   ```bash
   firebase deploy --only storage
   ```

3. **Option B:** paste the printed `manifest url:` into `PODCAST_MANIFEST_URL` in `Secrets.plist`.

## Firebase Storage rules

`storage.rules` allows public **read** on `podcasts/**`. Deploy after pulling:

```bash
firebase deploy --only storage
```
