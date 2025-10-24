import SwiftUI
import UIKit

struct ArticleShareView: View {
    var article: Article
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform: SharePlatform = .general
    @State private var customMessage: String = ""
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Preview
                ArticleSharePreview(article: article, platform: selectedPlatform)
                    .padding()
                
                // Share Options
                VStack(spacing: 20) {
                    // Platform Selection
                    platformSelectionView
                    
                    // Custom Message
                    customMessageView
                    
                    // Share Button
                    shareButton
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Del artikel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuller") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(article: article, platform: selectedPlatform, customMessage: customMessage)
        }
    }
    
    private var platformSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vælg platform")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(SharePlatform.allCases, id: \.self) { platform in
                    PlatformButton(
                        platform: platform,
                        isSelected: selectedPlatform == platform
                    ) {
                        selectedPlatform = platform
                        HapticManager.shared.selection()
                    }
                }
            }
        }
    }
    
    private var customMessageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tilføj besked (valgfrit)")
                .font(.headline)
            
            TextField("Skriv din besked...", text: $customMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }
    
    private var shareButton: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            showShareSheet = true
        }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Del artikel")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedPlatform.color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Article Share Preview

struct ArticleSharePreview: View {
    var article: Article
    let platform: SharePlatform
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            var mutableArticle = article
            let thumbnailURL = mutableArticle.thumbnailURL
            if let url = URL(string: thumbnailURL) {
                OptimizedImageView(url: url, cornerRadius: 12)
                    .frame(height: 200)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Category
                if let topicId = article.topicID {
                    Text(topicId.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(platform.color)
                }
                
                // Title
                Text(article.name ?? "")
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                // Subtitle
                if let intro = article.intro {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                // Platform-specific styling
                platformSpecificContent
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(platform.color.opacity(0.3), lineWidth: 2)
        )
    }
    
    @ViewBuilder
    private var platformSpecificContent: some View {
        switch platform {
        case .twitter:
            HStack {
                Image(systemName: "bird")
                    .foregroundColor(.blue)
                Text("Twitter")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
            }
            
        case .instagram:
            HStack {
                Image(systemName: "camera")
                    .foregroundColor(.purple)
                Text("Instagram")
                    .font(.caption)
                    .foregroundColor(.purple)
                Spacer()
            }
            
        case .facebook:
            HStack {
                Image(systemName: "person.2")
                    .foregroundColor(.blue)
                Text("Facebook")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
            }
            
        case .linkedin:
            HStack {
                Image(systemName: "briefcase")
                    .foregroundColor(.blue)
                Text("LinkedIn")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
            }
            
        case .whatsapp:
            HStack {
                Image(systemName: "message")
                    .foregroundColor(.green)
                Text("WhatsApp")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
            }
            
        case .general:
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
                Text("Del")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
            }
        }
    }
}

// MARK: - Platform Button

