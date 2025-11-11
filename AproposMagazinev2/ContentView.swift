//
//  ContentView.swift
//  AproposMagazinev2
//
//  Created by Frederik Kragh on 20/06/2025.
//  Updated with robust navigation structure based on Apple's NavigationCookbook
//

import SwiftUI


struct ContentView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @StateObject private var viewModel = ArticleViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    // Temporarily removed RecommendationEngine to fix crash
    // @StateObject private var recommendationEngine = RecommendationEngine.shared
    @State private var showWhatsNew = false
    @State private var whatsNewEntries: [WhatsNewEntry] = []
    
    init() {
        // Listen for deep link notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HandleDeepLink"),
            object: nil,
            queue: .main
        ) { _ in
            // NavigationCoordinator will be available in body
            // We'll handle this in onAppear
        }
    }
    
    var body: some View {
        TabView(selection: $navigationCoordinator.selectedTab) {
            // Home Tab
            NavigationStack(path: navigationCoordinator.path(for: .home)) { 
                HomeView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Article.self) { article in
                        ArticleDetailView(article: article)
                            .environmentObject(viewModel)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem { Label("Hjem", systemImage: "house.fill") }
            .tag(Tab.home)
            
            // Search Tab
            NavigationStack(path: navigationCoordinator.path(for: .search)) {
                SearchView_Enhanced()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Article.self) { article in
                        ArticleDetailView(article: article)
                            .environmentObject(viewModel)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem { Label("Artikler", systemImage: "doc.text") }
            .tag(Tab.search)
            
            // Categories Tab
            NavigationStack(path: navigationCoordinator.path(for: .categories)) {
                CategoriesView()
                    .environmentObject(viewModel)
                    .environmentObject(navigationCoordinator)
                    .navigationDestination(for: Article.self) { article in
                        ArticleDetailView(article: article)
                            .environmentObject(viewModel)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }
            .tag(Tab.categories)
            
            // Favorites Tab
            NavigationStack(path: navigationCoordinator.path(for: .favorites)) {
                FavoritesView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Article.self) { article in
                        ArticleDetailView(article: article)
                            .environmentObject(viewModel)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem { Label("Gemt", systemImage: "bookmark.fill") }
            .tag(Tab.favorites)
            
            // Profile Tab
            NavigationStack(path: navigationCoordinator.path(for: .profile)) {
                ProfileView_NewDesign()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Article.self) { article in
                        ArticleDetailView(article: article)
                            .environmentObject(viewModel)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem { Label("Profil", systemImage: "person.fill") }
            .tag(Tab.profile)
        }
        .accentColor(.primary) // Use primary color for active tabs (black in light mode, white in dark mode)
        .environmentObject(viewModel)
        .environment(\.navigationCoordinator, navigationCoordinator)
        .onAppear {
            // Set tab bar appearance with glass effect from backup
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground() // ✅ Transparent for glass effect
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial) // ✅ Glass effect
            
            // Configure normal state
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.systemGray
            ]
            
            // Configure selected state with primary color (black in light mode, white in dark mode)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.label
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.label
            ]
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .environmentObject(viewModel)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .onAppear {
            // TabView appeared
            
            // Handle pending deep links
            if let deepLink = navigationCoordinator.pendingDeepLink {
                navigationCoordinator.handleDeepLink(deepLink)
                navigationCoordinator.pendingDeepLink = nil
            }
            
            // Listen for deep link notifications
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HandleDeepLink"),
                object: nil,
                queue: .main
            ) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    Task { @MainActor in
                        navigationCoordinator.handleDeepLink(url)
                    }
                }
            }
            
            // Check for What's New after a short delay to ensure view is fully visible
            // This prevents the sheet from appearing before ContentView is ready
            Task { @MainActor in
                // Wait a bit for ContentView to be fully visible after splash screen
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                if !showWhatsNew && whatsNewEntries.isEmpty {
                    let shouldShow = WhatsNewManager.shared.shouldShowWhatsNew()
                    print("🔍 [ContentView] shouldShowWhatsNew: \(shouldShow)")
                    
                    if shouldShow {
                        let allEntries = WhatsNewManager.shared.getAllEntries()
                        print("🔍 [ContentView] Found \(allEntries.count) What's New entries")
                        whatsNewEntries = allEntries
                        showWhatsNew = true
                        print("✅ [ContentView] Showing What's New sheet")
                    } else {
                        print("⚠️ [ContentView] What's New should not be shown (already seen or no entries)")
                    }
                } else {
                    print("⚠️ [ContentView] What's New already shown or entries already loaded")
                }
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(entries: whatsNewEntries) {
                // Mark ALL entries as seen (so they won't show again)
                // This ensures users see What's New for each update, but only once per version
                for entry in whatsNewEntries {
                    WhatsNewManager.shared.markEntryAsSeen(entry)
                }
                showWhatsNew = false
            }
            .interactiveDismissDisabled()
        }
    }

    
    // MARK: - Navigation Destination Views
    
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .home:
            HomeContainer()
        case .search:
            SearchView_Enhanced()
        case .categories:
            CategoriesView()
                .environmentObject(navigationCoordinator)
        case .favorites:
            FavoritesView()
        case .profile:
            ProfileView_NewDesign()
                .environmentObject(viewModel)
        case .article(let article):
            ArticleDetailView(article: article)
                .environmentObject(viewModel)
        case .categoryDetail(let categoryName):
            CategoryDetailView(categoryName: categoryName)
                .environmentObject(viewModel)
                .environment(\.navigationCoordinator, navigationCoordinator)
        }
    }
}

// HomeContainer that can scroll to top when told
struct HomeContainer: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    // Temporarily removed RecommendationEngine to fix crash
    // @EnvironmentObject var recommendationEngine: RecommendationEngine
    
    var body: some View {
        ScrollViewReader { proxy in
            HomeView()
                .environmentObject(viewModel)
                .id("homeTop")
        }
        .onAppear {
            print("🏠 HomeContainer vises nu")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

