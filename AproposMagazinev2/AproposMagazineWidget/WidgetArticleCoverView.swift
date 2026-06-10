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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
