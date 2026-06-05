import SwiftUI
import SDWebImageSwiftUI

struct SeriesView: View {
    let seriesList: [ContentSeries]
    let articlesById: [String: Article]
    let onSelectSeries: (ContentSeries) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serier")
                .font(.title2.bold())
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(seriesList) { series in
                        Button {
                            onSelectSeries(series)
                        } label: {
                            SeriesCardView(
                                series: series,
                                coverArticle: series.articleIds.compactMap { articlesById[$0] }.first
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct SeriesCardView: View {
    let series: ContentSeries
    let coverArticle: Article?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = coverArticle?.thumbURL ?? coverArticle?.coverURL ?? coverArticle?.mobileImageURL {
                    WebImage(url: url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: 220, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(series.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)

            Text(series.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)
        }
    }
}
