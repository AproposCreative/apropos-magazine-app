import SwiftUI
import SDWebImageSwiftUI
// import SwiftUIIntrospect  // Temporarily disabled due to Swift 6.0 compatibility issues
import Shimmer

// MARK: - Scroll Offset Key





struct HomeView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    // Temporarily removed RecommendationEngine to fix crash
    // @EnvironmentObject var recommendationEngine: RecommendationEngine
    @State private var selectedHero = 0
    @State private var didLoad = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    init() {
        UIScrollView.appearance().bounces = false
    }
    
    private var progress: CGFloat {
        // 0 → 1 når man har scrollet 5 pixels (meget responsiv effekt)
        let threshold: CGFloat = 5
        let p = min(max(scrollOffset / threshold, 0), 1)
        return p // direkte progress
    }
    
    private func starImageName(for index: Int, rating: Int) -> String {
        let isFilled = index < rating
        if colorScheme == .dark {
            return isFilled ? "DarkStar" : "DimStar"
        } else {
            return isFilled ? "DimStar" : "DarkStar"
        }
    }

    private var heroHeight: CGFloat {
        UIScreen.main.bounds.height * 0.7
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ✅ GLAS-TOPBAR (indhold placeret inden i glass effekt)
            ZStack(alignment: .top) {
                // 👇 Glass overlay bag ved alt
                if progress > 0.01 {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(progress) // 🔧 START MED 0% OG BLIVER 100% HURTIGT
                        .frame(height: 104) // 60 + 44 for safe area
                        .ignoresSafeArea(edges: .top)
                }
                
                // 👇 Topbar-indhold placeret INDEN i glass effekt - ALTID synligt
                VStack(spacing: 0) {
                    // Safe area spacer
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 44)
                    
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
            
            ScrollView {
                // Scroll tracking - TOP-PROBE som første barn
                GeometryReader { geo in
                    Color.clear
                        .frame(height: 0.1)
                        .onChange(of: geo.frame(in: .named("homeScroll")).minY) { _, newValue in
                            // newValue is negative when scrolling down, so we make it positive
                            scrollOffset = max(0, -newValue)
                        }
                }
                .frame(height: 0.1)
                
                VStack(alignment: .leading) {
                    if viewModel.isLoading {
                        FullPageSkeleton()
                    } else {
                        contentBody
                    }
                }
            }
            .coordinateSpace(name: "homeScroll")
            .ignoresSafeArea(.container, edges: .top)
        }
        .id("homeTop")
        .onAppear {
            if !didLoad {
                didLoad = true
                preloadHeroArticles()
            }
        }
    }
    
    // MARK: - Pre-loading Methods
    
    private func preloadHeroArticles() {
        // Safety check: ensure articles are loaded and not loading
        guard !viewModel.articles.isEmpty && !viewModel.isLoading else {
            print("🔄 Articles not ready for preloading")
            return
        }
        
        // Only pre-load the first 2 hero articles to prevent overload
        let heroArticles = Array(viewModel.articles.prefix(2))
        for article in heroArticles {
            // Prevent duplicate loading and memory overload
            if article.author == nil && !viewModel.loadingArticles.contains(article.id) && viewModel.fullArticle?.id != article.id {
                print("🔄 Preloading article: \(article.name ?? "No name")")
                viewModel.loadFullArticle(with: article.id)
            }
        }
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
                    .padding(.top, -5) // Match hero section positioning
                
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
        VStack(alignment: .leading) {
            
            // Debug info
            if viewModel.articles.isEmpty {
                VStack {
                    Text("Debug: No articles loaded")
                        .foregroundColor(.red)
                    Text("Articles count: \(viewModel.articles.count)")
                    Text("Is loading: \(viewModel.isLoading ? "Yes" : "No")")
                    if let error = viewModel.fetchError {
                        Text("Error: \(error.localizedDescription)")
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            
            if !viewModel.articles.isEmpty {
                HeroSwipeBar(
                    articles: Array(viewModel.articles.prefix(5)),
                    selectedHero: $selectedHero,
                    heroHeight: heroHeight,
                    onFavorite: { article in
                        viewModel.toggleFavorite(for: article)
                    }
                )
                .padding(.top, -5) // Move hero section 5 pixels up to remove gap
            }

            if !viewModel.section.isEmpty {
                ArticleSectionView(
                    title: "Anbefalet til dig",
                    articles: viewModel.section, istopic: false
                )
                .padding(.top, 20)
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


            if !viewModel.articles.isEmpty {
                Text("Alle artikler")
                    .foregroundColor(.primary)
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 60)
                    .padding(.leading, 16)

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.articles.prefix(8).enumerated()), id: \.element.id) { index, article in
                        ReviewRowView(index: index + 1, article: article)
                    }
                }
                .padding(.top, 16)
                .background(Color("AppGray"))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                
                // Oprindelig liste med 8 artikler
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.articles.prefix(8)), id: \.id) { article in
                        ArticleStaticCell(article: article)
                        Divider()
                    }
                }
                .padding(.top, 20)
            }

            Spacer(minLength: 32)
        }
    }





}

