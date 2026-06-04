import SwiftUI
import Shimmer

struct ArticleImagePlaceholder: View {
    let showShimmer: Bool
    let cornerRadius: CGFloat

    init(showShimmer: Bool = true, cornerRadius: CGFloat = 8) {
        self.showShimmer = showShimmer
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.16, green: 0.16, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("AproposLogoWhite")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 76, maxHeight: 26)
                .opacity(0.35)
                .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shimmering(
            active: showShimmer,
            animation: .easeInOut(duration: 1.25).repeatForever(autoreverses: false).delay(0.15),
            gradient: Gradient(colors: [
                .clear,
                .white.opacity(0.18),
                .clear
            ]),
            bandSize: 0.35
        )
    }
}

