import SwiftUI
import SDWebImageSwiftUI
import UIKit
import WebKit

private struct ArticleStarRatingView: View {
    let rating: Int
    let maxRating: Int
    @Environment(\.colorScheme) private var colorScheme

    init(rating: Int, maxRating: Int = 6) {
        self.rating = max(0, min(rating, maxRating))
        self.maxRating = maxRating
    }

    private var filledColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.92)
    }

    private var emptyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(index <= rating ? filledColor : emptyColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) ud af \(maxRating) stjerner")
    }
}

/// Review disclaimer shown when the CMS "Presseakkreditering" switch is on.
private struct PressAccreditationDisclaimer: View {
    var body: some View {
        (
            Text("Disclaimer: ").font(.system(size: 14, weight: .semibold))
            + Text("Apropos Magazine har modtaget adgang eller eksemplar til anmeldelse. Som altid deler vi vores egne indtryk - uden filter.")
                .font(.system(size: 14, weight: .regular))
        )
        .foregroundColor(.secondary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - TrailerWebView to display YouTube or raw iframe HTML
struct TrailerWebView: UIViewRepresentable {
    let trailer: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = true
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard !trailer.isEmpty else { return }
        let trimmed = trailer.trimmingCharacters(in: .whitespacesAndNewlines)

        if context.coordinator.lastLoadedTrailer != trimmed {
            context.coordinator.lastLoadedTrailer = trimmed
            loadTrailer(uiView: uiView, trailer: trimmed)
        }
    }
    
    private func loadTrailer(uiView: WKWebView, trailer: String) {
        if let videoID = candidateVideoID(from: trailer) {
            let html = htmlEmbed(for: videoID)
            uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            return
        }
        
        if trailer.lowercased().contains("<iframe")
            || trailer.lowercased().contains("<video")
            || trailer.lowercased().contains("<embed") {
            let html = sanitizedHTML(from: trailer)
            uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            return
        }
        
        if let url = URL(string: trailer),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedTrailer: String = ""
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Always call decisionHandler - this is required by WKNavigationDelegate
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            // WebKit uses about:blank internally when loading inline HTML.
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            
            // Allow YouTube domains
            if let host = url.host,
               host.contains("youtube.com")
                    || host.contains("youtube-nocookie.com")
                    || host.contains("ytimg.com")
                    || host.contains("google.com") {
                decisionHandler(.allow)
                return
            }
            
            // Default: allow all other navigation
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let host = navigationResponse.response.url?.host,
               host.contains("youtube.com")
                    || host.contains("youtube-nocookie.com")
                    || host.contains("ytimg.com") {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.allow)
        }
    }
    
    // MARK: - Helpers
    
    private func candidateVideoID(from raw: String) -> String? {
        if raw.contains("embedly.com"),
           let url = extractYouTubeURLFromEmbedly(raw) {
            let id = extractYouTubeVideoID(from: url)
            if !id.isEmpty {
                return id
            }
        }
        let id = extractYouTubeVideoID(from: raw)
        if !id.isEmpty {
            return id
        }
        return nil
    }
    
    private func sanitizedHTML(from raw: String) -> String {
        var sanitized = raw
            .replacingOccurrences(of: "src=\"//", with: "src=\"https://")
            .replacingOccurrences(of: "src='//", with: "src='https://")
        
        if sanitized.contains("<iframe") && !sanitized.contains("allow=") {
            sanitized = sanitized.replacingOccurrences(
                of: "<iframe",
                with: "<iframe allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\""
            )
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no' />
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
                iframe, video { width: 100%; height: 100%; border: 0; border-radius: 12px; }
            </style>
        </head>
        <body>\(sanitized)</body>
        </html>
        """
    }
    
    private func htmlEmbed(for videoID: String) -> String {
        let embedURL = "https://www.youtube.com/embed/\(videoID)?rel=0&modestbranding=1&playsinline=1"
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no' />
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
                iframe { width: 100%; height: 100%; border: 0; border-radius: 12px; }
            </style>
        </head>
        <body>
            <iframe src="\(embedURL)"
                    frameborder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowfullscreen>
            </iframe>
        </body>
        </html>
        """
    }
    
    private func extractYouTubeURLFromEmbedly(_ embedlyHTML: String) -> String? {
        if let range = embedlyHTML.range(of: "src=\"//cdn.embedly.com/widgets/media.html?src=") {
            let afterSrc = String(embedlyHTML[range.upperBound...])
            if let endRange = afterSrc.range(of: "\"") {
                let encodedURL = String(afterSrc[..<endRange.lowerBound])
                if let decodedURL = encodedURL.removingPercentEncoding {
                    return decodedURL.hasPrefix("//") ? "https:" + decodedURL : decodedURL
                }
            }
        }
        
        if let youtubeRange = embedlyHTML.range(of: "youtube.com") {
            let beforeYoutube = String(embedlyHTML[..<youtubeRange.lowerBound])
            let afterYoutube = String(embedlyHTML[youtubeRange.lowerBound...])
            if let srcRange = beforeYoutube.range(of: "src=", options: .backwards) {
                let urlStart = String(beforeYoutube[srcRange.upperBound...])
                let fullURL = urlStart + afterYoutube
                if let endRange = fullURL.range(of: "\"") {
                    let youtubeURL = String(fullURL[..<endRange.lowerBound])
                    if let decodedURL = youtubeURL.removingPercentEncoding {
                        return decodedURL.hasPrefix("//") ? "https:" + decodedURL : decodedURL
                    }
                }
            }
        }
        return nil
    }
    
    private func extractYouTubeVideoID(from url: String) -> String {
        guard !url.isEmpty else { return "" }
        
        if url.contains("youtu.be/") {
            let components = url.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                return components[1].components(separatedBy: "?")[0]
            }
        }
        
        if url.contains("youtube.com/watch") {
            let components = URLComponents(string: url)
            return components?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
        }
        
        if url.contains("youtube.com/embed/") {
            let parts = url.components(separatedBy: "youtube.com/embed/")
            guard parts.count > 1 else { return "" }
            let remainder = parts[1]
            let videoID = remainder.components(separatedBy: CharacterSet(charactersIn: "?&")).first ?? ""
            return videoID
        }
        
        return ""
    }
}
struct ArticleDetailView: View {
    var article: Article
    var analyticsSource: AnalyticsService.ArticleOpenSource = .feed
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    // Temporarily removed RecommendationEngine to fix crash
    // @EnvironmentObject private var recommendationEngine: RecommendationEngine
    
