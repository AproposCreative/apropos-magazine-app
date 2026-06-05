# Udviklingsguide

## 🛠️ Setup

### 1. Xcode Konfiguration

- **Minimum Xcode Version**: 15.0+
- **Swift Version**: 5.9+
- **iOS Deployment Target**: 17.0+

### 2. Dependencies

Projektet bruger **Swift Package Manager**:

- Firebase (Auth, Firestore, Messaging)
- GoogleSignIn
- SDWebImageSwiftUI

Dependencies opdateres automatisk når projektet åbnes i Xcode.

### 3. Secrets Setup

1. Kopiér `Resources/Secrets.example.plist` til `Resources/Secrets.plist`
2. Tilføj dine API keys:
   ```xml
   <key>WEBFLOW_API_KEY</key>
   <string>din-webflow-api-key</string>
   
   <key>GOOGLE_API_KEY</key>
   <string>din-google-api-key</string>
   
   <key>OPENAI_API_KEY</key>
   <string>din-openai-api-key</string>
   ```

3. Sørg for at `Secrets.plist` er i `.gitignore`

### 4. Firebase Setup

1. Download `GoogleService-Info.plist` fra Firebase Console
2. Tilføj til projektet (sørg for at det er i target)
3. Firebase konfigureres automatisk i `AppDelegate.swift`

### 5. What's New Changelog

Appen viser automatisk "What's New" ved første start efter en opdatering.

#### Konfiguration

- **Datafil**: `Resources/WhatsNew/whatsnew.json`
- **Manager**: `Managers/WhatsNewManager.swift`
- **View**: `Views/WhatsNewView.swift`
- **Model**: `Models/WhatsNewEntry.swift`

#### Generer Changelog fra Git

Brug scriptet `Scripts/generate_whats_new.py` til at generere en ny changelog entry fra git commits:

```bash
# Generer changelog fra sidste tag til nu
Scripts/generate_whats_new.py --version 2.4.0 --since v2.3.0

# Eller lad scriptet finde sidste tag automatisk
Scripts/generate_whats_new.py --version 2.4.0

# Med custom title og subtitle
Scripts/generate_whats_new.py --version 2.4.0 \
  --title "Nyheder i Apropos Magazine" \
  --subtitle "Her er de vigtigste forbedringer i denne version."
```

#### Manuel Redigering

Du kan også redigere `Resources/WhatsNew/whatsnew.json` manuelt:

```json
[
  {
    "version": "2.4.0",
    "title": "Nyheder i Apropos Magazine",
    "subtitle": "Her er de vigtigste forbedringer i denne version.",
    "items": [
      {
        "icon": "sparkles",
        "title": "Ny feature",
        "description": "Beskrivelse af featuren"
      }
    ],
    "ctaTitle": "Se alle ændringer",
    "ctaURL": "https://aproposmagazine.com/changelog"
  }
]
```

#### Tilgængelige Icons

Scriptet mapper automatisk commit messages til SF Symbols:
- `fix`, `bug` → `wrench.fill`, `ant.fill`
- `refactor` → `gearshape.2.fill`
- `performance`, `speed` → `bolt.fill`
- `new`, `add`, `feature` → `sparkles`
- `design`, `ui` → `wand.and.stars`
- `update` → `arrow.triangle.2.circlepath`

#### Version Tracking

- Appen husker hvilken version brugeren har set
- Vises kun én gang per version
- Tracking gemmes i UserDefaults med key: `com.aproposmagazine.whatsnew.lastSeenVersion`

#### Integration

`ContentView.swift` viser automatisk `WhatsNewView` som sheet når:
1. En ny version er registreret
2. Brugeren ikke har set denne version før
3. Der findes en entry for den aktuelle version i `whatsnew.json`

## 📝 Code Style

### Swift Style Guide

Følg Apple's Swift API Design Guidelines og SwiftUI best practices.

#### Naming Conventions

- **Types**: PascalCase (`ArticleViewModel`, `WebflowService`)
- **Functions**: camelCase (`fetchArticles()`, `toggleFavorite()`)
- **Variables**: camelCase (`isLoading`, `selectedArticle`)
- **Constants**: camelCase eller PascalCase for static (`maxConcurrentLoads`, `AppConstants.Spacing.medium`)

#### File Organization

```swift
// MARK: - Imports
import Foundation
import SwiftUI

// MARK: - Model/View/ViewModel Definition
struct MyView: View {
    // MARK: - Properties
    @State private var isLoading = false
    
    // MARK: - Body
    var body: some View {
        // ...
    }
    
    // MARK: - Helper Methods
    private func helperMethod() {
        // ...
    }
}
```

#### SwiftUI Best Practices

1. **Brug `@State` for lokal state**
   ```swift
   @State private var searchText = ""
   ```

2. **Brug `@EnvironmentObject` for shared state**
   ```swift
   @EnvironmentObject var viewModel: ArticleViewModel
   ```

3. **Brug `@Published` i ViewModels**
   ```swift
   @Published var articles: [Article] = []
   ```

4. **Extract subviews for complex UI**
   ```swift
   var body: some View {
       VStack {
           headerView
           contentView
           footerView
       }
   }
   
   private var headerView: some View {
       // ...
   }
   ```

### Error Handling

Brug `Result` type for async operations:
```swift
func fetchArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
    // ...
    completion(.success(articles))
    // eller
    completion(.failure(error))
}
```

### Logging

