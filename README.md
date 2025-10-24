# Apropos Magazine iOS App

A modern, SwiftUI-based iOS application for Apropos Magazine, featuring dynamic content management, user authentication, and seamless reading experience.

## 📱 Features

- **Dynamic Content Loading**: Real-time article fetching from Webflow CMS
- **User Authentication**: Secure Firebase authentication with Google Sign-In
- **Offline Reading**: Cached articles for offline access
- **Modern UI**: Clean, responsive SwiftUI interface with dark/light mode support
- **Category Management**: Dynamic topic filtering and organization
- **Search Functionality**: Full-text search across articles
- **Favorites System**: Save and manage favorite articles
- **Share Integration**: Native iOS sharing capabilities

## 🏗️ Architecture

### Tech Stack
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming for data flow
- **Firebase**: Authentication and real-time database
- **Webflow CMS**: Content management system
- **SDWebImage**: Efficient image loading and caching
- **Core Data**: Local data persistence

### Project Structure
```
AproposMagazinev2/
├── Models/                 # Data models (Article, Topic, Author)
├── Views/                  # SwiftUI views and components
│   ├── Components/         # Reusable UI components
│   └── Helpers/           # View modifiers and utilities
├── ViewModels/            # Business logic and state management
├── Services/              # API services and data fetching
├── Helpers/               # Utility classes and extensions
└── Assets.xcassets/       # App assets and resources
```

## 🔧 Setup & Installation

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

### Environment Setup
1. Clone the repository:
```bash
git clone https://github.com/AproposCreative/apropos-magazine-app.git
cd apropos-magazine-app
```

2. Install dependencies:
```bash
# Dependencies are managed via Swift Package Manager
# Open in Xcode and dependencies will be resolved automatically
```

3. Configure environment variables:
```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your API keys
nano .env
```

### Required API Keys
- **Webflow API**: For content management
- **Google API**: For authentication and services
- **Firebase**: For user management and real-time features

## 🚀 Getting Started

1. **Open in Xcode**: `AproposMagazinev2.xcodeproj`
2. **Configure Signing**: Set your development team
3. **Update API Keys**: Ensure all environment variables are set
4. **Build & Run**: Command+R to build and run

## 📱 App Structure

### Main Views
- **HomeView**: Featured articles and hero content
- **CategoriesView**: Topic-based article browsing
- **SearchView**: Article search functionality
- **FavoritesView**: Saved articles management
- **ArticleDetailView**: Full article reading experience

### Key Components
- **ArticleCardView**: Reusable article display component
- **CategoryFilterView**: Topic filtering interface
- **SwipeBackModifier**: Custom navigation gestures
- **SecureConfig**: API key management

## 🔒 Security

- **API Key Management**: Secure storage using iOS Keychain
- **Environment Variables**: No hardcoded secrets in source code
- **Firebase Security Rules**: Proper authentication and authorization
- **HTTPS Only**: All network requests use secure connections

## 🧪 Testing

### Unit Tests
```bash
# Run unit tests
xcodebuild test -scheme AproposMagazinev2 -destination 'platform=iOS Simulator,name=iPhone 15'
```

### UI Tests
```bash
# Run UI tests
xcodebuild test -scheme AproposMagazinev2UITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 📦 Dependencies

- **Firebase/Auth**: User authentication
- **Firebase/Firestore**: Real-time database
- **SDWebImageSwiftUI**: Image loading and caching
- **GoogleSignIn**: Google authentication
- **Combine**: Reactive programming

## 🚀 Deployment

### App Store Preparation
1. **Version Bumping**: Update version in Info.plist
2. **Code Signing**: Configure production certificates
3. **Archive**: Create production build
4. **Upload**: Submit to App Store Connect

### CI/CD
- **GitHub Actions**: Automated testing and building
- **Fastlane**: Automated deployment pipeline
- **Code Quality**: SwiftLint integration

## 📊 Performance

- **Image Optimization**: Lazy loading and caching
- **Memory Management**: Efficient resource usage
- **Network Optimization**: Request batching and caching
- **Battery Optimization**: Background task management

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for code formatting
- Write comprehensive unit tests
- Document public APIs

## 📄 License

This project is proprietary software owned by Apropos Creative. All rights reserved.

## 👥 Team

- **Development**: Frederik Kragh
- **Design**: Apropos Creative Team
- **Content**: Apropos Magazine Editorial Team

## 📞 Support

For technical support or questions:
- **Email**: frederik@aproposcreative.com
- **Issues**: GitHub Issues for bug reports
- **Documentation**: See Wiki for detailed guides

---

**Built with ❤️ for Apropos Magazine**