    var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
    var relatedArticles: [Article] = []
    @EnvironmentObject var viewModel: ArticleViewModel
    private let podcastPlayerManager = PodcastPlayerManager.shared
    // @Environment(\.navigateToHome) private var navigateToHome
    @State private var htmlHeight: CGFloat = 100
    @State private var didLoadFullArticle = false
    @State private var shouldShowRelatedArticles = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isGeneratingShareCard = false
    @State private var intelligentRelatedArticles: [Article] = []
    @State private var displayCategories: [String] = []
    @State private var displaySection: String = ""
    @State private var headerImageFailed = false
    @State private var showGlassTopBar = false
    @State private var lastSavedScrollProgress: Double = -1
    @State private var showPaywall = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    let optionId = "b9a5ef043f1f58db54c41ed6fe3e746e"

    private var progress: CGFloat {
        showGlassTopBar ? 1 : 0
    }

    private var bestRelatedArticles: [Article] {
        Array(intelligentRelatedArticles.prefix(3))
    }

    private var bottomScrollPadding: CGFloat {
        PodcastMiniPlayerLayout.articleBottomPadding(
            isPlayerVisible: podcastPlayerManager.hasActiveEpisode
        )
    }

    private var latestPodcastEpisode: PodcastEpisode? {
        PodcastRepository.shared.episode(for: resolvedArticle)
    }
    
    private var resolvedArticle: Article {
        viewModel.articles.first(where: { $0.id == article.id }) ?? article
    }

    private var canReadFullArticle: Bool {
        ArticleAccessPolicy.canReadFullContent(
            article: resolvedArticle,
            isSubscribed: subscriptionManager.isSubscribed
        )
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // ✅ GLAS-TOPBAR (indhold placeret inden i glass effekt)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(progress)
                    .frame(height: 104)
                    .ignoresSafeArea(edges: .top)
                
                // 👇 Topbar-indhold placeret INDEN i glass effekt
                VStack(spacing: 0) {
                    // Safe area spacer
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 44)
                    
                    HStack {
                        // 👇 Venstre side - faste bredde for at matche højre side
                        HStack {
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18)) // 2 pixels mindre ikon
                                    .foregroundColor(textColor)
                                    .frame(width: 32, height: 32) // Mindre størrelse
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Spacer() // Fylder resten af venstre side
                        }
                        .frame(width: 72) // 32 + 8 + 32 = samme bredde som højre side

                        Spacer()

                        // 👇 Centreret logo
                        Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 30)
                            .opacity(0.9)

