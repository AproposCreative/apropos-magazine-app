# Gobio.dk iOS App - Opsætningsguide

## Forudsætninger

- Xcode 16.0+
- iOS 18.0+ deployment target
- Firebase-projekt (genbruger dit Apropos Magazine projekt eller opret nyt)
- TMDB API-nøgle

## Quick Start

### 1. Firebase Opsætning

Da du allerede har Firebase sat op fra Apropos Magazine, kan du enten:

**Option A: Genbrug eksisterende Firebase-projekt**
- Gå til [Firebase Console](https://console.firebase.google.com)
- Åbn dit eksisterende projekt
- Tilføj en ny iOS-app med bundle ID: `dk.gobio.app`
- Download `GoogleService-Info.plist` og placer den i `GobioDK/`

**Option B: Opret nyt Firebase-projekt**
- Opret nyt projekt i Firebase Console
- Aktiver Authentication (Email/Password + Google Sign-In)
- Aktiver Firestore Database
- Aktiver Cloud Messaging
- Download `GoogleService-Info.plist`

### 2. TMDB API-nøgle

1. Opret konto på [themoviedb.org](https://www.themoviedb.org/signup)
2. Gå til Settings > API
3. Anmod om en API-nøgle
4. Kopier din "API Read Access Token" (Bearer token)
5. Opret `Secrets.plist` i `GobioDK/Resources/`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>TMDB_API_KEY</key>
    <string>DIN_TMDB_API_READ_ACCESS_TOKEN</string>
</dict>
</plist>
```

### 3. Xcode Projekt

1. Opret nyt Xcode-projekt (App) med:
   - Product Name: GobioDK
   - Bundle Identifier: dk.gobio.app
   - Interface: SwiftUI
   - Language: Swift

2. Tilføj Swift Package Dependencies:
   - `firebase-ios-sdk` (11.14.0+)
     - FirebaseCore, FirebaseAuth, FirebaseFirestore, FirebaseMessaging
   - `GoogleSignIn-iOS` (9.0.0+)
   - `SDWebImageSwiftUI` (3.1.3+)

3. Kopier alle filer fra `GobioDK/` ind i projektet

4. Tilføj `GoogleService-Info.plist` til projektet

5. Konfigurer Capabilities:
   - Push Notifications
   - Background Modes (Remote notifications)
   - App Groups: `group.dk.gobio.app`

### 4. Google Sign-In

1. Åbn `GoogleService-Info.plist`
2. Find `REVERSED_CLIENT_ID`
3. Tilføj det som URL Scheme i Xcode: Target > Info > URL Types

### 5. Build & Run

```bash
# Åbn projektet
open GobioDK.xcodeproj

# Eller brug xcodebuild
xcodebuild -scheme GobioDK -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Hvad er genbrugt fra Apropos Magazine?

| Komponent | Status | Ændringer |
|-----------|--------|-----------|
| **Firebase Auth** | Genbrugt direkte | Ingen ændringer |
| **Google Sign-In** | Genbrugt direkte | Ny client ID |
| **Firestore Service** | Tilpasset | `favorites` → `watchlist`, nye datamodeller |
| **Notification Service** | Tilpasset | Nye FCM topics, premiere-påmindelser |
| **User Manager** | Tilpasset | Ny `UserProfile` med `preferredCity`, `watchlistMovieIds` |
| **SecureConfig** | Tilpasset | TMDB API-nøgle i stedet for Webflow |
| **Navigation Coordinator** | Tilpasset | Nye tabs og routes for film/biografer |
| **Cache Manager** | Kan genbruges | Tilpasses til filmdata |
| **Theme Manager** | Kan genbruges | Nyt farveskema (mørkt som standard) |
| **AppDelegate** | Tilpasset | Nye notification handlers, nyt URL scheme |

## Firestore Collections

```
users/{uid}
  - uid, email, displayName, photoURL
  - preferredCity: "København"
  - watchlistMovieIds: [912649, 1184918, ...]
  - notificationPreferences: { premiereAlerts: true, newMovies: true }
  - fcmToken: "..."

users/{uid}/watchlist/{tmdbId}
  - tmdbId: 912649
  - title: "Venom: The Last Dance"
  - posterPath: "/aosm8NMQ3UyoBVpSxyimorCQyNb.jpg"
  - releaseDate: "2026-03-20"
  - isUpcoming: false
  - notifyOnPremiere: true
  - addedAt: Timestamp
```

## FCM Topics

| Topic | Beskrivelse |
|-------|-------------|
| `gobio_all_users` | Alle brugere |
| `gobio_new_movies` | Nye film i biografen |
| `gobio_premieres` | Premiere-påmindelser |
| `gobio_premiere_{tmdbId}` | Specifik film-premiere |
| `gobio_weekly` | Ugentlige highlights |
