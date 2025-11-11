# Apropos Magazine iOS App

En moderne iOS-app til Apropos Magazine, bygget med SwiftUI og integreret med Webflow CMS, Firebase og Google Sign-In.

## 📱 Oversigt

Apropos Magazine app giver brugere adgang til artikler, kategorier, favoritter og personlig profil. Appen er bygget med moderne iOS-praksis og følger Apple's Human Interface Guidelines.

## 🏗️ Teknisk Stack

- **Framework**: SwiftUI
- **Sprog**: Swift 5.9+
- **Minimum iOS**: iOS 17.0+
- **Backend**: Webflow CMS (API v2)
- **Authentication**: Firebase Auth + Google Sign-In
- **Database**: Firebase Firestore
- **Push Notifications**: Firebase Cloud Messaging
- **Image Loading**: SDWebImageSwiftUI
- **Dependencies**: Swift Package Manager

## 📁 Projektstruktur

```
AproposMagazinev2/
├── Models/              # Data models (Article, Topic, Author, etc.)
├── Views/               # SwiftUI views
│   ├── Components/     # Genbrugelige UI komponenter
│   └── Helpers/        # View helpers og modifiers
├── ViewModels/          # ViewModels (MVVM pattern)
├── Services/            # Business logic og API services
├── Helpers/             # Utility functions og extensions
├── Resources/           # Assets, fonts, secrets
└── Scripts/            # Build scripts
```

Se [ARCHITECTURE.md](./ARCHITECTURE.md) for detaljeret arkitektur.

## 🚀 Hurtig Start

### Forudsætninger

- Xcode 15.0+
- macOS 14.0+
- CocoaPods (hvis nødvendigt)
- Webflow API key
- Firebase projekt konfigureret

### Installation

1. **Clone projektet**
   ```bash
   git clone <repository-url>
   cd AproposMagazinev2
   ```

2. **Konfigurer Secrets**
   - Kopiér `Resources/Secrets.example.plist` til `Resources/Secrets.plist`
   - Tilføj dine API keys i `Secrets.plist`:
     ```xml
     <key>WEBFLOW_API_KEY</key>
     <string>din-webflow-api-key</string>
     ```

3. **Konfigurer Firebase**
   - Tilføj `GoogleService-Info.plist` til projektet
   - Sørg for at Firebase er konfigureret i `AppDelegate.swift`

4. **Åbn projektet i Xcode**
   ```bash
   open AproposMagazinev2.xcodeproj
   ```

5. **Build og Run**
   - Vælg en simulator eller fysisk enhed
   - Tryk ⌘R for at build og køre

## 🔐 Sikkerhed

API keys og secrets håndteres via `SecureConfig`:
- **Keychain** (produktion)
- **Secrets.plist** (udvikling)
- **Environment variables** (CI/CD)

⚠️ **VIGTIGT**: `Resources/Secrets.plist` er i `.gitignore` - commit aldrig dine rigtige API keys!

## 📚 Dokumentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Arkitektur og design patterns
- [DEVELOPMENT.md](./DEVELOPMENT.md) - Udviklingsguide og best practices
- [SERVICES.md](./SERVICES.md) - API services dokumentation

## 🧪 Testing

Kør tests:
```bash
./Scripts/run-tests.sh
```

Eller i Xcode:
- ⌘U for at køre alle tests
- ⌘⌥U for at køre tests med coverage

## 🛠️ Udvikling

Se [DEVELOPMENT.md](./DEVELOPMENT.md) for:
- Code style guidelines
- Git workflow
- Debugging tips
- Troubleshooting

## 📦 Build & Deployment

### Development Build
```bash
xcodebuild -project AproposMagazinev2.xcodeproj \
           -scheme AproposMagazinev2 \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           build
```

### Production Build
1. Opdater version i `Info.plist`
2. Konfigurer signing i Xcode
3. Archive (⌘⌥B)
4. Upload til App Store Connect

## 🤝 Bidrag

1. Opret en feature branch
2. Commit dine ændringer
3. Push til remote
4. Opret en Pull Request

## 📄 Licens

[Indsæt licens information]

## 👥 Team

- Frederik Kragh - Lead Developer

## 🔗 Links

- [Webflow CMS](https://webflow.com)
- [Firebase Console](https://console.firebase.google.com)
- [Apple Developer](https://developer.apple.com)

---

**Opdateret**: November 2024

