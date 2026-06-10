import SwiftUI

struct ShareCardView: View {
    let title: String
    let authorName: String?
    let coverImage: UIImage?

    private let cardSize: CGFloat = 1080

    var body: some View {
        ZStack {
            backgroundLayer

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Image("AproposLogoWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                    .padding(.top, 80)
                    .padding(.leading, 80)

                Spacer()

                Text(title)
                    .font(.system(size: 72, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 32)

                if let authorName, !authorName.isEmpty {
                    Text(authorName)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 80)
                        .padding(.bottom, 48)
                }

                Text("aproposmagazine.dk")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: cardSize, height: cardSize)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(width: cardSize, height: cardSize)
                .clipped()
        } else {
            Color(red: 0.12, green: 0.12, blue: 0.14)
        }
    }
}

enum ShareCardGenerator {
    @MainActor
    static func generate(article: Article) async -> UIImage? {
        let coverImage = await loadCoverImage(for: article)
        let view = ShareCardView(
            title: article.name ?? "Artikel",
            authorName: article.authorName,
            coverImage: coverImage
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }

    static func shareURL(for article: Article) -> URL? {
        ShareLinkBuilder.articleURL(slug: article.slug, articleId: article.id)
    }

    private static func loadCoverImage(for article: Article) async -> UIImage? {
        let url = article.coverURL ?? article.thumbURL ?? article.mobileImageURL
        guard let url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
