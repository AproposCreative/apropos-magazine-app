import SwiftUI

/// Brand mark for overlays — uses the bundled vector logo (lightweight SVG).
struct AproposMagazineLogoMark: View {
    var body: some View {
        Image("AproposLogoBlack")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Apropos Magazine")
    }
}

/// White brand bar drawn on top of podcast artwork.
struct PodcastArtworkBrandOverlay: View {
    var barHeightRatio: CGFloat = 0.17

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    Color.white
                    AproposMagazineLogoMark()
                        .frame(height: max(22, proxy.size.height * barHeightRatio * 0.42))
                        .padding(.horizontal, 20)
                }
                .frame(height: max(48, proxy.size.height * barHeightRatio))
            }
        }
        .allowsHitTesting(false)
    }
}
