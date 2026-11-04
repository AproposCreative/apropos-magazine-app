import SwiftUI

/// Text and controls own the row height. Leading artwork receives that exact
/// height without contributing its intrinsic image size to layout.
struct LeadingArticleArtwork<Artwork: View, Content: View>: View {
    private let width: CGFloat
    private let spacing: CGFloat
    private let cornerRadius: CGFloat
    private let cornerStyle: RoundedCornerStyle
    private let artworkAllowsHitTesting: Bool
    private let artwork: (CGSize) -> Artwork
    private let content: Content
#if DEBUG && targetEnvironment(simulator)
    private var artworkFrame: ((CGRect) -> Void)?
#endif

    init(width: CGFloat, spacing: CGFloat, cornerRadius: CGFloat,
         cornerStyle: RoundedCornerStyle = .continuous, artworkAllowsHitTesting: Bool = false,
         @ViewBuilder artwork: @escaping (CGSize) -> Artwork, @ViewBuilder content: () -> Content) {
        self.width = width
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.artworkAllowsHitTesting = artworkAllowsHitTesting
        self.artwork = artwork
        self.content = content()
    }

    var body: some View {
        content
            .padding(.leading, width + spacing)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    artwork(CGSize(width: width, height: geometry.size.height))
                        .frame(width: width, height: geometry.size.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle))
                        // Cropping alone does not bound a resizable image's
                        // hit region. Keep article artwork off text/play taps.
                        .contentShape(Rectangle())
#if DEBUG && targetEnvironment(simulator)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            artworkFrame?($0)
                        }
#endif
                }
                .frame(width: width)
                .allowsHitTesting(artworkAllowsHitTesting)
                .accessibilityHidden(true)
            }
    }

#if DEBUG && targetEnvironment(simulator)
    func observingArtworkFrame(_ action: @escaping (CGRect) -> Void) -> Self {
        var copy = self
        copy.artworkFrame = action
        return copy
    }
#endif
}
