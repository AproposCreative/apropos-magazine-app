//
//  NavigationCoordinator.swift
//  AproposMagazinev2
//
//  Created by AI Assistant on 04/09/2025.
//  Robust navigation coordinator based on Apple's NavigationCookbook
//

import SwiftUI
import Foundation

// MARK: - Navigation Routes

/// Main navigation routes for the app
enum AppRoute: Hashable, Codable {
    case home
    case search
    case categories
    case favorites
    case article(Article)
    case author(Author)
    case categoryDetail(String) // category name
    case categoryList(title: String, articles: [Article]) // "Se alle"-liste fra Home
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

    
    /// Local navigation fixtures use the actual paths without installing the
    /// normal app's incoming-link observer or reaching its service runtime.
    init(observeIncomingArticleLinks: Bool = true) {
        guard observeIncomingArticleLinks else { return }
        // Listen for article navigation requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NavigateToArticle"),
            object: nil,
            queue: .main
        ) { notification in
            if let article = notification.userInfo?["article"] as? Article {
                MainActor.assumeIsolated {
                    _ = IncomingLinkRuntime.shared.accept(.article(id: article.id))
                }
            } else {
                AppDiagnostics.recordOperational(.navigationEventInvalid)
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

    /// A user tap on the active tab returns only that tab to its root.
    /// This is a user reselection boundary, separate from ordinary navigation.
    /// Ignore a request for another tab; its existing state must remain intact.
    func reselect(_ tab: Tab) {
        guard selectedTab == tab else { return }
        if tab == .home {
            navigateToHomeRoot()
        } else if !path(for: tab).wrappedValue.isEmpty {
            goToRoot(in: tab)
        }
    }

    /// Switch to home tab and reset its navigation stack to the root feed.
    func navigateToHomeRoot() {
        selectedTab = .home

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            goToRoot(in: .home)
            // Home also owns view/Boolean destinations outside homePath.
            // Recreate only its stack so selecting Home closes those routes too.
            homeStackID = UUID()
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

    /// Replace the top article (or top route) so related-article browsing
    /// doesn't stack Home → A → B and require two back taps.
    func replaceTopArticle(with article: Article, in tab: Tab? = nil) {
        let target = tab ?? selectedTab
        switch target {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
            homePath.append(article)
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
            searchPath.append(article)
        case .categories:
            if !categoriesPath.isEmpty { categoriesPath.removeLast() }
            categoriesPath.append(article)
        case .favorites:
            if !favoritesPath.isEmpty { favoritesPath.removeLast() }
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

    /// Navigate to an author detail page within a specific tab's stack
    func navigateToAuthor(_ author: Author, in tab: Tab? = nil) {
        let target = tab ?? selectedTab
        let route = AppRoute.author(author)
        switch target {
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
    
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool { IncomingLinkRuntime.shared.accept(url) }

    func navigateToArticleFromNotification(articleId: String) {
        _ = IncomingLinkRuntime.shared.accept(.article(id: articleId))
    }

    func scheduleNotificationNavigation(_ payload: NotificationNavigation.Payload) {
        guard IncomingLinkRuntime.shared.acceptNotification(payload) else { return }
        UserDefaults.standard.set(true, forKey: NotificationNavigation.skipBootloaderKey)
    }

    // Compatibility call on ContentView appearance. Ingress retains the latest
    // request itself; AppReadiness marks actual readiness immediately afterward.
    func flushPendingNotificationNavigationIfNeeded() {}

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
