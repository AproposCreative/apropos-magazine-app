import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoName: String
    let videoExtension: String
    let shouldLoop: Bool
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    init(videoName: String, videoExtension: String, shouldLoop: Bool = true) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.shouldLoop = shouldLoop
    }
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .onAppear {
                        print("VideoPlayer appeared - starting playback")
                        player.play()
                    }
                    .onDisappear {
                        print("VideoPlayer disappeared - pausing playback")
                        player.pause()
                    }
            } else if let errorMessage = errorMessage {
                // Show error state
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Video Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea(.all)
            } else {
                // Loading state
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading video...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea(.all)
            }
        }
        .onAppear {
            setupPlayer()
        }
    }
    
    private func setupPlayer() {
        print("Setting up video player for: \(videoName)")
        
        // First try to load from Assets.xcassets (dataset) - this is faster
        if let dataAsset = NSDataAsset(name: videoName) {
            print("Found video in Assets.xcassets dataset")
            
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoName).\(videoExtension)")
            
            do {
                try dataAsset.data.write(to: tempURL)
                print("Temporary video file created at: \(tempURL)")
                
                player = AVPlayer(url: tempURL)
                setupVideoLoop()
                
                // Preload video for immediate playback
                player?.currentItem?.preferredForwardBufferDuration = 1.0
                player?.automaticallyWaitsToMinimizeStalling = false
                
                return
            } catch {
                print("Error creating temporary file: \(error)")
                errorMessage = "Error creating temporary file: \(error.localizedDescription)"
                return
            }
        }
        
        // Fallback: try to load from bundle
        print("Video not found in Assets.xcassets, trying bundle...")
        
        guard let path = Bundle.main.path(forResource: videoName, ofType: videoExtension) else {
            let error = "Video file not found in bundle or Assets: \(videoName).\(videoExtension)"
            print(error)
            errorMessage = error
            return
        }
        
        print("Video file found at path: \(path)")
        
        let url = URL(fileURLWithPath: path)
        player = AVPlayer(url: url)
        
        // Preload video for immediate playback
        player?.currentItem?.preferredForwardBufferDuration = 1.0
        player?.automaticallyWaitsToMinimizeStalling = false
        
        setupVideoLoop()
        print("Video player setup complete")
    }
    
    private func setupVideoLoop() {
        // Only loop if shouldLoop is true
        if shouldLoop {
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                print("Video ended - looping")
                player?.seek(to: .zero)
                player?.play()
            }
        } else {
            // For non-looping videos, just post notification when finished
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                print("Video ended - not looping")
                // Notification will be handled by SplashView
            }
        }
    }
}

#Preview {
    VideoPlayerView(videoName: "Splash02", videoExtension: "mp4", shouldLoop: false)
}
