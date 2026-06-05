import SwiftUI
import SDWebImageSwiftUI

struct SeriesDetailView: View {
    let series: ContentSeries
    let articles: [Article]
    @Environment(\.navigationCoordinator) private var navigationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(series.name)
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 16)

                Text(series.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                LazyVStack(spacing: 16) {
                    ForEach(articles, id: \.id) { article in
                        Button {
                            navigationCoordinator.navigateToArticle(article, in: .home)
                        } label: {
                            SeriesArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SeriesArticleRow: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = article.thumbURL ?? article.coverURL ?? article.mobileImageURL {
                    WebImage(url: url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(article.name ?? "Artikel")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