                        Spacer()

                        // 👇 Højre knapper - samme faste størrelse
                        HStack(spacing: 8) {
                            Button(action: {
                                shareArticle()
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18)) // 2 pixels mindre ikon
                                    .foregroundColor(textColor)
                                    .frame(width: 32, height: 32) // Mindre størrelse
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .disabled(isGeneratingShareCard)

                            SafeFavoriteButton(
                                article: article,
                                onFavorite: { _ in
                                    // Optional onFavorite action can be added here
                                }
                            )
                        }
                        .frame(width: 72) // 32 + 8 + 32 = fast bredde
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
                        .onChange(of: geo.frame(in: .named("scroll")).minY) { _, newValue in
                            let shouldShow = newValue < -16
                            if shouldShow != showGlassTopBar {
                                withAnimation(AppMotion.easeOut(duration: 0.16, reduceMotion: reduceMotion)) {
                                    showGlassTopBar = shouldShow
                                }
                            }

                            let progress = min(max(-newValue / 1800, 0), 1)
                            let quantizedProgress = (progress * 20).rounded() / 20
                            guard abs(quantizedProgress - lastSavedScrollProgress) >= 0.05 else { return }
                            lastSavedScrollProgress = quantizedProgress
                            iCloudSyncService.shared.saveProgress(quantizedProgress, for: resolvedArticle.id)
                            AnalyticsService.shared.trackArticleReadIfNeeded(resolvedArticle, scrollProgress: quantizedProgress)
                        }
                }
                .frame(height: 0.1)
                
                VStack(alignment: .leading, spacing: 16) {
                    // 👇 Skubber alt ned under topbaren
                    Spacer().frame(height: 50)
                    
                    // Top tag shows the CMS Section (e.g. "Serier & Film")
                    Text(displaySection.isEmpty ? displayCategories.joined(separator: " | ") : displaySection)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Safety check for article name
                    if let articleName = resolvedArticle.name, !articleName.isEmpty {
                        Text(articleName)
                            .font(.system(size: 34, weight: .bold))
                            .lineSpacing(4) // Reduced from 8 to 4 for even tighter spacing
                            .foregroundColor(textColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                    }
                    
                    if let subtitle = resolvedArticle.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(textColor)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Only show stars if there's a rating
                    if let rating = resolvedArticle.stjerne, rating > 0 {
                        ArticleStarRatingView(rating: rating, maxRating: 6)
                        .padding(.top, -5)
                    }

                    // Updated category tags section - centered and using real category names
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            // Show author if available
                            if let authorName = resolvedArticle.author?.name, !authorName.isEmpty {
                                Text(authorName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(height: 22)
                                    .padding(.horizontal, 10)
                                    .background(Color(hex: "#262626"))
                                    .cornerRadius(8)
                                    .textCase(.uppercase)
                            }

                            // Display real category names from the article
                            ForEach(displayCategories, id: \.self) { category in
                                if !category.isEmpty {
                                    Text(category.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .frame(height: 22)
                                        .padding(.horizontal, 10)
                                        .background(Color(hex: "#262626"))
                                        .cornerRadius(8)
                                        .textCase(.uppercase)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center) // Center the entire HStack
                    }
                    .padding(.top, 5)

                    if let episode = latestPodcastEpisode {
                        HStack {
                            Spacer()
                            Button {
                                openPodcast(for: episode)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "headphones")
                                        .font(.caption.weight(.semibold))
                                    Text(PodcastPlaybackProgressStore.articlePlayButtonTitle(for: episode.id))
                                        .font(.caption.weight(.semibold))
                                        .textCase(.uppercase)
                                }
                                .foregroundColor(.white)
                                .frame(height: 28)
                                .padding(.horizontal, 12)
                                .background(Color(hex: "#262626"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                                )
                                .cornerRadius(10)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    // Safety check for thumbnail URL
                    var mutableArticle = resolvedArticle
                    let thumbnailURL = mutableArticle.thumbnailURL
                    ZStack {
                        ArticleImagePlaceholder(
                            mode: headerImageFailed ? .offline : .loading,
                            cornerRadius: 14
                        )

                        if let remoteURL = URL(string: thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                           !thumbnailURL.isEmpty,
                           !headerImageFailed,
                           let url = resolvedArticle.offlineDisplayImageURL(for: remoteURL) {
                            WebImage(url: url, options: [.retryFailed, .highPriority, .scaleDownLargeImages, .continueInBackground])
                                .onFailure { _ in
                                    headerImageFailed = true
                                }
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)

                    if let imageCaption = resolvedArticle.intro, !imageCaption.isEmpty {
                        Text(imageCaption)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(textColor)
                            .kerning(-0.43)
                            .lineSpacing(6)
                            .padding(.horizontal, 16)
                            .multilineTextAlignment(.leading)
                    }

                    if resolvedArticle.pressAccreditation {
                        PressAccreditationDisclaimer()
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }

                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.4),
                            Color.gray.opacity(0.4),
                            Color.gray.opacity(0.4)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 2)
                    .cornerRadius(1)
                    .padding(.top, 20)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    
                    if let content = resolvedArticle.content, !content.isEmpty {
                        if canReadFullArticle {
                            VStack(spacing: 0) {
                                HTMLTextView(html: content, articleId: resolvedArticle.id, dynamicHeight: $htmlHeight)
                                    .frame(height: max(htmlHeight, 240))
                                    .padding(.horizontal, 16)

                                if let trailer = resolvedArticle.trailer, !trailer.isEmpty {
                                    LazyVStack {
                                        TrailerWebView(trailer: trailer)
                                            .frame(height: 220)
                                            .cornerRadius(12)
                                            .clipped()
                                    }
                                    .padding(.top, 10)
                                    .padding(.horizontal, 16)
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 1)
                                        .padding(.top, 10)
                                        .padding(.horizontal, 16)
                                }

                                if let authorID = resolvedArticle.authorID, !authorID.isEmpty {
                                    AuthorCardView(authorID: authorID)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 4)
                                }
                            }
                        } else {
                            SubscriptionPaywallCard {
                                showPaywall = true
                            }
                        }
                    }

                    if shouldShowRelatedArticles && !bestRelatedArticles.isEmpty {
                        Text("Læs også")
                            .foregroundColor(Color("SerialNumberColorBOX"))
                            .font(.system(size: 25, weight: .bold))
                            .padding(.leading, 16)
                            .padding(.bottom, 0)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(bestRelatedArticles, id: \.id) { article in
                                    RelatedArticleCard(article: article)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 0)
                    }

                    Color.clear
                        .frame(height: bottomScrollPadding)
                    
                }
            }
            .coordinateSpace(name: "scroll")
            .allowsHitTesting(true)
        }
        .navigationBarBackButtonHidden(true)
        .enhancedSwipeToGoBack(isEnabled: true)
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ActivityView(activityItems: shareItems)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task(id: article.id) {
            shouldShowRelatedArticles = false
            htmlHeight = 240
            showGlassTopBar = false
            lastSavedScrollProgress = -1
            
            let resolvedCategories = viewModel.categories(for: resolvedArticle)
            displayCategories = resolvedCategories.isEmpty ? ["Generelt"] : resolvedCategories
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""

            iCloudSyncService.shared.markAsRead(articleId: article.id)
            CacheManager.shared.preloadArticleDetailImages(for: resolvedArticle)
            AnalyticsService.shared.trackArticleOpen(resolvedArticle, source: analyticsSource)
            
            if !didLoadFullArticle {
                didLoadFullArticle = true
                viewModel.loadFullArticle(with: article.id)
            }
            
            try? await Task.sleep(nanoseconds: 350_000_000)
            generateIntelligentRelatedArticles()
            shouldShowRelatedArticles = true
        }
        .onChange(of: viewModel.topics.count) { _, _ in
            let refreshedCategories = viewModel.categories(for: resolvedArticle)
            displayCategories = refreshedCategories.isEmpty ? ["Generelt"] : refreshedCategories
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""
        }
        .onChange(of: viewModel.sections.count) { _, _ in
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""
        }
        .onChange(of: viewModel.articles.count) { _, _ in
            generateIntelligentRelatedArticles()
        }
    }
}

