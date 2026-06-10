import SwiftUI

struct PodcastSectionView: View {
    let pairs: [PodcastArticlePair]
    let allPairs: [PodcastArticlePair]
    let authorProvider: (Article) -> String
    let categoriesProvider: (Article) -> [String]
    let onOpenArticle: (Article) -> Void
    let onPlayEpisode: (PodcastEpisode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Podcast")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                if allPairs.count > pairs.count {
                    NavigationLink {
                        PodcastListView(
                            pairs: allPairs,
                            authorProvider: authorProvider,
                            categoriesProvider: categoriesProvider,
                            onOpenArticle: onOpenArticle,
                            onPlayEpisode: onPlayEpisode
                        )
                    } label: {
                        Text("Se alle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
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
                            pair: pair,
                            categoryText: categoriesProvider(pair.article).first ?? pair.episode.subtitle ?? "Podcast",
                            onPlay: onPlayEpisode
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            onOpenArticle(pair.article)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct PodcastListView: View {
    let pairs: [PodcastArticlePair]
    let authorProvider: (Article) -> String
    let categoriesProvider: (Article) -> [String]
    let onOpenArticle: (Article) -> Void
    let onPlayEpisode: (PodcastEpisode) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(pairs) { pair in
                    Button {
                        onOpenArticle(pair.article)
                    } label: {
                        HStack(spacing: 12) {
                            PodcastCardThumbnail(pair: pair)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.episode.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(authorProvider(pair.article))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text(categoriesProvider(pair.article).first ?? pair.episode.subtitle ?? "Podcast")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    if let duration = pair.episode.duration, !duration.isEmpty {
                                        Text("· \(duration)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer(minLength: 8)

                            Button {
                                onPlayEpisode(pair.episode)
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
                            .buttonStyle(.plain)
                            .disabled(!pair.episode.hasPlayableAudioURL)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if pair.id != pairs.last?.id {
                        Divider()
                            .padding(.leading, 90)
                    }
                }
            }
        }
        .navigationTitle("Podcast")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PodcastCardThumbnail: View {
    let pair: PodcastArticlePair

    private var artworkURL: URL? {
        pair.episode.artworkURL ?? pair.article.mobileImageURL ?? pair.article.thumbURL ?? pair.article.coverURL
    }

    var body: some View {
        ZStack {
            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 10)
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
