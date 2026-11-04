# Services Dokumentation

Lydcache i lokal **1.40.0 (42)** følger [assetkontrakten](../Docs/PodcastAudioAssets.md): accepteret rå manifestbinding, artikelrevision og oprindelig favoritadgang føres gennem status, download, prefetch, deferred arbejde og afspillerens asynkrone filkontrol. URL alene giver ingen verificeret offlineadgang. V2-kvittering kontrollerer lokal filintegritet; legacybytes bliver ikke opgraderet. Lokalt verificeret med 942 fulde units, 25 UI-scenarier og berørte lydprøver igen i begge temaer; fuld evidens står i launch-journalen. Remote bytehash, AVPlayer/deviceaccept og fuld retention/purge er særskilte gates.

Indgående links i lokal **1.39.0 (41)** følger [routingkontrakten](../Docs/IncomingLinks.md): fælles AppDelegate-/sceneadapter, faktisk readiness, latest-only resolver og originale request-/kontotickets. Canonical artikel kommer før rå episodebinding og timestamp, også samme episode/nul. Offline slugmatch kræver netforbindelse; kun eksakt canonical ID kan bruges fra delvis cache. Playeren pauses før nyt item og afvist adoption lukkes kun for sin oprindelige session. AASA, OS-handoff, SDK-/deviceaccept og [kold lydcache-provenance](../Docs/PodcastAudioAssetPlan.md) er stadig åbne gates.

Favoritter/offline i lokal **1.38.0 (40)** følger [den aktuelle kontrakt](../Docs/FavoritesOwnership.md): FavoritesModel er eneste liste-/count-/buttonautoritet; guest/hashed konti og originale mutation-/observation-/access tickets adskilles. Firestore bruger `users/{uid}/favorites/{articleID}`, forventet UID og absolut gem/fjern. Favoritwrite og profilens bookmarkmirror afventes i samme per-artikel slot; øvrige profilsaves skriver ikke bookmarkfeltet. Ny observationID tilbagekaldes før listener-remove. Authpublicering har nonce/UID-hegn mellem hvert trin. Offlinebytes giver ingen membership og kontoskift rydder ikke globalt. Slutstatus er i launch-journalen; outbox, purge/migration og service/deviceaccept er åbne.

Ældre API-eksempler nedenfor er historisk reference; brug kontrakterne og de faktiske Swift-signaturer før ændringer. Recommendationservice er nu en ren beregning med immutable `RecommendationHistoryInput`; den gamle persistente recommendationcache er fjernet i 1.37.

Læsehistorik/anbefalinger i lokal 1.37.0 følger [ejer-/dokumentkontrakten](../Docs/ReadingHistoryOwnership.md). Den nye KVS-runtime forberedes kun uden for XCTest/smoke; legacy globale historikkeys bruges ikke. Originale callbacks og immutable recommendation-inputs er afgrænset fra senere konti. Gemmefejl kræver eksplicit retry, og processynlig readback er ikke cloudkvittering. Fuld offline-/favorit-/deletion-/iCloud-deviceaccept er fortsat åben.

Lytteposition fra lokal 1.36.0 følger [ejer-/sessionkontrakten](../Docs/PodcastProgressOwnership.md). Den guardede runtime modtager canonical Auth, har separat guest/hashed-account record og opretter ingen player/auth-listener. Det er lokal isolation, ikke iCloud-sync, kontosletning eller autorisation af medier. Gamle globale positioner tilskrives ikke automatisk.

Telemetry fra lokal 1.35.0 følger [den aktuelle privatlivskontrakt](../Docs/TelemetryPrivacy.md): separate default-off valg til analytics og lokal log, kanonisk kontokontekst, generationstickets og ingen Crashlytics-aktivering. Direkte app-ejede operational-logs bruger nu faste typed koder, og en statisk kildeguard forebygger dækkede bypasses. SDK-/upgrade-/retentionaccept er stadig en releasegate. [Support](../Docs/SupportContact.md) bruger brugerinitieret Mail/mailto/kopi uden backend-send eller automatisk vedhæftede data; faktisk levering er ikke verificeret.