// MARK: - Helper Functions
extension ArticleDetailView {
    private func shareArticle() {
        guard !isGeneratingShareCard else { return }
        isGeneratingShareCard = true
        HapticManager.shared.lightImpact()

        Task {
            let article = resolvedArticle
            let categories = viewModel.categories(for: article)
            let image = await ShareCardGenerator.generate(article: article)

            await MainActor.run {
                shareItems = ArticleShareComposer.shareItems(
                    for: article,
                    categories: categories,
                    image: image
                )
                isGeneratingShareCard = false
                showShareSheet = true
            }
        }
    }

    private func openPodcast(for episode: PodcastEpisode) {
        podcastPlayerManager.play(episode: episode, articleId: resolvedArticle.id)
    }
    
    // Generate intelligent related articles using RecommendationEngine
    private func generateIntelligentRelatedArticles() {
        // Safety check: ensure we have articles to work with
        guard !viewModel.articles.isEmpty else {
            intelligentRelatedArticles = []
            return
        }
        
        // Temporarily use only category-based filtering until RecommendationEngine is fixed
        let relatedArticles = viewModel.articles
            .filter { $0.id != resolvedArticle.id }
            .filter { relatedArticle in
                if let articleTopic = resolvedArticle.topicID,
                   let relatedTopic = relatedArticle.topicID,
                   articleTopic == relatedTopic {
                    return true
                }
                if let articleAuthor = resolvedArticle.authorID,
                   let relatedAuthor = relatedArticle.authorID,
                   articleAuthor == relatedAuthor {
                    return true
                }
                return false
            }
            .prefix(3)
        
        intelligentRelatedArticles = Array(relatedArticles)
    }
}

