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
    @EnvironmentObject var viewModel: ArticleViewModel
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var podcastPlayerManager = PodcastPlayerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var articleHeroNamespace
    // Temporarily removed RecommendationEngine to fix crash
    // @StateObject private var recommendationEngine = RecommendationEngine.shared
    @State private var showWhatsNew = false
    @State private var showNotificationOnboarding = false
    
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
    
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { navigationCoordinator.selectedTab },
            set: { newTab in
                if newTab == .home {
                    navigationCoordinator.navigateToHomeRoot()
                } else {
                    navigationCoordinator.selectedTab = newTab
                }
            }
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: tabSelection) {
                // Home Tab
                NavigationStack(path: navigationCoordinator.path(for: .home)) {
                    HomeView(articleHeroNamespace: articleHeroNamespace)
                        .environmentObject(viewModel)
                        .navigationDestination(for: Article.self) { article in
                            ArticleDetailView(article: article)
                                .environmentObject(viewModel)
                                .navigationTransition(.zoom(sourceID: article.id, in: articleHeroNamespace))
                                .transaction { transaction in
                                    if reduceMotion {
                                        transaction.disablesAnimations = true
                                    }
                                }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationView(for: route)
                        }
                        .navigationDestination(for: ContentSeries.self) { series in
                            SeriesDetailView(
                                series: series,
                                articles: series.articleIds.compactMap { id in
                                    viewModel.articles.first(where: { $0.id == id })
                                }
                            )
                            .environmentObject(viewModel)
                            .environment(\.navigationCoordinator, navigationCoordinator)
                        }
                }
                .id(navigationCoordinator.homeStackID)
                .background(InteractivePopGestureEnabler())
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
                .background(InteractivePopGestureEnabler())
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
                .background(InteractivePopGestureEnabler())
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
                .background(InteractivePopGestureEnabler())
                .tabItem { Label("Min side", systemImage: "person.crop.circle") }
                .tag(Tab.favorites)
            }
            .background(
                TabBarSelectionHandler(homeTabIndex: 0) {
                    navigationCoordinator.navigateToHomeRoot()
                }
            )
            .safeAreaInset(edge: .bottom) {
                if podcastPlayerManager.hasActiveEpisode {
                    Color.clear
                        .frame(height: PodcastMiniPlayerLayout.scrollBottomInset)
                }
            }
            
            if podcastPlayerManager.hasActiveEpisode {
                PodcastMiniPlayerBar()
                    .environmentObject(podcastPlayerManager)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 88)
                    .zIndex(2)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.84),
            value: podcastPlayerManager.hasActiveEpisode
        )
        .accentColor(.primary) // Use primary color for active tabs (black in light mode, white in dark mode)
        .environmentObject(viewModel)
        .environmentObject(podcastPlayerManager)
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
            
            Task { @MainActor in
                await PodcastRepository.shared.refreshManifest()
            }
            
            // Check for What's New after a short delay to ensure view is fully visible
            // This prevents the sheet from appearing before ContentView is ready
            Task { @MainActor in
                // Wait a bit for ContentView to be fully visible after splash screen
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                if !showWhatsNew {
                    let shouldShow = WhatsNewManager.shared.shouldShowWhatsNew()

                    if shouldShow {
                        showWhatsNew = true
                    } else {
                        await presentNotificationOnboardingIfNeeded()
                    }
                }
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(entries: WhatsNewManager.shared.entriesForDisplay()) {
                if let newest = WhatsNewManager.shared.entriesForDisplay().first {
                    WhatsNewManager.shared.markEntryAsSeen(newest)
                }
                showWhatsNew = false
                Task { @MainActor in
                    await presentNotificationOnboardingIfNeeded()
                }
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showNotificationOnboarding) {
            NotificationOnboardingView {
                showNotificationOnboarding = false
            }
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $podcastPlayerManager.isFullPlayerPresented) {
            PodcastAudioPlayerSheet()
                .environmentObject(viewModel)
                .environmentObject(podcastPlayerManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    @MainActor
    private func presentNotificationOnboardingIfNeeded() async {
        guard !showNotificationOnboarding else { return }
        guard await NotificationService.shared.shouldPresentOnboarding() else { return }
        showNotificationOnboarding = true
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ArticleViewModel())
    }
}

