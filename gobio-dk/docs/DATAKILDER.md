# Datakilder - Teknisk Oversigt

## Hvordan trækker vi biografdata?

Gobio.dk bruger en kombination af API'er og web scraping til at samle spilletider fra danske biografer.

---

## 1. TMDB API (Film-metadata)

**Formål:** Alt filmdata udover spilletider - posters, trailers, beskrivelser, cast, ratings.

**Gratis:** Ja, kræver kun en API-nøgle.

### Endpoints vi bruger

| Endpoint | Formål | Cache TTL |
|----------|--------|-----------|
| `GET /3/movie/now_playing?region=DK&language=da-DK` | Aktuelle film i DK biografer | 1 time |
| `GET /3/movie/upcoming?region=DK&language=da-DK` | Kommende film | 6 timer |
| `GET /3/movie/{id}?language=da-DK` | Film-detaljer | 24 timer |
| `GET /3/movie/{id}/videos?language=da-DK` | Trailers (YouTube keys) | 24 timer |
| `GET /3/movie/{id}/credits` | Cast & crew | 24 timer |
| `GET /3/search/movie?language=da-DK` | Søg i film | Ingen cache |

### Film-matching

For at matche film fra biografernes sider med TMDB-data bruges:
1. Titel-matching (fuzzy match med `levenshtein distance`)
2. TMDB søge-API som fallback
3. Manuel mapping-tabel for edge cases (f.eks. danske titler)

---

## 2. International Showtimes API (Spilletider)

**Formål:** Spilletider fra danske biografer med booking-links.

**Pris:** Fra 149€/md.

### Endpoints

| Endpoint | Formål |
|----------|--------|
| `GET /v4/cinemas?countries=DK` | Alle danske biografer |
| `GET /v4/showtimes?countries=DK&movie_id={id}` | Spilletider for en film |
| `GET /v4/showtimes?countries=DK&cinema_id={id}` | Spilletider for en biograf |
| `GET /v4/movies?countries=DK` | Film i danske biografer |

### Data der returneres
- Spilletid (dato + tidspunkt)
- Biograf (navn, adresse, kæde)
- Format (2D, 3D, IMAX)
- Sprog og undertekster
- Booking-link (direkte til biografens bookingside)

---

## 3. Web Scraping (Supplement/Fallback)

Hvis International Showtimes API ikke dækker alle biografer, bygger vi egne scrapers.

### Nordisk Film Biografer (nfbio.dk)

**Sider der scrapes:**
- `https://www.nfbio.dk/se-alle-aktuelle-film-her?city={city}`
- `https://new.nfbio.dk/` (nyere version)

**Teknisk:**
- Siden bruger JavaScript rendering → kræver Playwright/Puppeteer
- Spilletider vises i et grid med dato-tabs
- Booking-URL kan konstrueres: `https://www.nfbio.dk/film/{film-slug}`

### Vue / CinemaxX (cinemaxx.dk)

**Sider der scrapes:**
- `https://www.cinemaxx.dk/`
- `https://www.biografenvue.dk/`

**Teknisk:**
- Muligvis interne API-endpoints der kan interceptes
- Check network tab for XHR/fetch requests

### Scraping Schedule

```
┌─────────────────────────────────────────┐
│  Cron Schedule (UTC)                     │
│                                          │
│  06:00 - Fuld sync (alle biografer)     │
│  12:00 - Delta sync (ændringer)         │
│  18:00 - Delta sync (ændringer)         │
│  00:00 - Cleanup (fjern udløbne tider)  │
└─────────────────────────────────────────┘
```

### Rate Limiting

For at undgå at belaste biografernes servere:
- Max 1 request per sekund per kilde
- Exponential backoff ved fejl
- Respekter robots.txt
- Brug caching til at minimere requests

---

## 4. Data Pipeline

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Scrapers   │     │  Showtimes   │     │   TMDB       │
│   (nfbio,    │────>│   API        │────>│   API        │
│   vue, etc)  │     │              │     │              │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └─────────┬──────────┘                    │
                 │                               │
        ┌────────▼────────┐             ┌────────▼────────┐
        │  Normalization  │             │  Movie Metadata │
        │  & Dedup Layer  │             │  Enrichment     │
        └────────┬────────┘             └────────┬────────┘
                 │                               │
                 └──────────┬────────────────────┘
                            │
                   ┌────────▼────────┐
                   │   PostgreSQL    │
                   │   (Supabase)    │
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐
                   │   Redis Cache   │
                   │   (Upstash)     │
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐
                   │   API Server    │
                   │   (Next.js)     │
                   └─────────────────┘
```

---

## 5. Anbefalet Implementeringsrækkefølge

1. **TMDB API** → Gratis, hurtig at implementere, giver filmdata med det same
2. **International Showtimes API trial** → 7 dages gratis, test dansk dækning
3. **Kontakt biografkæder** → Etabler samarbejde parallelt
4. **Web scrapers** → Byg kun for biografer der ikke dækkes af Showtimes API
5. **Direkte API-integration** → Langsigtet mål med biografkæder
