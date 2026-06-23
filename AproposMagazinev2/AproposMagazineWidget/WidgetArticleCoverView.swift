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
            }
            // No AsyncImage fallback: widgets cannot reliably load images over the
            // network. Without a cached App Group image we keep the gradient + "A".
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
