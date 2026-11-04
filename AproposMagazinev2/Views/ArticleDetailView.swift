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

/// Single pill-shaped category/author tag used under the article header.
struct ArticleTagChip: View {
    let text: String
    #if DEBUG && targetEnvironment(simulator)
    var onTextFrame: ((CGRect) -> Void)? = nil
    #endif

    var body: some View {
        measuredText
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .padding(.horizontal, 10)
            .background(Color(hex: "#262626"))
            .cornerRadius(8)
    }

    @ViewBuilder private var measuredText: some View {
        #if DEBUG && targetEnvironment(simulator)
        styledText.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            onTextFrame?($0)
        }
        #else
        styledText
        #endif
    }

    private var styledText: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One production header group: the status keeps the same slot and view
/// lifetime when checking, stored, or retrying. Only its proposed width changes.
struct ArticleHeaderTagGroup<OfflineStatus: View>: View {
    @Environment(\.locale) private var interfaceLocale
    let authorName: String?
    let categories: [String]
    let openAuthor: () -> Void
    private let offlineStatus: OfflineStatus
    #if DEBUG && targetEnvironment(simulator)
    private var onFrame: ((String, CGRect) -> Void)? = nil
    #endif

    init(authorName: String?, categories: [String], openAuthor: @escaping () -> Void,
         @ViewBuilder offlineStatus: () -> OfflineStatus) {
        self.authorName = authorName; self.categories = categories
        self.openAuthor = openAuthor; self.offlineStatus = offlineStatus()
    }

    var body: some View {
        measured("container") {
            ArticleTagFlowLayout(spacing: 8, lineSpacing: 8, alignment: .center) {
                if let authorName, !authorName.isEmpty {
                    Button(action: openAuthor) { chip(authorName, key: "author") }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("article.header.author")
                }
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    if !category.isEmpty {
                        chip(AppLocalization.taxonomy(category, language: AppLocalization.language(for: interfaceLocale)),
                             key: "category.\(index)")
                    }
                }
                measured("status") { offlineStatus }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private func chip(_ text: String, key: String) -> some View {
        measured("chip." + key) {
            #if DEBUG && targetEnvironment(simulator)
            ArticleTagChip(text: text, onTextFrame: { onFrame?("text." + key, $0) })
            #else
            ArticleTagChip(text: text)
            #endif
        }
    }

    @ViewBuilder private func measured<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame?(key, $0) }
        #else
        content()
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    func measuringFrames(_ callback: @escaping (String, CGRect) -> Void) -> Self {
        var result = self; result.onFrame = callback; return result
    }
    #endif
}

/// Flow layout that places tag chips left-to-right and wraps onto new lines when
/// they no longer fit, keeping each line centered within the available width.
struct ArticleTagFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let width = proposal.width ?? (rows.map { $0.width }.max() ?? 0)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: item.proposal
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
        let proposal: ProposedViewSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        // A long chip can use a full row. Measure and place with the same width
        // constraint so wrapping cannot change between the two layout passes.
        let proposal = ProposedViewSize(width: maxWidth.isFinite ? max(0, maxWidth) : nil, height: nil)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(proposal)
            // Absent online status is not a chip and must not add a row or gap.
            guard size.width > 0 || size.height > 0 else { continue }
            let item = Item(index: index, size: size, proposal: proposal)
            let projectedWidth = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.items.isEmpty && projectedWidth > maxWidth {
                rows.append(current)
                current = Row(items: [item], width: size.width, height: size.height)
            } else {
                current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
                current.items.append(item)
            }
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
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

