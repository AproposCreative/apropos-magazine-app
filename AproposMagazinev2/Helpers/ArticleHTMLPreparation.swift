import Foundation

/// Pure article preparation. UIKit state and original access are captured by
/// the renderer before this work is sent to its bounded detached worker.
enum ArticleHTMLPreparation {
    private static let queue = DispatchQueue(label: "com.aproposmagazine.article-preparation", qos: .userInitiated)
    struct Input: Sendable {
        let html: String
        let targetImageWidth: Int
        let bodyFontSize: Double
        let documentID: String
        let contentKey: String?
    }
    struct Output: Sendable {
        let html: String
        let document: String
        let baseURL: URL?
    }
    static func prepare(_ input: Input, cache: OfflineArticleImageCache?,
                        isCancelled: @Sendable () -> Bool = { false }) -> Output? {
        queue.sync {
            guard !isCancelled() else { return nil }
            let cleaned = input.html.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
            let processed = ArticleHTMLProcessor.process(cleaned, targetImageWidth: input.targetImageWidth)
            guard !isCancelled() else { return nil }
            let prepared = cache?.prepareCapturedHTML(processed, contentKey: input.contentKey) ?? (html: processed, baseURL: nil)
            guard !isCancelled() else { return nil }
            return Output(html: prepared.html,
                document: document(html: prepared.html, bodyFontSize: input.bodyFontSize, documentID: input.documentID),
                baseURL: prepared.baseURL)
        }
    }
    static func document(html: String, bodyFontSize: Double, documentID: String) -> String {
        let css = """
          <style>
              body {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: \(bodyFontSize)px !important;
                  font-weight: 400 !important;
                  color: black !important;
                  background-color: transparent !important;
                  line-height: 1.7 !important;
                  overflow-wrap: anywhere;
                  word-break: normal;
                  margin: 0 !important;
                  padding: 0 16px !important;
              }
              div, span {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: \(bodyFontSize)px !important;
                  font-weight: 400 !important;
                  color: black !important;
                  background-color: transparent !important;
                  line-height: 1.7 !important;
                  margin: 0 !important;
                  padding: 0 !important;
              }
              p {
                  font-family: -apple-system, BlinkMacSystemFont, 'San Francisco', Arial, sans-serif !important;
                  font-size: \(bodyFontSize)px !important;
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
                  height: 360px !important;
                  min-height: 360px !important;
                  object-fit: cover !important;
                  object-position: center center !important;
                  display: block;
                  margin: 0 0 0.35em 0 !important;
                  margin-left: calc(-50vw + 50%) !important;
                  margin-right: calc(-50vw + 50%) !important;
                  border-radius: 0 !important;
                  padding: 0 !important;
                  box-shadow: none !important;
                  background-color: #0a0a0a !important;
              }
              img.apropos-lazy {
                  min-height: 360px !important;
                  background-color: #f0f0f0 !important;
              }
              .apropos-offline-media {
                  width: 100vw !important;
                  max-width: 100vw !important;
                  height: 360px !important;
                  min-height: 360px !important;
                  max-height: 360px !important;
                  margin: 0 0 0.35em 0 !important;
                  margin-left: calc(-50vw + 50%) !important;
                  margin-right: calc(-50vw + 50%) !important;
                  padding: 36px 24px !important;
                  box-sizing: border-box !important;
                  display: flex !important;
                  flex-direction: column !important;
                  align-items: center !important;
                  justify-content: center !important;
                  background: #f0f0f0 !important;
              }
              .apropos-offline-media__title {
                  font-size: 0.85em !important;
                  font-weight: 600 !important;
                  line-height: 1.35 !important;
                  color: #555555 !important;
                  text-align: center !important;
                  margin: 0 !important;
              }
              h1, h2, h3 {
                  font-weight: bold;
                  margin-top: 1.5em;
                  margin-bottom: 0.5em;
                  padding: 0 !important;
              }
              .apropos-image-credit {
                  text-align: center !important;
                  margin: 0.5em auto 1.5em auto !important;
                  padding: 0 !important;
              }
              img + .apropos-image-credit,
              .apropos-offline-media + .apropos-image-credit {
                  margin-top: 0.65em !important;
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
                  margin: 0.5em auto 1.5em auto !important;
                  font-size: 12px !important;
                  color: #666666 !important;
              }
              img + figcaption,
              .apropos-offline-media + figcaption {
                  margin-top: 0.65em !important;
              }
              ul, ol, blockquote {
                  padding: 0 !important;
                  margin-left: 0 !important;
                  margin-right: 0 !important;
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
                  img.apropos-lazy {
                      background-color: #1a1a1a !important;
                  }
                  .apropos-offline-media {
                      background: #1a1a1a !important;
                  }
                  .apropos-offline-media__title {
                      color: #aaaaaa !important;
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

        return """
        <html>
        <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <meta name=\"apropos-document\" content=\"\(documentID)\">
            \(css)
        </head>
        <body>\(html)</body>
        </html>
        """

    }
}
