//
//  NavigationCoordinator.swift
//  AproposMagazinev2
//
//  Created by AI Assistant on 04/09/2025.
//  Robust navigation coordinator based on Apple's NavigationCookbook
//

import SwiftUI
import Foundation
import OSLog

// MARK: - Navigation Routes

/// Main navigation routes for the app
enum AppRoute: Hashable, Codable {
    case home
    case search
    case categories
    case favorites
    case article(Article)
    case categoryDetail(String) // category name
    case categoryList(title: String, articles: [Article]) // "Se alle"-liste fra Home
}

/// A parsed, side-effect-free representation of an incoming deep link or
/// widget/notification URL. Parsing is intentionally separated from navigation
/// so it can be unit-tested in isolation (the navigation side effects are what
/// previously caused articles to open twice).
enum DeepLink: Equatable {
    case article(id: String)
    case category(name: String)
    case author(id: String)

    /// Parse an `aproposmagazine://` (or `https://aproposmagazine.com`) URL into
    /// a concrete action. Returns `nil` for unknown schemes/hosts or malformed
    /// links so callers can ignore them safely.
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "aproposmagazine" || url.host == "aproposmagazine.com" else {
            return nil
        }

        let knownTypes = ["article", "category", "author"]
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Resolve a (type, identifier) pair from any of the supported URL shapes:
        //  - custom-scheme host form:   aproposmagazine://article/{id}
        //  - universal-link path form:  https://aproposmagazine.com/article/{id}
        //  - fragment form:             aproposmagazine://home#article/{id}
        var type: String?
        var identifier: String?

        if url.scheme == "aproposmagazine", let host = url.host, knownTypes.contains(host) {
            type = host
            identifier = pathComponents.first
        } else if pathComponents.count >= 2 {
            type = pathComponents[0]
            identifier = pathComponents[1]
        } else if let fragment = url.fragment, fragment.hasPrefix("article/") {
            type = "article"
            identifier = String(fragment.dropFirst("article/".count))
        }

        guard let type, let identifier, !identifier.isEmpty else { return nil }

        switch type {
        case "article": return .article(id: identifier)
        case "category": return .category(name: identifier)
        case "author": return .author(id: identifier)
        default: return nil
        }
    }
}

/// Tab identifiers for the main tab bar
enum Tab: String, CaseIterable, Identifiable, Codable {
    case home = "Hjem"
    case search = "Artikler"
    case categories = "Kategorier"
    case favorites = "Min side"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "doc.text.fill"
        case .categories: return "square.grid.2x2.fill"
        case .favorites: return "person.crop.circle"
        }
    }
}

// MARK: - Navigation Coordinator

@MainActor
class NavigationCoordinator: ObservableObject {
    // Singleton instance
    static let shared = NavigationCoordinator()
    
    // Tab selection
    @Published var selectedTab: Tab = .home
    
    // Navigation paths for each tab
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var categoriesPath = NavigationPath()
    @Published var favoritesPath = NavigationPath()
    
