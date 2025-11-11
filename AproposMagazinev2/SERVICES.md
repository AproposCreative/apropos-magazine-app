# Services Dokumentation

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
- `openAIAPIKey: String` - OpenAI API key
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

### RecommendationEngine

**Location**: `Services/RecommendationEngine.swift`

**Purpose**: AI-baserede artikel anbefalinger.

#### Methods

##### `generateRecommendations(for:completion:)`
Generer anbefalinger baseret på bruger historik.

#### Integration

- OpenAI API (via `OpenAIManager`)
- Bruger læsehistorik
- Bruger favoritter

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

