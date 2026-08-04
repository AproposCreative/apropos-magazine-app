# Device smoke checklist (bugs + perf)

## Lock screen
- [ ] Play podcast → lock phone → only **one** native Now Playing card
- [ ] Control Center play/pause/skip still works
- [ ] No "Apropos Podcast" Live Activity pill

## Navigation
- [ ] Open article → Læs også → open related → **one** back returns to Home

## Auth / Min side
- [ ] Favorite articles while logged in
- [ ] Log out → Min side empty
- [ ] Log in again → cloud favorites restore (requires deployed Firestore `users` rules)

## Offline
- [ ] Favorite article (with audio) while online → article pill shows **Gemt**
- [ ] Airplane mode → open favorited article → body visible + **Gemt** pill; listen button only if audio cached
- [ ] Airplane mode → open non-favorited article → **Ikke downloadet** pill; no listen button
- [ ] Airplane mode → play unpinned audio from home → alert "Ikke downloadet"
- [ ] Airplane mode → play pinned/favorited audio → plays from cache

## Dual icon
- [ ] Only one "Apropos" icon after install (delete leftover Xcode/TestFlight install if two remain)

## Performance
- [ ] Cold launch feels snappy with cache
- [ ] Home scroll while podcast plays does not hitch once/sec
- [ ] Open long article → no repeated HTML reloads / layout jump storms

## Deploy note
```bash
firebase login --reauth
firebase deploy --only firestore:rules
```
