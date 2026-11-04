#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalIncomingLinkFixture: ObservableObject {
    @Published private(set) var owner = "Uafklaret"
    @Published private(set) var uiReady = false
    @Published private(set) var resolverCount = 0
    @Published private(set) var ignoredCount = 0
    @Published private(set) var article = "Ingen artikel åbnet"
    @Published private(set) var start = "Ingen lydstart modtaget"
    @Published private(set) var message: String?
    @Published private(set) var messageID: UUID?
    private var held: [IncomingLinkCoordinator.Request] = []
    private let canonicalArticle = Article(id: "fixture-article", name: "Lokal testartikel", slug: "fixture-article",
        content: "<p>Lokalt indhold.</p>", intro: "", topicID: "fixture-topic", isDraft: false,
        lastPublished: "2026-10-20T12:00:00Z", contentRevision: "fixture-revision")
    private lazy var coordinator = IncomingLinkCoordinator(onInvalidate: { [weak self] in
        self?.message = nil; self?.messageID = nil
        self?.article = "Ingen artikel åbnet"
        self?.start = "Ingen lydstart modtaget"
    }, deliver: { [weak self] request in
        self?.held.append(request)
        self?.resolverCount += 1
        // The fixture deliberately holds the original callback after cancel.
        // Its manual completion must still pass the actual coordinator gate.
        return {}
    })
    private lazy var entry = IncomingLinkEntry(disabled: false, handleGoogle: { _ in false }, accept: { [weak self] url in
        self?.coordinator.accept(url) ?? false
    })
    init() { receive(seconds: 0) }
    func select(_ uid: String) {
        coordinator.changeContext(to: .confirmed(userID: uid))
        owner = uid == "fixture-a" ? "Konto A" : "Konto B"
    }
    func ready() { uiReady = true; coordinator.setUIReady(true) }
    func receive(seconds: Int) {
        guard let url = URL(string: "aproposmagazine://article/fixture-article?t=\(seconds)") else { return }
        _ = entry.openURL(url)
    }
    func releaseOldest() {
        guard !held.isEmpty else { return }
        let original = held.removeFirst()
        defer { coordinator.complete(original.ticket) }
        guard coordinator.isCurrent(original.ticket) else { ignoredCount += 1; return }
        switch original.link {
        case .podcast(let id, let seconds):
            guard let canonical = IncomingLinkResolutionPolicy.article(identifier: id, in: [canonicalArticle], permits: { _ in true }),
                  IncomingLinkResolutionPolicy.episode(for: canonical, in: []) == nil else { return }
            article = "Artikel åbnet: \(canonical.id)"
            start = seconds.map { "Ønsket lydstart: \($0) s" } ?? "Lydstart: gemt position"
            // Canonical article is available; this inert fixture has no audio.
            // Use the production feedback surface without claiming playback.
            message = "Artiklen er åbnet, men der er ingen tilgængelig lyd til den."
            messageID = UUID()
        case .article(let id): article = "Artikel åbnet: \(id)"
        default: break
        }
    }
    func dismissMessage(id: UUID) {
        guard messageID == id else { return }
        message = nil; messageID = nil
    }
}

/// Manual memory-only ingress. This is not a WK/AVPlayer/service acceptance test.
@MainActor
struct LocalIncomingLinkSmokeView: View {
    @StateObject private var fixture = LocalIncomingLinkFixture()
    var body: some View {
        NavigationStack {
            Form {
                Section("Lokalt linkforløb") {
                    Text("Manuelle opslag i hukommelsen. Ingen afspiller eller tjenester startes.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("incoming.fixture.intro")
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("incoming.fixture.firebase")
                    Text("Aktiv læser: \(fixture.owner)").accessibilityIdentifier("incoming.fixture.owner")
                    Text(fixture.uiReady ? "UI: klar" : "UI: ikke klar").accessibilityIdentifier("incoming.fixture.readiness")
                    Button("Bekræft konto A") { fixture.select("fixture-a") }
                        .accessibilityIdentifier("incoming.fixture.accountA")
                    Button("Bekræft konto B") { fixture.select("fixture-b") }
                        .accessibilityIdentifier("incoming.fixture.accountB")
                    Button("Gør UI klar") { fixture.ready() }.accessibilityIdentifier("incoming.fixture.ready")
                }
                Section("Oprindelige callbacks") {
                    Text("Startede opslag: \(fixture.resolverCount)").accessibilityIdentifier("incoming.fixture.requests")
                    Text("Afviste gamle svar: \(fixture.ignoredCount)").accessibilityIdentifier("incoming.fixture.ignored")
                    Button("Modtag nyt link ved 45 s") { fixture.receive(seconds: 45) }.accessibilityIdentifier("incoming.fixture.latest45")
                    Button("Modtag nyt link ved 0 s") { fixture.receive(seconds: 0) }.accessibilityIdentifier("incoming.fixture.latest0")
                    Button("Aflevér ældste opslag") { fixture.releaseOldest() }.accessibilityIdentifier("incoming.fixture.release")
                }
                Section("Kun ejet resultat") {
                    Text(fixture.article).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("incoming.fixture.article")
                    Text(fixture.start).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("incoming.fixture.start")
                }
            }
            .tint(.primary)
            .accessibilityIdentifier("incoming.fixture.form")
            .navigationTitle("Lokale links")
            .navigationBarTitleDisplayMode(.inline)
        }
        .incomingLinkFeedback(message: fixture.message, messageID: fixture.messageID, dismiss: fixture.dismissMessage)
    }
}
#endif
