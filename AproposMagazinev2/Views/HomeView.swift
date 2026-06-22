import SwiftUI
import SDWebImageSwiftUI
// import SwiftUIIntrospect  // Temporarily disabled due to Swift 6.0 compatibility issues
import Shimmer

// MARK: - Scroll Offset Key





struct HomeView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @ObservedObject private var podcastRepository = PodcastRepository.shared
    @ObservedObject private var podcastPlayerManager = PodcastPlayerManager.shared
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var articleHeroNamespace: Namespace.ID? = nil
    @State private var selectedHero = 0
    @State private var didLoad = false
    @State private var showGlassTopBar = false
    @State private var topSafeAreaInset: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0
    @State private var didRequestRecommendations = false
    @Environment(\.colorScheme) var colorScheme
    
    init(articleHeroNamespace: Namespace.ID? = nil) {
        self.articleHeroNamespace = articleHeroNamespace
        UIScrollView.appearance().bounces = false
    }
    
    private var progress: CGFloat {
        showGlassTopBar ? 1 : 0
    }
    
    private var heroHeight: CGFloat {
        UIScreen.main.bounds.height * 0.7
    }

    private var recommendedArticles: [Article] {
        if !viewModel.personalizedRecommendations.isEmpty {
            return viewModel.personalizedRecommendations.map(\.0)
        }
        if viewModel.section.count > 1 {
            return viewModel.section
        }

        let fallback = viewModel.allSectionArticles.isEmpty ? viewModel.articles : viewModel.allSectionArticles
        return Array(fallback.prefix(6))
    }

    private var podcastPairs: [PodcastArticlePair] {
        PodcastRepository.shared.latestPodcastPairsIncludingPending(from: viewModel.articles, limit: 2)
    }

    private var allPodcastPairs: [PodcastArticlePair] {
        PodcastRepository.shared.latestPodcastPairsIncludingPending(from: viewModel.articles, limit: 100)
    }

    private var resumablePodcastPair: PodcastArticlePair? {
        guard let pair = PodcastRepository.shared.resumablePair(from: viewModel.articles) else {
            return nil
        }
        if podcastPlayerManager.currentEpisode?.id == pair.episode.id {
            return nil
        }
        return pair
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ✅ GLAS-TOPBAR (indhold placeret inden i glass effekt)
            ZStack(alignment: .top) {
                if showGlassTopBar {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(progress)
                        .frame(height: topSafeAreaInset + 60)
                        .ignoresSafeArea(edges: .top)
                }
                
                // 👇 Topbar-indhold placeret INDEN i glass effekt - ALTID synligt
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topSafeAreaInset)
                    
                    HStack {
                        Spacer()

                        // 👇 Centreret logo - ALTID synligt
                        Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 30)
                            .opacity(0.9)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                } // Luk VStack for safe area spacing
            } // Luk indre ZStack
            .zIndex(1)
            .ignoresSafeArea(edges: .top)
            
            ScrollViewReader { scrollProxy in
                ScrollView {
                    // Scroll tracking - TOP-PROBE som første barn
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("homeScroll")).minY) { _, newValue in
                                let shouldShow = newValue < -16
                                if shouldShow != showGlassTopBar {
                                    withAnimation(AppMotion.easeOut(duration: 0.16, reduceMotion: reduceMotion)) {
                                        showGlassTopBar = shouldShow
                                    }
                                }
                            }
                    }
                    .frame(height: 0)
                    .id("homeScrollTop")

                    VStack(alignment: .leading) {
                        if viewModel.isLoading {
                            FullPageSkeleton()
                                .padding(.top, -topSafeAreaInset)
                        } else if viewModel.fetchError != nil && viewModel.articles.isEmpty {
                            EmptyStateView(
                                icon: "exclamationmark.triangle.fill",
                                title: "Kunne ikke hente artikler",
                                subtitle: "Tjek forbindelsen, eller prøv at opdatere igen.",
                                actionTitle: "Prøv igen"
                            ) {
                                viewModel.fetchArticles(forceRefresh: true)
                            }
                            .padding(.top, 160)
                            .padding(.horizontal, 16)
                        } else {
                            contentBody
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollHomeToTop)) { _ in
                    withAnimation(AppMotion.easeOut(duration: 0.25, reduceMotion: reduceMotion)) {
                        scrollProxy.scrollTo("homeScrollTop", anchor: .top)
                    }
                    showGlassTopBar = false
                }
            }
            .onPreferenceChange(HeroScrollOffsetKey.self) { heroScrollOffset = $0 }
            .coordinateSpace(name: "homeScroll")
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaPadding(.top, 0)
            .ignoresSafeArea(edges: .top)
            .refreshable {
                async let articles: Void = viewModel.refreshArticles()
                async let podcasts: Void = podcastRepository.refreshManifest(force: true)
                _ = await (articles, podcasts)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        topSafeAreaInset = geometry.safeAreaInsets.top
                    }
                    .onChange(of: geometry.safeAreaInsets.top) { _, newValue in
                        topSafeAreaInset = newValue
                    }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .id("homeTop")
        .onAppear {
            if !didLoad {
                didLoad = true
                preloadHeroArticles()
                preloadVisibleHomeImages()
                Task {
                    await podcastRepository.refreshManifest()
                }
            }
        }
        .onChange(of: viewModel.heroArticles.map(\.id)) { _, _ in
            selectedHero = 0
        }
    }
    
    // MARK: - Pre-loading Methods
    
    private func preloadHeroArticles() {
        // Safety check: ensure articles are loaded and not loading
        guard !viewModel.articles.isEmpty && !viewModel.isLoading else {
            return
        }

        // Keep launch smooth: warm only the first hero image.
        CacheManager.shared.preloadImages(for: Array(viewModel.heroArticles.prefix(1)))
    }

    private func preloadVisibleHomeImages() {
        guard !viewModel.articles.isEmpty && !viewModel.isLoading else {
            return
        }

        let likelyVisible = Array(
            viewModel.heroArticles.prefix(2)
            + podcastPairs.prefix(2).map(\.article)
            + recommendedArticles.prefix(4)
        )

        CacheManager.shared.preloadImages(for: likelyVisible)
    }
    
    private var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            // Hero section shimmer
            VStack(alignment: .leading, spacing: 16) {
                // Hero image shimmer
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: heroHeight)
                    .shimmering(
                        active: true,
                        animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.6),
                            Color.clear
                        ])
                    )
                
                // Hero title shimmer
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                        .shimmering(
                            active: true,
                            animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.6),
                                Color.clear
                            ])
                        )
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                        .frame(maxWidth: 0.7)
                        .shimmering(
                            active: true,
                            animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.6),
                                Color.clear
                            ])
                        )
                }
                .padding(.horizontal, 16)
            }
            
            // Articles shimmer
            VStack(spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 60)
                            .shimmering(
                                active: true,
                                animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.6),
                                    Color.clear
                                ])
                            )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .frame(maxWidth: .infinity)
                                .shimmering(
                                    active: true,
                                    animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color.white.opacity(0.6),
                                        Color.clear
                                    ])
                                )
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                                .frame(maxWidth: 0.6)
                                .shimmering(
                                    active: true,
                                    animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color.white.opacity(0.6),
                                        Color.clear
                                    ])
                                )
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 24)
        }
    }



    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.articles.isEmpty {
                HeroSwipeBar(
                    articles: viewModel.heroArticles,
                    selectedHero: $selectedHero,
                    heroHeight: heroHeight,
                    scrollOffset: heroScrollOffset,
                    heroTransitionNamespace: articleHeroNamespace,
                    onFavorite: { article in
                        viewModel.toggleFavorite(for: article)
                    }
                )
                .padding(.top, -topSafeAreaInset)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: HeroScrollOffsetKey.self,
                                value: geo.frame(in: .named("homeScroll")).minY
                            )
                    }
                }
            }

            if let pair = resumablePodcastPair {
                PodcastContinueListeningBanner(
                    pair: pair,
                    onContinue: {
                        podcastPlayerManager.play(episode: pair.episode, articleId: pair.article.id)
                    },
                    onOpenArticle: {
                        navigationCoordinator.navigateToArticle(pair.article, in: .home)
                    }
                )
                .padding(.top, 20)
            }

            if !podcastPairs.isEmpty {
                PodcastSectionView(
                    pairs: podcastPairs,
                    allPairs: allPodcastPairs,
                    authorProvider: { article in
                        if let resolvedAuthor = viewModel.author(for: article)?.name,
                           !resolvedAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return resolvedAuthor
                        }
                        if let embeddedAuthor = article.author?.name,
                           !embeddedAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return embeddedAuthor
                        }
                        if let hostName = PodcastRepository.shared.episodeMetadata(for: article)?.hosts.first,
                           !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return hostName
                        }
                        return "Lyt til artiklen"
                    },
                    categoriesProvider: { article in
                        viewModel.categories(for: article)
                    },
                    onOpenArticle: { article in
                        navigationCoordinator.navigateToArticle(article, in: .home)
                    },
                    onPlayEpisode: { episode in
                        let articleId = podcastPairs.first(where: { $0.episode.id == episode.id })?.article.id
                            ?? allPodcastPairs.first(where: { $0.episode.id == episode.id })?.article.id
                        podcastPlayerManager.play(episode: episode, articleId: articleId)
                    }
                )
                .padding(.top, 20)
            }

            if !recommendedArticles.isEmpty {
                ArticleSectionView(
                    title: "Anbefalet til dig",
                    articles: viewModel.personalizedRecommendations.isEmpty
                        ? recommendedArticles
                        : viewModel.personalizedRecommendations.map(\.0),
                    istopic: false,
                    recommendationReasons: Dictionary(
                        uniqueKeysWithValues: viewModel.personalizedRecommendations.map { ($0.0.id, $0.1) }
                    ),
                    onArticleSelected: { article in
                        let reason = viewModel.personalizedRecommendations.first(where: { $0.0.id == article.id })?.1 ?? ""
                        RecommendationService.shared.trackRecommendationTap(article: article, reason: reason)
                    }
                )
                .padding(.top, 20)
                .onAppear {
                    guard !didRequestRecommendations else { return }
                    didRequestRecommendations = true
                    viewModel.fetchPersonalizedRecommendationsIfNeeded()
                }
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        guard !didRequestRecommendations else { return }
                        didRequestRecommendations = true
                        viewModel.fetchPersonalizedRecommendationsIfNeeded()
                    }
            }

            if !viewModel.allAnmeldelser.isEmpty {
                ArticleSectionView(
                    title: "Anmeldelser",
                    articles: viewModel.allAnmeldelser, istopic: false
                )
                .padding(.top, 40)
            }

            if !viewModel.popular.isEmpty {
                ArticleSectionView(
                    title: "Populært",
                    articles: viewModel.popular, istopic: false
                )
                .padding(.top, 40)
            }

            if !viewModel.musicArticles.isEmpty {
                ArticleSectionView(
                    title: "Musik",
                    articles: viewModel.musicArticles, istopic: true
                )
                .padding(.top, 40)
            }
            
            if !viewModel.kulturArticles.isEmpty {
                ArticleSectionView(
                    title: "Kultur",
                    articles: viewModel.kulturArticles, istopic: true
                )
                .padding(.top, 40)
            }
            
            if !viewModel.serierFilmArticles.isEmpty {
                ArticleSectionView(
                    title: "Serier & Film",
                    articles: viewModel.serierFilmArticles, istopic: true
                )
                .padding(.top, 40)
            }
            Color.clear
                .frame(height: PodcastMiniPlayerLayout.feedBottomPadding(isPlayerVisible: podcastPlayerManager.hasActiveEpisode))
        }
    }





}