    /// Release the (heavy) WKWebView and stop any trailer playback when the article
    /// closes, so browsing many articles doesn't accumulate web content processes.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
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
    @Environment(\.locale) private var interfaceLocale
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    
    var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
    var relatedArticles: [Article] = []
    @EnvironmentObject var viewModel: ArticleViewModel
    private let podcastPlayerManager = PodcastPlayerManager.shared
    @ObservedObject private var podcastProgress = PodcastProgressRuntime.store
    @ObservedObject private var readingHistory = ReadingHistoryRuntime.model
    // @Environment(\.navigateToHome) private var navigateToHome
    @State private var readingMotion = ArticleReadingMotionController()
    @State private var readerResume = ReaderResumeRuntime.makeController()
    @State private var historyBinding = ReaderHistoryBinding(model: ReadingHistoryRuntime.model,
        markRead: { ReadingHistoryRuntime.shared.markRead($0) })
    @State private var historySession: ReaderHistoryBinding.Session?
    @State private var readerIsVisible = false
    @State private var availabilitySelection: ArticleViewModel.AvailabilitySelection?
    @State private var htmlHeight: CGFloat = 100
    @StateObject private var articleLoadState = ArticleHTMLLoadState()
    @State private var shouldShowRelatedArticles = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isGeneratingShareCard = false
    @State private var intelligentRelatedArticles: [Article] = []
    @State private var displayCategories: [String] = []
    @State private var displaySection: String = ""
    @State private var showGlassTopBar = false
    @State private var showPaywall = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var offlineManager = OfflineManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @ViewBuilder private var offlineBodyStatus: some View {
        if let ticket = offlineManager.captureAccess(articleID: resolvedArticle.id),
           ticket.contentRevision == resolvedArticle.bodyRevision,
           let state = offlineManager.bodyState(ticket: ticket) {
            let requiresAudio = ArticleAudioLanguagePolicy.requiresAudio(for: resolvedArticle)
            let audioState = requiresAudio ? offlineManager.audioState(ticket: ticket) : nil
            let progress = requiresAudio ? offlineManager.audioProgress(ticket: ticket) : nil
            if offlineManager.isCurrentAccess(ticket) {
                ArticleOfflineBodyStatusView(ticket: ticket, state: state, prepare: { original in
                    _ = offlineManager.prepareBodyStatus(ticket: original, force: true)
                }, retry: { viewModel.retryOfflineContent(ticket: ticket) },
                    audioState: audioState, audioProgress: progress, requiresAudio: requiresAudio)
            }
        } else if !offlineManager.isOnline {
            ArticleOfflineStatusControl(state: .notDownloaded)
        }
    }

    let optionId = "b9a5ef043f1f58db54c41ed6fe3e746e"

    private var progress: CGFloat {
        showGlassTopBar ? 1 : 0
    }

    private var readerActivationIdentity: String {
        "\(article.id)|\(readingHistory.snapshot.generation.uuidString)|\(readerIsVisible)"
    }

    private var bestRelatedArticles: [Article] {
        Array(intelligentRelatedArticles.prefix(3))
    }

    private var bottomScrollPadding: CGFloat {
        PodcastMiniPlayerLayout.articleBottomPadding(
            isPlayerVisible: podcastPlayerManager.hasActiveEpisode, size: dynamicTypeSize
        )
    }

    private func listenEpisode(in repository: PodcastRepository) -> PodcastEpisode? {
        let currentArticle = resolvedArticle
        guard ArticleAudioLanguagePolicy.requiresAudio(for: currentArticle) else { return nil }
        return repository.episode(for: currentArticle)
    }

    private func canListen(to episode: PodcastEpisode) -> Bool {
        OfflineAvailability.canOfferListenButton(for: episode, articleID: resolvedArticle.id,
            isOnline: offlineManager.isOnline)
    }

    @ObservedObject private var availability = ArticleAvailabilityService.model

    private var resolvedArticle: Article {
        // Prefer the freshly fetched full article (guaranteed to carry the body
        // content + author). The feed list can be stale or omit a brand-new
        // article entirely — in which case updateArticleInAllArrays never inserts
        // it — so relying on it alone leaves the body blank ("et stort felt").
        if let full = viewModel.fullArticle, full.id == article.id,
           let content = full.content, !content.isEmpty {
            return availability.sanitized(full) ?? full.strippingBodyContent()
        }
        let candidate = viewModel.visibleArticles.first(where: { $0.id == article.id }) ?? article
        return availability.sanitized(candidate) ?? candidate.strippingBodyContent()
    }

    private var detailRequestIdentity: ArticleDetailRequestIdentity {
        ArticleDetailRequestIdentity(viewModel.visibleArticles.first(where: { $0.id == article.id }) ?? article,
                                     availabilityRevision: availability.approvedRevision(for: article.id))
    }

    private var canReadFullArticle: Bool {
        ArticleAccessPolicy.canReadFullContent(
            article: resolvedArticle,
            isSubscribed: subscriptionManager.isSubscribed
        )
    }
    
