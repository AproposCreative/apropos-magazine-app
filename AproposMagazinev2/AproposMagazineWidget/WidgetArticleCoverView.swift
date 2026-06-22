import SwiftUI
import UIKit

struct WidgetArticleCoverView: View {
    let article: WidgetArticle
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.18, blue: 0.19),
                    Color(red: 0.08, green: 0.08, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text("A")
                .font(.system(size: 22, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.34))

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
