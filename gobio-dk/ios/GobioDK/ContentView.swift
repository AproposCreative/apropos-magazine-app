import SwiftUI

struct ContentView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @StateObject private var viewModel = MovieViewModel()
    
    var body: some View {
        TabView(selection: $navigationCoordinator.selectedTab) {
            NavigationStack(path: navigationCoordinator.path(for: .home)) {
                HomeView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Movie.self) { movie in
                        MovieDetailView(movie: movie)
                            .environmentObject(viewModel)
                    }
            }
            .tabItem { Label("Film", systemImage: "film.fill") }
            .tag(Tab.home)
            
            NavigationStack(path: navigationCoordinator.path(for: .search)) {
                SearchView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Movie.self) { movie in
                        MovieDetailView(movie: movie)
                            .environmentObject(viewModel)
                    }
            }
            .tabItem { Label("Søg", systemImage: "magnifyingglass") }
            .tag(Tab.search)
            
            NavigationStack(path: navigationCoordinator.path(for: .cinemas)) {
                CinemasView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Movie.self) { movie in
                        MovieDetailView(movie: movie)
                            .environmentObject(viewModel)
                    }
            }
            .tabItem { Label("Biografer", systemImage: "building.2.fill") }
            .tag(Tab.cinemas)
            
            NavigationStack(path: navigationCoordinator.path(for: .watchlist)) {
                WatchlistView()
                    .environmentObject(viewModel)
                    .navigationDestination(for: Movie.self) { movie in
                        MovieDetailView(movie: movie)
                            .environmentObject(viewModel)
                    }
            }
            .tabItem { Label("Watchlist", systemImage: "heart.fill") }
            .tag(Tab.watchlist)
            
            NavigationStack(path: navigationCoordinator.path(for: .profile)) {
                ProfileView()
                    .environmentObject(viewModel)
            }
            .tabItem { Label("Profil", systemImage: "person.fill") }
            .tag(Tab.profile)
        }
        .tint(Color(hex: "6366F1"))
        .environmentObject(viewModel)
        .environment(\.navigationCoordinator, navigationCoordinator)
        .onAppear {
            setupTabBarAppearance()
            
            Task {
                await viewModel.loadInitialData()
            }
            
            viewModel.setupWatchlistListener()
        }
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
        
        let accentColor = UIColor(Color(hex: "6366F1"))
        appearance.stackedLayoutAppearance.selected.iconColor = accentColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accentColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
