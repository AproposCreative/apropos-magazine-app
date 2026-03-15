import SwiftUI
import WebKit

struct TrailerView: View {
    let youtubeKey: String
    let title: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            YouTubePlayerView(videoKey: youtubeKey)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Trailer: \(title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Luk") { dismiss() }
                    }
                }
        }
    }
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; }
                html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; }
            </style>
        </head>
        <body>
            <iframe
                src="https://www.youtube.com/embed/\(videoKey)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
        
        webView.loadHTMLString(embedHTML, baseURL: nil)
    }
}
