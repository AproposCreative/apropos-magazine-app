import SDWebImageSwiftUI
import SwiftUI

enum PodcastMiniPlayerLayout {
    static let barHeight: CGFloat = 56
    static let contentGap: CGFloat = 20

    /// Reserved scroll inset above the tab bar when the mini player is visible.
    static var scrollBottomInset: CGFloat {
        barHeight + contentGap
    }

    static func articleBottomPadding(isPlayerVisible: Bool) -> CGFloat {
        isPlayerVisible ? scrollBottomInset + 40 : 2
    }

    static func feedBottomPadding(isPlayerVisible: Bool) -> CGFloat {
        isPlayerVisible ? scrollBottomInset + 8 : 56
    }
}

struct PodcastMiniPlayerBar: View {
    @EnvironmentObject private var podcastPlayer: PodcastPlayerManager
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    private var backgroundTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.18)
    }

    private var primaryForeground: Color {
        .white.opacity(0.96)
    }

    private var secondaryForeground: Color {
        .white.opacity(0.66)
    }
    
    private var subtitleText: String {
        guard let episode = podcastPlayer.currentEpisode else { return "" }
        let article = PodcastEpisode.matchingArticle(for: episode, in: viewModel.articles)
        return episode.playerSubtitleLine(matchingArticle: article) { viewModel.author(for: $0) }
    }

    var body: some View {
        if let episode = podcastPlayer.currentEpisode {
            HStack(spacing: 10) {
                ZStack {
                    ArticleImagePlaceholder(showShimmer: false, cornerRadius: 9)
                    WebImage(url: episode.artworkURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 39, height: 39)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Button {
                    podcastPlayer.togglePlayPause()
                } label: {
                    Group {
                        if podcastPlayer.isBuffering && !podcastPlayer.isPlaying {
                            ProgressView()
                                .controlSize(.small)
                                .tint(primaryForeground)
                        } else {
                            Image(systemName: podcastPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(primaryForeground)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    podcastPlayer.isBuffering && !podcastPlayer.isPlaying
                        ? "Indlæser lyd"
                        : (podcastPlayer.isPlaying ? "Pause" : "Afspil")
                )

                Button {
                    podcastPlayer.seekForward(seconds: 30)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryForeground)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(backgroundTint)
            )
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(colorScheme == .dark ? 0.35 : 0.3))
                        .frame(width: max(8, proxy.size.width * podcastPlayer.progress), height: 1)
                        .padding(.horizontal, 1)
                        .padding(.bottom, 1)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.14), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.12), radius: 6, x: 0, y: 1)
            .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        isPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            isPressed = false
                        }
                    }
                }
                podcastPlayer.openFullPlayer()
            }
        }
    }
}
