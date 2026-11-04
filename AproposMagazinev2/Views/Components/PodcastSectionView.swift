import SwiftUI

struct PodcastSectionView: View {
    @ObservedObject var progressStore: PodcastPlaybackProgressStore
    let pairs: [PodcastArticlePair]
    let allPairs: [PodcastArticlePair]
    let authorProvider: (PodcastArticlePair) -> String
    let categoriesProvider: (Article) -> [String]
    let onOpenArticle: (Article) -> Void
    let onPlayPair: (PodcastArticlePair) -> Void
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lydindhold")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                if allPairs.count > pairs.count {
                    Group {
                        if let onSeeAll {
                            Button("Se alle", action: onSeeAll)
                        } else {
                            NavigationLink {
                                PodcastListView(progressStore: progressStore, pairs: allPairs,
                                    authorProvider: authorProvider, categoriesProvider: categoriesProvider,
                                    onOpenArticle: onOpenArticle, onPlayPair: onPlayPair)
                            } label: { Text("Se alle") }
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.seeAll.podcasts")
                }
            }
            .padding(.horizontal, 16)

            if pairs.isEmpty {
                Text("Ingen podcastafsnit endnu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(pairs) { pair in
                        PodcastCardView(
                            progressStore: progressStore,
                            pair: pair,
                            categoryText: categoriesProvider(pair.article).first ?? pair.episode.subtitle ?? "Lydindhold",
                            onPlay: onPlayPair,
                            onOpenArticle: onOpenArticle
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct PodcastListView: View {
    @ObservedObject var progressStore: PodcastPlaybackProgressStore
    let pairs: [PodcastArticlePair]
    let authorProvider: (PodcastArticlePair) -> String
    let categoriesProvider: (Article) -> [String]
    let onOpenArticle: (Article) -> Void
    let onPlayPair: (PodcastArticlePair) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.podcastRowGeometryProbe) private var geometryProbe
#endif
    private var accessibleLayout: Bool { dynamicTypeSize.isAccessibilitySize }
    private var rowLayout: AnyLayout {
        accessibleLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(pairs) { pair in
                    LeadingArticleArtwork(width: 80, spacing: 12, cornerRadius: 10,
                        artworkAllowsHitTesting: true) { size in
                        Button { onOpenArticle(pair.article) } label: {
                            PodcastCardThumbnail(pair: pair)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .contentShape(Rectangle())
#if DEBUG && targetEnvironment(simulator)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                    geometryProbe?("list.\(pair.episode.id).artworkLabel", $0)
                                }
#endif
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    } content: {
                        rowLayout {
                            Button {
                                onOpenArticle(pair.article)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pair.episode.title).font(.headline).foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(authorProvider(pair)).font(.subheadline).foregroundStyle(.secondary)
                                    if !accessibleLayout { Spacer(minLength: 0) }
                                    HStack(alignment: .bottom, spacing: 8) {
                                        Text(categoriesProvider(pair.article).first ?? pair.episode.subtitle ?? "Lydindhold")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .accessibilityIdentifier("home.podcast.list.category.\(pair.episode.id)")
                                        if let duration = pair.episode.duration, !duration.isEmpty {
                                            Text("· \(duration)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: accessibleLayout ? nil : 64, alignment: .leading)
#if DEBUG && targetEnvironment(simulator)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                    geometryProbe?("list.\(pair.episode.id).text", $0)
                                }
#endif
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.podcast.list.article.\(pair.article.id)")
                            VStack(alignment: .trailing, spacing: 8) {
                                if pair.episode.isAINarration {
                                    AINarrationBadge(style: .compact)
                                }
                                if !accessibleLayout { Spacer(minLength: 0) }
                                Button {
                                    onPlayPair(pair)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: pair.episode.hasPlayableAudioURL ? "play.fill" : "clock")
                                            .font(.caption2.weight(.bold))
                                        Text(LocalizedStringKey(pair.episode.hasPlayableAudioURL
                                            ? progressStore.snapshot.playButtonTitle(for: pair.episode.id) : "Kommer"))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .accessibilityIdentifier("home.podcast.list.playLabel.\(pair.episode.id)")
                                    }
                                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(pair.episode.hasPlayableAudioURL ? Color(hex: "#262626") : Color.gray.opacity(0.55))
                                        .clipShape(Capsule())
                                        .frame(minWidth: 44, minHeight: 44, alignment: .bottom).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(!pair.episode.hasPlayableAudioURL)
                                .accessibilityIdentifier("home.podcast.list.play.\(pair.episode.id)")
#if DEBUG && targetEnvironment(simulator)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                    geometryProbe?("list.\(pair.episode.id).play", $0)
                                }
#endif
                            }
                            .frame(minHeight: accessibleLayout ? nil : 64, alignment: .bottom)
                        }
                    }
#if DEBUG && targetEnvironment(simulator)
                    .observingArtworkFrame { geometryProbe?("list.\(pair.episode.id).image", $0) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        geometryProbe?("list.\(pair.episode.id).content", $0)
                    }
#endif
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.podcast.list.row.\(pair.episode.id)")

                    if pair.id != pairs.last?.id {
                        Divider()
                            .padding(.leading, 108)
                    }
                }
            }
        }
        .accessibilityIdentifier("home.podcast.list")
        .navigationTitle("Lydindhold")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PodcastCardThumbnail: View {
    let pair: PodcastArticlePair
    @Environment(\.homeImagePolicy) private var imagePolicy
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.podcastRowFixtureArtwork) private var fixtureArtwork
#endif

    private var artworkURL: URL? {
        pair.episode.artworkURL ?? pair.article.mobileImageURL ?? pair.article.thumbURL ?? pair.article.coverURL
    }

    var body: some View {
        ZStack {
            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 10)
            if imagePolicy.allowsRemoteImages {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
#if DEBUG && targetEnvironment(simulator)
            if let artwork = fixtureArtwork?(pair.episode.id) {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fill)
            }
#endif
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Local geometry/artwork injection only. Production defaults keep the real
/// image policy, loaders and layout; neither callback creates service work.
private struct PodcastRowGeometryProbeKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}
private struct PodcastRowFixtureArtworkKey: EnvironmentKey {
    static let defaultValue: ((String) -> UIImage?)? = nil
}
extension EnvironmentValues {
    var podcastRowGeometryProbe: ((String, CGRect) -> Void)? {
        get { self[PodcastRowGeometryProbeKey.self] }
        set { self[PodcastRowGeometryProbeKey.self] = newValue }
    }
    var podcastRowFixtureArtwork: ((String) -> UIImage?)? {
        get { self[PodcastRowFixtureArtworkKey.self] }
        set { self[PodcastRowFixtureArtworkKey.self] = newValue }
    }
}
#endif