// MARK: - Hero Swipe Bar

private func heroSwipeSlideOpacity(for phase: ScrollTransitionPhase, reduceMotion: Bool) -> Double {
    guard !reduceMotion else { return 1 }
    guard !phase.isIdentity else { return 1 }
    let distance = min(abs(phase.value), 1)
    return Double(1 - distance * 0.72)
}

private func heroSwipeSlideScale(for phase: ScrollTransitionPhase, reduceMotion: Bool) -> CGFloat {
    guard !reduceMotion else { return 1 }
    guard !phase.isIdentity else { return 1 }
    let distance = min(abs(phase.value), 1)
    return 1 - distance * 0.015
}

struct HeroSwipeBar: View {
    let articles: [Article]
    @Binding var selectedHero: Int
    let heroHeight: CGFloat
    let scrollOffset: CGFloat
    let heroTransitionNamespace: Namespace.ID?
    let onFavorite: (Article) -> Void
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        let prefersReducedMotion = reduceMotion

        ZStack(alignment: .top) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(articles.enumerated()), id: \.offset) { index, article in
                        NavigationLink(value: article) {
                            HeroCardView(
                                article: article,
                                height: heroHeight,
                                scrollOffset: scrollOffset,
                                heroTransitionNamespace: heroTransitionNamespace,
                                selectedHero: $selectedHero,
                                index: index,
                                totalCount: articles.count
                            )
                            .frame(width: UIScreen.main.bounds.width, height: heroHeight)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(index)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .opacity(heroSwipeSlideOpacity(for: phase, reduceMotion: prefersReducedMotion))
                                .scaleEffect(heroSwipeSlideScale(for: phase, reduceMotion: prefersReducedMotion))
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: heroScrollPosition)
            .scrollClipDisabled()
            .frame(height: heroHeight)
            
            // Fixed Dots (Page Indicator)
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<articles.count, id: \.self) { dotIndex in
                        let isSelected = dotIndex == selectedHero
                        Image(isSelected ? "CapsuleDot" : "Dot")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: isSelected ? 25 : 8, height: 8)
                            .background(isSelected ? Color.clear : (colorScheme == .dark ? Color.black.opacity(1.0) : Color.white.opacity(0.8)))
                            .clipShape(
                                RoundedRectangle(cornerRadius: isSelected ? 0 : 4)
                            )
                            .padding(.top , 10) // Prevent clipping
                    }
                }
                .animation(AppMotion.heroCarouselSpring(reduceMotion: prefersReducedMotion), value: selectedHero)
                .padding(.bottom, 70)
            }
            .padding(.bottom, 20)
             
            .frame(height: heroHeight)
        }
        .frame(height: heroHeight)
        .onAppear {
            CacheManager.shared.preloadImages(for: Array(articles.prefix(2)))
        }
    }

    private var heroScrollPosition: Binding<Int?> {
        Binding(
            get: { selectedHero },
            set: { newValue in
                guard let newValue, newValue != selectedHero else { return }
                selectedHero = newValue
                preloadAdjacentArticles(currentIndex: newValue)
            }
        )
    }

    // MARK: - Pre-loading Methods
    
    private func preloadAdjacentArticles(currentIndex: Int) {
        // Keep hero swipe smooth by avoiding article detail preloading here.
    }
}






