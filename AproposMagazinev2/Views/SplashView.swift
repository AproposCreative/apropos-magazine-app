import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct BootloaderView: View {
    /// Allow the full splash clip (~5s) to play; never block on network.
    private static let maxSplashNanoseconds: UInt64 = 5_500_000_000

    @EnvironmentObject private var viewModel: ArticleViewModel
    @State private var showBootloader = true
    @State private var videoFinished = false

    /// Skip video only when we can paint Home instantly from cache,
    /// or when accessibility / notification deep-link requires it.
    private var shouldSkipBootVideo: Bool {
        UserDefaults.standard.bool(forKey: NotificationNavigation.skipBootloaderKey)
            || UIAccessibility.isReduceMotionEnabled
            || !viewModel.articles.isEmpty
    }

    var body: some View {
        ZStack {
            if showBootloader && !shouldSkipBootVideo {
                BootloaderVideoPlayerView {
                    videoFinished = true
                    tryFinishBootloader()
                }
                .transition(.opacity)
            } else if !showBootloader {
                ContentView()
                    .transition(.opacity)
            } else {
                // Reduce-motion / cache-hit path before ContentView mounts.
                Color.black
                    .ignoresSafeArea()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            viewModel.start()
            if shouldSkipBootVideo {
                videoFinished = true
                tryFinishBootloader()
            }
        }
        .onChange(of: viewModel.articles.count) { _, count in
            // Cache hydrated after start() — skip video and enter Home immediately.
            if count > 0, showBootloader, !videoFinished, shouldSkipBootVideo {
                videoFinished = true
                tryFinishBootloader()
            }
        }
        .task {
            guard !shouldSkipBootVideo else { return }
            try? await Task.sleep(nanoseconds: Self.maxSplashNanoseconds)
            videoFinished = true
            tryFinishBootloader()
        }
    }

    private func tryFinishBootloader() {
        guard showBootloader else { return }
        guard videoFinished || shouldSkipBootVideo else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            showBootloader = false
        }

        UserDefaults.standard.removeObject(forKey: NotificationNavigation.skipBootloaderKey)
    }
}

private struct BootloaderVideoPlayerView: View {
    let onComplete: () -> Void
    @StateObject private var model = BootloaderVideoModel()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if model.player == nil {
                Image("AM_logo_white 1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
            }

            if let player = model.player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
                    .opacity(model.isReadyToDisplay ? 1 : 0)
            }
        }
        .onAppear {
            model.start(onComplete: onComplete)
        }
        .onDisappear {
            model.cleanup()
        }
    }
}

@MainActor
private final class BootloaderVideoModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isReadyToDisplay = false

    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var didComplete = false
    private var onComplete: (() -> Void)?

    func start(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        guard player == nil else { return }

        Task { @MainActor in
            guard let videoURL = await Self.resolveVideoURL() else {
                completeOnce()
                return
            }

            let item = AVPlayerItem(url: videoURL)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = true
            newPlayer.actionAtItemEnd = .pause
            player = newPlayer

            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.isReadyToDisplay = true
                        self.player?.play()
                    case .failed:
                        self.completeOnce()
                    default:
                        break
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.completeOnce()
                }
            }
        }
    }

    func cleanup() {
        player?.pause()
        player = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func completeOnce() {
        guard !didComplete else { return }
        didComplete = true
        onComplete?()
    }

    private static func resolveVideoURL() async -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "Splash02", withExtension: "mp4") {
            return bundleURL
        }
        return await writeDataAssetToTempIfNeeded()
    }

    private static func writeDataAssetToTempIfNeeded() async -> URL? {
        guard let dataAsset = NSDataAsset(name: "Splash02") else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Splash02-boot.mp4")
        let data = dataAsset.data

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: tempURL, options: .atomic)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
