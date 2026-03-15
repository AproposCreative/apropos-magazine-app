# Tech Stack - Detaljeret Oversigt

## Overblik

```
Frontend:  Next.js 15 (web) + React Native / Expo 53 (app)
Backend:   Next.js API Routes + Node.js scrapers
Database:  PostgreSQL (Supabase)
Cache:     Redis (Upstash)
Auth:      Supabase Auth
Hosting:   Vercel (web) + Railway (scrapers)
CI/CD:     GitHub Actions
```

---

## Frontend - Web (gobio.dk)

| Teknologi | Version | Formål |
|-----------|---------|--------|
| **Next.js** | 15.x | React framework med App Router, SSR, ISR |
| **React** | 19.x | UI-bibliotek |
| **TypeScript** | 5.7+ | Type-sikkerhed |
| **Tailwind CSS** | 4.x | Utility-first CSS |
| **Lucide React** | latest | Ikonbibliotek |
| **date-fns** | 4.x | Dato-formatering (dansk locale) |
| **Zod** | 3.x | Runtime-validering af API-data |

### Hvorfor Next.js?

- **SEO:** Server-side rendering er kritisk for at film-sider indekseres af Google
- **Performance:** Automatic code splitting, image optimization, edge caching
- **Developer Experience:** Hot reload, file-based routing, API routes i samme projekt
- **Vercel:** Nem deploy med preview-environments per PR

---

## Frontend - Mobil App

| Teknologi | Version | Formål |
|-----------|---------|--------|
| **React Native** | 0.79+ | Cross-platform mobile framework |
| **Expo** | SDK 53 | Build tools, OTA updates, device APIs |
| **Expo Router** | 5.x | File-based navigation |
| **NativeWind** | 4.x | Tailwind CSS for React Native |
| **Expo Notifications** | latest | Push-notifikationer |
| **Zustand** | 5.x | Letvægts state management |

### Hvorfor Expo?

- **Cross-platform:** Én codebase for iOS og Android
- **EAS Build:** Cloud-builds uden lokal Mac
- **OTA Updates:** Opdater app uden at gå gennem App Store review
- **Expo Notifications:** Push-notifikationer med minimal opsætning

---

## Backend

| Teknologi | Version | Formål |
|-----------|---------|--------|
| **Next.js API Routes** | 15.x | REST API endpoints |
| **Supabase** | latest | Database, auth, real-time |
| **Upstash Redis** | latest | Caching (serverless Redis) |
| **Resend** | latest | Transaktionelle emails |
| **Playwright** | 1.50+ | Web scraping |
| **Cheerio** | 1.x | HTML parsing |
| **Pino** | 9.x | Logging |

---

## Database Schema

Se `supabase/migrations/001_initial_schema.sql` for det fulde schema.

Kernetabeller:
- `profiles` - Brugerprofiler (udvider Supabase Auth)
- `movies` - Film-cache fra TMDB
- `cinema_chains` - Biografkæder
- `cinemas` - Individuelle biografer
- `showtimes` - Spilletider
- `watchlist_items` - Brugerens watchlist
- `notifications` - Notifikationslog
- `push_tokens` - Push-tokens for mobilapp

---

## Infrastruktur

```
┌─────────────────────────────────────────────────┐
│                   Vercel                         │
│                                                  │
│  ┌─────────────────┐  ┌──────────────────────┐ │
│  │   Next.js Web   │  │   API Routes         │ │
│  │   (SSR + ISR)   │  │   (Serverless)       │ │
│  └─────────────────┘  └──────────────────────┘ │
└────────────────────────┬────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
┌────────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
│   Supabase    │ │   Upstash   │ │   Railway   │
│   (Postgres   │ │   (Redis)   │ │   (Scrapers)│
│   + Auth)     │ │             │ │             │
└───────────────┘ └─────────────┘ └─────────────┘
```

### Hosting-valg

| Service | Tier | Pris | Formål |
|---------|------|------|--------|
| **Vercel** | Hobby → Pro | Gratis → $20/md | Web hosting + API |
| **Supabase** | Free → Pro | Gratis → $25/md | Database + Auth |
| **Upstash** | Free → Pay-as-you-go | Gratis → ~$10/md | Redis cache |
| **Railway** | Starter | ~$5/md | Scraper cron jobs |
| **Resend** | Free → Starter | Gratis → $20/md | Email notifications |
| **Sentry** | Developer | Gratis | Error monitoring |

---

## Udviklings-setup

### Forudsætninger

- Node.js 22+
- npm eller pnpm
- Git
- Supabase CLI (`npm i -g supabase`)
- Expo CLI (`npm i -g expo-cli`)

### Quick Start

```bash
# Klon repo
git clone https://github.com/your-org/gobio-dk.git
cd gobio-dk

# Web
cd web
cp .env.example .env.local
# Udfyld .env.local med dine API-nøgler
npm install
npm run dev

# Mobile (i et andet terminal)
cd mobile
npm install
npx expo start

# Scrapers (i et tredje terminal)
cd scrapers
npm install
npm run scrape:all
```