    var body: some View {
        ZStack {
            ArticleAvailabilityGate(articleID: article.id, availability: availability,
                                    retry: { availabilitySelection = viewModel.observeArticleAvailability(for: article.id) },
                                    back: { presentationMode.wrappedValue.dismiss() }) {
                readerContent
            }
        }
        .articleNativeBackNavigation()
        .onAppear {
            readerIsVisible = true
            availabilitySelection = viewModel.observeArticleAvailability(for: article.id)
        }
        .onChange(of: article.id) { _, _ in
            guard readerIsVisible else { return }
            let previous = availabilitySelection
            availabilitySelection = nil
            if let previous { viewModel.stopObservingArticleAvailability(previous) }
            availabilitySelection = viewModel.observeArticleAvailability(for: article.id)
        }
        .onDisappear {
            readerIsVisible = false
            if let historySession { historyBinding.endSession(historySession) }
            historySession = nil
            let previous = availabilitySelection
            availabilitySelection = nil
            if let previous { viewModel.stopObservingArticleAvailability(previous) }
        }
    }

    private var readerContent: some View {
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
                                article: resolvedArticle,
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
            .overlay(alignment: .bottom) {
                ArticleReadingProgressLine(controller: readingMotion)
                    .frame(height: 1.5)
            }
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


                        }
                }
                .frame(height: 0.1)
                .background(ArticleReaderScrollProbe(controller: readingMotion))
                
                VStack(alignment: .leading, spacing: 16) {
                    // 👇 Skubber alt ned under topbaren
                    Spacer().frame(height: 50)
                    
                    // Top tag shows the CMS Section (e.g. "Serier & Film")
                    LocalizedArticleTaxonomy(displaySection.isEmpty ? displayCategories : [displaySection])
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Safety check for article name
                    if let articleName = resolvedArticle.name, !articleName.isEmpty {
                        ArticleHeaderTitle(text: articleName, textColor: textColor)
                    }
                    
                    if let subtitle = resolvedArticle.subtitle, !subtitle.isEmpty {
                        ArticleHeaderSubtitle(text: subtitle, textColor: textColor)
                    }
                    
                    // Only show stars if there's a rating
                    if let rating = resolvedArticle.stjerne, rating > 0 {
                        ArticleStarRatingView(rating: rating, maxRating: 6)
                        .padding(.top, -5)
                    }

                    ArticleHeaderTagGroup(authorName: resolvedArticle.author?.name,
                        categories: displayCategories, openAuthor: openAuthorPageIfPossible) {
                        offlineBodyStatus
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 5)

                    ArticleListenHeroSection(catalog: PodcastRepository.shared,
                        selection: { listenEpisode(in: $0) },
                        title: { canListen(to: $0) ? podcastProgress.snapshot.articlePlayButtonTitle(for: $0.id) : "Lyd kræver internet" },
                        play: { openPodcast(for: $0) }, isEnabled: { canListen(to: $0) }) {
                        // Safety check for thumbnail URL
                        var mutableArticle = resolvedArticle
                        let thumbnailURL = mutableArticle.thumbnailURL
                        PreparedArticleImage(articleID: resolvedArticle.id, revision: resolvedArticle.bodyRevision,
                            remoteURL: URL(string: thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines)), style: .cover)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // Photo credit for the hero image (CMS "Foto Credit"). Same small
                    // gray caption style as inline body-image credits, but left-aligned.
                    if let credit = resolvedArticle.fotoCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !credit.isEmpty {
                        Text(credit)
                            .font(.system(size: 12))
                            .foregroundColor(colorScheme == .dark ? Color(white: 0.67) : Color(white: 0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, -8)
                    }

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
                    
                    ReadingHistoryNotice(model: readingHistory)
                        .padding(.horizontal, 16)

                    if let content = resolvedArticle.content, !content.isEmpty {
                        if canReadFullArticle {
                            VStack(spacing: 0) {
                                ReaderResumeNotice(controller: readerResume, motion: readingMotion)
                                    .padding(.horizontal, 16)
                                ArticleHTMLBody(html: content, articleId: resolvedArticle.id, articleRevision: resolvedArticle.bodyRevision, dynamicHeight: $htmlHeight, loadState: articleLoadState,
                                             readingMotion: readingMotion, historyBinding: historyBinding, historySession: historySession,
                                             resumeController: readerResume, resumeOwner: readingHistory.context.namespace?.recordBinding)

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
                    } else {
                        ArticleBodyLoadingState(isLoading: viewModel.loadingArticles.contains(article.id),
                                                isOffline: !offlineManager.isOnline) {
                            viewModel.loadFullArticle(with: article.id, initialArticle: article)
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
            .readerScrollInput(controller: readingMotion)
            .allowsHitTesting(true)
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ActivityView(activityItems: shareItems)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task(id: readerActivationIdentity) {
            guard readerIsVisible else { return }
            let activation = readerActivationIdentity
            if let historySession { historyBinding.endSession(historySession) }
            historySession = nil
            readerResume.invalidate()
            // A new owner gets a fresh document/motion measurement. Existing
            // viewport callbacks retain their old session and are rejected.
            readingMotion = ArticleReadingMotionController()
            shouldShowRelatedArticles = false
            htmlHeight = 240
            showGlassTopBar = false
            
            let resolvedCategories = viewModel.categories(for: resolvedArticle)
            displayCategories = resolvedCategories.isEmpty ? ["Generelt"] : resolvedCategories
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""

            let originalArticle = resolvedArticle
            let originalSource = analyticsSource
            historySession = historyBinding.beginArticle(articleID: originalArticle.id, onOpen: {
                AnalyticsService.shared.trackArticleOpen(originalArticle, source: originalSource)
            }, onProgress: { value in
                AnalyticsService.shared.trackArticleReadIfNeeded(originalArticle, scrollProgress: value)
            })
            guard activation == readerActivationIdentity, readerIsVisible else { return }
            CacheManager.shared.preloadArticleDetailImages(for: originalArticle)
            
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            guard !Task.isCancelled, activation == readerActivationIdentity, readerIsVisible else { return }
            generateIntelligentRelatedArticles()
            shouldShowRelatedArticles = true
        }
        .task(id: detailRequestIdentity) {
            viewModel.loadFullArticle(with: article.id, initialArticle: article)
        }
        .onDisappear {
            if let historySession { historyBinding.endSession(historySession) }
            historySession = nil
            viewModel.cancelFullArticleLoad(for: article.id)
        }
        .onChange(of: viewModel.topics.count) { _, _ in
            let refreshedCategories = viewModel.categories(for: resolvedArticle)
            displayCategories = refreshedCategories.isEmpty ? ["Generelt"] : refreshedCategories
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""
        }
        .onChange(of: viewModel.sections.count) { _, _ in
            displaySection = viewModel.sectionName(for: resolvedArticle) ?? ""
        }
        .onChange(of: viewModel.visibleArticles.count) { _, _ in
            generateIntelligentRelatedArticles()
        }
    }
}

// MARK: - Helper Functions
extension ArticleDetailView {
    private func shareArticle() {
        guard !isGeneratingShareCard else { return }
        isGeneratingShareCard = true
        let shareLanguage = AppLocalization.language(for: interfaceLocale)
        HapticManager.shared.lightImpact()

        Task {
            let article = resolvedArticle
            let categories = viewModel.categories(for: article)
            let image = await ShareCardGenerator.generate(article: article)

            await MainActor.run {
                shareItems = ArticleShareComposer.shareItems(
                    for: article,
                    categories: categories,
                    image: image,
                    language: shareLanguage
                )
                isGeneratingShareCard = false
                showShareSheet = true
            }
        }
    }

    private func openAuthorPageIfPossible() {
        if let author = resolvedArticle.author ?? viewModel.author(for: resolvedArticle) {
            navigationCoordinator.navigateToAuthor(author)
            return
        }
        guard let authorID = resolvedArticle.authorID, !authorID.isEmpty else { return }
        viewModel.fetchAuthor(by: authorID) { result in
            DispatchQueue.main.async {
                if case .success(let author) = result {
                    navigationCoordinator.navigateToAuthor(author)
                }
            }
        }
    }

    private func openPodcast(for episode: PodcastEpisode) {
        _ = podcastPlayerManager.play(episode: episode, articleId: resolvedArticle.id,
            routeIsCurrent: {
                canListen(to: episode) && listenEpisode(in: PodcastRepository.shared).map {
                    ArticleListenAction.sameRecording(episode, $0)
                } == true
            })
    }
    
    // Build related articles using lightweight category/topic matching.
    private func generateIntelligentRelatedArticles() {
        // Safety check: ensure we have articles to work with
        guard !viewModel.visibleArticles.isEmpty else {
            intelligentRelatedArticles = []
            return
        }
        
        let relatedArticles = viewModel.visibleArticles
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
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    @State private var imageFailed = false
    
    var body: some View {
        Button {
            navigationCoordinator.replaceTopArticle(with: article)
        } label: {
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
