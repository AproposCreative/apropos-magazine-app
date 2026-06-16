import SwiftUI
import UIKit

struct WidgetArticleCoverView: View {
    let article: WidgetArticle
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            Color(red: 0.82, green: 0.82, blue: 0.84)

            if let uiImage = WidgetImageStore.uiImage(for: article) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = remoteImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var remoteImageURL: URL? {
        let value = article.thumbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }
}