## 🔌 API Services

### WebflowService

**Location**: `Services/WebflowService.swift`

**Purpose**: Håndterer alle API calls til Webflow CMS.

#### Methods

##### `fetchArticles(completion:)`
Henter alle artikler fra Webflow CMS.

```swift
WebflowService.shared.fetchArticles { result in
    switch result {
    case .success(let articles):
        // Handle articles
    case .failure(let error):
        // Handle error
    }
}
```

**Response**: `Result<[Article], Error>`

##### `fetchTopics(completion:)`
Henter alle kategorier/topics.

```swift
WebflowService.shared.fetchTopics { topics in
    // Handle topics
}
```

**Response**: `[Topic]`

##### `fetchAuthors(completion:)`
Henter alle forfattere.

```swift
WebflowService.shared.fetchAuthors { authors in
    // Handle authors
}
```

**Response**: `[Author]`

##### `fetchStarsMapping(completion:)`
Henter stjerner mapping fra Webflow collection fields.

```swift
WebflowService.shared.fetchStarsMapping { mapping in
    // mapping: [String: String] e.g., ["1": "1 stjerne"]
}
```

**Response**: `[String: String]`

#### API Configuration

- **Base URL**: `https://api.webflow.com/v2`
- **Collection ID**: `67dbf17ba540975b5b21c2a6`
- **Authentication**: Bearer token via `SecureConfig.shared.webflowAPIKey`
- **Headers**:
  - `Authorization: Bearer {token}`
  - `accept-version: 1.0.0`

#### Error Handling

```swift
enum WebflowError: LocalizedError {
    case missingAPIToken
    // ...
}
```

---

### AuthService

**Location**: `Services/AuthService.swift`

**Purpose**: Håndterer Firebase Authentication.

#### Methods

##### `signIn(withEmail:password:completion:)`
Email/password login.

##### `signUp(withEmail:password:completion:)`
Opret ny bruger.

##### `signOut()`
Log ud.

##### `resetPassword(email:completion:)`
Nulstil password.

#### Integration

Bruger Firebase Auth:
- Email/Password authentication
- Google Sign-In (via `GoogleSignInService`)
- Anonymous authentication (optional)

---

### FirestoreService

**Location**: `Services/FirestoreService.swift`

**Purpose**: Håndterer Firestore database operations.

#### Collections

- **users** - Brugerprofiler
- **articles/{articleId}/comments** - Kommentarer
- **favorites/{userId}** - Bruger favoritter

#### Methods

##### `configurePersistenceIfNeeded()`
Konfigurerer offline persistence.

##### `saveFavorite(articleId:userId:completion:)`
Gem favorit artikel.

##### `removeFavorite(articleId:userId:completion:)`
Fjern favorit artikel.

---

### UserManager

**Location**: `Services/UserManager.swift`

**Purpose**: Håndterer bruger profil data.

#### Properties

- `@Published var currentUser: UserProfile?`
- `@Published var errorMessage: String?`

#### Methods

##### `loadUserProfile(for:completion:)`
Hent bruger profil fra Firestore.

##### `saveUserProfile(_:completion:)`
Gem bruger profil til Firestore.

##### `updateFavorites(_:completion:)`
Opdater favoritter liste.

#### Data Model

```swift
struct UserProfile: Codable {
    let uid: String
    let email: String
    let displayName: String?
    let photoURL: String?
    let favorites: [String]
    let readingHistory: [String]
    // ...
}
```

---

### SecureConfig

**Location**: `Services/SecureConfig.swift`

**Purpose**: Sikker håndtering af API keys og secrets.

#### API Key Sources (i prioritetsrækkefølge)

1. **Keychain** (Production)
2. **Secrets.plist** (Development)
3. **Environment Variables** (CI/CD)