// MARK: - Related Article Card
struct RelatedArticleCard: View {
    let article: Article
    @Environment(\.colorScheme) var colorScheme
    @State private var imageFailed = false
    
    var body: some View {
        NavigationLink(value: article) {
            VStack(alignment: .leading, spacing: 8) {
                relatedImage
                
                Text(article.name ?? "")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 200, height: 40, alignment: .topLeading)
            }
            .frame(width: 200, alignment: .topLeading)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var relatedImage: some View {
        var mutableArticle = article
        let thumbnailURL = mutableArticle.thumbnailURL

        ZStack {
            ArticleImagePlaceholder(mode: imageFailed ? .offline : .loading, cornerRadius: 8)

            if let imageURL = URL(string: thumbnailURL), !thumbnailURL.isEmpty, !imageFailed {
                WebImage(url: imageURL, options: [.retryFailed, .scaleDownLargeImages])
                    .onFailure { _ in
                        imageFailed = true
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 200, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: article.id) { _, _ in
            imageFailed = false
        }
    }
}

// Preview Provider
struct ArticleDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let html = """
        <div class=\\"image-container\\">
          <img src=\\"https://images.unsplash.com/photo-1575936123452-b67c3203c357?q=80&w=2070\\" alt=\\"Concert\\" class=\\"background-image\\" />
          <div class=\\"overlay\\"></div>
          <div class=\\"text-box\\">
            <p>
              Men her er entréen stadig… Publikum lyser med lightere og synger med om de gamle ballader, vejer og hopper med som om, de havde billetter til Bring Me The Horizon i Royal Arena. For Bullet har stadig fans. Mange af dem. Og de ved, hvordan man spiller deres rolle, også selvom det er med samme overbevisning som en mand i et Batman-kostume på Strøget.
            </p>
          </div>
        </div>

        <style>
        .image-container {
          position: relative;
          width: 100%;
          height: auto;
          max-width: 600px;
          overflow: hidden;
        }
        .background-image {
          width: 100%;
          height: auto;
          display: block;
        }
        .overlay {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background: linear-gradient(to bottom, rgba(0, 0, 0, 0.5), rgba(0, 0, 0, 0.7));
          z-index: 1;
        }
        .text-box {
          position: absolute;
          bottom: 0;
          padding: 16px;
          color: white;
          color: white;
          z-index: 2;
          backdrop-filter: blur(10px);
          background-color: rgba(0, 0, 0, 0.4);
          width: 100%;
          box-sizing: border-box;
          font-family: sans-serif;
        }
        </style>
        """

        let sampleArticle = Article(
            id: "1",
            name: "Eksempelartikel med billede og overlay",
            slug: "eksempel",
            content: html,
            trailer: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            intro: "En kort og fængende introduktion til denne fantastiske artikel.",
            stjerne: 4,
            topicID: "teknologi",
            topicsIDs: ["SwiftUI", "iOS", "Design"],
            authorID: "AI Assistent",
            thumbURL: nil,
            coverURL: nil,
            location: "København",
            subtitle: nil,
            isDraft: nil
        )

        return NavigationView {
            ArticleDetailView(article: sampleArticle, relatedArticles: ArticleViewModel.preview.articles)
        }
        .environmentObject(ArticleViewModel.preview)
    }
}

// UIKit share sheet wrapper with enhanced configuration
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Configure the activity view controller
        activityViewController.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks,
            .markupAsPDF
        ]
        
        // Set the subject for email sharing
        if activityItems.first is String {
            activityViewController.setValue("Ny artikel fra Apropos Magazine", forKey: "subject")
        }
        
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
