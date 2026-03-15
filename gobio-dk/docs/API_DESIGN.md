# API Design - Gobio.dk

## Base URL

```
Production:  https://gobio.dk/api
Development: http://localhost:3000/api
```

## Authentication

Supabase Auth med JWT tokens. Inkluder token i `Authorization` header:

```
Authorization: Bearer <supabase-access-token>
```

Offentlige endpoints (film, spilletider, biografer) kræver ingen auth.
Bruger-endpoints (watchlist, notifikationer, profil) kræver auth.

---

## Endpoints

### Film

#### `GET /api/movies`

Hent liste over film.

**Query parameters:**
| Parameter | Type | Default | Beskrivelse |
|-----------|------|---------|-------------|
| `tab` | string | `now_playing` | `now_playing`, `upcoming`, `popular` |
| `page` | number | `1` | Side-nummer |

**Response:**
```json
{
  "success": true,
  "data": {
    "movies": [
      {
        "tmdbId": 912649,
        "title": "Venom: The Last Dance",
        "originalTitle": "Venom: The Last Dance",
        "overview": "Eddie Brock og symbioten Venom...",
        "posterUrl": "https://image.tmdb.org/t/p/w500/...",
        "releaseDate": "2026-03-20",
        "genres": [28, 878],
        "tmdbRating": 6.8,
        "isUpcoming": false
      }
    ]
  },
  "meta": {
    "page": 1,
    "totalPages": 10,
    "total": 200
  }
}
```

#### `GET /api/movies/:id`

Hent film-detaljer med trailer og cast.

**Response:**
```json
{
  "success": true,
  "data": {
    "movie": {
      "tmdbId": 912649,
      "title": "Venom: The Last Dance",
      "overview": "...",
      "posterUrl": "https://image.tmdb.org/t/p/w500/...",
      "backdropUrl": "https://image.tmdb.org/t/p/w1280/...",
      "trailerYoutubeKey": "abc123def",
      "releaseDate": "2026-03-20",
      "runtimeMinutes": 120,
      "genres": ["Action", "Sci-Fi"],
      "cast": [
        {
          "name": "Tom Hardy",
          "character": "Eddie Brock / Venom",
          "profileUrl": "https://image.tmdb.org/t/p/w185/..."
        }
      ],
      "director": "Kelly Marcel",
      "tmdbRating": 6.8
    }
  }
}
```

#### `GET /api/movies/search?q=`

Søg i film. Kræver `q` parameter (min. 2 tegn).

---

### Spilletider

#### `GET /api/showtimes`

Hent spilletider med filtre.

**Query parameters:**
| Parameter | Type | Beskrivelse |
|-----------|------|-------------|
| `city` | string | By-navn (f.eks. "København") |
| `date` | string | Dato i `YYYY-MM-DD` format |
| `movie_id` | number | Film-ID |
| `cinema_id` | number | Biograf-ID |

**Response:**
```json
{
  "success": true,
  "data": {
    "showtimes": [
      {
        "id": 42,
        "movieId": 1,
        "cinema": {
          "id": 1,
          "name": "Imperial",
          "chainName": "Nordisk Film Biografer",
          "chainSlug": "nordisk-film",
          "city": "København"
        },
        "startsAt": "2026-03-20T19:00:00+01:00",
        "format": "2D",
        "language": "Engelsk",
        "subtitles": "Dansk",
        "is3d": false,
        "isImax": false,
        "bookingUrl": "https://nfbio.dk/film/venom-the-last-dance",
        "hallName": "Sal 1"
      }
    ]
  }
}
```

---

### Biografer

#### `GET /api/cinemas`

Hent alle biografer, valgfrit filtreret på by.

**Query parameters:**
| Parameter | Type | Beskrivelse |
|-----------|------|-------------|
| `city` | string | Filtrer på by |

#### `GET /api/cinemas/cities`

Hent liste over byer med biografer.

**Response:**
```json
{
  "success": true,
  "data": {
    "cities": ["København", "Aarhus", "Odense", "Aalborg", "Esbjerg"]
  }
}
```

---

### Watchlist (kræver auth)

#### `GET /api/watchlist`

Hent brugerens watchlist.

#### `POST /api/watchlist/:movieId`

Tilføj film til watchlist. Returnerer `409` hvis filmen allerede er tilføjet.

#### `DELETE /api/watchlist/:movieId`

Fjern film fra watchlist.

---

### Notifikationer (kræver auth)

#### `GET /api/notifications`

Hent brugerens notifikationer.

#### `PATCH /api/notifications/:id/read`

Marker notifikation som læst.

#### `POST /api/notifications/register`

Registrer push-token for mobilapp.

**Body:**
```json
{
  "token": "ExponentPushToken[xxxx]",
  "platform": "ios"
}
```

---

## Error Responses

Alle fejl returneres med dette format:

```json
{
  "success": false,
  "error": "Beskrivelse af fejlen"
}
```

HTTP status codes:
- `400` - Bad request (ugyldige parametre)
- `401` - Unauthorized (manglende eller ugyldig auth)
- `404` - Not found
- `409` - Conflict (f.eks. allerede i watchlist)
- `429` - Rate limited
- `500` - Server error
