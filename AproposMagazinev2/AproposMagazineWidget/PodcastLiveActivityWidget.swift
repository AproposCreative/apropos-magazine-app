import ActivityKit
import SwiftUI
import WidgetKit

struct PodcastLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PodcastActivityAttributes.self) { context in
            PodcastLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PodcastArtworkView(
                        url: context.state.artworkURL,
                        articleId: context.state.artworkArticleId
                    )
                        .frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.episodeTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.authorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.elapsed, total: max(context.state.duration, 1))
                        .tint(.white)
                }
            } compactLeading: {
                PodcastArtworkView(
                    url: context.state.artworkURL,
                    articleId: context.state.artworkArticleId
                )
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}

private struct PodcastLiveActivityLockScreenView: View {
    let context: ActivityViewContext<PodcastActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            PodcastArtworkView(
                url: context.state.artworkURL,
                articleId: context.state.artworkArticleId
            )
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.showName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.state.episodeTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: context.state.elapsed, total: max(context.state.duration, 1))
            }

            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
        }
        .padding(.horizontal, 12)
    }
}

private struct PodcastArtworkView: View {
    let url: URL?
    let articleId: String?

    var body: some View {
        Group {
            if let articleId, let uiImage = WidgetImageStore.uiImage(forArticleId: articleId) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.35)
                    }
                }
            } else {
                Color.gray.opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
