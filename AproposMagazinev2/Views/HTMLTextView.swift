import SwiftUI
import WebKit

struct HTMLTextView: UIViewRepresentable {
    var html: String
    @Binding var dynamicHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "heightHandler")
        
        // Configure web view to handle media better
        webView.configuration.allowsInlineMediaPlayback = true
        webView.configuration.mediaTypesRequiringUserActionForPlayback = []
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Safety check: ensure html is not empty
        guard !html.isEmpty else {
            dynamicHeight = 100
            return
        }
        
        // Fjern alle <style>...</style> tags fra HTML
        let cleanedHTML = html.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)

        let css = """
          <style>
              body, p, div, span {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: 18px !important;
                  font-weight: 400 !important;
                  color: black !important;
                  background-color: transparent !important;
                  line-height: 1.7 !important;
                  margin: 0 !important;
                  padding: 0 !important;
              }
              img {
                  width: 100vw !important;
                  max-width: 100vw !important;
                  height: auto !important;
                  display: block;
                  margin: 0 !important;
                  margin-left: calc(-50vw + 50%) !important; /* Center the image and make it full width */
                  margin-right: calc(-50vw + 50%) !important;
                  border-radius: 0 !important;
                  padding: 0 !important;
                  box-shadow: none !important;
              }
              h1, h2, h3 {
                  font-weight: bold;
                  margin-top: 1.5em;
                  margin-bottom: 0.5em;
              }
              /* Spotify link styling */
              a[href*="spotify.com"], a[href*="open.spotify.com"] {
                  display: block !important;
                  margin: 2em 0 !important;
                  padding: 0 !important;
                  text-decoration: none !important;
                  border-radius: 12px !important;
                  overflow: hidden !important;
                  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15) !important;
                  transition: transform 0.2s ease, box-shadow 0.2s ease !important;
                  cursor: pointer !important;
                  position: relative !important;
                  z-index: 10 !important;
              }
              a[href*="spotify.com"]:hover, a[href*="open.spotify.com"]:hover {
                  transform: translateY(-2px) !important;
                  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.2) !important;
              }
              a[href*="spotify.com"]:active, a[href*="open.spotify.com"]:active {
                  transform: translateY(0) !important;
                  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15) !important;
              }
              /* Any embedded iframe or div that looks like a Spotify player */
              iframe[src*="spotify.com"], div[class*="spotify"], div[id*="spotify"] {
                  margin: 2em 0 !important;
                  border-radius: 12px !important;
                  overflow: hidden !important;
                  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15) !important;
                  display: block !important;
                  position: relative !important;
                  z-index: 10 !important;
              }
              /* Ensure all links are visible and clickable */
              a {
                  color: inherit !important;
                  text-decoration: none !important;
                  cursor: pointer !important;
              }
              /* Make sure embedded content is visible */
              embed, object, iframe {
                  display: block !important;
                  max-width: 100% !important;
                  margin: 1em 0 !important;
              }
              @media (prefers-color-scheme: dark) {
                  body, p, div, span {
                      color: white !important;
                      background-color: transparent !important;
                  }
              }
          </style>
        """

        let htmlString = """
        <html>
        <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            \(css)
        </head>
        <body>\(cleanedHTML)</body>
        </html>
        """

        // Safety check: ensure the HTML string is valid
        guard !htmlString.isEmpty else {
            dynamicHeight = 100
            return
        }
        
        uiView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLTextView

        init(_ parent: HTMLTextView) {
            self.parent = parent
        }
        
        // Handle link clicks
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // Only handle user-initiated navigation (clicks), not automatic loading
                if navigationAction.navigationType == .linkActivated {
                    // Open external links in Safari
                    if url.absoluteString.contains("spotify.com") || url.absoluteString.contains("open.spotify.com") {
                        UIApplication.shared.open(url)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            function sendHeight() {
                try {
                    var height = document.documentElement.scrollHeight;
                    if (height && height > 0) {
                        window.webkit.messageHandlers.heightHandler.postMessage(height);
                    }
                } catch (e) {
                    console.error('Error getting height:', e);
                }
            }
            function ready(fn) {
                if (document.readyState != 'loading'){
                    fn();
                } else {
                    document.addEventListener('DOMContentLoaded', fn);
                }
            }
            ready(function() {
                try {
                    var imgs = Array.from(document.images);
                    if (imgs.length === 0) {
                        sendHeight();
                    } else {
                        var loaded = 0;
                        imgs.forEach(function(img) {
                            if (img.complete) {
                                loaded++;
                            } else {
                                img.addEventListener('load', function() {
                                    loaded++;
                                    if (loaded === imgs.length) {
                                        sendHeight();
                                    }
                                });
                                img.addEventListener('error', function() {
                                    loaded++;
                                    if (loaded === imgs.length) {
                                        sendHeight();
                                    }
                                });
                            }
                        });
                        if (loaded === imgs.length) {
                            sendHeight();
                        }
                    }
                    setTimeout(sendHeight, 500);
                    setTimeout(sendHeight, 1500);
                    window.addEventListener('resize', sendHeight);
                } catch (e) {
                    console.error('Error in ready function:', e);
                }
            });
            """
            webView.evaluateJavaScript(js, completionHandler: { result, error in
                if let error = error {
                    print("JavaScript evaluation error: \(error)")
                }
            })
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Only log significant errors, not WEBP decoding issues
            if !error.localizedDescription.contains("WEBP") && !error.localizedDescription.contains("makeImagePlus") {
                print("WebView navigation failed: \(error)")
            }
            // Set a default height if navigation fails
            DispatchQueue.main.async {
                self.parent.dynamicHeight = 100
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler" {
                if let height = message.body as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.parent.dynamicHeight = height
                    }
                } else if let heightString = message.body as? String, let height = Double(heightString), height > 0 {
                    DispatchQueue.main.async {
                        self.parent.dynamicHeight = height
                    }
                }
            }
        }
    }
}
