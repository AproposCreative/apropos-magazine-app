import SwiftUI
import SDWebImageSwiftUI
import UIKit
import WebKit

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
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.configuration.allowsInlineMediaPlayback = true
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Safety check: ensure trailer is not empty
        guard !trailer.isEmpty else { return }
        
        let trimmed = trailer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If input looks like HTML embed, load directly
        if trimmed.lowercased().contains("<iframe") || trimmed.lowercased().contains("<video") || trimmed.lowercased().contains("<embed") {
            let html = """
            <html><head><meta name='viewport' content='initial-scale=1, maximum-scale=1, user-scalable=no' />
            <style>html,body{margin:0;padding:0;background:transparent} iframe,video{width:100%;height:100%;border:0;border-radius:12px}</style>
            </head><body>\(trimmed)</body></html>
            """
            uiView.loadHTMLString(html, baseURL: nil)
            return
        }

        if let url = URL(string: trimmed), (url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https") {
            if trimmed.contains("youtube.com") || trimmed.contains("youtu.be") {
                // Convert YouTube link to embed format
                let videoID = extractYouTubeVideoID(from: trimmed)
                if !videoID.isEmpty {
                    let embedURL = "https://www.youtube.com/embed/\(videoID)?rel=0&modestbranding=1"
                    let embedHTML = """
                    <html><head><meta name='viewport' content='initial-scale=1, maximum-scale=1, user-scalable=no' />
                    <style>html,body{margin:0;padding:0;background:transparent} iframe{width:100%;height:100%;border:0;border-radius:12px}</style>
                    </head><body><iframe src="\(embedURL)" frameborder="0" allowfullscreen></iframe></body></html>
                    """
                    uiView.loadHTMLString(embedHTML, baseURL: nil)
                }
            } else {
                // Load other URLs directly
                let request = URLRequest(url: url)
                uiView.load(request)
            }
        }
    }
    
    private func extractYouTubeVideoID(from url: String) -> String {
        // Safety check
        guard !url.isEmpty else { return "" }
        
        // Handle youtu.be URLs
        if url.contains("youtu.be/") {
            let components = url.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                let videoID = components[1].components(separatedBy: "?")[0]
                return videoID.isEmpty ? "" : videoID
            }
        }
        
        // Handle youtube.com URLs
        if url.contains("youtube.com/watch") {
            let components = URLComponents(string: url)
            let videoID = components?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
            return videoID.isEmpty ? "" : videoID
        }
        
        return ""
    }
}

struct ArticleDetailView: View {
    var article: Article
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
    // @Environment(\.navigateToHome) private var navigateToHome
    @State private var htmlHeight: CGFloat = 100
    @State private var didLoadFullArticle = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var scrollOffset: CGFloat = 0
    @State private var intelligentRelatedArticles: [Article] = []
    
    private var progress: CGFloat {
        // 0 → 1 når man har scrollet 5 pixels (meget responsiv effekt)
        let threshold: CGFloat = 5
        let p = min(max(scrollOffset / threshold, 0), 1)
        return p // direkte progress
    }
    let optionId = "b9a5ef043f1f58db54c41ed6fe3e746e"
    
