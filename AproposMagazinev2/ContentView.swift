//
//  ContentView.swift
//  AproposMagazinev2
//
//  Created by Frederik Kragh on 20/06/2025.
//  Updated with robust navigation structure based on Apple's NavigationCookbook
//

import SwiftUI


struct ContentView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var viewModel = ArticleViewModel()
    // Temporarily removed RecommendationEngine to fix crash
    // @StateObject private var recommendationEngine = RecommendationEngine.shared
    
    var body: some View {
        TabView(selection: $navigationCoordinator.selectedTab) {
            // Home Tab
            NavigationStack(path: navigationCoordinator.path(for: .home)) { 
                HomeView()
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
                ProfileView()
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
            print("🌱 ContentView vises nu")
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
        case .favorites:
            FavoritesView()
        case .profile:
            ProfileView()
        case .article(let article):
            ArticleDetailView(article: article)
                .environmentObject(viewModel)
        case .categoryDetail(let categoryName):
            CategoryDetailView(categoryName: categoryName)
                .environmentObject(viewModel)
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