struct PlatformButton: View {
    let platform: SharePlatform
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: platform.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : platform.color)
                
                Text(platform.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? platform.color : Color(.tertiarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Platform

enum SharePlatform: CaseIterable {
    case general
    case twitter
    case instagram
    case facebook
    case linkedin
    case whatsapp
    
    var displayName: String {
        switch self {
        case .general: return "Generelt"
        case .twitter: return "Twitter"
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .linkedin: return "LinkedIn"
        case .whatsapp: return "WhatsApp"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "square.and.arrow.up"
        case .twitter: return "bird"
        case .instagram: return "camera"
        case .facebook: return "person.2"
        case .linkedin: return "briefcase"
        case .whatsapp: return "message"
        }
    }
    
    var color: Color {
        switch self {
        case .general: return .blue
        case .twitter: return .blue
        case .instagram: return .purple
        case .facebook: return .blue
        case .linkedin: return .blue
        case .whatsapp: return .green
        }
    }
    
    var urlScheme: String? {
        switch self {
        case .twitter: return "twitter://"
        case .instagram: return "instagram://"
        case .facebook: return "fb://"
        case .linkedin: return "linkedin://"
        case .whatsapp: return "whatsapp://"
        case .general: return nil
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var article: Article
    let platform: SharePlatform
    let customMessage: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let shareText = generateShareText()
        let shareURL = generateShareURL()
        
        var activityItems: [Any] = [shareText]
        
        if let url = shareURL {
            activityItems.append(url)
        }
        
        // Add image if available
        var mutableArticle = article
        let thumbnailURL = mutableArticle.thumbnailURL
        if let imageURL = URL(string: thumbnailURL) {
            // This would be enhanced to actually load and share the image
            activityItems.append(imageURL)
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Configure for specific platform
        configureForPlatform(activityViewController)
        
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    private func generateShareText() -> String {
        var text = ""
        
        if !customMessage.isEmpty {
            text += "\(customMessage)\n\n"
        }
        
        text += "📰 \(article.name ?? "Artikel")\n"
        
        if let intro = article.intro {
            text += "\(intro)\n\n"
        }
        
        text += "Læs mere på Apropos Magazine"
        
        return text
    }
    
    private func generateShareURL() -> URL? {
        // Generate a deep link to the article
        let baseURL = "https://aproposmagazine.com"
        let articlePath = "/article/\(article.slug ?? article.id)"
        return URL(string: baseURL + articlePath)
    }
    
    private func configureForPlatform(_ activityViewController: UIActivityViewController) {
        switch platform {
        case .twitter:
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .saveToCameraRoll
            ]
            
        case .instagram:
            // Instagram sharing would be enhanced with image generation
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .print
            ]
            
        case .facebook:
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks
            ]
            
        case .linkedin:
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .saveToCameraRoll
            ]
            
        case .whatsapp:
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .print
            ]
            
        case .general:
            activityViewController.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList
            ]
        }
    }
}

// MARK: - Social Media Integration

class SocialMediaManager: ObservableObject {
    static let shared = SocialMediaManager()
    
    private init() {}
    
    func shareToTwitter(article: Article, message: String = "") {
        let text = generateTwitterText(article: article, message: message)
        let url = generateShareURL(article: article)
        
        var twitterURL = "https://twitter.com/intent/tweet?text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = url {
            twitterURL += "&url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        if let url = URL(string: twitterURL) {
            UIApplication.shared.open(url)
        }
    }
    
    func shareToFacebook(article: Article, message: String = "") {
        let url = generateShareURL(article: article)
        let facebookURL = "https://www.facebook.com/sharer/sharer.php?u=\(url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: facebookURL) {
            UIApplication.shared.open(url)
        }
    }
    
    func shareToLinkedIn(article: Article, message: String = "") {
        let url = generateShareURL(article: article)
        let linkedInURL = "https://www.linkedin.com/sharing/share-offsite/?url=\(url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: linkedInURL) {
            UIApplication.shared.open(url)
        }
    }
    
    private func generateTwitterText(article: Article, message: String) -> String {
        var text = ""
        
        if !message.isEmpty {
            text += "\(message) "
        }
        
        text += "📰 \(article.name ?? "Artikel")"
        
        if let intro = article.intro {
            let truncatedIntro = String(intro.prefix(100))
            text += " - \(truncatedIntro)"
        }
        
        return text
    }
    
    private func generateShareURL(article: Article) -> URL? {
        let baseURL = "https://aproposmagazine.com"
        let articlePath = "/article/\(article.slug ?? article.id)"
        return URL(string: baseURL + articlePath)
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func shareArticle(_ article: Article) -> some View {
        self.sheet(isPresented: .constant(true)) {
            ArticleShareView(article: article)
        }
    }
}

#Preview {
    let sampleArticle = Article(
        id: "1",
        name: "Justice (O Days Festival): Total forløsning i mudder og bassdrops",
        slug: "justice-o-days-festival",
        content: "Sample content",
        intro: "Lørdagen blev reddet af to franske prædikanter med bassdrops i stedet for bibelvers.",
        stjerne: 4,
        topicID: "Festival",
        topicsIDs: ["Festival", "Musik"],
        authorID: "Frederik Emil",
        thumbURL: URL(string: "https://picsum.photos/400/300")!,
        coverURL: nil,
        location: "Odense",
        subtitle: nil,
        isDraft: nil
    )
    
    ArticleShareView(article: sampleArticle)
}