    // Computed property for intelligent related articles
    private var bestRelatedArticles: [Article] {
        if !intelligentRelatedArticles.isEmpty {
            return Array(intelligentRelatedArticles.prefix(3))
        }
        // Fallback to simple category-based filtering
        guard !viewModel.articles.isEmpty else {
            return []
        }
        
        return viewModel.articles
            .filter { $0.id != article.id }
            .filter { relatedArticle in
                // Same category/topic
                if let articleTopic = article.topicID,
                   let relatedTopic = relatedArticle.topicID,
                   articleTopic == relatedTopic {
                    return true
                }
                // Same author
                if let articleAuthor = article.authorID,
                   let relatedAuthor = relatedArticle.authorID,
                   articleAuthor == relatedAuthor {
                    return true
                }
                // Similar topics
                let articleTopics = Set(article.topicsIDs ?? [])
                let relatedTopics = Set(relatedArticle.topicsIDs ?? [])
                if !articleTopics.intersection(relatedTopics).isEmpty {
                    return true
                }
                return false
            }
            .prefix(3)
            .map { $0 }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // ✅ GLAS-TOPBAR (indhold placeret inden i glass effekt)
            ZStack(alignment: .top) {
                // 👇 Glass overlay bag ved alt
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(progress) // 🔧 START MED 0% OG BLIVER 100% HURTIGT
                    .frame(height: 104) // 60 + 44 for safe area
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
                                showShareSheet = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18)) // 2 pixels mindre ikon
                                    .foregroundColor(textColor)
                                    .frame(width: 32, height: 32) // Mindre størrelse
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }

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
                            // newValue is negative when scrolling down, so we make it positive
                            scrollOffset = max(0, -newValue)
                            // Debug logging for scroll tracking
                            if scrollOffset > 0 && scrollOffset.truncatingRemainder(dividingBy: 10) < 1 {
                                print("📄 Article scroll offset: \(scrollOffset), Progress: \(progress)")
                            }
                        }
                }
                .frame(height: 0.1)
                
                VStack(alignment: .leading, spacing: 16) {
                    // 👇 Skubber alt ned under topbaren
                    Spacer().frame(height: 50)
                    
                    // ✅ All your content
                    Text("Musik | Festival")
                        .font(.custom("SFProText-Semibold", size: 15))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Safety check for article name
                    if let articleName = article.name, !articleName.isEmpty {
                        Text(articleName)
                            .font(.custom("SFProText-Bold", size: 34).bold())
                            .lineSpacing(4) // Reduced from 8 to 4 for even tighter spacing
                            .foregroundColor(textColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                    }
                    
                    if let subtitle = article.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.custom("SFProText-Medium", size: 18))
                            .foregroundColor(textColor)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Only show stars if there's a rating
                    if let rating = article.stjerne, rating > 0 {
                        HStack(spacing: 1.5) {
                            ForEach(0..<6) { index in
                                Image(index < rating ? "DarkStar" : "DimStar")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, -5)
                    }

                    // Updated category tags section - centered and using real category names
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            // Show author if available
                            if let authorName = article.author?.name, !authorName.isEmpty {
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
                            ForEach(viewModel.categories(for: article), id: \.self) { category in
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

                    Spacer()

                    // Safety check for thumbnail URL
                    var mutableArticle = article
                    let thumbnailURL = mutableArticle.thumbnailURL
                    if !thumbnailURL.isEmpty,
                       let url = URL(string: thumbnailURL),
                       UIApplication.shared.canOpenURL(url) {
                        WebImage(url: url)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 320)
                            .clipped()
                    }

                    if let imageCaption = article.intro, !imageCaption.isEmpty {
                        Text(imageCaption)
                            .font(.custom("SFProText-Medium", size: 20))
                            .foregroundColor(textColor)
                            .kerning(-0.43)
                            .padding(.horizontal)
                            .multilineTextAlignment(.leading)
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
                    
                    if let content = article.content, !content.isEmpty {
                        HTMLTextView(html: content, dynamicHeight: $htmlHeight)
                            .frame(height: max(htmlHeight, 1200)) // Øget minimum højde for at sikre scrolling
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                            
                            

                        // Trailer / Video after content if present
                        if let trailer = article.trailer, !trailer.isEmpty {
                            TrailerWebView(trailer: trailer)
                                .frame(height: 220)
                                .padding(.top, 10)
                                .padding(.horizontal, 16)

                            
                            // Pæn separator mellem trailer og tekst
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .padding(.top, 10)
                                .padding(.horizontal, 16)
                        }

                        //MARK: Author card detail view
                        if let authorID = article.authorID, !authorID.isEmpty {
                            AuthorCardView(authorID: authorID)
                                .padding()
                        }
                        
                        Text("Related Articles")
                            .foregroundColor(Color("SerialNumberColorBOX"))
                            .font(.custom("SFProDisplay-Bold", size: 25))
                            .padding(.leading, 16)
                            .padding(.bottom, 0)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(bestRelatedArticles, id: \.id) { article in
                                    RelatedArticleCard(article: article)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 0)

                        Spacer(minLength: 2)
                    }
                    
                }
            }
            .coordinateSpace(name: "scroll")
        }
        .navigationBarBackButtonHidden(true)
        .enhancedSwipeToGoBack(isEnabled: true)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                let shareText = createRichShareText()
                ActivityView(activityItems: [shareText, url])
            }
        }
        .onAppear {
            if !didLoadFullArticle {
                didLoadFullArticle = true
                viewModel.loadFullArticle(with: article.id)
            }
            
            // Set up share URL for the article
            if let articleURL = URL(string: "https://aproposmagazine.com/article/\(article.id)") {
                shareURL = articleURL
            }
            
            // Generate intelligent related articles
            DispatchQueue.main.async {
                generateIntelligentRelatedArticles()
            }
        }
    }
}