#### Methods

##### `storeAPIKey(_:for:)`
Gem API key i Keychain.

```swift
SecureConfig.shared.storeAPIKey("your-key", for: "webflow")
```

##### `getAPIKey(for:)`
Hent API key fra Keychain.

```swift
let key = SecureConfig.shared.getAPIKey(for: "webflow")
```

#### Properties

- `webflowAPIKey: String` - Webflow API key
- `googleAPIKey: String` - Google API key
- OpenAI-nøgle og gammel reasons-URL findes ikke længere i iOS. Anbefalinger bruger lokal `ReaderRecommendationPolicy`; se [afgrænsningen](../Docs/LegacyRecommendationRetirement.md).
- `fcmBackendURL: URL?` - FCM backend URL

#### Configuration

API keys læses fra `Resources/Secrets.plist`:
```xml
<key>WEBFLOW_API_KEY</key>
<string>your-api-key</string>
```

---

### CacheManager

**Location**: `Services/CacheManager.swift`

**Purpose**: Lokal caching af artikler.

#### Methods

##### `cacheArticles(_:)`
Cache artikler lokalt.

```swift
CacheManager.shared.cacheArticles(articles)
```

##### `getCachedArticles() -> [Article]?`
Hent cached artikler.

```swift
if let cached = CacheManager.shared.getCachedArticles() {
    // Use cached articles
}
```

##### `clearCache()`
Ryd cache.

#### Storage

- **Location**: UserDefaults
- **Key**: `"cached_articles"`
- **Format**: JSON encoded `[Article]`

---

### OfflineManager

**Location**: `Services/OfflineManager.swift`

**Purpose**: Håndterer offline funktionalitet.

#### Properties

- `@Published var isOnline: Bool`
- `@Published var syncInProgress: Bool`
- `@Published var lastSyncDate: Date?`

#### Methods

##### `syncWhenOnline()`
Synkroniser data når online.

##### `processPendingActions()`
Processer pending actions når online.

#### Network Monitoring

Bruger `NWPathMonitor` til at overvåge netværksstatus.

---

### NotificationService

**Location**: `Services/NotificationService.swift`

**Purpose**: Håndterer push notifications.

#### Methods

##### `requestAuthorization(completion:)`
Anmod om notification tilladelse.

##### `registerForRemoteNotifications()`
Registrer for remote notifications.

##### `handleNotification(_:)`
Håndter indkommende notification.

#### Integration

- Firebase Cloud Messaging (FCM)
- Local notifications
- Deep linking til artikler

---

### ThemeManager

**Location**: `Services/ThemeManager.swift`

**Purpose**: Håndterer dark/light mode.

#### Properties

- `@Published var currentTheme: AppTheme`

#### Methods

##### `setTheme(_:)`
Sæt app theme.

```swift
ThemeManager.shared.setTheme(.dark)
```

#### Themes

```swift
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
}
```

#### Persistence

Theme gemmes i UserDefaults med key `"appTheme"`.

---

### RecommendationService

**Location**: `Services/RecommendationService.swift` og `Helpers/ReaderRecommendationPolicy.swift`.

`ArticleViewModel.fetchPersonalizedRecommendationsIfNeeded` sender aktuelle artikler, favoritter, læsehistorik og kontoens læseinteresser til den lokale policy. Den vælger publicerede, ulæste artikler med emnevariation og faktiske begrundelser. Læseinteresser er adskilt fra pushabonnementer. Viewmodelen afviser sene resultater efter kontoskift og filtrerer kendt utilgængeligt indhold.

`generateRecommendations(articles:favorites:subscribedCategoryIds:readArticleIds:userID:)` returnerer artikel/begrundelse-par asynkront. Cache er separat for UID/guest med seks timers levetid og generationskontrol ved cachewrite/clear. Der bruges ingen OpenAI-manager eller reasons-HTTP. Det gamle endpoint er [afgrænset i den lokale kandidat](../Docs/LegacyRecommendationRetirement.md).

