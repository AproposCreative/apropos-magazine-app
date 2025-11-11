# Arkitektur Dokumentation

## 📐 Overordnet Arkitektur

Apropos Magazine app følger **MVVM (Model-View-ViewModel)** arkitektur med følgende lag:

```
┌─────────────────────────────────────┐
│           Views (SwiftUI)            │
│  HomeView, SearchView, ProfileView   │
└──────────────┬──────────────────────┘
               │ @EnvironmentObject
┌──────────────▼──────────────────────┐
│         ViewModels                    │
│  ArticleViewModel, NavigationCoord.   │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│         Services                     │
│  WebflowService, AuthService, etc.   │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│         Models                       │
│  Article, Topic, Author, UserProfile │
└──────────────────────────────────────┘
```

## 🏗️ Projektstruktur

### Models/
Data modeller der repræsenterer appens domæne:

- **Article.swift** - Artikel model med Webflow CMS integration
- **Topic.swift** - Kategori/topic model
- **Author.swift** - Forfatter model
- **UserProfile.swift** - Bruger profil model
- **NavigationCoordinator.swift** - Navigation state management
- **AppState.swift** - Global app state
- **UserPreferences.swift** - Brugerindstillinger
- **ReadingProgress.swift** - Læseforløb tracking
- **WhatsNewEntry.swift** - What's New changelog model

### Views/
SwiftUI views organiseret i mapper:

#### Hovedviews:
- **HomeView.swift** - Hjemmeskærm med hero slider
- **SearchView_Enhanced.swift** - Søgning med pagination
- **CategoriesView.swift** - Kategorier oversigt
- **FavoritesView.swift** - Gemte artikler
- **ProfileView_NewDesign.swift** - Instagram-style profil
- **ArticleDetailView.swift** - Artikel detaljevisning

#### Components/
Genbrugelige UI komponenter:
- **ArticleCardView_Enhanced.swift** - Artikel kort
- **HeroSwipeBar.swift** - Hero slider komponent
- **CategoryFilterView.swift** - Kategori filter
- **LogoView.swift** - App logo komponent
- Og mange flere...

#### Helpers/
View helpers og modifiers:
- **SwipeBackModifier.swift** - Swipe-to-go-back gesture
- **CustomTopBarModifier.swift** - Custom top bar
- **EnhancedSwipeBackModifier.swift** - Forbedret swipe back

### ViewModels/
Business logic og state management:

- **ArticleViewModel.swift** - Central ViewModel for artikler
  - Håndterer artikel fetching
  - Favoritter management
  - Firestore synkronisering
  - AI recommendations

### Services/
Business logic og API integration:

#### Core Services:
- **WebflowService.swift** - Webflow CMS API integration
- **AuthService.swift** - Firebase Authentication
- **FirestoreService.swift** - Firestore database operations
- **UserManager.swift** - Bruger profil management
- **SecureConfig.swift** - API keys og secrets management

#### Feature Services:
- **CacheManager.swift** - Lokal caching
- **OfflineManager.swift** - Offline support
- **NotificationService.swift** - Push notifications
- **SocialService.swift** - Kommentarer og sociale features
- **RecommendationEngine.swift** - AI-baserede anbefalinger
- **ThemeManager.swift** - Dark/Light mode management

#### Managers:
- **WhatsNewManager.swift** - What's New changelog management
  - Automatisk visning ved opdatering
  - Version tracking
  - Changelog fra git commits

### Helpers/
Utility functions og extensions:

