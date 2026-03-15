# Gobio.dk - Projekt Grundlag

## Projektbeskrivelse

**Gobio.dk** er en dansk biografguide-platform (app + website) der samler spilletider for biograffilm på tværs af alle biografkæder i Danmark. Platformen giver brugerne et samlet overblik over hvad der spiller, hvor og hvornår - uanset om det er Nordisk Film Biografer, Vue (tidl. CinemaxX), eller en af de mange mindre/uafhængige biografer.

### Kerneværdi
I dag skal man besøge flere forskellige hjemmesider for at sammenligne spilletider. Gobio.dk løser dette ved at samle alt ét sted - ligesom Momondo gør for flyrejser, gør Gobio.dk det for biografoplevelser.

---

## Funktionalitet

### MVP (Minimum Viable Product)

| # | Feature | Beskrivelse |
|---|---------|-------------|
| 1 | **Filmkatalog** | Oversigt over alle aktuelle og kommende film med poster, beskrivelse, genre, instruktør, skuespillere og varighed |
| 2 | **Trailers** | Indlejrede YouTube-trailers på hver filmside |
| 3 | **Spilletider på tværs** | Samlet visning af spilletider fra alle biografkæder, filtreret på by, dato og biograf |
| 4 | **Bestil-knap (redirect)** | En "Bestil billetter"-knap der redirecter brugeren til den pågældende biografkædes bookingside |
| 5 | **Brugeroprettelse** | Opret konto med email/password eller social login (Google/Apple) |
| 6 | **Watchlist** | Tilføj film til en personlig "vil se"-liste |
| 7 | **Premiere-notifikationer** | Push-notifikation (app) og email når en film på brugerens watchlist har premiere |
| 8 | **Søgning & filtrering** | Søg på filmnavn, genre, biograf, by |
| 9 | **By-vælger** | Vælg by/region for at se relevante biografer og spilletider |

### Post-MVP (Fremtidige features)

| # | Feature | Beskrivelse |
|---|---------|-------------|
| 10 | **Brugeranmeldelser** | Brugere kan rate og anmelde film |
| 11 | **Sociale features** | Del film med venner, se hvad venner vil se |
| 12 | **Pris-sammenligning** | Vis billetpriser fra forskellige biografer |
| 13 | **Biografprofiler** | Detaljeret info om hver biograf (faciliteter, parkereing, tilgængelighed) |
| 14 | **Personlige anbefalinger** | AI-baserede filmanbefalinger baseret på smagshistorik |
| 15 | **Kalenderintegration** | Tilføj forestilling til telefon-kalender |
| 16 | **Kampagnetilbud** | Vis tilbud og rabatter fra biograferne |

---

## Datakilder - Hvordan trækkes data?

### Svaret på dit spørgsmål: Ja, det kan lade sig gøre!

Der er flere måder at aggregere biografdata på, og de kan kombineres:

### 1. International Showtimes API (Anbefalet primær kilde)

**URL:** https://api.internationalshowtimes.com

En kommerciel API der leverer biografdata for 120+ lande inklusive Danmark.

- **Hvad den leverer:** Spilletider, biografer, filmmetadata, billettlinks, formater (IMAX, 3D, osv.)
- **Pris:** Fra 149€/måned (Basic) til 299€/måned (Business)
- **Gratis prøveperiode:** 7 dage
- **Fordele:** Struktureret data, pålidelig, inkluderer booking-links
- **Ulemper:** Månedlig omkostning, afhængighed af tredjepart

### 2. TMDB API (The Movie Database) - Film-metadata

**URL:** https://developer.themoviedb.org

Gratis API for filmdata (ikke spilletider).

- **Hvad den leverer:** Filmbeskrivelser, posters, trailers (YouTube-links), cast, ratings, udgivelsesdatoer, genrer
- **Pris:** Gratis (kræver API-nøgle)
- **Endpoints vi bruger:**
  - `GET /3/movie/popular` - Populære film
  - `GET /3/movie/upcoming` - Kommende film
  - `GET /3/movie/{id}/videos` - Trailers
  - `GET /3/movie/{id}` - Film-detaljer
  - `GET /3/search/movie` - Søgning
- **Sprog:** Understøtter dansk (`da-DK`)