// MARK: - Hero Card View

struct HeroCardView: View {
    let article: Article
    let height: CGFloat
    let scrollOffset: CGFloat
    let heroTransitionNamespace: Namespace.ID?
    @State private var imageFailed = false
    @State private var heroImageIndex = 0
    @Binding var selectedHero: Int
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let totalCount: Int
    
    // Get categories for this article
    private var articleCategories: [String] {
        var categories: [String] = []
        
        // Add main topic category
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        // Add multi-topic categories if available
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }

    // Top-tagget i heroen viser artiklens section (som i artikel-visningen),
    // med topics som fallback hvis ingen section findes.
    private var heroTopTag: String {
        if let section = viewModel.sectionName(for: article), !section.isEmpty {
            return section
        }
        return Array(articleCategories.prefix(2)).joined(separator: " | ")
    }

    private var filledStarColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.92)
    }

    private var emptyStarColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.14)
    }

    private var heroBottomGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.3), .black]),
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.42),
                .init(color: .white.opacity(0.12), location: 0.62),
                .init(color: .white.opacity(0.38), location: 0.78),
                .init(color: .white.opacity(0.72), location: 0.9),
                .init(color: .white, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var heroImageCandidates: [URL] {
        var candidates: [URL] = []
        if let thumb = article.thumbURL { candidates.append(thumb) }
        if let cover = article.coverURL { candidates.append(cover) }
        // Last-resort fallback so hero never appears blank if large assets are missing.
        if let mobile = article.mobileImageURL { candidates.append(mobile) }

        var mutableArticle = article
        let fallbackURLString = mutableArticle.thumbnailURL
        if !fallbackURLString.isEmpty, let parsed = safeURL(from: fallbackURLString) {
            candidates.append(parsed)
        }

        var unique: [URL] = []
        var seen = Set<String>()
        for url in candidates {
            if seen.insert(url.absoluteString).inserted {
                unique.append(url)
            }
        }
        return unique
    }

    private var heroImageURL: URL? {
        guard heroImageCandidates.indices.contains(heroImageIndex) else { return nil }
        return heroImageCandidates[heroImageIndex]
    }

    private func safeURL(from raw: String) -> URL? {
        if let url = URL(string: raw) {
            return url
        }
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        return URL(string: encoded)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ArticleImagePlaceholder(mode: imageFailed ? .offline : .loading, cornerRadius: 0)
                .frame(width: UIScreen.main.bounds.width, height: height)

            if !imageFailed {
                WebImage(url: heroImageURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                    .resizable()
                    .onSuccess { _, _, _ in
                        imageFailed = false
                    }
                    .onFailure { _ in
                        let nextIndex = heroImageIndex + 1
                        if heroImageCandidates.indices.contains(nextIndex) {
                            heroImageIndex = nextIndex
                            imageFailed = false
                        } else {
                            imageFailed = true
                        }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: height)
                    .clipped()
                    .heroParallax(scrollOffset: scrollOffset, height: height)
                    .heroTransitionSource(id: article.id, namespace: heroTransitionNamespace)
                    .opacity(1)
            }

            // Gradient Overlay
            heroBottomGradient
                .frame(maxWidth: .infinity, maxHeight: height)

            // Foreground Content
            VStack(alignment: .leading, spacing: 12) {
                Spacer()

                VStack(alignment: .center, spacing: 30) {
                    // Tagline: vis section (magen til artikel-visningen), fallback til topics
                    Text(heroTopTag)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        
                    // Title
                    Text(article.name ?? "Titel")
                        .font(.system(size: 34, weight: .bold))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -18)

                    // Rating (if available)
                    if let rating = article.stjerne, rating > 0 {
                        HStack(spacing: 6) {
                            ForEach(1...6, id: \.self) { index in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(index <= rating ? filledStarColor : emptyStarColor)
                            }
                        }
                        .padding(.horizontal, 40)
                    }

                    HStack(spacing: 8) {
                        if let authorName = article.author?.name {
                            Text(authorName)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                                .background(Capsule().fill(colorScheme == .dark ? Color(hex: "#262626") : .white))
                                .textCase(.uppercase)
                        }

                        // Display actual categories for the article (max 2)
                        ForEach(Array(articleCategories.prefix(2)), id: \.self) { category in
                            Text(category.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Capsule().fill(colorScheme == .dark ? Color(hex: "#262626") : .white))
                        }
                    }
                    .padding(.top, -15) // Optional: adjust if needed

                    // Buttons
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            NavigationLink(value: article) {
                                HStack {
                                    Text("Læs nu")
                                }
                                .font(.headline)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                )
                                .foregroundColor(.black)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                // Add haptic feedback
                                HapticManager.shared.lightImpact()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                                    viewModel.toggleFavorite(for: article)
                                }
                            } label: {
                                Image(systemName: viewModel.isFavorite(article) ? "checkmark" : "plus")
                                    .foregroundColor(colorScheme == .dark ? .black : .black)
                                    .font(.title2)
                                    .frame(width: 24, height: 24) // 🔧 Fixed frame to prevent size changes
                                    .padding(12)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: .infinity))

                                    .scaleEffect(viewModel.isFavorite(article) ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isFavorite(article))
                            }
                            .allowsHitTesting(true)
                            .contentShape(Rectangle())
                        }
                        Spacer()
                    }
                    .padding(.top, 15)
                }
                .padding(.horizontal, 8)
               
                .padding(.bottom, 20)
            }
           
            .frame(width: UIScreen.main.bounds.width - 32, height: height)
        }
        .frame(height: height)
        .cornerRadius(0)
        .shadow(color: colorScheme == .dark ? .black.opacity(0.25) : .clear, radius: colorScheme == .dark ? 10 : 0)
        .padding(.horizontal, 0)
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .onFirstAppear {
            // No eager detail fetch here; keeps first-scroll smooth.
        }
        .onChange(of: article.id) { _, _ in
            heroImageIndex = 0
            imageFailed = false
        }
    }
}







