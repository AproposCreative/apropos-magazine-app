import SDWebImageSwiftUI
import SwiftUI
import UIKit

enum PodcastMiniPlayerLayout {
    static let barHeight: CGFloat = 56
    static let contentGap: CGFloat = 20
    static let bottomOffset: CGFloat = 88

    /// Same dimensions reserve feed/reader space and size the visible surface.
    /// UIKit line heights follow the SwiftUI environment, including previews and
    /// accessibility sizes; normal text retains the owner's 56-point layout.
    static func height(for size: DynamicTypeSize) -> CGFloat {
        let category: UIContentSizeCategory
        switch size {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let title = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).lineHeight
        let subtitle = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).lineHeight
        let badge = UIFont.systemFont(ofSize: 10, weight: .semibold).lineHeight + 4
        return max(barHeight, ceil(title + max(subtitle, badge) + 2 + 12))
    }

    static func topEdge(containerBottom: CGFloat, for size: DynamicTypeSize,
                        bottomOffset: CGFloat = PodcastMiniPlayerLayout.bottomOffset) -> CGFloat {
        containerBottom - bottomOffset - height(for: size)
    }

    static func scrollBottomInset(for size: DynamicTypeSize) -> CGFloat {
        height(for: size) + contentGap
    }

    static func articleBottomPadding(isPlayerVisible: Bool, size: DynamicTypeSize) -> CGFloat {
        isPlayerVisible ? scrollBottomInset(for: size) + 40 : 2
    }

    static func feedBottomPadding(isPlayerVisible: Bool, size: DynamicTypeSize) -> CGFloat {
        isPlayerVisible ? scrollBottomInset(for: size) + 8 : 56
    }
}

/// The existing root's space reservation, shared with service-free tab fixtures.
struct PodcastMiniPlayerReservation: ViewModifier {
    let isVisible: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if isVisible {
                Color.clear.frame(height: PodcastMiniPlayerLayout.scrollBottomInset(for: dynamicTypeSize))
            }
        }
    }
}

private struct PodcastMiniPlayerTopEdgeKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct PodcastMiniPlayerBottomOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = PodcastMiniPlayerLayout.bottomOffset
}

private struct PodcastMiniPlayerMaximumWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    var podcastMiniPlayerBottomOffset: CGFloat {
        get { self[PodcastMiniPlayerBottomOffsetKey.self] }
        set { self[PodcastMiniPlayerBottomOffsetKey.self] = newValue }
    }

    var podcastMiniPlayerMaximumWidth: CGFloat {
        get { self[PodcastMiniPlayerMaximumWidthKey.self] }
        set { self[PodcastMiniPlayerMaximumWidthKey.self] = newValue }
    }
    /// Fixed-height active player's top in root-local vertical layout; nil
    /// means there is no active player to reserve space for.
    var podcastMiniPlayerTopEdge: CGFloat? {
        get { self[PodcastMiniPlayerTopEdgeKey.self] }
        set { self[PodcastMiniPlayerTopEdgeKey.self] = newValue }
    }
}


/// Reserve scroll content from intrinsic viewport metrics, without depending on
/// a hosting view's window origin during native navigation.
struct PodcastMiniPlayerScrollClearance<ScrollContent: View>: View {
    private let existingBottomPadding: CGFloat
    private let makeScrollContent: (CGFloat) -> ScrollContent
    @Environment(\.podcastMiniPlayerTopEdge) private var playerTop

    init(existingBottomPadding: CGFloat = 0,
         @ViewBuilder content: @escaping (CGFloat) -> ScrollContent) {
        self.existingBottomPadding = existingBottomPadding
        self.makeScrollContent = content
    }

    var body: some View {
        GeometryReader { viewport in
            // The proposal excludes the navigation chrome above the content;
            // adding its inherited top inset reconstructs the host-local bottom.
            let usableBottom = viewport.size.height + viewport.safeAreaInsets.top
            let clearance = playerTop.map {
                max(0, usableBottom - $0 + PodcastMiniPlayerLayout.contentGap - existingBottomPadding)
            } ?? 0
            makeScrollContent(clearance)
        }
    }
}

/// Keep placement before the caller's existing z-index and transition.
struct PodcastMiniPlayerPlacement: ViewModifier {
    @Environment(\.podcastMiniPlayerBottomOffset) private var bottomOffset
    @Environment(\.podcastMiniPlayerMaximumWidth) private var maximumWidth
    func body(content: Content) -> some View {
        content.frame(maxWidth: maximumWidth).padding(.horizontal, 24).padding(.bottom, bottomOffset)
    }
}

struct PodcastMiniPlayerBar: View {
    @EnvironmentObject private var podcastPlayer: PodcastPlayerManager
    @EnvironmentObject private var viewModel: ArticleViewModel
    private var subtitleText: String {
        guard let episode = podcastPlayer.currentEpisode else { return "" }
        let article = PodcastEpisode.matchingArticle(for: episode, in: viewModel.articles)
        return episode.playerSubtitleLine(matchingArticle: article) { viewModel.author(for: $0) }
    }