### 3. Web Scraping (Backup/supplement)

Hvis International Showtimes API ikke dækker alle danske biografer, kan vi supplere med web scraping:

| Kilde | URL | Data |
|-------|-----|------|
| Nordisk Film Biografer | nfbio.dk | Spilletider, film, biografer |
| Vue (CinemaxX) | cinemaxx.dk / biografenvue.dk | Spilletider, film, biografer |
| Kino.dk | kino.dk | Aggregeret data (som reference) |

**Teknisk tilgang:**
- Headless browser (Puppeteer/Playwright) til JavaScript-renderede sider
- Scheduled scraping (cron jobs) 2-4 gange dagligt
- Rate limiting og respekt for robots.txt

**Juridisk bemærkning:** Web scraping af offentligt tilgængelige spilletider er generelt lovligt i EU, men:
- Vi viser kun spilletider og redirecter til booking (vi sælger ikke billetter)
- Vi bør kontakte biografkæderne for at etablere samarbejde
- GDPR-compliance er påkrævet for alle brugerdata

### 4. Direkte samarbejde med biografkæder (Langsigtet strategi)

Den mest bæredygtige løsning er at etablere partnerskaber:
- Kontakte Nordisk Film Biografer, Vue og uafhængige biografer
- Foreslå datadeling via API eller feed (XML/JSON)
- Værditilbud: Vi sender trafik til deres bookingsider

> **Anbefalet tilgang:** Start med TMDB API (gratis filmmeta) + International Showtimes API (prøveperiode), og kontakt biografkæderne parallelt for direkte samarbejde.

---

## Danske biografkæder og -er

### Store kæder

| Kæde | Antal biografer | Markedsandel | Website |
|------|----------------|--------------|---------|
| **Nordisk Film Biografer** | 23 biografer | ~42-44% | nfbio.dk |
| **Vue** (tidl. CinemaxX) | 4-6 biografer | ~15-20% | cinemaxx.dk / biografenvue.dk |

### Uafhængige biografer (udvalg)

| Biograf | By | Website |
|---------|-----|---------|
| Grand Teatret | København | grandteatret.dk |
| Cinemateket | København | dfi.dk/cinemateket |
| Øst for Paradis | Aarhus | paradisbio.dk |
| Bibliografen | Bagsværd | bibliografen.dk |
| BIG BIO | Herlev/Nordhavn | bigbio.dk |
| Fotorama | Aarhus/Viborg | fotorama.dk |
| Atlas Biograferne | Rødovre | atlas-bio.dk |

---

## Teknisk Arkitektur

### Tech Stack

```
┌──────────────────────────────────────────────────────┐
│                    FRONTEND                           │
│                                                      │
│  ┌─────────────────┐    ┌──────────────────────┐    │
│  │   Mobil App      │    │   Website             │    │
│  │   React Native   │    │   Next.js 15          │    │
│  │   + Expo SDK 53  │    │   (App Router)        │    │
│  │   iOS + Android  │    │   gobio.dk            │    │
│  └────────┬─────────┘    └──────────┬────────────┘    │
│           │                         │                 │
│           └────────┬────────────────┘                 │
│                    │                                  │
│         Shared UI Components                          │
│         (React Native Web)                            │
└────────────────────┼─────────────────────────────────┘
                     │
                     │ REST API / GraphQL
                     │
┌────────────────────┼─────────────────────────────────┐
│                 BACKEND                               │
│                    │                                  │
│  ┌─────────────────▼──────────────────┐              │
│  │         API Server                  │              │
│  │         Node.js + Express           │              │
│  │         eller Next.js API Routes    │              │
│  └──────┬──────────┬──────────┬───────┘              │
│         │          │          │                       │
│  ┌──────▼──┐ ┌─────▼────┐ ┌──▼──────────┐          │
│  │ Auth    │ │ Showtime │ │ Notification │          │
│  │ Service │ │ Aggr.    │ │ Service      │          │
│  └─────────┘ └──────────┘ └─────────────┘          │
│                                                      │
│  ┌──────────────────────────────────────┐            │
│  │        Data Aggregation Layer        │            │
│  │  - TMDB API Client                   │            │
│  │  - Int. Showtimes API Client         │            │
│  │  - Web Scrapers (fallback)           │            │
│  └──────────────────────────────────────┘            │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────┼───────────────────────────────┐
│                 DATABASE                              │
│                      │                                │
│  ┌───────────────────▼────────────────────┐          │
│  │         PostgreSQL (Supabase)           │          │
│  │  - Brugere, Watchlists, Præferencer    │          │
│  │  - Film-cache, Spilletider-cache       │          │
│  │  - Notifikationslog                    │          │
│  └────────────────────────────────────────┘          │
│                                                      │
│  ┌────────────────────────────────────────┐          │
│  │         Redis Cache                     │          │
│  │  - Spilletider (TTL: 2-4 timer)       │          │
│  │  - Film-metadata (TTL: 24 timer)      │          │
│  │  - Session management                  │          │
│  └────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────┘
```

