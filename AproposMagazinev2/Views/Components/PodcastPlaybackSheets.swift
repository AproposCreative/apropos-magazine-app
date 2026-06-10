import AVKit
import MediaPlayer
import SDWebImageSwiftUI
import SwiftUI
import UIKit

struct PodcastAudioPlayerSheet: View {
    @EnvironmentObject private var podcastPlayer: PodcastPlayerManager
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var showQueueSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    private var currentEpisode: PodcastEpisode? {
        podcastPlayer.currentEpisode
    }

    private var queueEpisodes: [PodcastEpisode] {
        let repoEpisodes = PodcastRepository.shared
            .latestPodcastPairs(from: viewModel.articles, limit: 100)
            .map(\.episode)
        if let currentEpisode {
            return [currentEpisode] + repoEpisodes.filter { $0.id != currentEpisode.id }
        }
        return repoEpisodes
    }

    private var currentArticle: Article? {
        guard let episode = currentEpisode else { return nil }
        return viewModel.articles.first { article in
            if let articleId = episode.articleId, !articleId.isEmpty {
                return article.id.caseInsensitiveCompare(articleId) == .orderedSame
            }
            if let slug = episode.articleSlug, !slug.isEmpty {
                return article.slug?.caseInsensitiveCompare(slug) == .orderedSame
            }
            return false
        }
    }

    private var progress: Double {
        guard podcastPlayer.duration > 0 else { return 0 }
        return min(max(podcastPlayer.currentTime / podcastPlayer.duration, 0), 1)
    }

    private var currentTimeLabel: String {
        formatTime(podcastPlayer.currentTime)
    }

    private var remainingTimeLabel: String {
        let remaining = max(0, podcastPlayer.duration - podcastPlayer.currentTime)
        return "-\(formatTime(remaining))"
    }

    private var playbackRateLabel: String {
        let value = podcastPlayer.playbackRate
        if floor(Double(value)) == Double(value) {
            return "\(Int(value))x"
        }
        return String(format: "%.2gx", value)
    }

    private var categoryLine: String {
        guard let currentArticle else { return "Apropos Magazine" }
        let categories = viewModel.categories(for: currentArticle)
        if categories.isEmpty {
            return "Apropos Magazine"
        }
        return categories.joined(separator: " • ")
    }

    private var authorLine: String {
        guard let currentEpisode else { return "Apropos Magazine" }
        return currentEpisode.playerSubtitleLine(
            matchingArticle: currentArticle,
            authorLookup: { viewModel.author(for: $0) }
        )
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var primaryForeground: Color {
        isDarkMode ? .white : .primary
    }

    private var secondaryForeground: Color {
        isDarkMode ? .white.opacity(0.75) : .secondary
    }

    private var tertiaryForeground: Color {
        isDarkMode ? .white.opacity(0.72) : .secondary
    }

    private var controlBackground: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.white.opacity(0.92)
    }

    private var artworkDisplayURL: URL? {
        if let episodeArtwork = currentEpisode?.artworkURL {
            return episodeArtwork
        }
        if let mobile = currentArticle?.mobileImageURL {
            return mobile
        }
        if let thumb = currentArticle?.thumbURL {
            return thumb
        }
        if let cover = currentArticle?.coverURL {
            return cover
        }
        return nil
    }

