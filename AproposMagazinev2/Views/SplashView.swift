import SwiftUI
import AVKit

struct BootloaderView: View {
    @State private var isVideoFinished = false
    @State private var opacity: Double = 1.0
    @State private var showRootView = false

    var body: some View {
        ZStack {
            if showRootView {
                Group {
                    ContentView() // Naviger til hovedappen
                        .transition(.opacity)
                        .onAppear {
                            print("✅ ContentView er nu synlig")
                        }
                }
            } else {
                BootloaderVideoPlayerView(videoName: "Splash02", fileExtension: "mp4") {
                    print("🎬 Video færdig – forsøger at vise Root View nu")
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 1.0)) {
                            opacity = 0.0
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sekund
                        print("✅ Sætter showRootView til true")
                        showRootView = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(opacity)
                .ignoresSafeArea(.all)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.all)
        .onAppear {
            print("🚀 BootloaderView appeared")
            // Failsafe fallback-timer
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 sekunder
                if !showRootView {
                    print("⏰ Timeout – tvinger visning af rootView")
                    showRootView = true
                }
            }
        }
    }
}

struct BootloaderVideoPlayerView: UIViewControllerRepresentable {
    let videoName: String
    let fileExtension: String
    let onFinished: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = true
        
        // Fjern alle UI elementer og sikr fuld skærm
        controller.contentOverlayView?.backgroundColor = .clear
        
        // Konfigurer video til at fylde hele skærmen
        controller.videoGravity = .resizeAspectFill
        
        // Prøv først at load fra Assets.xcassets (dataset)
        if let dataAsset = NSDataAsset(name: videoName) {
            print("Loading video from Assets.xcassets dataset")
            
            // Opret midlertidig fil
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoName).\(fileExtension)")
            
            do {
                try dataAsset.data.write(to: tempURL)
                let player = AVPlayer(url: tempURL)
                controller.player = player
                
                // Konfigurer player til fuld skærm
                player.allowsExternalPlayback = false
                
                // Start afspilning automatisk
                player.play()
                
                // Lyt efter når videoen er færdig
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    onFinished()
                }
                
                return controller
            } catch {
                print("Error creating temporary file: \(error)")
            }
        }
        
        // Fallback: prøv at load fra bundle
        if let path = Bundle.main.path(forResource: videoName, ofType: fileExtension) {
            let player = AVPlayer(url: URL(fileURLWithPath: path))
            controller.player = player
            
            // Konfigurer player til fuld skærm
            player.allowsExternalPlayback = false
            
            // Start afspilning automatisk
            player.play()
            
            // Lyt efter når videoen er færdig
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                onFinished()
            }
            
            return controller
        }
        
        // Fallback: Hvis videoen ikke kan loades, gå direkte til appen
        print("⚠️ Video kunne ikke loades - går direkte til appen")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onFinished()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Sikr at videoen altid fylder hele skærmen
        uiViewController.videoGravity = .resizeAspectFill
    }
} 