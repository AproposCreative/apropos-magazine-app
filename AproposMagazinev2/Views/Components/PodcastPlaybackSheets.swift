import AVKit
import MediaPlayer
import SDWebImageSwiftUI
import SwiftUI
import UIKit

/// Presentation only: preserve the configured fractional playback rate in text.
/// This does not choose a rate or create a player/session.
func podcastPlaybackRateText(_ value: Float) -> String {
    if floor(Double(value)) == Double(value) {
        return "\(Int(value))x"
    }
    return String(format: "%.3gx", value)
}

/// The timeline owns only presentation. It never advances the playback value
/// to represent indeterminate loading or forwards seek actions while loading.
struct PodcastPlayerTimeline: View {
    @Binding var value: Double
    let isLoading: Bool
    let tint: Color
    let onEditingChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var systemScenePhase
    #if DEBUG && targetEnvironment(simulator)
    var reduceMotionOverride: Bool? = nil
    var scenePhaseOverride: ScenePhase? = nil
    #endif

    private var reduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return reduceMotionOverride ?? systemReduceMotion
        #else
        return systemReduceMotion
        #endif
    }
    private var scenePhase: ScenePhase {
        #if DEBUG && targetEnvironment(simulator)
        return scenePhaseOverride ?? systemScenePhase
        #else
        return systemScenePhase
        #endif
    }

    var body: some View {
        ZStack {
            if isLoading {
                PodcastTimelineLoadingGlow(tint: tint, reduceMotion: reduceMotion, scenePhase: scenePhase)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lyden indlæses")
                    .accessibilityValue("Indlæser")
                    .accessibilityIdentifier("podcast.timeline.loading")
            } else {
                Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                    .tint(tint)
                    .accessibilityLabel("Afspilningsposition")
                    .accessibilityIdentifier("podcast.timeline.seek")
            }
        }
        .frame(minHeight: 44)
    }
}

struct PodcastPlayerPlayControl: View {
    let isLoading: Bool
    let isPlaying: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying || isLoading ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(isLoading ? "Pause indlæsning" : (isPlaying ? "Pause" : "Afspil")))
        .accessibilityIdentifier("podcast.player.playPause")
    }
}

private struct PodcastTimelineLoadingGlow: View {
    let tint: Color
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    @State private var started = Date()

    var body: some View {
        Group {
            if !reduceMotion && scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(started))
                        .truncatingRemainder(dividingBy: 2.4)
                    let fraction = min(1, elapsed / 1.8)
                    let opacity = elapsed <= 1.8 ? 1 : max(0, 1 - (elapsed - 1.8) / 0.4)
                    track(fraction: fraction, opacity: opacity)
                }
            } else {
                // No periodic schedule or pulse in reduced motion/inactive scenes.
                track(fraction: 1, opacity: 0.65)
            }
        }
        .frame(height: 24)
        .onAppear { started = Date() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { started = Date() } }
        .onChange(of: reduceMotion) { _, _ in started = Date() }
    }

    private func track(fraction: Double, opacity: Double) -> some View {
        Canvas { context, size in
            let y = (size.height - 6) / 2
            let base = Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: 6), cornerRadius: 3)
            context.fill(base, with: .color(tint.opacity(0.12)))
            let width = size.width * fraction
            guard width > 0, opacity > 0 else { return }
            let line = Path(roundedRect: CGRect(x: 0, y: y, width: width, height: 6), cornerRadius: 3)
            let light = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [tint.opacity(0.12), tint.opacity(0.4), tint.opacity(0.95)]),
                startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: width, y: y))
            context.opacity = opacity
            var halo = context
            halo.addFilter(.blur(radius: 4))
            halo.fill(line, with: light)
            context.fill(line, with: light)
        }
        .accessibilityHidden(true)
    }
}

