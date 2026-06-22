import SwiftUI

struct WidgetArticleCardView: View {
    let article: WidgetArticle
    var isMedium: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APROPOS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .tracking(0.8)

            bottomOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: isMedium ? 5 : 4) {
            if !topicLine.isEmpty {
                Text(topicLine)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Text(article.name)
                .font(.system(size: isMedium ? 18 : 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(isMedium ? 3 : 4)
                .minimumScaleFactor(0.78)

            if let rating = article.stjerne {
                WidgetStarRatingView(rating: rating)
            }

            Text(WidgetArticleFormatting.ctaText(for: article))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 2)
        }
    }

    private var topicLine: String {
        WidgetArticleFormatting.topicLine(for: article)
    }
}

enum WidgetStarStyle {
    case onDarkBackground
    case onLightBackground
}

struct WidgetStarRatingView: View {
    let rating: Int
    var style: WidgetStarStyle = .onDarkBackground

    private var starColor: Color {
        style == .onDarkBackground ? .white : Color(red: 0.1, green: 0.1, blue: 0.12)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(starColor)
            }
        }
    }
}

struct WidgetTodayArticleRow: View {
    let article: WidgetArticle
    var thumbnailSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            WidgetArticleCoverView(article: article, cornerRadius: 8)
                .frame(width: thumbnailSize, height: thumbnailSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(article.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(thumbnailSize > 60 ? 3 : 2)
                    .minimumScaleFactor(0.82)

                if let rating = article.stjerne {
                    WidgetStarRatingView(rating: rating)
                } else {
                    Text(WidgetArticleFormatting.topicLine(for: article))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}
