# Podcast upload (Apropos Magazine)

Upload raw audio from NotebookLM to **Firebase Storage**. Appen henter episoder automatisk fra `podcasts/manifest.json` — **ingen app-update per episode**.

## Din workflow (ny episode)

### 1. Upload rå lyd

**Firebase Console** → Storage → `podcasts/incoming/`

1. Opret mappe med **Webflow artikel-slug**, fx `min-ny-artikel/`
2. Upload rå `.m4a` fra NotebookLM
3. *(Anbefalet)* Læg `podcast.json` i samme mappe:

```json
{
  "title": "Backrooms",
  "hosts": ["Liv Brandt", "Frederik Kragh"]
}
```

### 2. Kør publish-script

```bash
cd "/Users/frederikkragh/Library/CloudStorage/Dropbox/AproposMagazine.com/07. iOS App - Apropos Magazine"
export PODCAST_NOTIFY_SECRET="dit-hemmelige-token"   # valgfrit: push-notifikation
./scripts/podcast-auto-publish.sh
```

Scriptet:
- Optimerer lyd (AAC 96k)
- Uploader til `podcasts/articles/{slug}/`
- Gemmer `podcast.json` metadata i articles-mappen
- **Opdaterer `podcasts/manifest.json`** (appen henter automatisk)
- Sender push *(hvis `PODCAST_NOTIFY_SECRET` er sat)*

### 3. Færdig

Brugere med den nye app-version ser episoden efter næste app-åbning eller pull-to-refresh på forsiden.

> **Én gang:** Denne build skal udgives med dynamisk manifest. Derefter ingen app-update per podcast.

## Opdater eksisterende episode

1. Upload/replace rå `.m4a` i `podcasts/articles/{slug}/`
2. Kør `./scripts/podcast-auto-publish.sh`
3. Manifest opdateres — samme audio-URL hvis token bevares

## Kun manifest (uden re-encode)

```bash
./scripts/podcast-auto-publish.sh --manifest-only
```

## Mappestruktur

```
podcasts/
  manifest.json          ← appens katalog (auto-genereret)
  incoming/              ← nye rå filer
    {slug}/
      episode.m4a
      podcast.json       ← titel + værter
  articles/              ← optimeret lyd
    {slug}/
      {slug}.m4a
      podcast.json
```

## Push-notifikation

- **Titel:** `Ny Apropos Podcast ude nu: {titel}`
- **Brødtekst:** `{titel}, {værter}`
- Sendes til `new_articles` + `new_podcasts`

### Deploy push-endpoint (én gang)

Cloud function `sendPodcastNotification` skal deployes før scriptet kan sende push automatisk.

```bash
firebase login --reauth
cd "/Users/frederikkragh/Library/CloudStorage/Dropbox/AproposMagazine.com/07. iOS App - Apropos Magazine"

# Vælg et hemmeligt token (gem det sikkert — bruges i begge trin)
firebase functions:secrets:set PODCAST_NOTIFY_SECRET

# Deploy kun podcast-notify function
firebase deploy --only functions:sendPodcastNotification --project apropos-magazine-6004a
```

Verificer at endpoint svarer **403** (ikke 404):

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://us-central1-apropos-magazine-6004a.cloudfunctions.net/sendPodcastNotification"
```

Brug derefter samme secret lokalt ved publish:

```bash
export PODCAST_NOTIFY_SECRET="dit-token"
./scripts/podcast-auto-publish.sh
```

## Første gang / auth

```bash
brew install ffmpeg
gcloud auth application-default login
```

## Flags

| Flag | Betydning |
|------|-----------|
| `--dry-run` | Vis hvad der ville ske |
| `--incoming-only` | Kun `podcasts/incoming/` |
| `--scan-only` | Kun optimer store filer |
| `--manifest-only` | Kun opdater manifest.json |
| `--force` | Re-optimer alle |