// MARK: - Helper Functions
extension ArticleDetailView {
    
    // Generate intelligent related articles using RecommendationEngine
    private func generateIntelligentRelatedArticles() {
        // Safety check: ensure we have articles to work with
        guard !viewModel.articles.isEmpty else {
            intelligentRelatedArticles = []
            return
        }
        
        // Temporarily use only category-based filtering until RecommendationEngine is fixed
        let relatedArticles = viewModel.articles
            .filter { $0.id != article.id }
            .filter { relatedArticle in
                // Same category/topic
                if let articleTopic = article.topicID,
                   let relatedTopic = relatedArticle.topicID,
                   articleTopic == relatedTopic {
                    return true
                }
                // Same author
                if let articleAuthor = article.authorID,
                   let relatedAuthor = relatedArticle.authorID,
                   articleAuthor == relatedAuthor {
                    return true
                }
                return false
            }
            .prefix(3)
        
        intelligentRelatedArticles = Array(relatedArticles)
    }
    
    // Helper function to create rich share text
    private func createRichShareText() -> String {
        var shareText = "📰 \(article.name ?? "Artikel")"
        
        // Add subtitle if available
        if let subtitle = article.subtitle {
            shareText += "\n\n\(subtitle)"
        }
        
        // Add intro if available (truncated for better preview)
        if let intro = article.intro {
            let truncatedIntro = intro.count > 150 ? String(intro.prefix(150)) + "..." : intro
            shareText += "\n\n\(truncatedIntro)"
        }
        
        // Add author if available
        if let authorName = article.author?.name {
            shareText += "\n\n👤 Af: \(authorName)"
        }
        
        // Add rating if available
        if let stjerne = article.stjerne {
            shareText += "\n\n⭐ \(stjerne)"
        }
        
        // Add categories
        let categories = viewModel.categories(for: article)
        if !categories.isEmpty {
            shareText += "\n\n🏷️ \(categories.joined(separator: ", "))"
        }
        
        // Add location if available
        if let location = article.location {
            shareText += "\n\n📍 \(location)"
        }
        
        // Add magazine branding
        shareText += "\n\n📖 Læs hele artiklen på Apropos Magazine"
        shareText += "\n\n#AproposMagazine #Kultur #Musik"
        
        return shareText
    }
}

// MARK: - Related Article Card
struct RelatedArticleCard: View {
    let article: Article
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationLink(value: article) {
            VStack(alignment: .leading, spacing: 8) {
                if let imageURL = article.thumbURL ?? article.coverURL {
                    WebImage(url: imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 120)
                        .clipped()
                }
                
                Text(article.name ?? "")
                    .font(.custom("SFProText-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 200)
        }
        .buttonStyle(PlainButtonStyle())
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