    var body: some View {
        if let episode = podcastPlayer.currentEpisode {
            PodcastMiniPlayerContent(
                title: episode.title, subtitle: subtitleText, artworkURL: episode.artworkURL,
                isAINarration: episode.isAINarration, isBuffering: podcastPlayer.isBuffering,
                isPlaying: podcastPlayer.isPlaying, progress: podcastPlayer.progress,
                togglePlayPause: { podcastPlayer.togglePlayPause() },
                seekForward: { podcastPlayer.seekForward(seconds: 30) },
                openPlayer: { podcastPlayer.openFullPlayer() },
                closePlayer: { podcastPlayer.closePlayer() }
            )
        }
    }
}

/// iPad keeps the accepted glyphs, with independent native touch targets.
private struct PodcastMiniPlayerControlTarget: ViewModifier {
    let compactDimension: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.frame(width: 44, height: 44).contentShape(Rectangle())
        } else {
            content.frame(width: compactDimension, height: compactDimension)
        }
    }
}

/// The real player surface accepts presentation and actions without constructing
/// AVPlayer or service singletons. Local interaction checks use this same view.
struct PodcastMiniPlayerContent: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let isAINarration: Bool
    let isBuffering: Bool
    let isPlaying: Bool
    let progress: Double
    let togglePlayPause: () -> Void
    let seekForward: () -> Void
    let openPlayer: () -> Void
    let closePlayer: () -> Void
    var reduceMotionOverride: Bool? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var isPressed = false
    @State private var dragOffset: CGFloat = 0
    
    private var backgroundTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.18)
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.9)
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.66)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ArticleImagePlaceholder(showShimmer: false, cornerRadius: 9)
                WebImage(url: artworkURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 39, height: 39)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Button(action: openWithFeedback) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("podcast.mini.title")
                .accessibilityAction(named: "Luk afspiller") { dismissPlayer() }

                HStack(spacing: 6) {
                    if isAINarration {
                        AINarrationBadge(style: .compact)
                    }
                    Text(subtitle)
                        .accessibilityIdentifier("podcast.mini.subtitle")
                        .font(.caption2)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            Button {
                togglePlayPause()
            } label: {
                Group {
                    if isBuffering && !isPlaying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(primaryForeground)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primaryForeground)
                    }
                }
                .modifier(PodcastMiniPlayerControlTarget(compactDimension: 24))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("podcast.mini.playPause")
            .accessibilityLabel(
                isBuffering && !isPlaying
                    ? "Indlæser lyd"
                    : (isPlaying ? "Pause" : "Afspil")
            )

            Button {
                seekForward()
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryForeground)
                    .modifier(PodcastMiniPlayerControlTarget(compactDimension: 22))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Spol 30 sekunder frem")
            .accessibilityIdentifier("podcast.mini.forward")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(height: PodcastMiniPlayerLayout.height(for: dynamicTypeSize))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(backgroundTint)
        )
        .overlay {
            GeometryReader { proxy in
                let horizontalInset: CGFloat = 16
                let trackWidth = max(0, proxy.size.width - horizontalInset * 2)
                Capsule()
                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(colorScheme == .dark ? 0.45 : 0.38))
                    .frame(width: trackWidth * progress, height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, horizontalInset)
                    .padding(.bottom, 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.14), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.12), radius: 6, x: 0, y: 1)
        .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
        .offset(y: dragOffset)
        .opacity(1 - min(dragOffset / 160, 0.65))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { openWithFeedback() }
        // A recognized drag consumes the touch; releasing it must not also
        // activate the title/artwork action underneath. Short taps remain buttons.
        .highPriorityGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    // Only follow downward swipes so the bar can be flicked away.
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    let shouldDismiss = value.translation.height > 70
                        || value.predictedEndTranslation.height > 160
                    if shouldDismiss {
                        withAnimation(AppMotion.playerSpring(response: 0.42, damping: 0.86, reduceMotion: reduceMotion)) {
                            closePlayer()
                        }
                        dragOffset = 0
                    } else {
                        withAnimation(AppMotion.playerSpring(response: 0.3, damping: 0.82, reduceMotion: reduceMotion)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("podcast.mini.surface")
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { isPressed = false }
        }
        .accessibilityAction(named: "Luk afspiller") {
            dismissPlayer()
        }
    }

    private func openWithFeedback() {
        if !reduceMotion {
            withAnimation(AppMotion.playerSpring(response: 0.28, damping: 0.72, reduceMotion: reduceMotion)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(AppMotion.playerSpring(response: 0.34, damping: 0.82, reduceMotion: reduceMotion)) {
                    isPressed = false
                }
            }
        }
        openPlayer()
    }

    private func dismissPlayer() {
        withAnimation(AppMotion.playerSpring(response: 0.42, damping: 0.86, reduceMotion: reduceMotion)) {
            closePlayer()
        }
    }
}
