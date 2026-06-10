import SDWebImageSwiftUI
import SwiftUI

struct PodcastCardView: View {
    let pair: PodcastArticlePair
    let categoryText: String
    let onPlay: (PodcastEpisode) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var artworkURL: URL? {
        pair.episode.artworkURL ?? pair.article.mobileImageURL ?? pair.article.thumbURL ?? pair.article.coverURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                ArticleImagePlaceholder(showShimmer: false, cornerRadius: 12)

                WebImage(url: artworkURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages, .queryMemoryData])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("PODCAST")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(pair.episode.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let duration = pair.episode.duration, !duration.isEmpty {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(categoryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button {
                        onPlay(pair.episode)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: pair.episode.hasPlayableAudioURL ? "play.fill" : "clock")
                                .font(.caption2.weight(.bold))
                            Text(pair.episode.hasPlayableAudioURL
                                ? PodcastPlaybackProgressStore.playButtonTitle(for: pair.episode.id)
                                : "Kommer")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(pair.episode.hasPlayableAudioURL ? Color(hex: "#262626") : Color.gray.opacity(0.55))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!pair.episode.hasPlayableAudioURL)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