// MARK: - Article Section

import SwiftUI

    struct ArticleSectionView: View {
        let title: String
        let articles: [Article]
        var istopic: Bool
        var recommendationReasons: [String: String] = [:]
        var onArticleSelected: ((Article) -> Void)? = nil
        @EnvironmentObject var viewModel: ArticleViewModel

        var body: some View {
            let spacing: CGFloat = 10
            let isSection = title == "Musik" || title == "Kultur" || title == "Serier & Film"
            let cardWidth: CGFloat = isSection ? 270 : 173
            let cardHeight: CGFloat = isSection ? 310 : 96
            // Keep full card + text visible to avoid clipping in Home sections.
            let sectionHeight: CGFloat = isSection ? (cardHeight + 150) : (cardHeight + 120)

            VStack(alignment: .leading, spacing: 16) {
                titleBar
                articleScrollView(spacing: spacing, cardWidth: cardWidth, cardHeight: cardHeight, isSection: isSection, sectionHeight: sectionHeight)
            }
        }
        
        @ViewBuilder
        private var titleBar: some View {
            let allArticles = getAllArticlesForTitle()

            HStack {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWeight(.heavy)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                
                if allArticles.count > articles.count {
                    NavigationLink(destination: SimpleCategoryView(title: title, articles: allArticles)) {
                        Text("Se alle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        
        private func getAllArticlesForTitle() -> [Article] {
            switch title {
            case "Musik":
                return viewModel.allMusicArticles
            case "Kultur":
                return viewModel.allKulturArticles
            case "Serier & Film":
                return viewModel.allSerierFilmArticles
            case "Anmeldelser":
                return viewModel.allAnmeldelserArticles
            case "Populært":
                return viewModel.allPopularArticles
            case "Anbefalet til dig":
                return viewModel.allSectionArticles
            default:
                return articles // Fallback to passed articles
            }
        }
        
        private func articleScrollView(spacing: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat, isSection: Bool, sectionHeight: CGFloat) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                        NavigationLink(value: article) {
                            ArticleCardView_Enhanced(
                                article: article,
                                isFavorite: viewModel.favorites.contains(article),
                                cardHeight: cardHeight,
                                showStars: isSection,
                                showTopic: istopic,
                                recommendationReason: recommendationReasons[article.id]
                            ) { article in
                                viewModel.toggleFavorite(for: article)
                            }
                            .frame(width: cardWidth)
                            .frame(height: sectionHeight - 8, alignment: .top)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            onArticleSelected?(article)
                        })
                    }
                }
                .padding(.leading, 16) // Align with title padding
                .padding(.trailing, 16) // Add trailing padding for last card
            }
            .frame(height: sectionHeight)
        }
    }

