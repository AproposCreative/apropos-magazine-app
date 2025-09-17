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
    case profile
    case article(Article)
    case categoryDetail(String) // category name
}

/// Tab identifiers for the main tab bar
enum Tab: String, CaseIterable, Identifiable, Codable {
    case home = "Hjem"
    case search = "Artikler"
    case categories = "Kategorier"
    case favorites = "Gemt"
    case profile = "Profil"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "doc.text.fill"
        case .categories: return "square.grid.2x2.fill"
        case .favorites: return "bookmark.fill"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - Navigation Coordinator

@MainActor
class NavigationCoordinator: ObservableObject {
    // Tab selection
    @Published var selectedTab: Tab = .home
    
    // Navigation paths for each tab
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var categoriesPath = NavigationPath()
    @Published var favoritesPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    
    // Deep linking support
    @Published var pendingDeepLink: URL?
    
    init() {
        // Listen for article navigation requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NavigateToArticle"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let article = notification.userInfo?["article"] as? Article {
                Task { @MainActor in
                    self?.navigateToArticle(article, in: .home)
                }
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
        case .profile:
            return Binding(
                get: { self.profilePath },
                set: { self.profilePath = $0 }
            )
        }
    }
    
    // MARK: - Navigation Actions
    
    /// Navigate to a specific tab
    func navigateToTab(_ tab: Tab) {
        selectedTab = tab
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
        case .profile:
            profilePath.append(article)
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
        case .profile:
            profilePath.append(route)
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
        case .profile:
            if !profilePath.isEmpty { profilePath.removeLast() }
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
        case .profile:
            profilePath = NavigationPath()
        }
    }
    
    // MARK: - Deep Linking
    
    /// Handle deep link navigation
    func handleDeepLink(_ url: URL) {
        // Parse URL and navigate accordingly
        // This can be expanded based on your deep linking requirements
        pendingDeepLink = url
    }
    
    // MARK: - Notification Navigation
    
    /// Navigate to article from notification
    func navigateToArticleFromNotification(articleId: String) {
        // Switch to home tab first
        selectedTab = .home
        
        // Clear any existing navigation path
        homePath = NavigationPath()
        
        // Post notification to fetch and navigate to article
        NotificationCenter.default.post(
            name: NSNotification.Name("FetchArticleForNavigation"),
            object: nil,
            userInfo: ["articleId": articleId]
        )
    }
}

// MARK: - Environment Key

private struct NavigationCoordinatorKey: EnvironmentKey {
    @MainActor static var defaultValue: NavigationCoordinator {
        NavigationCoordinator()
    }
}

extension EnvironmentValues {
    var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}
