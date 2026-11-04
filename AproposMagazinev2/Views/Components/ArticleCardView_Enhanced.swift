import SwiftUI
import SDWebImageSwiftUI

struct ArticleCardView_Enhanced: View {
    
    // MARK: - Properties
    let showTopic: Bool
    var article: Article
    let cardHeight: CGFloat
    let showStars: Bool
    let recommendationReason: String?
    let categories: [String]
    let imageURL: URL?
    let onOpen: ((Article) -> Void)?
    let openAccessibilityID: String?
    let deferImageUntilVisible: Bool
    private let editorialDateTexts: [ArticleContentLanguage: String]
    @Environment(\.locale) private var locale
    var bottom = Int()
    @State private var isLoaded = false
    @State private var loadFailed = false
    @State private var coverEnteredViewport = false
    @Environment(\.homeImagePolicy) private var imagePolicy
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.homeCoverAdmissionProbe) private var coverAdmissionProbe
#endif
    @Environment(\.colorScheme) var colorScheme
    @ScaledMetric(relativeTo: .body) private var titleFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var detailFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var dateFontSize: CGFloat = 15

    private var accessibilityPrefix: String {
        openAccessibilityID ?? "article.open.\(article.id)"
    }
    private var coverImageAdmitted: Bool { !deferImageUntilVisible || coverEnteredViewport }

    private func starImageName(isFilled: Bool) -> String {
        let filledAsset = "DarkStar"
        let emptyAsset = "DimStar"
        if colorScheme == .light {
            return isFilled ? emptyAsset : filledAsset
        }
        return isFilled ? filledAsset : emptyAsset
    }
    // MARK: - Initialization
    
    init(
        article: Article,
        cardHeight: CGFloat = 200,
        showStars: Bool = false,
        showTopic: Bool = true,
        recommendationReason: String? = nil,
        categories: [String] = ["Generelt"],
        imageURL: URL? = nil,
        onOpen: ((Article) -> Void)? = nil,
        openAccessibilityID: String? = nil,
        deferImageUntilVisible: Bool = false
    ) {
        self.article = article
        self.cardHeight = cardHeight
        self.showStars = showStars
        self.showTopic = showTopic
        self.recommendationReason = recommendationReason
        self.categories = categories.isEmpty ? ["Generelt"] : categories
        self.imageURL = imageURL ?? article.mobileImageURL ?? article.thumbURL ?? article.coverURL
        self.onOpen = onOpen
        self.openAccessibilityID = openAccessibilityID
        self.deferImageUntilVisible = deferImageUntilVisible
        self.editorialDateTexts = Dictionary(uniqueKeysWithValues: ArticleContentLanguage.allCases.compactMap { language in
            ArticleDisplayDateFormatter.shared.string(from: article.date, language: language).map { (language, $0) }
        })
    }

    
    // MARK: - View
    
    var body: some View {
        if let onOpen {
            Button { onOpen(article) } label: { cardContent }
                .buttonStyle(.plain)
                .accessibilityIdentifier(openAccessibilityID ?? "article.open.\(article.id)")
        } else { cardContent }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            imageSection
            contentSection.padding(.top, 6)
        }
    }
}

// MARK: - Image Section
private extension ArticleCardView_Enhanced {
    
