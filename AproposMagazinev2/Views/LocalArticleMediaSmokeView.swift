#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import WebKit
import FirebaseCore

/// Exercises the real article CSS and coordinator with local pixels only.
@MainActor
private final class LocalArticleMediaFixture: ObservableObject {
    @Published var article = "A"
    @Published var metrics = ""
    @Published var stage = "Klar til prøve"
    let loadState = ArticleHTMLLoadState()
    private weak var web: WKWebView?
    lazy var testing = ArticleHTMLLoadTesting(onWebViewReady: { [weak self] web, _ in self?.web = web })
    private var image: String {
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='360'><rect width='600' height='360' fill='#163d5b'/><circle cx='440' cy='100' r='90' fill='#d9a665'/><path d='M0 330L210 100L410 360Z' fill='#446e6c'/><path d='M280 360L490 180L600 290V360Z' fill='#698e8b'/></svg>"
        return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
    }
    var prose: String {
        """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
        <p>Historie \(article). Et øjeblik til at se nærmere.</p>
        <figure><img id="fixture-image" alt="Lokalt prøvebillede" src="\(image)"><figcaption id="fixture-credit">Foto: Apropos · lokal prøve</figcaption></figure>
        <p id="fixture-after">Historien fortsætter her, hvor billedet giver plads til nye perspektiver.</p>
        <p>Teksten og billedets kreditering skal blive på deres plads, også når et billede ikke kan vises.</p>
        """
    }
    private let measure = """
    (() => { const image = document.querySelector('#fixture-image') || document.querySelector('.apropos-offline-media');
      const credit = document.querySelector('#fixture-credit'), after = document.querySelector('#fixture-after');
      if (!image || !credit || !after) return null;
      return JSON.stringify({slot:image.getBoundingClientRect().height,credit:credit.getBoundingClientRect().top + window.scrollY,
        after:after.getBoundingClientRect().top + window.scrollY,height:document.body.scrollHeight,
        failed:!!document.querySelector('.apropos-offline-media')}); })()
    """
    func failImage() {
        guard loadState.phase == .ready, let web else { return }
        let original = article
        Task { @MainActor [weak self, weak web] in
            guard let self, let web, self.article == original else { return }
            do {
                let before = try await web.evaluateJavaScript(self.measure) as? String ?? ""
                guard self.article == original else { return }
                self.metrics = before; self.stage = "Før billedfejl"
                // Real WebKit decoding failure, without a network request.
                _ = try await web.evaluateJavaScript("document.getElementById('fixture-image').src='data:image/png;base64,AAAA'; void 0")
                for _ in 0..<100 {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    guard self.article == original else { return }
                    let value = try await web.evaluateJavaScript(self.measure) as? String ?? ""
                    if value.contains("\"failed\":true") {
                        self.metrics = "{\"before\":\(before),\"after\":\(value)}"
                        self.stage = "Billedfejl vist"; return
                    }
                }
                self.stage = "Prøven fik ingen billedfejl"
            } catch { if self.article == original { self.stage = "Prøven kunne ikke måle" } }
        }
    }
    func showB() { article = "B"; metrics = ""; stage = "Klar til prøve" }
}

struct LocalArticleMediaSmokeView: View {
    @StateObject private var fixture = LocalArticleMediaFixture()
    var body: some View { LocalArticleMediaContent(fixture: fixture, state: fixture.loadState) }
}

private struct LocalArticleMediaContent: View {
    @ObservedObject var fixture: LocalArticleMediaFixture
    @ObservedObject var state: ArticleHTMLLoadState
    @State private var height: CGFloat = 240
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .accessibilityIdentifier("media.fixture.firebase")
                Text("\(fixture.article) · \(String(describing: state.phase)) · \(fixture.stage)")
                    .accessibilityIdentifier("media.fixture.status").accessibilityValue(fixture.metrics)
                HStack {
                    Button("Vis billedfejl", action: fixture.failImage).accessibilityIdentifier("media.fixture.fail")
                        .disabled(state.phase != .ready || fixture.stage != "Klar til prøve")
                    Button("Artikel B", action: fixture.showB).accessibilityIdentifier("media.fixture.b")
                }
            }.font(.caption).dynamicTypeSize(.large).buttonStyle(.bordered).padding(8)
            ScrollView {
                ArticleHTMLBody(html: fixture.prose, articleId: "media-\(fixture.article)", articleRevision: "1",
                    dynamicHeight: $height, loadState: state,
                    prepareHTML: { html, _ in .init(html: html, baseURL: nil) }, loadTesting: fixture.testing)
            }.accessibilityIdentifier("media.fixture.scroll")
        }.tint(.primary)
    }
}
#endif
