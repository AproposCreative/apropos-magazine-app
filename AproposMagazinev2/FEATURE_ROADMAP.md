# Feature Roadmap — Apropos Magazine (iOS)

**Opdateret:** juli 2026  
**Formål:** Afspejle hvad der er bygget, hvad der er bag feature flags, og hvad der giver mest værdi næste.

---

## ✅ Shipped (produktion / TestFlight-klar)

### Kerne-app
- **4 tabs:** Hjem, Artikler, Kategorier, Min side
- **Artikler:** Webflow/Firestore-sync, hero, kategorier, søg, relaterede artikler
- **Artikelvisning:** HTML-brødtekst (WebView), intro, stjerner (6-skala), foto-credit, trailer-embed, share cards
- **Offline:** Billed-cache til artikler, disk-cache til podcast-lyd
- **Læseprogress:** iCloud-sync + analytics
- **Push:** Ny artikel (+ AI-oplæsning når lyd er klar), silent refresh til feed/widget
- **Deep links:** `aproposmagazine://article/{id}` fra widget og notifikationer

### AI-oplæsning (ElevenLabs) — ikke AVSpeech
- **Pipeline:** Webflow webhook → `narration_queue` → `generateNarrationOnQueue` (Cloud Function)
- **TTS:** ElevenLabs med chunking, jingle, upload til `podcasts/narration/{slug}/`
- **Politik:** Ingen push ved engelske oversættelser eller republication; narration køes stadig
- **Scripts:** `scripts/narration-poc.mjs`, `narration-queue.mjs`, `narration-scan.mjs`, `podcast-auto-publish.mjs`
- **UI:** "Oplæst med AI"-badge på lydindhold-kort og i afspilleren
- **Afhængighed:** ElevenLabs-kvote — generering fejler med `quota_exceeded` når kvoten er brugt op

### Podcast / lydafspiller
- **Kilder:** AI-narration (`podcasts/narration/`) + manuelle/NotebookLM-afsnit (`podcasts/articles/`)
- **Manifest:** `podcasts/manifest.json` — app henter automatisk
- **Afspiller:** Mini-player, fuld player, kø, sleep timer, hastighed, lock screen / Control Center
- **Lock screen:** Kun native Now Playing (Live Activity er slået fra for at undgå dobbelt afspiller)
- **Performance:** Throttled UI-opdateringer, deferred disk-cache, ingen feed-refresh under aktiv afspilning
- **Hjem:** Sektion "Lydindhold", "Fortsæt hvor du slap"

### Widget
- **Seneste artikel:** Small / medium / large via App Group (`WidgetDataStore`)
- **Billeder:** WidgetImageStore med hurtig refresh efter første sync

### Dual home-screen icons
- Ikke en packaging-bug: én app-target. To ikoner = to installs med samme display-navn (fx Xcode + TestFlight, eller gammel bundle ID).
- Slet den forældede install på enheden. Display-navn er forkortet til **"Apropos"**.

### Backend (Firebase Functions)
| Function | Rolle |
|----------|--------|
| `webflowWebhook` | Sync artikel + kø narration + push-politik |
| `generateNarrationOnQueue` | ElevenLabs TTS + manifest + push |
| `syncArticlesScheduled` | Firestore-sync hvert 30. min |
| `generateSeries` / scheduled | AI-genererede artikelserier |
| `generateRecommendationReasons` | Personlige anbefalingstekster |
| `sendPodcastNotification` | Manuel podcast-push |

---

## 🟡 Bygget men ikke tændt (paywall)

### Abonnement
- **Feature flag:** `subscriptions_enabled` = `false` i `FeatureFlags` (default)
- **Adgangspolitik:** `ArticleAccessPolicy` + `isPremium` på artikler
- **UI:** Paywall-kort i artikelvisning når flag er slået til og bruger ikke er abonnent
- **Mangler før launch:**
  1. Produkter i App Store Connect (StoreKit 2)
  2. `SubscriptionManager` koblet til køb/gendannelse
  3. Sæt `subscriptions_enabled` til `true` når produkter er live
  4. TestFlight-test af premium vs. gratis artikler

---

## 🔧 Kendte opfølgningspunkter

| Emne | Status |
|------|--------|
| ElevenLabs backfill | Kør `narration-scan.mjs` → `narration-queue.mjs --run` efter kvote-genopfyldning |
| Widget-freshness | Silent push + `WidgetDataStore` — verificér på device efter ny artikel |
| `FEATURE_ROADMAP.md` | Denne fil |
| Orphan components | `MarqueeText.swift` fjernet (erstattet af statisk/truncated tekst i player) |

---

## 🎯 Anbefalet næste sprint (prioriteret)

### 1. Monetisering (høj impact)
- App Store Connect-abonnementer
- Tænd `subscriptions_enabled`
- Paywall-copy og onboarding

### 2. Indhold & lyd (høj impact)
- ElevenLabs-kvote + backfill manglende artikler
- Overvåg `generateNarrationOnQueue`-logs

### 3. Discovery (medium impact)
- Vis `generateRecommendationReasons` i "Anbefalet til dig"
- Forbedret søg (filtre, historik)

### 4. Læseoplevelse — quick wins (medium impact, lav indsats)
- Læsetid på artikelkort ("X min")
- Fontstørrelse i artikelvisning (UserDefaults)
- Læsehistorik på Min side

### 5. Video (medium impact, høj indsats)
- Native `AVPlayer` til trailere i stedet for `WKWebView`
- Picture-in-Picture

---

## 📋 Backlog (ikke startet / tidligere idéer)

Disse stod i den gamle roadmap og er **ikke** implementeret:

- AVSpeechSynthesizer on-device TTS (erstattet af ElevenLabs-pipeline)
- Social: læsegrupper, kommentarer, threaded replies
- Interaktive artikler: polls, timelines, 360°/AR
- Gamification: achievements, leaderboards
- macOS-app, App Clips, Siri shortcuts
- Cross-device sync ud over iCloud læseprogress

---

## 📊 Fase-overblik

| Fase | Fokus | Status |
|------|--------|--------|
| **1 — Core** | Artikler, push, widget, offline billeder | ✅ |
| **2 — Lyd** | ElevenLabs, podcast player, Live Activity | ✅ (kvote/backfill rester) |
| **3 — Monetisering** | Paywall + StoreKit | 🟡 Kode klar, flag off |
| **4 — Personalisering** | Recommendation reasons, smarter feed | 🔜 |
| **5 — Polish** | Læsetid, font, video player | 🔜 |

---

## Relateret dokumentation

- `Docs/LaunchReadinessChecklist.md` — device profiling og release-smoke-test
- `Docs/PodcastAudioWorkflow.md` — manuel NotebookLM-upload + manifest
- `Docs/PODCAST_UPLOAD.md` — upload-detaljer
- `functions/notificationPolicy.js` — push-filtrering (engelsk, republication)