    var imageSection: some View {
        GeometryReader { geometry in
            ZStack {
                ArticleImagePlaceholder(mode: imagePolicy.allowsRemoteImages && coverImageAdmitted ? (loadFailed ? .offline : (isLoaded ? .idle : .loading)) : .idle, cornerRadius: 8)

                if imagePolicy.allowsRemoteImages, coverImageAdmitted, !loadFailed, let cardImageURL = imageURL {
                    WebImage(url: cardImageURL, options: [.retryFailed, .continueInBackground])
                        .resizable()
                        .onSuccess { _, _, _ in
                            DispatchQueue.main.async {
                                isLoaded = true
                            }
                        }
                        .onFailure { _ in
                            DispatchQueue.main.async {
                                loadFailed = true
                            }
                        }
                        .transition(.identity)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: geometry.size.width, height: cardHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: article.id) { _, _ in
                isLoaded = false
                loadFailed = false
            }
        }
        .frame(height: cardHeight)
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            // Text is measured eagerly for the rail's natural height. Only the
            // cover waits for its first viewport entry; keep it admitted when
            // scrolling back so the existing image/cache lifecycle continues.
            if deferImageUntilVisible, visible, !coverEnteredViewport { coverEnteredViewport = true }
        }
#if DEBUG && targetEnvironment(simulator)
        .onChange(of: coverImageAdmitted, initial: true) { _, admitted in
            coverAdmissionProbe?(accessibilityPrefix, admitted)
        }
#endif
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

#if DEBUG && targetEnvironment(simulator)
/// Installed only by the local Home fixture. It observes the actual native
/// visibility admission without starting image requests or adding product UI.
private struct HomeCoverAdmissionProbeKey: EnvironmentKey {
    static let defaultValue: ((String, Bool) -> Void)? = nil
}
extension EnvironmentValues {
    var homeCoverAdmissionProbe: ((String, Bool) -> Void)? {
        get { self[HomeCoverAdmissionProbeKey.self] }
        set { self[HomeCoverAdmissionProbeKey.self] = newValue }
    }
}
#endif

struct StarsFromText: View {
    let starText: String
    @Environment(\.colorScheme) var colorScheme

    private func starImageName(isFilled: Bool) -> String {
        let filledAsset = "DarkStar"
        let emptyAsset = "DimStar"
        if colorScheme == .light {
            return isFilled ? emptyAsset : filledAsset
        }
        return isFilled ? filledAsset : emptyAsset
    }

    var body: some View {
        let count = extractRating(from: starText)
        // Only show stars if there's a valid rating
        if count > 0 {
            HStack(spacing: 4) {
                ForEach(0..<6) { index in
                    Image(starImageName(isFilled: index < count))
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
    

    var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            if showTopic {
                LocalizedArticleTaxonomy(categories.first ?? "Generelt")
                    .font(.system(size: detailFontSize, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityPrefix + ".category")
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
                .font(.system(size: titleFontSize, weight: .regular))
                .lineLimit(showTopic ? 3 : 2) // 3 lines for large cards (Musik section), 2 for small cards
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
                .accessibilityIdentifier(accessibilityPrefix + ".title")
            
            // Intro
            if showTopic {
                // Intro – up to 3 lines, no ellipsis
                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .aproposArticleSubtitle()
                        .lineLimit(3) // 3 lines for large cards (Musik section)
                        .fixedSize(horizontal: false, vertical: true)
                        .clipped()
                        .accessibilityIdentifier(accessibilityPrefix + ".intro")
                        
                }
            }
            if !showTopic {
                if let recommendationReason, !recommendationReason.isEmpty {
                    Text(LocalizedStringKey(recommendationReason))
                        .aproposArticleSubtitle()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .accessibilityIdentifier(accessibilityPrefix + ".intro")
                } else if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .aproposArticleSubtitle()
                        .fixedSize(horizontal: false, vertical: true) // allow full height
                        .padding(.bottom, intro.count >= 20 ? 10 : 5)
                        .lineLimit(2)
                        .accessibilityIdentifier(accessibilityPrefix + ".intro")
                }
            }

            
            // Stars - only show if stjerne is not nil
            if showStars, let rating = article.stjerne {
                HStack(spacing: 4) {
                    ForEach(0..<6) { index in
                        Image(starImageName(isFilled: index < rating))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(min(6, max(0, rating))) ud af 6 stjerner")
                .accessibilityIdentifier(accessibilityPrefix + ".rating")
            }
            
            // Date
            if let date = editorialDateTexts[AppLocalization.language(for: locale)] {
                Text(date)
                    .font(.system(size: dateFontSize, weight: .bold))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityPrefix + ".date")
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
            cardHeight: 500
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
