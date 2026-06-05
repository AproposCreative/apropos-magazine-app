import SwiftUI
import Shimmer

enum ArticleImagePlaceholderMode {
    case loading
    case offline
    case idle
}

struct ArticleImagePlaceholder: View {
    let mode: ArticleImagePlaceholderMode
    let cornerRadius: CGFloat

    init(mode: ArticleImagePlaceholderMode = .loading, cornerRadius: CGFloat = 8) {
        self.mode = mode
        self.cornerRadius = cornerRadius
    }

    /// Backward-compatible initializer used across the app.
    init(showShimmer: Bool, cornerRadius: CGFloat = 8) {
        self.mode = showShimmer ? .loading : .idle
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            switch mode {
            case .offline:
                offlinePlaceholder
            case .loading, .idle:
                brandedPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var brandedPlaceholder: some View {
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

            if mode == .idle {
                Image("AproposLogoWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 76, maxHeight: 26)
                    .opacity(0.35)
                    .padding(14)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shimmering(
            active: mode == .loading,
            animation: .easeInOut(duration: 1.25).repeatForever(autoreverses: false).delay(0.15),
            gradient: Gradient(colors: [
                .clear,
                .white.opacity(0.18),
                .clear
            ]),
            bandSize: 0.35
        )
    }

    private var offlinePlaceholder: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05)

            VStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .shadow(color: Color.white.opacity(0.35), radius: 8, x: 0, y: 0)

                Text("Medie offline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .shadow(color: Color.white.opacity(0.28), radius: 10, x: 0, y: 0)

                Text("Tjek din internetforbindelse")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.white.opacity(0.18), radius: 8, x: 0, y: 0)
            }
            .padding(.horizontal, 20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.white.opacity(0.04), radius: 12, x: 0, y: 0)
    }
}