// MARK: - Hero Swipe Bar

struct HeroSwipeBar: View {
    let articles: [Article]
    @Binding var selectedHero: Int
    let heroHeight: CGFloat
    let onFavorite: (Article) -> Void
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .top) {
            // Swipable Cards with enhanced snapping
            TabView(selection: $selectedHero) {
                ForEach(Array(articles.enumerated()), id: \.0) { (index, article) in
                    NavigationLink(destination: ArticleDetailView(article: article)) {
                        HeroCardView(
                            article: article,
                            height: heroHeight,
                            selectedHero: $selectedHero,
                            index: index,
                            totalCount: articles.count
                        )
                        .tag(index)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: heroHeight)
                                .onChange(of: selectedHero) { _, newValue in
                        // Ensure smooth snapping animation
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedHero = newValue
                        }
                        
                        // Pre-load adjacent articles for smooth swiping
                        preloadAdjacentArticles(currentIndex: newValue)
                    }
            
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
                            .animation(.easeInOut(duration: 0.25), value: selectedHero)
                    }
                }
                .padding(.bottom, 70)
            }
            .padding(.bottom, 20)
             
            .frame(height: heroHeight)
        }
        .frame(height: heroHeight)
        .onAppear {
            // Only pre-load the first 2 hero articles to prevent overload
            let articlesToPreload = Array(articles.prefix(2))
            for article in articlesToPreload {
                // Prevent duplicate loading and memory overload
                if article.author == nil && !viewModel.loadingArticles.contains(article.id) && viewModel.fullArticle?.id != article.id {
                    viewModel.loadFullArticle(with: article.id)
                }
            }
        }
    }
    
    // MARK: - Pre-loading Methods
    
    private func preloadAdjacentArticles(currentIndex: Int) {
        // Only pre-load the current article to prevent overload
        let indicesToLoad = [currentIndex]
        
        for index in indicesToLoad {
            guard index >= 0 && index < articles.count else { continue }
            let article = articles[index]
            // Prevent duplicate loading and memory overload
            if article.author == nil && !viewModel.loadingArticles.contains(article.id) && viewModel.fullArticle?.id != article.id {
                viewModel.loadFullArticle(with: article.id)
            }
        }
    }
}






// MARK: - Hero Card View

struct HeroCardView: View {
    let article: Article
    let height: CGFloat
    @State private var didLoad = false
    @Binding var selectedHero: Int
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
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
    
    private func starImageName(for index: Int, rating: Int) -> String {
        let isFilled = index < rating
        if colorScheme == .dark {
            return isFilled ? "DarkStar" : "DimStar"
        } else {
            return isFilled ? "DimStar" : "DarkStar"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            var mutableArticle = article
            WebImage(url: URL(string: mutableArticle.thumbnailURL), options: [.retryFailed, .refreshCached])
                .onSuccess { _, _, _ in
                   
                }
                .onFailure { error in
                    print("Image failed: \(error.localizedDescription)")
                }
                          .resizable()
                          .aspectRatio(contentMode: .fill)
                          .frame(width: UIScreen.main.bounds.width, height: height)
                          .clipped()
                         
                          
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    .clear,
                    colorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.1),
                    colorScheme == .dark ? .black : .white
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: height)