### Detaljeret Tech Stack

| Lag | Teknologi | Begrundelse |
|-----|-----------|-------------|
| **Mobil App** | React Native + Expo SDK 53 | Cross-platform (iOS + Android), hurtig udvikling, OTA-opdateringer |
| **Website** | Next.js 15 (App Router) | SEO-venlig, server-side rendering, deler komponenter med app |
| **UI Framework** | Tailwind CSS + shadcn/ui (web), NativeWind (app) | Konsistent design, hurtig styling |
| **Backend** | Node.js + Express / Next.js API Routes | JavaScript/TypeScript hele vejen, god økosystem |
| **Database** | PostgreSQL via Supabase | Relationel, gratis tier, auth inkluderet, real-time subscriptions |
| **Cache** | Redis (Upstash) | Serverless Redis, gratis tier, perfekt til spilletids-cache |
| **Auth** | Supabase Auth | Email/password, Google, Apple login out-of-the-box |
| **Push Notifications** | Expo Notifications (app) + Resend (email) | Pålidelig levering, gratis tiers |
| **Filmdara** | TMDB API | Gratis, omfattende, dansk sprog understøttet |
| **Spilletider** | International Showtimes API + scrapers | Dækkende data med fallback |
| **Hosting** | Vercel (web) + Supabase (db) + Railway (scrapers) | Generøse gratis tiers, nem skalering |
| **CI/CD** | GitHub Actions | Automatisk test, build og deploy |
| **Monitoring** | Sentry | Fejlsporing i produktion |

---

## Database Schema

### ER-Diagram (Overordnet)

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│   users      │────<│  watchlist    │>────│     movies       │
│              │     │  _items      │     │                  │
└──────┬───────┘     └──────────────┘     └────────┬─────────┘
       │                                           │
       │             ┌──────────────┐              │
       │             │  showtimes   │>─────────────┘
       │             │              │
       │             └──────┬───────┘
       │                    │
       │             ┌──────▼───────┐
       │             │   cinemas    │
       │             │              │
       │             └──────┬───────┘
       │                    │
       │             ┌──────▼───────┐
       └────────────>│notifications │
                     │              │
                     └──────────────┘
```

### Tabeller

```sql
-- Brugere
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    preferred_city VARCHAR(100) DEFAULT 'København',
    notification_preferences JSONB DEFAULT '{"push": true, "email": true}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Film (cachet fra TMDB)
CREATE TABLE movies (
    id SERIAL PRIMARY KEY,
    tmdb_id INTEGER UNIQUE NOT NULL,
    title VARCHAR(500) NOT NULL,
    original_title VARCHAR(500),
    overview TEXT,
    poster_url TEXT,
    backdrop_url TEXT,
    trailer_youtube_key VARCHAR(20),
    release_date DATE,
    runtime_minutes INTEGER,
    genres JSONB,
    cast_list JSONB,
    director VARCHAR(255),
    tmdb_rating DECIMAL(3,1),
    danish_title VARCHAR(500),
    is_upcoming BOOLEAN DEFAULT FALSE,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Biografkæder
CREATE TABLE cinema_chains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    logo_url TEXT,
    website_url TEXT NOT NULL,
    booking_base_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Biografer
CREATE TABLE cinemas (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER REFERENCES cinema_chains(id),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    address TEXT,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    phone VARCHAR(20),
    website_url TEXT,
    facilities JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chain_id, slug)
);