/// Pure full-player presentation. The live wrapper retains playback, identity,
/// persistence and sharing effects; local fixtures inject inert platform slots.
struct PodcastFullPlayerPresentation<Route: View>: View {
    let title: String
    let category: String
    let author: String
    let isAINarration: Bool
    let isLoading: Bool
    let isPlaying: Bool
    @Binding var sliderValue: Double
    let currentTimeLabel: String
    let remainingTimeLabel: String
    let playbackRateLabel: String
    let onEditingChanged: (Bool) -> Void
    let onCycleRate: () -> Void
    let onBackward: () -> Void
    let onPlayPause: () -> Void
    let onForward: () -> Void
    let onSleepTimer: (PodcastPlayerManager.SleepTimerOption) -> Void
    let onShare: () -> Void
    let onQueue: () -> Void
    let onGoToArticle: (() -> Void)?
    let onCopyLink: (() -> Void)?
    let artworkImage: Image?
    let route: Route
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        ScrollView(.vertical) {
        VStack(spacing: 0) {
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.2))
                .frame(width: 42, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            VStack(spacing: 14) {
                PodcastPlayerArtworkFrame(image: artworkImage)
                    .padding(.horizontal, 20)
                    .fullPlayerMeasured("artwork")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LocalizedArticleTaxonomy(category)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("podcast.full.category")
                            .fullPlayerMeasured("category")

                        if isAINarration {
                            AINarrationBadge(style: .prominent)
                                .fixedSize()
                                .accessibilityIdentifier("podcast.full.ai")
                                .fullPlayerMeasured("ai")
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            PodcastPlayerMarqueeTitle(title: title, foreground: primaryForeground)
                                .accessibilityIdentifier("podcast.full.title")
                                .fullPlayerMeasured("title")

                            Text(author)
                                .font(.headline.weight(.regular))
                                .foregroundStyle(secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("podcast.full.author")
                                .fullPlayerMeasured("author")
                        }

                        Spacer(minLength: 8)

                        Menu {
                                if let onGoToArticle {
                                    Button("Gå til artikel", action: onGoToArticle)
                                }
                                if let onCopyLink {
                                    Button("Kopier link", action: onCopyLink)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(primaryForeground.opacity(0.9))
                                    .frame(width: 34, height: 34)
                                    .background(controlBackground, in: Circle())
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Flere muligheder")
                            .accessibilityIdentifier("podcast.full.options")
                            .fullPlayerMeasured("options")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                    VStack(spacing: 14) {
                        VStack(spacing: 8) {
                            PodcastPlayerTimeline(
                                value: $sliderValue,
                                isLoading: isLoading,
                                tint: primaryForeground.opacity(0.95),
                                onEditingChanged: onEditingChanged
                            )
                            .fullPlayerMeasured("timeline")

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
                                onCycleRate()
                            } label: {
                                Text(playbackRateLabel)
                                .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(primaryForeground.opacity(0.95))
                                .fixedSize()
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Afspilningshastighed")
                            .accessibilityValue(playbackRateLabel)
                            .accessibilityIdentifier("podcast.full.rate")
                            .fullPlayerMeasured("rate")

                            Button {
                                onBackward()
                            } label: {
                                Image(systemName: "gobackward.15")
                                .font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(primaryForeground)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("15 sekunder tilbage")
                            .accessibilityIdentifier("podcast.full.backward")
                            .fullPlayerMeasured("backward")

                            PodcastPlayerPlayControl(
                                isLoading: isLoading,
                                isPlaying: isPlaying,
                                tint: primaryForeground,
                                action: { onPlayPause() }
                            )
                            .fullPlayerMeasured("play")

                            Button {
                                onForward()
                            } label: {
                                Image(systemName: "goforward.30")
                                .font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(primaryForeground)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("30 sekunder frem")
                            .accessibilityIdentifier("podcast.full.forward")
                            .fullPlayerMeasured("forward")

                            Menu {
                                ForEach(PodcastPlayerManager.SleepTimerOption.allCases) { option in
                                    Button(LocalizedStringKey(option.title)) {
                                        onSleepTimer(option)
                                    }
                                }
                            } label: {
                                Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(primaryForeground.opacity(0.95))
                                .fixedSize()
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stopur")
                            .accessibilityIdentifier("podcast.full.sleep")
                            .fullPlayerMeasured("sleep")
                        }
                    .frame(maxWidth: .infinity)
                        .padding(.top, 1)

                        VStack(spacing: 10) {
                            HStack(spacing: 34) {
                                Button {
                                    onShare()
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(primaryForeground.opacity(0.92))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Del podcast-klip")
                                .accessibilityIdentifier("podcast.full.share")
                                .fullPlayerMeasured("share")

                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(isDarkMode ? .white.opacity(0.35) : .black.opacity(0.35))
                                    .accessibilityLabel("Transskription kommer snart")

                                route
                                    .frame(width: 44, height: 44)
                                    .accessibilityIdentifier("podcast.full.route")
                                    .fullPlayerMeasured("route")

                                Button {
                                    onQueue()
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(primaryForeground.opacity(0.92))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Afspilningskø")
                            .accessibilityIdentifier("podcast.full.queue")
                                .fullPlayerMeasured("queue")
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .fullPlayerMeasured("content")
        }
        .accessibilityIdentifier("podcast.full.scroll")
        .fullPlayerMeasured("viewport")
        .background {
            PodcastPlayerSheetBackground(image: artworkImage)
                .fullPlayerMeasured("ambient")
                .ignoresSafeArea()
        }
    }
}

/// Overflow-only motion in a fixed title viewport; accessibility gets the full
/// string once, independent of the current visual offset.
struct PodcastPlayerMarqueeTitle: View {
    let title: String
    let foreground: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.podcastTitleReduceMotionOverride) private var reduceMotionOverride
    #endif
    private var reduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return reduceMotionOverride ?? systemReduceMotion
        #else
        return systemReduceMotion
        #endif
    }
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0
    @State private var started = Date()
    @State private var visible = false
    private let font = Font.title2.weight(.bold)

    var body: some View {
        Group {
            if reduceMotion || dynamicType.isAccessibilitySize {
                Text(title).font(font).foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fullPlayerMeasured("title.glyph")
            } else {
                // This hidden sample supplies the actual Dynamic Type line height,
                // not a fixed UIKit/font-size estimate.
                Text("Ag").font(font).hidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        GeometryReader { bounds in
                            let overflow = max(0, textWidth - bounds.size.width)
                            Group {
                                if overflow > 0.5 && scenePhase == .active && visible {
                                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { clock in
                                        let travel = Double(overflow) / 24
                                        let cycle = 4 + 2 * travel
                                        let elapsed = max(0, clock.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: cycle)
                                        let offset = elapsed < 2 ? 0 : elapsed < 2 + travel ? (elapsed - 2) * 24 : elapsed < 4 + travel ? Double(overflow) : max(0, Double(overflow) - (elapsed - 4 - travel) * 24)
                                        line(width: bounds.size.width, offset: CGFloat(offset), overflow: overflow)
                                    }
                                } else {
                                    line(width: bounds.size.width, offset: 0, overflow: overflow)
                                }
                            }
                            .onChange(of: bounds.size.width) { _, _ in started = Date() }
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .onScrollVisibilityChange(threshold: 0.01) { value in visible = value; started = Date() }
        .onChange(of: title) { _, _ in started = Date() }
        .onChange(of: reduceMotion) { _, _ in started = Date() }
        .onChange(of: scenePhase) { _, _ in started = Date() }
    }

    private func line(width: CGFloat, offset: CGFloat, overflow: CGFloat) -> some View {
        Text(title).font(font).foregroundStyle(foreground)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { value in textWidth = value; started = Date() }
            .fullPlayerMeasured("title.glyph")
            .offset(x: -offset)
            .frame(width: width, alignment: .leading)
            .clipped()
            .mask {
                let edge = min(0.25, 14 / max(1, width))
                LinearGradient(stops: [
                    .init(color: offset > 0.5 ? .clear : .black, location: 0),
                    .init(color: .black, location: edge),
                    .init(color: .black, location: 1 - edge),
                    .init(color: overflow - offset > 0.5 ? .clear : .black, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .accessibilityHidden(true)
    }
}

struct PodcastAudioPlayerSheet: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject private var podcastPlayer: PodcastPlayerManager
    @ObservedObject private var podcastProgress = PodcastProgressRuntime.store
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var showQueueSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var progressIssue: String?
    @State private var progressIssueGeneration: UUID?
    @State private var frozenTitle = ""
    @State private var frozenCategory = ""
    @State private var frozenAuthor = ""
    @State private var frozenArtworkURL: URL?

    private var currentEpisode: PodcastEpisode? {
        podcastPlayer.currentEpisode
    }

    private func presentProgressIssueIfNeeded() {
        guard let message = podcastProgress.snapshot.issueMessage else {
            progressIssue = nil
            progressIssueGeneration = nil
            return
        }
        progressIssueGeneration = podcastProgress.snapshot.generation
        progressIssue = message
    }

    private func refreshFrozenDisplay(for episode: PodcastEpisode) {
        frozenTitle = episode.title
        frozenCategory = categoryLine.uppercased()
        frozenAuthor = authorLine
        frozenArtworkURL = artworkDisplayURL
    }

    private func prepareQueueIfNeeded() {
        let repoEpisodes = PodcastRepository.shared
            .latestPodcastPairs(from: viewModel.articles, limit: 100)
            .map(\.episode)
        podcastPlayer.prepareQueueIfNeeded(episodes: repoEpisodes)
    }

    private var currentArticle: Article? {
        guard let episode = currentEpisode else { return nil }
        return PodcastEpisode.matchingArticle(for: episode, in: viewModel.articles)
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
        podcastPlaybackRateText(podcastPlayer.playbackRate)
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

            if let title = podcastPlayer.offlinePreparationTitle, let id = podcastPlayer.offlinePreparationID {
                PodcastOfflinePreparationView(title: title) {
                    if podcastPlayer.cancelOfflinePreparation(id: id), podcastPlayer.currentEpisode == nil {
                        podcastPlayer.dismissFullPlayer()
                    }
                }
            } else if let episode = currentEpisode {
                ZStack {
                    WebImage(url: frozenArtworkURL ?? artworkDisplayURL, isAnimating: .constant(false)) { phase in
                        playerPresentation(for: episode, image: phase.image)
                    }
                    .id(frozenArtworkURL ?? artworkDisplayURL)
                }
                .onAppear {
                    refreshFrozenDisplay(for: episode)
                    presentProgressIssueIfNeeded()
                    sliderValue = progress
                    prepareQueueIfNeeded()
                }
                .onChange(of: currentEpisode?.id) { _, _ in
                    if let episode = currentEpisode {
                        refreshFrozenDisplay(for: episode)
                    }
                    prepareQueueIfNeeded()
                }
                .onChange(of: podcastProgress.snapshot.issueMessage) { _, _ in
                    presentProgressIssueIfNeeded()
                }
                .onChange(of: podcastProgress.snapshot.generation) { _, _ in
                    progressIssue = nil
                    progressIssueGeneration = nil
                }
                .alert("Lytteposition", isPresented: Binding(get: { progressIssue != nil }, set: {
                    if !$0 { progressIssue = nil }
                })) {
                    if podcastProgress.snapshot.canRetry {
                        Button("Prøv igen") {
                            guard progressIssueGeneration == podcastProgress.snapshot.generation else { return }
                            podcastProgress.retryStorage()
                        }
                    }
                    Button("OK", role: .cancel) { progressIssue = nil }
                } message: {
                    Text(LocalizedStringKey(progressIssue ?? ""))
                }
                .onChange(of: podcastPlayer.isBuffering) { _, buffering in
                    if buffering { isSeeking = false }
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
        let shareLanguage = AppLocalization.language(for: interfaceLocale)
        Task { @MainActor in
            shareItems = ArticleShareComposer.podcastClipShareItems(
                episode: episode,
                article: currentArticle,
                timestamp: podcastPlayer.currentTime,
                language: shareLanguage
            )
            showShareSheet = true
        }
    }

    private var backgroundLayer: some View { PodcastPlayerSheetBackground() }

    private var articleURL: URL? {
        guard let slug = currentArticle?.slug?.trimmingCharacters(in: .whitespacesAndNewlines),
              !slug.isEmpty else {
            return nil
        }
        return URL(string: "https://www.aproposmagazine.com/\(slug)")
    }

    private func playerPresentation(for episode: PodcastEpisode, image: Image?) -> some View {
                PodcastFullPlayerPresentation(
                    title: frozenTitle.isEmpty ? episode.title : frozenTitle,
                    category: frozenCategory.isEmpty ? categoryLine.uppercased() : frozenCategory,
                    author: frozenAuthor.isEmpty ? authorLine : frozenAuthor,
                    isAINarration: episode.isAINarration,
                    isLoading: podcastPlayer.isBuffering && !podcastPlayer.isPlaying,
                    isPlaying: podcastPlayer.isPlaying,
                    sliderValue: $sliderValue,
                    currentTimeLabel: currentTimeLabel,
                    remainingTimeLabel: remainingTimeLabel,
                    playbackRateLabel: playbackRateLabel,
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing && !(podcastPlayer.isBuffering && !podcastPlayer.isPlaying) {
                            podcastPlayer.seek(to: sliderValue * podcastPlayer.duration)
                        }
                    },
                    onCycleRate: { podcastPlayer.cyclePlaybackRate() },
                    onBackward: { podcastPlayer.seekBackward(seconds: 15) },
                    onPlayPause: { podcastPlayer.togglePlayPause() },
                    onForward: { podcastPlayer.seekForward(seconds: 30) },
                    onSleepTimer: { podcastPlayer.setSleepTimer($0) },
                    onShare: shareCurrentPodcastClip,
                    onQueue: { showQueueSheet = true },
                    onGoToArticle: currentArticle.map { article in {
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToArticle"),
                            object: nil, userInfo: ["article": article])
                        podcastPlayer.dismissFullPlayer()
                    } },
                    onCopyLink: articleURL.map { link in { UIPasteboard.general.string = link.absoluteString } },
                    artworkImage: image,
                    route: AirPlayRouteButton()
                )
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

struct PodcastPlayerSheetBackground: View {
    var image: Image? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }
    var body: some View {
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

            if let image, !reduceTransparency {
                GeometryReader { bounds in
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                        .scaleEffect(1.12)
                        .blur(radius: 48)
                        .saturation(1.3)
                    LinearGradient(colors: isDarkMode
                        ? [.black.opacity(0.36), .black.opacity(0.52), .black.opacity(0.70)]
                        : [.white.opacity(0.52), .white.opacity(0.68), .white.opacity(0.84)],
                        startPoint: .top, endPoint: .bottom)
                }
                .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PodcastPlayerArtworkFrame: View {
    let image: Image?
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 0)
            if let image {
                GeometryReader { bounds in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                }
            }
            PodcastArtworkBrandOverlay()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("podcast.full.artwork")
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct PodcastTitleReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}
extension EnvironmentValues {
    var podcastTitleReduceMotionOverride: Bool? {
        get { self[PodcastTitleReduceMotionOverrideKey.self] }
        set { self[PodcastTitleReduceMotionOverrideKey.self] = newValue }
    }
}
private struct FullPlayerGeometryProbeKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}
extension EnvironmentValues {
    var fullPlayerGeometryProbe: ((String, CGRect) -> Void)? {
        get { self[FullPlayerGeometryProbeKey.self] }
        set { self[FullPlayerGeometryProbeKey.self] = newValue }
    }
}
#endif

private struct FullPlayerFrameProbe: ViewModifier {
    let key: String
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.fullPlayerGeometryProbe) private var probe
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { probe?(key, $0) }
        #else
        content
        #endif
    }
}
private extension View {
    func fullPlayerMeasured(_ key: String) -> some View { modifier(FullPlayerFrameProbe(key: key)) }
}

struct PodcastQueueSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                            Text(queueSubtitle(for: episode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                            if dynamicTypeSize.isAccessibilitySize && episode.id == currentEpisodeID {
                                nowPlayingBadge
                                    .padding(.top, 4)
                            }
                        }

                        Spacer()

                        if !dynamicTypeSize.isAccessibilitySize && episode.id == currentEpisodeID {
                            nowPlayingBadge
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("podcast.queue.episode.\(episode.id)")
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("podcast.queue.list")
            .navigationTitle("Kø")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var nowPlayingBadge: some View {
        Text("Afspiller")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("podcast.queue.nowPlaying")
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