`trackRecommendationTap` sender fortsat gennem AnalyticsService; faktisk telemetrysamtykke/withdrawal er en åben L03-opgave, ikke løst af endpointlukningen.

---

### SocialService

**Location**: `Services/SocialService.swift`

**Purpose**: Håndterer sociale features (kommentarer).

#### Methods

##### `loadComments(for:completion:)`
Hent kommentarer for artikel.

##### `addComment(_:for:completion:)`
Tilføj kommentar.

#### Data Model

```swift
struct Comment: Codable {
    let id: String
    let userId: String
    let text: String
    let timestamp: Date
    let replies: [Comment]
}
```

---

### WhatsNewManager

**Location**: `Managers/WhatsNewManager.swift`

**Purpose**: Håndterer "What's New" changelog visning.

#### Properties

- `static let shared: WhatsNewManager` - Singleton instance

#### Methods

##### `entryToPresent() -> WhatsNewEntry?`
Henter den relevante changelog entry for den aktuelle app version.

```swift
if let entry = WhatsNewManager.shared.entryToPresent() {
    // Show What's New view
}
```

**Return**: `WhatsNewEntry?` - Entry hvis der er en ny version der ikke er set før, ellers `nil`

##### `markEntryAsSeen(_:)`
Markerer en changelog entry som set.

```swift
WhatsNewManager.shared.markEntryAsSeen(entry)
```

#### Version Comparison

Manageren sammenligner versions numre semantisk:
- `2.4.0` > `2.3.0` ✓
- `2.3.1` > `2.3.0` ✓
- `2.3.0` == `2.3.0` (allerede set)

#### Data Source

Læser fra `Resources/WhatsNew/whatsnew.json`:
```json
[
  {
    "version": "2.4.0",
    "title": "Nyheder i Apropos Magazine",
    "subtitle": "Her er de vigtigste forbedringer.",
    "items": [
      {
        "icon": "sparkles",
        "title": "Ny feature",
        "description": "Beskrivelse"
      }
    ],
    "ctaTitle": "Se alle ændringer",
    "ctaURL": "https://aproposmagazine.com/changelog"
  }
]
```

#### Persistence

- **Storage**: UserDefaults
- **Key**: `com.aproposmagazine.whatsnew.lastSeenVersion`
- **Value**: Seneste set version (e.g., `"2.3.0"`)

#### Integration

Automatisk integration i `ContentView.swift`:
```swift
@State private var whatsNewEntry: WhatsNewEntry?

.onAppear {
    if whatsNewEntry == nil, let entry = WhatsNewManager.shared.entryToPresent() {
        whatsNewEntry = entry
    }
}
.sheet(item: $whatsNewEntry) { entry in
    WhatsNewView(entry: entry) {
        WhatsNewManager.shared.markEntryAsSeen(entry)
        whatsNewEntry = nil
    }
    .interactiveDismissDisabled()
}
```

---

## 🔄 Service Dependencies

```
ArticleViewModel
    ├── WebflowService (fetch articles)
    ├── CacheManager (cache articles)
    ├── UserManager (favorites sync)
    └── FirestoreService (database)

UserManager
    ├── FirestoreService (save/load profile)
    └── AuthService (authentication)

NotificationService
    ├── Firebase Messaging (FCM)
    └── ArticleViewModel (navigate to article)
```

## 🔐 Security Considerations

### API Keys
- Aldrig commit API keys til git
- Brug `SecureConfig` for alle API keys
- Keychain for production
- Secrets.plist for development (i .gitignore)

### Data Privacy
- Brug `privacy: .public` kun for non-sensitive logs
- Brug `privacy: .private` for sensitive data
- Følg GDPR guidelines

### Network Security
- HTTPS for alle API calls
- Certificate pinning (overvej for production)
- ATS (App Transport Security) enabled

---

**Opdateret**: November 2024

