#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import WebKit
import FirebaseCore

private actor LocalArticlePreparationGate {
    private var held = true
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func prepare(_ input: ArticleHTMLPreparation.Input) async -> ArticleHTMLPreparation.Output? {
        if held { await withCheckedContinuation { continuations.append($0) } }
        // Deliberately return old work too: the real worker must reject it.
        return ArticleHTMLPreparation.prepare(input, cache: nil)
    }
    func release() {
        held = false
        let pending = continuations; continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private final class LocalArticleLoadingFixture: ObservableObject {
    @Published var article = "A"
    @Published var revision = 1
    let loadState = ArticleHTMLLoadState()
    let motion = ArticleReadingMotionController()
    private let gate = LocalArticlePreparationGate()
    private weak var web: WKWebView?
    private weak var coordinator: HTMLTextView.Coordinator?
    lazy var testing = ArticleHTMLLoadTesting(
        prepare: { [gate] input, _ in await gate.prepare(input) },
        timeoutNanoseconds: 60_000_000_000,
        onWebViewReady: { [weak self] web, coordinator in
            self?.web = web; self?.coordinator = coordinator
        })
    var title: String { "Historie \(article) · udgave \(revision)" }
    var prose: String {
        "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\">" +
        "<h2>\(title)</h2>" + (1...8).map {
            "<p>Afsnit \($0). Der er tid til at læse videre. Stemmerne i byen bliver stille, mens vi følger historien og finder plads til detaljerne.</p>"
        }.joined()
    }
    func release() { Task { await gate.release() } }
    func show(_ article: String) {
        self.article = article
        revision += 1
    }
    func fail(provisional: Bool) {
        guard let web, let coordinator else { return }
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData)
        if provisional {
            coordinator.webView(web, didFailProvisionalNavigation: coordinator.expectedNavigation, withError: error)
        } else {
            coordinator.webView(web, didFail: coordinator.expectedNavigation, withError: error)
        }
    }
    func terminate() {
        guard let web, let coordinator else { return }
        coordinator.webViewWebContentProcessDidTerminate(web)
    }
}

struct LocalArticleLoadingSmokeView: View {
    @StateObject private var fixture = LocalArticleLoadingFixture()
    var body: some View { LocalArticleLoadingContent(fixture: fixture, state: fixture.loadState) }
}

private struct LocalArticleLoadingContent: View {
    @ObservedObject var fixture: LocalArticleLoadingFixture
    @ObservedObject var state: ArticleHTMLLoadState
    @State private var height: CGFloat = 240
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .accessibilityIdentifier("loading.fixture.firebase")
                Text("\(fixture.title) · \(String(describing: state.phase))")
                    .accessibilityIdentifier("loading.fixture.status")
                HStack {
                    Button("Frigiv tekst", action: fixture.release).accessibilityIdentifier("loading.fixture.release")
                    Button("Artikel B") { fixture.show("B") }.accessibilityIdentifier("loading.fixture.b")
                    Button("Tilbage til A") { fixture.show("A") }.accessibilityIdentifier("loading.fixture.a")
                }
                HStack {
                    Button("Processtop", action: fixture.terminate).accessibilityIdentifier("loading.fixture.terminate")
                    Button("Navigation") { fixture.fail(provisional: false) }.accessibilityIdentifier("loading.fixture.fail")
                    Button("Tidlig fejl") { fixture.fail(provisional: true) }.accessibilityIdentifier("loading.fixture.provisional")
                }
            }
            .font(.caption).padding(8).dynamicTypeSize(.large).buttonStyle(.bordered)
            .background(Color(uiColor: .systemBackground))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tid til at læse").font(.largeTitle.bold()).padding(.horizontal, 16)
                    ArticleHTMLBody(html: fixture.prose, articleId: "loading-\(fixture.article)",
                        articleRevision: "revision-\(fixture.revision)", dynamicHeight: $height,
                        loadState: state, readingMotion: fixture.motion,
                        prepareHTML: { html, _ in .init(html: html, baseURL: nil) }, loadTesting: fixture.testing)
                }
            }
            .accessibilityIdentifier("loading.fixture.scroll")
        }
        .tint(.primary)
    }
}
#endif