- **CategoryAnalytics.swift** - Kategori analytics
- **HapticManager.swift** - Haptic feedback
- **KeyboardNotificationManager.swift** - Keyboard handling
- **Extensions/** - Swift extensions
- **Constants/** - App konstanter

### Managers/
Business logic managers:

- **WhatsNewManager.swift** - What's New changelog management
  - Version tracking
  - Changelog presentation
  - UserDefaults persistence

## 🔄 Data Flow

### Artikel Henting Flow

```
User Action (HomeView)
    ↓
ArticleViewModel.fetchArticles()
    ↓
WebflowService.fetchArticles()
    ↓
SecureConfig.webflowAPIKey
    ↓
Webflow API Request
    ↓
Parse Response → [Article]
    ↓
ArticleViewModel.articles = [Article]
    ↓
@Published triggers UI update
    ↓
HomeView re-renders
```

### Favoritter Flow

```
User taps favorite button
    ↓
ArticleViewModel.toggleFavorite()
    ↓
Update local favorites array
    ↓
Save to UserDefaults (offline)
    ↓
Sync with Firestore (online)
    ↓
UserManager.updateFavorites()
    ↓
UI updates automatically
```

## 🎨 Design Patterns

### 1. MVVM (Model-View-ViewModel)
- **Views**: SwiftUI views, kun UI logic
- **ViewModels**: Business logic, state management
- **Models**: Data structures

### 2. Singleton Pattern
Services bruger singleton pattern:
```swift
class WebflowService {
    static let shared = WebflowService()
    private init() {}
}
```

### 3. Observer Pattern
Bruger `@Published` og `@ObservedObject` for reactive updates:
```swift
@Published var articles: [Article] = []
```

### 4. Dependency Injection
Bruger `@EnvironmentObject` for dependency injection:
```swift
.environmentObject(viewModel)
```

### 5. Factory Pattern
Navigation bruger factory pattern:
```swift
func destinationView(for route: AppRoute) -> some View
```

## 🔐 Security Architecture

### API Key Management
```
SecureConfig.shared
    ├── Keychain (Production)
    ├── Secrets.plist (Development)
    └── Environment Variables (CI/CD)
```

### Data Flow for Secrets:
1. Check Keychain first
2. Fallback to Secrets.plist
3. Fallback to environment variables
4. Log warning if none found

## 📱 Navigation Architecture

### NavigationCoordinator
Central navigation state management:
- Tab selection
- Navigation paths per tab
- Deep linking support
- Route-based navigation

### Navigation Flow:
```
TabView
    ├── Home Tab (NavigationStack)
    ├── Search Tab (NavigationStack)
    ├── Categories Tab (NavigationStack)
    ├── Favorites Tab (NavigationStack)
    └── Profile Tab (NavigationStack)
```

## 🗄️ Data Persistence

### 1. UserDefaults
- Favoritter (offline backup)
- User preferences
- Cache metadata

### 2. Firestore
- User profiles
- Favoritter (synced)
- Reading progress
- Comments

### 3. Local Cache
- Article cache (CacheManager)
- Image cache (SDWebImage)
- Offline articles

## 🔄 State Management

### Local State (@State)
- View-specific state
- UI state (isLoading, searchText, etc.)

### Shared State (@EnvironmentObject)
- ArticleViewModel
- NavigationCoordinator
- ThemeManager

### Global State
- UserManager.shared
- CacheManager.shared
- OfflineManager.shared

## 🧩 Key Components

### ArticleViewModel
Central ViewModel der håndterer:
- Artikel fetching og caching
- Favoritter management
- Firestore synkronisering
- AI recommendations
- Topics og authors

### WebflowService
API service for Webflow CMS:
- Fetch articles
- Fetch topics
- Fetch authors
- Fetch sections
- Stars mapping

### SecureConfig
Sikker håndtering af API keys:
- Keychain integration
- Secrets.plist support
- Environment variable fallback

## 🚀 Performance Optimizations

1. **Lazy Loading**: Pagination i SearchView
2. **Image Caching**: SDWebImage med disk cache
3. **Article Caching**: CacheManager for offline support
4. **Concurrent Loading**: Limited concurrent article loads
5. **Memory Management**: Proper cleanup i deinit

## 🔍 Debugging & Logging

Alle services bruger `OSLog`:
```swift
private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "ServiceName")
```

Logging levels:
- `.info` - General information
- `.debug` - Debug information
- `.error` - Errors
- `.warning` - Warnings

---

**Opdateret**: November 2024

