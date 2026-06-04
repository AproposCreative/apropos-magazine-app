import SwiftUI
import AVKit
import UIKit

struct BootloaderView: View {
    @EnvironmentObject private var viewModel: ArticleViewModel
    @State private var showBootloader = true
    @State private var videoFinished = false

    var body: some View {
        ZStack {
            if showBootloader && !UIAccessibility.isReduceMotionEnabled {
                BootloaderVideoPlayerView {
                    videoFinished = true
                    tryFinishBootloader()
                }
                .transition(.opacity)
            } else if !showBootloader {
                ContentView()
                    .transition(.opacity)
            } else {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            viewModel.start()
            if UIAccessibility.isReduceMotionEnabled {
                videoFinished = true
                tryFinishBootloader()
            }
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            tryFinishBootloader()
        }
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            videoFinished = true
            tryFinishBootloader()
        }
    }

    private func tryFinishBootloader() {
        guard showBootloader else { return }
        guard videoFinished else { return }
        guard !viewModel.isLoading else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            showBootloader = false
        }
    }
}

private struct BootloaderVideoPlayerView: View {
    let onComplete: () -> Void
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var didComplete = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if player == nil {
                Image("AM_logo_white 1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
            }

            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear(perform: prepareAndPlay)
        .onDisappear(perform: cleanup)
    }

    private func prepareAndPlay() {
        guard player == nil else { return }

        guard let videoURL = Self.bundleVideoURL() ?? Self.assetVideoURL() else {
            completeOnce()
            return
        }

        let item = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            completeOnce()
        }

        newPlayer.play()
    }

    private func cleanup() {
        player?.pause()
        player = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func completeOnce() {
        guard !didComplete else { return }
        didComplete = true
        onComplete()
    }

    private static func bundleVideoURL() -> URL? {
        Bundle.main.url(forResource: "Splash02", withExtension: "mp4")
    }

    private static func assetVideoURL() -> URL? {
        guard let dataAsset = NSDataAsset(name: "Splash02") else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Splash02.mp4")

        if FileManager.default.fileExists(atPath: tempURL.path) {
            return tempURL
        }

        do {
            try dataAsset.data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
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