    var body: some View {
        ZStack {
            backgroundLayer
                .ignoresSafeArea()

            if let episode = currentEpisode {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.2))
                        .frame(width: 42, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    VStack(spacing: 14) {
                        artworkView(for: episode)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(categoryLine)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(secondaryForeground)
                                .textCase(.uppercase)

                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(episode.title)
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(primaryForeground)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Text(authorLine)
                                        .font(.headline.weight(.regular))
                                        .foregroundStyle(secondaryForeground)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 8)

                                Menu {
                                        if let article = currentArticle {
                                            Button("Gå til artikel") {
                                                NotificationCenter.default.post(
                                                    name: NSNotification.Name("NavigateToArticle"),
                                                    object: nil,
                                                    userInfo: ["article": article]
                                                )
                                                podcastPlayer.dismissFullPlayer()
                                            }
                                        }
                                        if let link = articleURL {
                                            Button("Kopier link") {
                                                UIPasteboard.general.string = link.absoluteString
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(primaryForeground.opacity(0.9))
                                            .frame(width: 34, height: 34)
                                            .background(controlBackground, in: Circle())
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)

                            VStack(spacing: 14) {
                                VStack(spacing: 8) {
                                    Slider(
                                        value: $sliderValue,
                                        in: 0...1,
                                        onEditingChanged: { editing in
                                            isSeeking = editing
                                            if !editing {
                                                podcastPlayer.seek(to: sliderValue * podcastPlayer.duration)
                                            }
                                        }
                                    )
                                    .tint(primaryForeground.opacity(0.95))

                                    HStack {
                                        Text(currentTimeLabel)
                                            .font(.caption)
                                            .foregroundStyle(tertiaryForeground)
                                        Spacer()
                                        Text(remainingTimeLabel)
                                            .font(.caption)
                                            .foregroundStyle(tertiaryForeground)
                                    }
                                }

                            HStack(spacing: 10) {
                                    Button {
                                        podcastPlayer.cyclePlaybackRate()
                                    } label: {
                                        Text(playbackRateLabel)
                                        .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(primaryForeground.opacity(0.95))
                                        .frame(width: 28, height: 30)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        podcastPlayer.seekBackward(seconds: 15)
                                    } label: {
                                        Image(systemName: "gobackward.15")
                                        .font(.system(size: 24, weight: .regular))
                                            .foregroundStyle(primaryForeground)
                                        .frame(width: 36, height: 36)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        podcastPlayer.togglePlayPause()
                                    } label: {
                                        Group {
                                            if podcastPlayer.isBuffering && !podcastPlayer.isPlaying {
                                                ZStack {
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.system(size: 60, weight: .regular))
                                                        .foregroundStyle(primaryForeground.opacity(0.35))
                                                    ProgressView()
                                                        .controlSize(.regular)
                                                        .tint(primaryForeground)
                                                }
                                            } else {
                                                Image(systemName: podcastPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                                    .font(.system(size: 60, weight: .regular))
                                                    .foregroundStyle(primaryForeground)
                                            }
                                        }
                                        .frame(width: 64, height: 64)
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
                                        .font(.system(size: 24, weight: .regular))
                                            .foregroundStyle(primaryForeground)
                                        .frame(width: 36, height: 36)
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        ForEach(PodcastPlayerManager.SleepTimerOption.allCases) { option in
                                            Button(option.title) {
                                                podcastPlayer.setSleepTimer(option)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "moon.zzz.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(primaryForeground.opacity(0.95))
                                        .frame(width: 28, height: 30)
                                    }
                                    .buttonStyle(.plain)
                                }
                            .frame(maxWidth: .infinity)
                                .padding(.top, 1)

                                VStack(spacing: 10) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "speaker.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(secondaryForeground)
                                            .frame(width: 18)

                                        SystemVolumeSlider(tintColor: isDarkMode ? .white : .label)
                                            .frame(height: 30)

                                        Image(systemName: "speaker.wave.3.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(secondaryForeground)
                                            .frame(width: 18)
                                    }

                                    HStack(spacing: 34) {
                                        Button {
                                            shareCurrentPodcastClip()
                                        } label: {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 19, weight: .medium))
                                                .foregroundStyle(primaryForeground.opacity(0.92))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Del podcast-klip")

                                        Image(systemName: "quote.bubble")
                                            .font(.system(size: 19, weight: .medium))
                                            .foregroundStyle(isDarkMode ? .white.opacity(0.35) : .black.opacity(0.35))
                                            .accessibilityLabel("Transskription kommer snart")

                                        AirPlayRouteButton()
                                            .frame(width: 34, height: 34)

                                        Button {
                                            showQueueSheet = true
                                        } label: {
                                            Image(systemName: "list.bullet")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundStyle(primaryForeground.opacity(0.92))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }
                }
                .onAppear {
                    sliderValue = progress
                    podcastPlayer.setQueue(episodes: queueEpisodes)
                }
                .onChange(of: queueEpisodes) { _, newQueue in
                    podcastPlayer.setQueue(episodes: newQueue)
                }
                .onChange(of: podcastPlayer.currentTime) { _, _ in
                    guard !isSeeking else { return }
                    sliderValue = progress
                }
                .onChange(of: podcastPlayer.duration) { _, _ in
                    guard !isSeeking else { return }
                    sliderValue = progress
                }
                .sheet(isPresented: $showQueueSheet) {
                    PodcastQueueSheet(
                        episodes: podcastPlayer.queue,
                        currentEpisodeID: podcastPlayer.currentEpisode?.id,
                        onTapEpisode: { episode in
                            podcastPlayer.playFromQueue(episode)
                            showQueueSheet = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showShareSheet) {
                    if !shareItems.isEmpty {
                        ActivityView(activityItems: shareItems)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private func shareCurrentPodcastClip() {
        guard let episode = currentEpisode else { return }
        Task {
            let items = await ArticleShareComposer.podcastClipShareItems(
                episode: episode,
                article: currentArticle,
                timestamp: podcastPlayer.currentTime
            )
            await MainActor.run {
                shareItems = items
                showShareSheet = true
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    isDarkMode ? Color(red: 0.13, green: 0.15, blue: 0.19) : Color(uiColor: .systemGroupedBackground),
                    isDarkMode ? Color(red: 0.07, green: 0.08, blue: 0.11) : Color(uiColor: .secondarySystemGroupedBackground),
                    isDarkMode ? Color.black : Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Keep the full-player background lightweight to avoid dropped frames.
        }
    }

    private var articleURL: URL? {
        guard let slug = currentArticle?.slug?.trimmingCharacters(in: .whitespacesAndNewlines),
              !slug.isEmpty else {
            return nil
        }
        return URL(string: "https://www.aproposmagazine.com/\(slug)")
    }

    private func artworkView(for episode: PodcastEpisode) -> some View {
        let side = min(UIScreen.main.bounds.width - 64, 320)

        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))

            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 22)

            WebImage(url: artworkDisplayURL)
                .resizable()
                .aspectRatio(contentMode: .fill)

            PodcastArtworkBrandOverlay()
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isDarkMode ? 0.35 : 0.12), radius: 24, x: 0, y: 14)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct PodcastQueueSheet: View {
    let episodes: [PodcastEpisode]
    let currentEpisodeID: String?
    let onTapEpisode: (PodcastEpisode) -> Void

    var body: some View {
        NavigationStack {
            List(episodes) { episode in
                Button {
                    onTapEpisode(episode)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 10)
                            WebImage(url: episode.artworkURL)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text(queueSubtitle(for: episode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if episode.id == currentEpisodeID {
                            Text("Afspiller")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Kø")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func queueSubtitle(for episode: PodcastEpisode) -> String {
        if let subtitle = episode.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if !episode.hosts.isEmpty {
            return episode.hosts.joined(separator: ", ")
        }
        return "Apropos Magazine"
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    let tintColor: UIColor

    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.tintColor = tintColor
        volumeView.backgroundColor = .clear
        hideRouteButton(in: volumeView)
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        uiView.tintColor = tintColor
        hideRouteButton(in: uiView)
    }

    private func hideRouteButton(in volumeView: MPVolumeView) {
        for subview in volumeView.subviews where subview is UIButton {
            subview.isHidden = true
        }
    }
}

private struct AirPlayRouteButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = colorScheme == .dark ? .white : .label
        routePicker.activeTintColor = colorScheme == .dark ? .white : .label
        routePicker.prioritizesVideoDevices = false
        routePicker.backgroundColor = .clear
        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = colorScheme == .dark ? .white : .label
        uiView.activeTintColor = colorScheme == .dark ? .white : .label
    }
}