// MARK: - Simple Category View
struct SimpleCategoryView: View {
    let title: String
    let articles: [Article]
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var showNavTitle = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                // Den store overskrift – vises kun i toppen
                if !showNavTitle {
                    Text(title)
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // Artikelliste
                VStack(spacing: 0) {
                    ForEach(articles) { article in
                        NavigationLink(value: article) {
                            ArticleRowCompact(article: article)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if article.id != articles.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .padding(.top, showNavTitle ? 12 : 0)
                
                Spacer(minLength: 80)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = scrollOffset <= -30
            }
        }
        .navigationTitle(showNavTitle ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(showNavTitle ? title : "")
                    .font(.headline)
                    .opacity(showNavTitle ? 1 : 0)
            }
        }
        .onAppear {
            showNavTitle = false
        }
    }
}

#Preview {
    NavigationView {
        HomeView()
            .environmentObject(ArticleViewModel())
    }
}

struct ReviewRowView: View {
    let index: Int
    let article: Article

    var body: some View {
        NavigationLink(value: article) {
            
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.subheadline.bold())
                    .foregroundColor(Color("SerialNumberColor"))
                    .frame(width: 24, height: 24)
                    .background(Color("SerialNumberColorBOX"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top ,0)
                    .padding(.leading ,5)
                Text(article.name ?? "Uden titel")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.bottom , 15)
            .padding(.leading , 15)
            .padding(.trailing , 10)
            .padding(.top, 3)
            .background(Color("AppGray"))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle()) // Prevents default blue arrow/highlight
    }
}

