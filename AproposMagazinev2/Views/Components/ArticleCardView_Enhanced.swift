import SwiftUI
import SDWebImageSwiftUI

struct ArticleCardView_Enhanced: View {
    
    // MARK: - Properties
    let showTopic: Bool
    var article: Article
    let onFavorite: ((Article) -> Void)?
    let isFavorite: Bool
    let cardHeight: CGFloat
    let showStars: Bool
    var bottom = Int()
    @State private var isLoaded = false
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    // Add a computed property to safely check if article is favorite
    private var isArticleFavorite: Bool {
        return viewModel.isFavorite(article)
    }
    
    // Safe action to toggle favorite
    private func safeToggleFavorite() {
        // Add haptic feedback
        HapticManager.shared.lightImpact()
        viewModel.toggleFavorite(for: article)
        onFavorite?(article)
    }
    // MARK: - Initialization
    
    init(article: Article, isFavorite: Bool = false, cardHeight: CGFloat = 200, showStars: Bool = false, showTopic: Bool = true, onFavorite: ((Article) -> Void)? = nil) {
        self.article = article
        self.isFavorite = isFavorite
        self.cardHeight = cardHeight
        self.onFavorite = onFavorite
        self.showStars = showStars
        self.showTopic = showTopic
    }

    
    // MARK: - View
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
//            if showStars{
////                MusickimageSection
//            }else{
                imageSection
//               
//            }
                
            contentSection
                .padding(.top , 6)
                
        }
       // .aproposCardStyle()
    }
}

// MARK: - Image Section
private extension ArticleCardView_Enhanced {
    
    var imageSection: some View {
        GeometryReader { geometry in
            var mutableArticle = article
            let thumbnailURL = mutableArticle.thumbnailURL
            WebImage(url: URL(string: thumbnailURL), options: [.retryFailed, .continueInBackground])
                .resizable()
                .onSuccess { _, _, _ in
                    DispatchQueue.main.async {
                        isLoaded = true
                    }
                }
                .onFailure { error in
                    print("Image failed: \(error.localizedDescription)")
                }
                .transition(.fade(duration: 0.3)) // ✅ Smooth fade in
                .aspectRatio(contentMode: .fill) // ✅ Fill like center crop
                .frame(width: geometry.size.width, height: cardHeight) // ✅ Fixed size
                .clipped() // ✅ Crop overflowing parts
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // ✅ Align to top-left
        }
        .frame(height: cardHeight)
    }
//    var MusickimageSection: some View {
//        
//        GeometryReader { geometry in
//            ZStack(alignment: .topTrailing) {
//                WebImage(url: URL(string: article.thumbnailURL), options: [.retryFailed, .continueInBackground])
//                    .onSuccess { _, _, _ in
////                        isLoaded = true
//                    }
//                    .onFailure { error in
//                        print("Image failed: \(error.localizedDescription)")
//                    }
//                
//                    .resizable()
//                    .indicator(.activity) // ✅ Show loading indicator
//                    .transition(.fade(duration: 0.3)) // ✅ Smooth fade in
//                    .aspectRatio(contentMode: .fill) // ✅ Fill like center crop
//                    .frame(width: geometry.size.width, height: cardHeight) // ✅ Fixed size
//                    .clipped() // ✅ Crop overflowing parts
//                     
//                   
//            }
//            .frame(height: cardHeight)
//        }
//        .frame(height: cardHeight)
//    }
}

struct StarsFromText: View {
    let starText: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let count = extractRating(from: starText)
        // Only show stars if there's a valid rating
        if count > 0 {
            HStack(spacing: 4) {
                ForEach(0..<6) { index in
                    Image(index < count ? 
                        (colorScheme == .dark ? "DarkStar" : "DimStar") : 
                        (colorScheme == .dark ? "DimStar" : "DarkStar"))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
            }
        } else {
            EmptyView()
        }
    }

    private func extractRating(from text: String) -> Int {
        let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return min(6, Int(digits) ?? 0) // Changed from 5 to 6
    }
}
// MARK: - Content Section

private extension ArticleCardView_Enhanced {
    

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
    
    var contentSection: some View {
        let colorScheme = colorScheme // Capture the environment variable
        return VStack(alignment: .leading, spacing: 8) {
            
            if showTopic {
                Text(articleCategories.first ?? "Generelt")
                    .font(.custom("SFProText-Semibold", size: 12))
                    .textCase(.uppercase)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(alignment: .leading)
                    // Underline that "hugs" the text width
                    .background(
                        GeometryReader { geo in
                            let textWidth = geo.size.width
                            Rectangle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: textWidth, height: 1)
                                .alignmentGuide(.bottom) { d in d[.bottom] }
                                .offset(y: geo.size.height + 1)
                        }
                    )
                    .padding(.top, 6)
            }
            
            // Title
            Text(article.name ?? "Titel")
                .font(.custom("SFProText-Regular", size: 16))
                .lineLimit(showTopic ? 3 : 2) // 3 lines for large cards (Musik section), 2 for small cards
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
            
            // Intro
            if showTopic {
                // Intro – up to 3 lines, no ellipsis
                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .aproposArticleSubtitle()
                        .font(.custom("SFProText-Regular", size: 12))
                        .lineLimit(3) // 3 lines for large cards (Musik section)
                        .clipped()
                        
                }
            }
            if !showTopic {
                // Intro – up to 3 lines, no ellipsis
                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .aproposArticleSubtitle()
                        .font(.custom("SFProText-Regular", size: 12))
                        .fixedSize(horizontal: false, vertical: true) // allow full height
                        .padding(.bottom, intro.count >= 20 ? 10 : 5)
                        .lineLimit(2)
                }
            }

            
            // Stars - only show if stjerne is not nil
            if showStars, let rating = article.stjerne {
                HStack(spacing: 4) {
                    ForEach(0..<6) { index in
                        Image(index < rating ? 
                            (colorScheme == .dark ? "DarkStar" : "DimStar") : 
                            (colorScheme == .dark ? "DimStar" : "DarkStar"))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
            }
            
            // Date
            if let date = article.date {
                Text(date)
                    .font(.custom("SFProDisplay-Bold", size: 15))
                    .foregroundColor(.secondary)
            }
        }
        .padding(2)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 2) {
        ArticleCardView_Enhanced(
            article: Article(
                id: "1",
                name: "Eksempel artikel med lang titel der går over flere linjer",
                slug: "eksempel-artikel",
                content: "<p>Dette er indholdet</p>",
                intro: "Dette er en beskrivelse af artiklen som kan være ret lang og gå over flere linjer for at vise hvordan teksten håndteres.",
                stjerne: 4,
                topicID: "topic1",
                date: "2024-01-15"
            ),
            isFavorite: true,
            cardHeight: 500,
            onFavorite: { _ in }
        )
        
        ArticleCardView_Enhanced(
            article: Article(
                id: "2",
                name: "Kort artikel",
                slug: "kort-artikel",
                content: "<p>Kort indhold</p>",
                intro: "",
                stjerne: nil,
                topicID: "topic2",
                date: nil
            ),
            cardHeight: 180,
            showStars: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