Brug `OSLog` for alle services:
```swift
private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "ServiceName")

logger.info("Information message")
logger.debug("Debug message")
logger.error("Error: \(error.localizedDescription, privacy: .public)")
logger.warning("Warning message")
```

## 🔄 Git Workflow

### Branch Strategy

- **main** - Production ready code
- **develop** - Development branch
- **feature/*** - Feature branches
- **bugfix/*** - Bug fix branches

### Commit Messages

Følg conventional commits:
```
feat: Add dark mode support
fix: Fix memory leak in ArticleViewModel
docs: Update README.md
refactor: Simplify navigation logic
test: Add unit tests for WebflowService
```

### Pull Request Process

1. Opret feature branch fra `develop`
2. Commit ændringer med descriptive messages
3. Push til remote
4. Opret Pull Request
5. Code review
6. Merge til `develop`

## 🐛 Debugging

### Xcode Debugging

1. **Breakpoints**: Sæt breakpoints i kritiske steder
2. **LLDB Commands**:
   ```lldb
   po viewModel.articles.count
   po viewModel.isLoading
   ```

3. **View Hierarchy Debugger**: ⌘⇧Y

### Console Logging

Alle services logger til console via `OSLog`:
```swift
logger.debug("Fetching articles...")
```

Filtrer logs i Console app:
- Subsystem: `com.aproposmagazine.app`
- Category: `WebflowService`, `ArticleViewModel`, etc.

### Network Debugging

1. **Charles Proxy** eller **Proxyman** for API debugging
2. **Webflow API Console** for API requests
3. **Firebase Console** for Firestore operations

### Memory Debugging

1. **Instruments** - Memory Leaks
2. **Xcode Memory Graph Debugger**: ⌘⇧M
3. Check for retain cycles i closures

## 🧪 Testing

Projektet har **ingen automatiske test targets** (unit/UI). Verificer ændringer manuelt på simulator eller fysisk iPhone før TestFlight.

### Manual Testing Checklist

- [ ] App launches successfully
- [ ] Articles load from Webflow
- [ ] Home hero edge-to-edge (ingen hvidt gap)
- [ ] Article typography, inline images, image credits
- [ ] “Læs også” cards aligned correctly
- [ ] Navigation works correctly (tabs, back, home)
- [ ] Min side: logged out + Google login + favorites
- [ ] Categories fit without unwanted bounce/scroll
- [ ] Favorites sync with Firestore when logged in
- [ ] Offline mode works
- [ ] Push notifications work
- [ ] Podcast playback and mini player
- [ ] Dark/Light mode switching
- [ ] Image loading and caching
- [ ] What's New vises én gang efter opdatering

### Fremtidige automatiske tests

Hvis vi tilføjer tests igen, start med små unit tests for ren logik (fx `ArticleHTMLProcessor`, podcast manifest parsing) — ikke Xcode-skabelon-tests.

## 🚀 Build & Deployment

### Development Build

```bash
xcodebuild -project AproposMagazinev2.xcodeproj \
           -scheme AproposMagazinev2 \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           build
```

### Production Build

1. **Update Version**
   - Opdater `CFBundleShortVersionString` i `Info.plist`
   - Opdater `CFBundleVersion` (build number)

2. **Configure Signing**
   - Vælg team i Xcode
   - Vælg provisioning profile

3. **Archive**
   - Product → Archive (⌘⌥B)
   - Wait for archive to complete

4. **Distribute**
   - Click "Distribute App"
   - Choose distribution method (App Store, Ad Hoc, etc.)
   - Follow wizard

## 🔧 Troubleshooting

### Common Issues

#### 1. "Missing API Key" Error

**Problem**: App can't find API keys

**Solution**:
1. Check `Resources/Secrets.plist` exists
2. Verify key names match `SecureConfig` expectations
3. Check Keychain for stored keys
4. Verify environment variables (if using CI/CD)

#### 2. Firebase Not Initializing

**Problem**: Firebase services not working

**Solution**:
1. Verify `GoogleService-Info.plist` is in project
2. Check Firebase is configured in `AppDelegate`
3. Verify bundle identifier matches Firebase project
4. Check Firebase console for errors

#### 3. Images Not Loading

**Problem**: Images don't appear

**Solution**:
1. Check network connection
2. Verify image URLs are valid
3. Check SDWebImage cache
4. Verify ATS (App Transport Security) settings

#### 4. Navigation Not Working

**Problem**: Navigation links don't work

**Solution**:
1. Verify `NavigationCoordinator` is injected
2. Check `NavigationStack` is set up correctly
3. Verify `navigationDestination` modifiers
4. Check for navigation state issues

#### 5. Memory Issues

**Problem**: App crashes due to memory

**Solution**:
1. Check for retain cycles
2. Verify proper cleanup in `deinit`
3. Check image cache size
4. Limit concurrent operations

### Debugging Tips

1. **Enable Verbose Logging**: Set log level to `.debug` in development
2. **Use Instruments**: Profile app for performance issues
3. **Check Console**: Look for warnings and errors
4. **Test on Device**: Some issues only appear on physical devices
5. **Clean Build**: ⌘⇧K, then rebuild

## 📚 Resources

### Documentation
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Webflow API Documentation](https://developers.webflow.com)

### Tools
- [Xcode](https://developer.apple.com/xcode/)
- [Instruments](https://developer.apple.com/documentation/xcode/instruments)
- [Firebase Console](https://console.firebase.google.com)

### Learning Resources
- [Apple's SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Hacking with Swift](https://www.hackingwithswift.com)

---

**Opdateret**: November 2024