    // Deep linking support
    @Published private(set) var homeStackID = UUID()
    private(set) var pendingNotificationPayload: NotificationNavigation.Payload?

    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "NavigationCoordinator")
    
    private init() {
        // Listen for article navigation requests
        // Since this is a singleton, we don't need weak self
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NavigateToArticle"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let article = notification.userInfo?["article"] as? Article {
                Task { @MainActor in
                    self.selectedTab = .home
                    await AppReadiness.waitUntilUIReady()
                    await Task.yield()
                    self.navigateToArticle(article, in: .home)
                }
            } else {
                self.logger.warning("NavigateToArticle notification mangler Article objekt")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Navigation Path Access
    
    /// Get the navigation path for a specific tab
    func path(for tab: Tab) -> Binding<NavigationPath> {
        switch tab {
        case .home:
            return Binding(
                get: { self.homePath },
                set: { self.homePath = $0 }
            )
        case .search:
            return Binding(
                get: { self.searchPath },
                set: { self.searchPath = $0 }
            )
        case .categories:
            return Binding(
                get: { self.categoriesPath },
                set: { self.categoriesPath = $0 }
            )
        case .favorites:
            return Binding(
                get: { self.favoritesPath },
                set: { self.favoritesPath = $0 }
            )
        }
    }
    
    // MARK: - Navigation Actions
    
    /// Navigate to a specific tab
    func navigateToTab(_ tab: Tab) {
        if tab == .home {
            navigateToHomeRoot()
            return
        }
        selectedTab = tab
    }

    /// Switch to home tab and reset its navigation stack to the root feed.
    func navigateToHomeRoot() {
        selectedTab = .home

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            goToRoot(in: .home)
        }

        NotificationCenter.default.post(name: .scrollHomeToTop, object: nil)
    }
    
    /// Navigate to an article within a specific tab's navigation stack
    func navigateToArticle(_ article: Article, in tab: Tab) {
        switch tab {
        case .home:
            homePath.append(article)
        case .search:
            searchPath.append(article)
        case .categories:
            categoriesPath.append(article)
        case .favorites:
            favoritesPath.append(article)
        }
    }
    
    /// Navigate to category detail
    func navigateToSeries(_ series: ContentSeries, in tab: Tab) {
        switch tab {
        case .home:
            homePath.append(series)
        case .search:
            searchPath.append(series)
        case .categories:
            categoriesPath.append(series)
        case .favorites:
            favoritesPath.append(series)
        }
    }

    /// Navigate to category detail
    func navigateToCategory(_ categoryName: String, in tab: Tab) {
        let route = AppRoute.categoryDetail(categoryName)
        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .categories:
            categoriesPath.append(route)
        case .favorites:
            favoritesPath.append(route)
        }
    }
    
    /// Go back one step in the navigation stack for a specific tab
    func goBack(in tab: Tab) {
        switch tab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .categories:
            if !categoriesPath.isEmpty { categoriesPath.removeLast() }
        case .favorites:
            if !favoritesPath.isEmpty { favoritesPath.removeLast() }
        }
    }
    
    /// Go to the root of the navigation stack for a specific tab
    func goToRoot(in tab: Tab) {
        switch tab {
        case .home:
            homePath = NavigationPath()
        case .search:
            searchPath = NavigationPath()
        case .categories:
            categoriesPath = NavigationPath()
        case .favorites:
            favoritesPath = NavigationPath()
        }
    }
    
    // MARK: - Deep Linking
    
    /// Handle deep link navigation
    func handleDeepLink(_ url: URL) {
        logger.info("Håndterer deep link: \(url.absoluteString, privacy: .public)")

        guard let link = DeepLink.parse(url) else {
            logger.warning("Ukendt eller ugyldigt deep link: \(url.absoluteString, privacy: .public)")
            return
        }

        switch link {
        case .article(let id):
            navigateToArticleFromNotification(articleId: id)
        case .category(let name):
            navigateToCategory(name, in: .categories)
        case .author(let id):
            // Can be expanded when an author detail view is implemented.
            logger.debug("Author deep link: \(id, privacy: .public)")
        }
    }
    
    // MARK: - Notification Navigation
    
    /// Navigate to article from notification
    func navigateToArticleFromNotification(articleId: String) {
        selectedTab = .home
        homePath = NavigationPath()

        NotificationCenter.default.post(
            name: NSNotification.Name("FetchArticleForNavigation"),
            object: nil,
            userInfo: ["articleId": articleId]
        )
    }

    func scheduleNotificationNavigation(_ payload: NotificationNavigation.Payload) {
        pendingNotificationPayload = payload
        UserDefaults.standard.set(true, forKey: NotificationNavigation.skipBootloaderKey)

        NotificationCenter.default.post(
            name: NSNotification.Name("OpenArticleFromNotification"),
            object: nil,
            userInfo: NotificationNavigation.userInfo(for: payload)
        )
    }

    func flushPendingNotificationNavigationIfNeeded() {
        guard let payload = pendingNotificationPayload else { return }

        selectedTab = .home

        NotificationCenter.default.post(
            name: NSNotification.Name("OpenArticleFromNotification"),
            object: nil,
            userInfo: NotificationNavigation.userInfo(for: payload)
        )
    }

    func clearPendingNotificationNavigation(for identifier: String) {
        guard let pending = pendingNotificationPayload else { return }
        let matchesIdentifier = pending.articleIdentifier == identifier
        let matchesSlug = pending.articleSlug?.compare(identifier, options: .caseInsensitive) == .orderedSame
        guard matchesIdentifier || matchesSlug else { return }
        pendingNotificationPayload = nil
    }
}

// MARK: - Environment Key

private struct NavigationCoordinatorKey: EnvironmentKey {
    @MainActor static var defaultValue: NavigationCoordinator {
        NavigationCoordinator.shared
    }
}

extension EnvironmentValues {
    var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}
