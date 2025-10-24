# Contributing to Apropos Magazine iOS App

Thank you for your interest in contributing to the Apropos Magazine iOS app! This document provides guidelines and information for contributors.

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0+ development environment
- Git installed and configured
- Basic knowledge of Swift and SwiftUI

### Development Setup
1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/apropos-magazine-app.git
   cd apropos-magazine-app
   ```
3. Open `AproposMagazinev2.xcodeproj` in Xcode
4. Configure your development environment (see README.md)

## 📋 Development Guidelines

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for consistent formatting
- Write self-documenting code with clear variable names
- Add comments for complex business logic
- Follow the existing code structure and patterns

### SwiftUI Best Practices
- Use `@State`, `@Binding`, and `@ObservedObject` appropriately
- Implement proper view lifecycle methods
- Create reusable components in the `Components/` directory
- Use environment objects for shared state
- Implement proper error handling

### Architecture Patterns
- Follow MVVM pattern for view models
- Use Combine for reactive programming
- Implement proper separation of concerns
- Keep business logic in ViewModels
- Use Services for external API calls

## 🧪 Testing

### Unit Tests
- Write unit tests for all ViewModels
- Test business logic and data transformations
- Aim for >80% code coverage
- Use descriptive test names

### UI Tests
- Test critical user flows
- Verify navigation works correctly
- Test accessibility features
- Ensure proper error handling

### Running Tests
```bash
# Run all tests
xcodebuild test -scheme AproposMagazinev2

# Run specific test target
xcodebuild test -scheme AproposMagazinev2 -only-testing:AproposMagazinev2Tests
```

## 🔧 Pull Request Process

### Before Submitting
1. **Create a feature branch** from `main`
2. **Write tests** for new functionality
3. **Update documentation** if needed
4. **Run tests** to ensure everything passes
5. **Check code style** with SwiftLint

### Pull Request Guidelines
- **Clear title**: Describe what the PR does
- **Detailed description**: Explain changes and motivation
- **Link issues**: Reference any related issues
- **Screenshots**: For UI changes, include before/after
- **Testing notes**: Describe how to test the changes

### PR Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] UI tests pass
- [ ] Manual testing completed

## Screenshots (if applicable)
Add screenshots here

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes
```

## 🐛 Bug Reports

### Before Reporting
1. Check existing issues
2. Verify the bug exists in the latest version
3. Try to reproduce the issue

### Bug Report Template
```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Environment:**
- iOS Version: [e.g. 17.0]
- Device: [e.g. iPhone 15]
- App Version: [e.g. 1.0.0]

**Additional context**
Any other context about the problem.
```

## ✨ Feature Requests

### Before Requesting
1. Check if the feature already exists
2. Consider if it aligns with the app's purpose
3. Think about implementation complexity

### Feature Request Template
```markdown
**Is your feature request related to a problem?**
A clear description of what the problem is.

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Any alternative solutions or features you've considered.

**Additional context**
Add any other context or screenshots about the feature request.
```

## 🔒 Security

### Security Guidelines
- **Never commit API keys** or sensitive information
- **Use environment variables** for configuration
- **Follow secure coding practices**
- **Report security issues** privately to maintainers

### Reporting Security Issues
If you discover a security vulnerability, please:
1. **Do not** create a public issue
2. Email security concerns to: frederik@aproposcreative.com
3. Include detailed information about the vulnerability
4. Allow time for the issue to be addressed before disclosure

## 📚 Documentation

### Code Documentation
- Document public APIs with Swift doc comments
- Use `///` for single-line documentation
- Use `/** */` for multi-line documentation
- Include parameter descriptions and return values

### Example
```swift
/// Fetches articles from the Webflow API
/// - Parameter category: Optional category filter
/// - Returns: Array of Article objects
/// - Throws: NetworkError if request fails
func fetchArticles(category: String? = nil) async throws -> [Article] {
    // Implementation
}
```

## 🏷️ Release Process

### Version Numbering
- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

### Release Checklist
- [ ] Update version numbers
- [ ] Update CHANGELOG.md
- [ ] Run full test suite
- [ ] Update documentation
- [ ] Create release notes
- [ ] Tag release in Git

## 💬 Communication

### Getting Help
- **GitHub Discussions**: For general questions
- **Issues**: For bug reports and feature requests
- **Email**: frederik@aproposcreative.com for private matters

### Code of Conduct
- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the project's coding standards

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to Apropos Magazine iOS App! 🎉