struct ArticleStaticCell: View {
    let article: Article
    var hasRoundedImage: Bool = true
    @EnvironmentObject var viewModel: ArticleViewModel
    @State private var imageLoaded = false
    @State private var imageFailed = false

    // Get categories for this article
    private var articleCategories: [String] {
        var categories: [String] = []
        
        // Add main topic category
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        // Add multi-topic categories if available
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }

    private var placeholderMode: ArticleImagePlaceholderMode {
        if imageFailed { return .offline }
        if imageLoaded { return .idle }
        return .loading
    }

    var body: some View {
        NavigationLink(value: article) {
            // Prevents default blue arrow/highlight
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Thumbnail
                    var mutableArticle = article
                    ZStack {
                        ArticleImagePlaceholder(mode: placeholderMode, cornerRadius: hasRoundedImage ? 8 : 0)

                        if !imageFailed {
                            AsyncImage(url: URL(string: mutableArticle.thumbnailURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .onAppear {
                                            imageLoaded = true
                                        }
                                case .failure:
                                    Color.clear
                                        .onAppear {
                                            imageFailed = true
                                            imageLoaded = false
                                        }
                                default:
                                    Color.clear
                                }
                            }
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(hasRoundedImage ? 8 : 0)
                    .onChange(of: article.id) { _, _ in
                        imageLoaded = false
                        imageFailed = false
                    }
                    
                    // Title & Category
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.name ?? "Title")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                        
                        Text(articleCategories.joined(separator: " | "))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .frame(height: 100)
                        .alignmentGuide(.top) { _ in 0 }
                }
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}












extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)
        
        if hex.hasPrefix("#") {
            _ = scanner.scanString("#")
        }
        
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}
//MArk":- meeeeee
extension View {
    func onFirstAppear(_ perform: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(perform: perform))
    }
}
private struct OnFirstAppearModifier: ViewModifier {
    @State private var hasAppeared = false
    let perform: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    perform()
                }
            }
    }
}


// MARK: - Simple Category View (Same layout as CategoryArticlesView)