            // Foreground Content
            VStack(alignment: .leading, spacing: 12) {
                Spacer()

                VStack(alignment: .center, spacing: 30) {
                    // Tagline (max 2 categories)
                    Text(Array(articleCategories.prefix(2)).joined(separator: " | "))
                        .font(.custom("SFProText-Semibold", size: 15))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        
                    // Title
                    Text(article.name ?? "Titel")
                        .font(.custom("SFProText-Bold", size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -18)

                    // Rating (if available)
                    if let rating = article.stjerne, rating > 0 {
                        HStack(spacing: 6) {
                            ForEach(0..<6) { index in
                                Image(starImageName(for: index, rating: rating))
                                    .resizable()
                                    .frame(width: 18, height: 18)
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
                            NavigationLink(destination: ArticleDetailView(article: article)) {
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
        .shadow(radius: 10)
        .padding(.horizontal, 0)
        .ignoresSafeArea(.container, edges: .top)
        .contentShape(Rectangle())
        .onFirstAppear {
            // Prevent duplicate loading and memory overload
            if article.author == nil && !viewModel.loadingArticles.contains(article.id) && viewModel.fullArticle?.id != article.id {
                viewModel.loadFullArticle(with: article.id)
            }
        }
    }
}







// MARK: - Article Section

import SwiftUI

    struct ArticleSectionView: View {
        let title: String
        let articles: [Article]
        var istopic: Bool
        @EnvironmentObject var viewModel: ArticleViewModel

        var body: some View {
            let spacing: CGFloat = 10
            let isSection = title == "Musik" || title == "Kultur" || title == "Serier & Film"
            let cardWidth: CGFloat = isSection ? 270 : 173
            let cardHeight: CGFloat = isSection ? 310 : 96
            let sectionHeight: CGFloat = isSection ? 415 : 160

            VStack(alignment: .leading, spacing: 16) {
                titleBar
                articleScrollView(spacing: spacing, cardWidth: cardWidth, cardHeight: cardHeight, isSection: isSection, sectionHeight: sectionHeight)
            }
        }
        
        private var titleBar: some View {
            HStack {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWeight(.heavy)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                
                NavigationLink(destination: SimpleCategoryView(title: title, articles: getAllArticlesForTitle())) {
                    Text("Se alle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
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
                HStack(spacing: spacing) {
                    ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                        NavigationLink(destination: ArticleDetailView(article: article)) {
                            ArticleCardView_Enhanced(
                                article: article,
                                isFavorite: viewModel.favorites.contains(article),
                                cardHeight: cardHeight,
                                showStars: isSection,
                                showTopic: istopic
                            ) { article in
                                viewModel.toggleFavorite(for: article)
                            }
                            .frame(width: cardWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onAppear {
                            // Prevent duplicate loading and memory overload
                            if article.author == nil && !viewModel.loadingArticles.contains(article.id) && viewModel.fullArticle?.id != article.id {
                                viewModel.loadFullArticle(with: article.id)
                            }
                        }
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
                        NavigationLink(destination: ArticleDetailView(article: article)) {
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
        NavigationLink(destination: ArticleDetailView(article: article)) {
            
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
    var hasRoundedImage: Bool = false  // 🔧 Default to false
    @EnvironmentObject var viewModel: ArticleViewModel

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

    var body: some View {
        NavigationLink(destination: ArticleDetailView(article: article)) {
            // Prevents default blue arrow/highlight
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Thumbnail
                    var mutableArticle = article
                    AsyncImage(url: URL(string: mutableArticle.thumbnailURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(hasRoundedImage ? 8 : 0) // ✅ Conditional rounding
                    
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

