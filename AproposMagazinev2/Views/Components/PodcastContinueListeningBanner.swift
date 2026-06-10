import SDWebImageSwiftUI
import SwiftUI

struct PodcastContinueListeningBanner: View {
    let pair: PodcastArticlePair
    let onContinue: () -> Void
    let onOpenArticle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    ArticleImagePlaceholder(showShimmer: false, cornerRadius: 12)
                    WebImage(url: artworkURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pair.episode.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("Podcast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: onContinue) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                        Text("Fortsæt")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#262626"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture(perform: onOpenArticle)
        }
        .padding(.horizontal, 16)
    }
}
