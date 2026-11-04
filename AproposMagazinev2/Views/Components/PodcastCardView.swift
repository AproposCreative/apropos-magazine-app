import SDWebImageSwiftUI
import SwiftUI

struct PodcastCardView: View {
    @ObservedObject var progressStore: PodcastPlaybackProgressStore
    let pair: PodcastArticlePair
    let categoryText: String
    let onPlay: (PodcastArticlePair) -> Void
    let onOpenArticle: (Article) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.homeImagePolicy) private var imagePolicy
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.podcastRowGeometryProbe) private var geometryProbe
    @Environment(\.podcastRowFixtureArtwork) private var fixtureArtwork
#endif

    private var accessibleLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var artworkURL: URL? {
        pair.episode.artworkURL ?? pair.article.mobileImageURL ?? pair.article.thumbURL ?? pair.article.coverURL
    }

    var body: some View {
        LeadingArticleArtwork(width: 92, spacing: 14, cornerRadius: 12,
            artworkAllowsHitTesting: true) { size in
            Button { onOpenArticle(pair.article) } label: {
                ZStack {
                    ArticleImagePlaceholder(showShimmer: false, cornerRadius: 12)
                    if imagePolicy.allowsRemoteImages {
                        WebImage(url: artworkURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages, .queryMemoryData])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
#if DEBUG && targetEnvironment(simulator)
                    if let artwork = fixtureArtwork?(pair.episode.id) {
                        Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    }
#endif
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
#if DEBUG && targetEnvironment(simulator)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    geometryProbe?("card.\(pair.episode.id).artworkLabel", $0)
                }
#endif
            }
            .buttonStyle(.plain)
            // The title provides the same accessible action once. Artwork
            // remains a separate touch target without a parent card gesture.
            .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Button { onOpenArticle(pair.article) } label: {
                    Text(pair.episode.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(accessibleLayout ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Åbn artikel: \(pair.episode.title)")
                .accessibilityIdentifier("home.podcast.open.\(pair.article.id)")

                Spacer(minLength: 4)

                if accessibleLayout {
                    VStack(alignment: .leading, spacing: 8) {
                        durationLabel
                        categoryLabel
                        playButton
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        durationLabel
                        categoryLabel
                        Spacer(minLength: 0)
                        playButton
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
#if DEBUG && targetEnvironment(simulator)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                geometryProbe?("card.\(pair.episode.id).text", $0)
            }
#endif
        }
#if DEBUG && targetEnvironment(simulator)
        .observingArtworkFrame { geometryProbe?("card.\(pair.episode.id).image", $0) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            geometryProbe?("card.\(pair.episode.id).content", $0)
        }
#endif
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.podcast.card.\(pair.episode.id)")
    }

    @ViewBuilder private var durationLabel: some View {
        if let duration = pair.episode.duration, !duration.isEmpty {
            Label {
                let text = Text(duration).accessibilityIdentifier("home.podcast.duration.\(pair.episode.id)")
                if accessibleLayout { text.lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                else { text }
            } icon: { Image(systemName: "clock").accessibilityHidden(true) }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var categoryLabel: some View {
        LocalizedArticleTaxonomy(categoryText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(accessibleLayout ? nil : 1)
            .accessibilityIdentifier("home.podcast.category.\(pair.episode.id)")
    }

    private var playButton: some View {
        Button { onPlay(pair) } label: {
            HStack(spacing: 4) {
                Image(systemName: pair.episode.hasPlayableAudioURL ? "play.fill" : "clock")
                    .font(.caption2.weight(.bold))
                let text = Text(LocalizedStringKey(pair.episode.hasPlayableAudioURL
                    ? progressStore.snapshot.playButtonTitle(for: pair.episode.id) : "Kommer"))
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("home.podcast.playLabel.\(pair.episode.id)")
                if accessibleLayout { text.lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                else { text }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pair.episode.hasPlayableAudioURL ? Color(hex: "#262626") : Color.gray.opacity(0.55))
            .clipShape(Capsule())
            .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!pair.episode.hasPlayableAudioURL)
        .accessibilityIdentifier("home.podcast.play.\(pair.episode.id)")
#if DEBUG && targetEnvironment(simulator)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            geometryProbe?("card.\(pair.episode.id).play", $0)
        }
#endif
    }
}