-- Spilletider
CREATE TABLE showtimes (
    id SERIAL PRIMARY KEY,
    movie_id INTEGER REFERENCES movies(id) ON DELETE CASCADE,
    cinema_id INTEGER REFERENCES cinemas(id) ON DELETE CASCADE,
    starts_at TIMESTAMPTZ NOT NULL,
    format VARCHAR(50),
    language VARCHAR(50),
    subtitles VARCHAR(50),
    is_3d BOOLEAN DEFAULT FALSE,
    is_imax BOOLEAN DEFAULT FALSE,
    booking_url TEXT,
    hall_name VARCHAR(100),
    source VARCHAR(50) NOT NULL,
    external_id VARCHAR(255),
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(cinema_id, movie_id, starts_at)
);

-- Watchlist
CREATE TABLE watchlist_items (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    movie_id INTEGER REFERENCES movies(id) ON DELETE CASCADE,
    notify_on_premiere BOOLEAN DEFAULT TRUE,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, movie_id)
);

-- Notifikationer
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    movie_id INTEGER REFERENCES movies(id),
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

-- Indexes for performance
CREATE INDEX idx_showtimes_movie ON showtimes(movie_id);
CREATE INDEX idx_showtimes_cinema ON showtimes(cinema_id);
CREATE INDEX idx_showtimes_starts_at ON showtimes(starts_at);
CREATE INDEX idx_showtimes_lookup ON showtimes(movie_id, cinema_id, starts_at);
CREATE INDEX idx_cinemas_city ON cinemas(city);
CREATE INDEX idx_watchlist_user ON watchlist_items(user_id);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX idx_movies_tmdb ON movies(tmdb_id);
CREATE INDEX idx_movies_release ON movies(release_date);
```

---

## API Design

### REST API Endpoints

#### Film

```
GET    /api/movies                    # Liste over aktuelle film
GET    /api/movies/upcoming           # Kommende film
GET    /api/movies/:id                # Film-detaljer med trailers
GET    /api/movies/:id/showtimes      # Spilletider for en film
GET    /api/movies/search?q=          # Søg i film
```

#### Spilletider

```
GET    /api/showtimes                  # Alle spilletider (filtreret)
       ?city=København
       &date=2026-03-15
       &movie_id=123
       &cinema_id=456
GET    /api/showtimes/today            # Dagens spilletider
```

#### Biografer

```
GET    /api/cinemas                    # Alle biografer
GET    /api/cinemas/:id                # Biograf-detaljer
GET    /api/cinemas/:id/showtimes      # Spilletider for en biograf
GET    /api/cinemas/cities             # Liste over byer med biografer
```

#### Brugere & Auth

```
POST   /api/auth/register             # Opret bruger
POST   /api/auth/login                # Login
POST   /api/auth/logout               # Logout
GET    /api/auth/me                   # Nuværende bruger
PATCH  /api/users/me                  # Opdater profil
PATCH  /api/users/me/preferences      # Opdater præferencer
```

#### Watchlist

```
GET    /api/watchlist                  # Brugerens watchlist
POST   /api/watchlist/:movieId         # Tilføj film til watchlist
DELETE /api/watchlist/:movieId         # Fjern film fra watchlist
```

#### Notifikationer

```
GET    /api/notifications              # Brugerens notifikationer
PATCH  /api/notifications/:id/read     # Marker som læst
POST   /api/notifications/register     # Registrer push-token (app)
```

### API Response Format

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 150
  }
}
```

### Eksempel: Film med spilletider

