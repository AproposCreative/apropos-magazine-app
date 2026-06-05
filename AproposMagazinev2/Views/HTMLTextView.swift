import SwiftUI
import WebKit

struct HTMLTextView: UIViewRepresentable {
    var html: String
    var articleId: String? = nil
    @Binding var dynamicHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "heightHandler")
        
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
        let sanitizedHTML = ArticleHTMLProcessor.process(cleanedHTML)
        let offlinePrepared = OfflineArticleImageCache.shared.prepareHTMLForOfflineDisplay(
            sanitizedHTML,
            articleId: articleId
        )
        let displayHTML = offlinePrepared.html
        let offlineBaseURL = offlinePrepared.baseURL

        let css = """
          <style>
              body, div, span {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: 18px !important;
                  font-weight: 400 !important;
                  color: black !important;
                  background-color: transparent !important;
                  line-height: 1.7 !important;
                  margin: 0 !important;
                  padding: 0 !important;
              }
              p {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: 18px !important;
                  font-weight: 400 !important;
                  color: black !important;
                  background-color: transparent !important;
                  line-height: 1.7 !important;
                  margin: 0 0 1.25em 0 !important;
                  padding: 0 !important;
              }
              p:last-child,
              p:last-of-type {
                  margin-bottom: 0 !important;
              }
              .apropos-image-credit:last-child,
              .apropos-image-credit:last-of-type,
              figcaption:last-child,
              figcaption:last-of-type {
                  margin-bottom: 0 !important;
              }
              img {
                  width: 100vw !important;
                  max-width: 100vw !important;
                  height: auto !important;
                  display: block;
                  margin: 0 !important;
                  margin-left: calc(-50vw + 50%) !important;
                  margin-right: calc(-50vw + 50%) !important;
                  border-radius: 0 !important;
                  padding: 0 !important;
                  box-shadow: none !important;
                  background-color: #0a0a0a !important;
              }
              .apropos-offline-media {
                  width: 100vw !important;
                  max-width: 100vw !important;
                  min-height: 200px !important;
                  margin: 0 !important;
                  margin-left: calc(-50vw + 50%) !important;
                  margin-right: calc(-50vw + 50%) !important;
                  padding: 36px 24px !important;
                  box-sizing: border-box !important;
                  display: flex !important;
                  flex-direction: column !important;
                  align-items: center !important;
                  justify-content: center !important;
                  gap: 8px !important;
                  background: #0a0a0a !important;
                  border: 1px solid rgba(255, 255, 255, 0.14) !important;
                  box-shadow: 0 0 24px rgba(255, 255, 255, 0.04) inset !important;
              }
              .apropos-offline-media__title {
                  font-size: 13px !important;
                  font-weight: 600 !important;
                  line-height: 1.35 !important;
                  color: rgba(255, 255, 255, 0.72) !important;
                  text-align: center !important;
                  text-shadow: 0 0 12px rgba(255, 255, 255, 0.28) !important;
                  margin: 0 !important;
              }
              .apropos-offline-media__subtitle {
                  font-size: 12px !important;
                  font-weight: 400 !important;
                  line-height: 1.4 !important;
                  color: rgba(255, 255, 255, 0.42) !important;
                  text-align: center !important;
                  text-shadow: 0 0 10px rgba(255, 255, 255, 0.16) !important;
                  margin: 0 !important;
              }
              h1, h2, h3 {
                  font-weight: bold;
                  margin-top: 1.5em;
                  margin-bottom: 0.5em;
              }
              .apropos-image-credit {
                  text-align: center !important;
                  margin: -0.25em auto 1.5em auto !important;
                  padding: 0 !important;
              }
              .apropos-image-credit span {
                  display: inline-block !important;
                  font-size: 12px !important;
                  line-height: 1.3 !important;
                  color: #666666 !important;
                  background: rgba(0, 0, 0, 0.06) !important;
                  padding: 4px 12px !important;
                  border-radius: 999px !important;
              }
              figcaption {
                  text-align: center !important;
                  margin: -0.25em auto 1.5em auto !important;
                  font-size: 12px !important;
                  color: #666666 !important;
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
                  img {
                      background-color: #0a0a0a !important;
                  }
                  .apropos-offline-media {
                      background: #0a0a0a !important;
                      border-color: rgba(255, 255, 255, 0.14) !important;
                  }
                  .apropos-image-credit span {
                      color: #aaaaaa !important;
                      background: rgba(255, 255, 255, 0.1) !important;
                  }
                  figcaption {
                      color: #aaaaaa !important;
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
        <body>\(displayHTML)</body>
        </html>
        """

        // Safety check: ensure the HTML string is valid
        guard !htmlString.isEmpty else {
            dynamicHeight = 100
            return
        }

        let cacheKey = "\(articleId ?? "")|\(htmlString)"
        // Critical perf guard: avoid reloading identical HTML on every parent state update.
        if FeatureFlags.htmlDiffGuardEnabled && context.coordinator.lastLoadedHTML == cacheKey {
            return
        }
        context.coordinator.lastLoadedHTML = cacheKey
        uiView.loadHTMLString(htmlString, baseURL: offlineBaseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLTextView
        var lastLoadedHTML: String?

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
                    var body = document.body;
                    var height = body ? body.scrollHeight : document.documentElement.scrollHeight;
                    if (body && body.lastElementChild) {
                        var lastRect = body.lastElementChild.getBoundingClientRect();
                        var bodyRect = body.getBoundingClientRect();
                        var contentBottom = lastRect.bottom - bodyRect.top;
                        if (contentBottom > 0) {
                            height = Math.ceil(contentBottom);
                        }
                    }
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
            function replaceBrokenImage(img) {
                if (!img || img.dataset.approposOfflineHandled === '1') return;
                img.dataset.approposOfflineHandled = '1';
                var box = document.createElement('div');
                box.className = 'apropos-offline-media';
                box.innerHTML = '<p class="apropos-offline-media__title">Medie offline</p><p class="apropos-offline-media__subtitle">Tjek din internetforbindelse</p>';
                if (img.parentNode) {
                    img.parentNode.replaceChild(box, img);
                }
                sendHeight();
            }
            function attachOfflineFallbacks() {
                try {
                    var imgs = Array.from(document.images);
                    imgs.forEach(function(img) {
                        if (img.dataset.approposOfflineHandled === '1') return;
                        if (img.complete && img.naturalWidth === 0) {
                            replaceBrokenImage(img);
                            return;
                        }
                        img.addEventListener('error', function() {
                            replaceBrokenImage(img);
                        });
                    });
                } catch (e) {
                    console.error('Error attaching offline fallbacks:', e);
                }
            }
            ready(function() {
                try {
                    attachOfflineFallbacks();
                    var imgs = Array.from(document.images);
                    if (imgs.length === 0) {
                        sendHeight();
                    } else {
                        var loaded = 0;
                        imgs.forEach(function(img) {
                            if (img.dataset.approposOfflineHandled === '1') {
                                loaded++;
                                return;
                            }
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
                    setTimeout(function() {
                        attachOfflineFallbacks();
                        sendHeight();
                    }, 500);
                    setTimeout(function() {
                        attachOfflineFallbacks();
                        sendHeight();
                    }, 1500);
                    window.addEventListener('resize', sendHeight);
                } catch (e) {
                    console.error('Error in ready function:', e);
                }
            });
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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
