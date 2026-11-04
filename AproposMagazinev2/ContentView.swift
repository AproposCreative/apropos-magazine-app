//
//  ContentView.swift
//  AproposMagazinev2
//
//  Created by Frederik Kragh on 20/06/2025.
//  Updated with robust navigation structure based on Apple's NavigationCookbook
//

import Combine
import SwiftUI

/// Only the normal app constructs this bridge. The model itself has no player,
/// SDK, timer or storage dependency and is also used by local Home fixtures.
@MainActor
enum PodcastPlayerPresentationRuntime {
    static let model: PodcastPlayerPresentationModel = {
        let player = PodcastPlayerManager.shared
        let model = PodcastPlayerPresentationModel(read: {
            .init(activeEpisodeID: player.currentEpisode?.id,
                preparationID: player.offlinePreparationID,
                preparationTitle: player.offlinePreparationTitle,
                isFullPlayerPresented: player.isFullPlayerPresented,
                offlinePlaybackMessage: player.offlinePlaybackMessage)
        })
        model.observe(player.objectWillChange.eraseToAnyPublisher())
        model.synchronize()
        return model
    }()
}

struct ContentView: View {
    @ObservedObject private var navigationCoordinator = NavigationCoordinator.shared
    @EnvironmentObject var viewModel: ArticleViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var incomingLinks = IncomingLinkRuntime.shared
    @ObservedObject private var notificationInbox = NotificationInboxRuntime.model
    private let podcastPlayerManager = PodcastPlayerManager.shared
    @ObservedObject private var podcastPresentation = PodcastPlayerPresentationRuntime.model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var articleHeroNamespace
    @State private var replayIntroduction = false

    private var notificationUnreadCount: Int {
        NotificationTabBadge.unreadCount(in: notificationInbox, language: viewModel.articleLanguage)
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
        AproposNavigationShell(selection: tabSelection,
            hasActiveEpisode: podcastPresentation.snapshot.hasActiveEpisode,
            hasPreparation: podcastPresentation.snapshot.preparationTitle != nil,
            favoritesUnreadCount: notificationUnreadCount,
            onTabReselected: { navigationCoordinator.reselect($0) }) {
            navigationPages
        } accessory: {
            if let title = podcastPresentation.snapshot.preparationTitle,
               let id = podcastPresentation.snapshot.preparationID,
               !podcastPresentation.snapshot.hasActiveEpisode {
                PodcastOfflinePreparationBar(title: title, open: {
                    podcastPlayerManager.isFullPlayerPresented = true
                }, cancel: {
                    _ = podcastPlayerManager.cancelOfflinePreparation(id: id)
                })
                .zIndex(2)
            } else if podcastPresentation.snapshot.hasActiveEpisode {
                PodcastMiniPlayerBar()
                    .environmentObject(podcastPlayerManager)
                    .zIndex(2)
                    .transition(AppMotion.playerTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            AppMotion.playerSpring(response: 0.48, damping: 0.84, reduceMotion: reduceMotion),
            value: podcastPresentation.snapshot.hasActiveEpisode
        )
        .accentColor(.primary) // Use primary color for active tabs (black in light mode, white in dark mode)
        .environmentObject(viewModel)
        .environmentObject(podcastPlayerManager)
        .environment(\.navigationCoordinator, navigationCoordinator)
        .environment(\.locale, AppLocalization.locale(for: viewModel.articleLanguage))
        .modifier(SavedArticleAccountPresenter(gate: viewModel.accountSaveGate))
        .onChange(of: viewModel.articleLanguage) { _, _ in
            // Retire incompatible article audio through the existing session
            // lifecycle before projecting the newly selected text language.
            podcastPlayerManager.reconcileContentLanguage()
            // Hidden stacks must not reopen a previous-language article.
            for tab in [Tab.home, .search, .categories, .favorites] {
                navigationCoordinator.goToRoot(in: tab)
            }
            // The shared language preference is updated by the existing
            // selection path before this view callback. Reproject its unread
            // badge immediately, without marking any message read.
            NotificationInboxRuntime.didBecomeActive()
        }
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

            navigationCoordinator.flushPendingNotificationNavigationIfNeeded()
            AppReadiness.markUIReady()
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .modifier(ReaderIntroductionPresenter(automatic: true,
            startupBlocked: navigationCoordinator.selectedTab != .home
                || !navigationCoordinator.homePath.isEmpty || !navigationCoordinator.searchPath.isEmpty
                || !navigationCoordinator.categoriesPath.isEmpty || !navigationCoordinator.favoritesPath.isEmpty
                || podcastPresentation.snapshot.hasActiveEpisode
                || podcastPresentation.snapshot.preparationID != nil
                || podcastPresentation.snapshot.isFullPlayerPresented
                || viewModel.accountSaveGate.request != nil,
            replayRequested: $replayIntroduction,
            featureSetupRequested: viewModel.accountSaveGate.needsSetup,
            canOpenFeatureSetup: { viewModel.accountSaveGate.permitsSetup },
            didOpenFeatureSetup: { viewModel.accountSaveGate.acknowledgeSetup() }))
        .sheet(isPresented: Binding(
            get: { podcastPresentation.snapshot.isFullPlayerPresented },
            set: { podcastPlayerManager.isFullPlayerPresented = $0 }
        )) {
            PodcastAudioPlayerSheet()
                .environmentObject(viewModel)
                .environmentObject(podcastPlayerManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .alert(
            "Kan ikke afspille",
            isPresented: Binding(
                get: { podcastPresentation.snapshot.offlinePlaybackMessage != nil },
                set: { if !$0 { podcastPlayerManager.clearOfflinePlaybackMessage() } }
            )
        ) {
            Button("OK", role: .cancel) {
                podcastPlayerManager.clearOfflinePlaybackMessage()
            }
        } message: {
            Text(LocalizedStringKey(podcastPresentation.snapshot.offlinePlaybackMessage ?? ""))
        }
        .alert("Gem efter login", isPresented: Binding(
            get: { viewModel.accountSaveGate.message != nil },
            set: { if !$0 { viewModel.accountSaveGate.clearMessage() } })) {
                Button("OK") { viewModel.accountSaveGate.clearMessage() }
        } message: {
            Text(LocalizedStringKey(viewModel.accountSaveGate.message ?? ""))
        }
        .onChange(of: incomingLinks.acceptedIntentRevision) { _, _ in viewModel.accountSaveGate.cancel() }
    }

    @ViewBuilder private var navigationPages: some View {
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
                            viewModel.visibleArticles.first(where: { $0.id == id })
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
                    ArticleDetailView(article: article, analyticsSource: .search)
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
        .tabItem { NotificationFavoritesTabLabel(unreadCount: notificationUnreadCount) }
        .modifier(NotificationTabBadge(unreadCount: notificationUnreadCount))
        .tag(Tab.favorites)
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
        case .author(let author):
            AuthorDetailView(author: author)
                .environmentObject(viewModel)
        case .categoryDetail(let categoryName):
            CategoryDetailView(categoryName: categoryName)
                .environmentObject(viewModel)
                .environment(\.navigationCoordinator, navigationCoordinator)
        case .categoryList(let title, let articles):
            SimpleCategoryView(title: title, articles: articles)
                .environmentObject(viewModel)
        }
    }
}

// HomeContainer that can scroll to top when told
struct HomeContainer: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    
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