```json
{
  "success": true,
  "data": {
    "movie": {
      "id": 1,
      "tmdb_id": 912649,
      "title": "Venom: The Last Dance",
      "danish_title": "Venom: The Last Dance",
      "overview": "Eddie Brock og symbioten Venom...",
      "poster_url": "https://image.tmdb.org/t/p/w500/...",
      "trailer_youtube_key": "abc123",
      "release_date": "2026-03-20",
      "runtime_minutes": 120,
      "genres": ["Action", "Sci-Fi"],
      "director": "Kelly Marcel",
      "tmdb_rating": 6.8
    },
    "showtimes": [
      {
        "id": 42,
        "cinema": {
          "name": "Imperial",
          "chain": "Nordisk Film Biografer",
          "city": "København"
        },
        "starts_at": "2026-03-20T19:00:00+01:00",
        "format": "2D",
        "language": "Engelsk",
        "subtitles": "Dansk",
        "booking_url": "https://nfbio.dk/film/venom-the-last-dance?cinema=imperial"
      },
      {
        "id": 43,
        "cinema": {
          "name": "Vue København",
          "chain": "Vue",
          "city": "København"
        },
        "starts_at": "2026-03-20T20:30:00+01:00",
        "format": "IMAX 3D",
        "language": "Engelsk",
        "subtitles": "Dansk",
        "booking_url": "https://cinemaxx.dk/film/venom-the-last-dance"
      }
    ]
  }
}
```

---

## User Flow

### Primær brugerrejse

```
1. Åbn gobio.dk / app
        │
2. Vælg by (København, Aarhus, Odense...)
        │
3. Se aktuelle film med posters
        │
4. Tryk på en film
        │
5. Se filminfo + trailer + spilletider fra ALLE biografer
        │
6. Tryk "Bestil" → Redirectes til biografens hjemmeside
        │
   (Valgfrit:)
        │
7. Opret bruger → Tilføj til watchlist → Få notifikation ved premiere
```

### Wireframes (Tekstbaseret)

#### Forside (Mobil)

```
┌─────────────────────────────┐
│  🎬 gobio.dk          ☰    │
│  📍 København  ▼            │
├─────────────────────────────┤
│  🔍 Søg efter film...       │
├─────────────────────────────┤
│                             │
│  AKTUELT I BIOGRAFEN        │
│                             │
│  ┌────┐ ┌────┐ ┌────┐      │
│  │    │ │    │ │    │      │
│  │ 🎬 │ │ 🎬 │ │ 🎬 │      │
│  │    │ │    │ │    │      │
│  └────┘ └────┘ └────┘      │
│  Film 1  Film 2  Film 3    │
│                             │
│  KOMMER SNART               │
│                             │
│  ┌────┐ ┌────┐ ┌────┐      │
│  │    │ │    │ │    │      │
│  │ 🎬 │ │ 🎬 │ │ 🎬 │      │
│  │    │ │    │ │    │      │
│  └────┘ └────┘ └────┘      │
│  Film 4  Film 5  Film 6    │
│                             │
├─────────────────────────────┤
│  🏠 Hjem  🎬 Film  ❤ Liste │
│                  👤 Profil  │
└─────────────────────────────┘
```

#### Filmside

```
┌─────────────────────────────┐
│  ← Tilbage            ❤    │
├─────────────────────────────┤
│  ┌─────────────────────┐    │
│  │                     │    │
│  │   ▶ Se Trailer      │    │
│  │                     │    │
│  └─────────────────────┘    │
│                             │
│  Venom: The Last Dance      │
│  ⭐ 6.8 │ Action │ 120 min  │
│                             │
│  Eddie Brock og symbioten   │
│  Venom er på flugt...       │
│                             │
│  SPILLETIDER                │
│  ─────────────────────      │
│  📅 I dag │ I morgen │ Lør  │
│                             │
│  🏢 Imperial (NFBio)        │
│  19:00 │ 21:30              │
│  [Bestil billetter →]       │
│                             │
│  🏢 Vue København           │
│  20:30 (IMAX 3D)            │
│  [Bestil billetter →]       │
│                             │
│  🏢 Grand Teatret           │
│  18:00 │ 20:15              │
│  [Bestil billetter →]       │
│                             │
└─────────────────────────────┘
```

---

## Projektplan & Tidsestimat

### Fase 1: Foundation (Uge 1-3)

- [ ] Opsæt Next.js projekt med TypeScript
- [ ] Opsæt Supabase (database + auth)
- [ ] Implementer database schema
- [ ] TMDB API integration (filmdata + trailers)
- [ ] Grundlæggende UI-komponenter (design system)

### Fase 2: Kernefunktionalitet (Uge 4-7)

- [ ] Filmkatalog (forside, filmside, søgning)
- [ ] International Showtimes API integration
- [ ] Spilletidsvisning med by- og datfilter
- [ ] "Bestil billetter" redirect-funktion
- [ ] Responsive web-design

