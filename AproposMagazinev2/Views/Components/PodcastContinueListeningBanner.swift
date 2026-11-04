import SDWebImageSwiftUI
import SwiftUI

struct PodcastContinueListeningBanner: View {
    let pair: PodcastArticlePair
    let onContinue: () -> Void
    let onOpenArticle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.homeImagePolicy) private var imagePolicy
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accessibleLayout: Bool { dynamicTypeSize.isAccessibilitySize }
    private var contentLayout: AnyLayout {
        accessibleLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 14))
    }

    private var artworkURL: URL? {
        pair.episode.artworkURL ?? pair.article.mobileImageURL ?? pair.article.thumbURL ?? pair.article.coverURL
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fortsæt hvor du slap")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.primary)

            contentLayout {
                Button(action: onOpenArticle) {
                    contentLayout {
                        ZStack {
                            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 12)
                            if imagePolicy.allowsRemoteImages {
                                WebImage(url: artworkURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(pair.episode.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(accessibleLayout ? nil : 2)
                            if !accessibleLayout { Spacer(minLength: 0) }
                            Text("Podcast").font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("home.resume.category")
                        }
                        .frame(maxWidth: .infinity, minHeight: accessibleLayout ? nil : 72, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Åbn artikel: \(pair.episode.title)")
                .accessibilityIdentifier("home.resume.open")

                Button(action: onContinue) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                        let text = Text("Fortsæt")
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("home.resume.playLabel")
                        if accessibleLayout { text.lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        else { text }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#262626"))
                    .clipShape(Capsule())
                    .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.resume.play")
            }
            .padding(12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.resume.card")
        }
        .padding(.horizontal, 16)
    }
}