### Fase 3: Brugerfunktioner (Uge 8-10)

- [ ] Brugerregistrering og login
- [ ] Watchlist-funktionalitet
- [ ] Notifikationssystem (email)
- [ ] Brugerpræferencer (favorit-by)

### Fase 4: Mobil App (Uge 11-14)

- [ ] Expo/React Native projekt setup
- [ ] Delt komponent-bibliotek (web + app)
- [ ] Push-notifikationer (Expo Notifications)
- [ ] App Store + Google Play submission

### Fase 5: Polish & Launch (Uge 15-16)

- [ ] Performance-optimering
- [ ] SEO-optimering
- [ ] Fejlhåndtering og monitoring (Sentry)
- [ ] Beta-test med brugere
- [ ] Lancering af gobio.dk

---

## Budget & Omkostninger

### Månedlige driftsomkostninger (estimat)

| Service | Gratis tier | Betalt tier |
|---------|-------------|-------------|
| **Vercel** (hosting) | Gratis (hobby) | $20/md (Pro) |
| **Supabase** (database + auth) | Gratis (500MB) | $25/md (Pro) |
| **International Showtimes API** | 7 dage gratis | 149-299€/md |
| **TMDB API** | Gratis | Gratis |
| **Upstash Redis** | Gratis (10K req/dag) | $10/md |
| **Resend** (email) | 3.000 emails/md gratis | $20/md |
| **Sentry** (monitoring) | Gratis (5K events) | $26/md |
| **Domæne** (gobio.dk) | - | ~100 kr/år |
| **Apple Developer** | - | 749 kr/år |
| **Google Play Developer** | - | $25 (engangsbetaling) |

**Total (start med gratis tiers):** ~149-299€/md (primært Showtimes API)
**Total (betalt tiers):** ~400-600€/md

### Alternativ: Uden Showtimes API (kun web scraping)

Hvis man bygger egne scrapers i stedet for International Showtimes API:
- **Railway** (scraper hosting): $5/md
- **Total besparelse:** ~150-300€/md
- **Ulempe:** Mere vedligeholdelse, risiko for at sider ændrer struktur

---

## Juridiske overvejelser

### GDPR Compliance
- Privacypolicy på dansk
- Cookie-consent banner
- Ret til sletning af brugerdata
- Data Processing Agreement med underleverandører
- Kun nødvendige data indsamles

### Vilkår og betingelser
- Gobio.dk sælger IKKE billetter - vi redirecter kun
- Ansvarsfraskrivelse for korrekthed af spilletider
- Vi er ikke ansvarlige for transaktioner på biografernes sider

### Ophavsret
- Filmposters og trailers bruges under fair use / via officielle API'er
- TMDB kræver attribution: "This product uses the TMDB API but is not endorsed or certified by TMDB"

---

## Konkurrenceanalyse

| Platform | Styrker | Svagheder |
|----------|---------|-----------|
| **kino.dk** | Etableret brand, billetsalg | Gammel UI, langsom, kun web |
| **nfbio.dk** | Kun Nordisk Film biografer | Kun én kæde |
| **cinemaxx.dk** | Kun Vue biografer | Kun én kæde |
| **gobio.dk (os)** | Alle biografer, moderne UI, app, watchlist, notifikationer | Ny spiller, ingen brand endnu |

### Vores differentiering
1. **Alt samlet ét sted** - ingen grund til at besøge 5 hjemmesider
2. **Moderne app** - native iOS/Android med push-notifikationer
3. **Watchlist + notifikationer** - bliv mindet om premierer
4. **Hurtig og brugervenlig** - moderne tech stack, ingen bloat
5. **Gratis for brugerne** - ingen billetgebyrer (vi redirecter bare)

---

## Næste skridt

1. **Valider idéen:** Undersøg om der er interesse (landing page + signup)
2. **Sikr datakilde:** Tilmeld International Showtimes API trial og test dansk dækning
3. **Start udvikling:** Begynd med Fase 1 (Foundation)
4. **Kontakt biografer:** Send partnerskabsforslag til Nordisk Film og Vue
5. **Domæne:** Registrer gobio.dk

---

*Dokumentet er sidst opdateret: 15. marts 2026*
