#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

@MainActor
private final class LocalResumeMetrics: ObservableObject {
    @Published var writes = 0
    @Published var storedEntries: [ReaderResumeRecord.Entry] = []
}

private final class LocalResumeMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var fail = false
    private let didWrite: @Sendable ([ReaderResumeRecord.Entry]) -> Void
    init(didWrite: @escaping @Sendable ([ReaderResumeRecord.Entry]) -> Void) { self.didWrite = didWrite }
    func read() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func setFailure(_ value: Bool) { lock.lock(); fail = value; lock.unlock() }
    func write(_ value: Data) throws {
        let record = try ReaderResumeRecord.decode(value)
        lock.lock()
        if fail { lock.unlock(); throw ReaderResumeRecord.Failure.unavailable }
        data = value
        lock.unlock()
        didWrite(record.entries)
    }
}

/// Production renderer, history binding, resume controller/store and controls.
/// Only storage/account selection is replaced by explicit in-memory fixtures.
@MainActor
private final class LocalResumeFixture: ObservableObject {
    @Published private(set) var owner = "A"
    @Published private(set) var revision = 1
    @Published private(set) var session: ReaderHistoryBinding.Session?
    @Published private(set) var presentation = UUID()
    @Published private(set) var motion = ArticleReadingMotionController()
    @Published private(set) var controller: ReaderResumeController
    @Published private(set) var inputResult = "Ingen testhandling"
    @Published private(set) var visibleParagraph = "Ikke målt"
    @Published var failWrites = false
    let history: ReadingHistoryModel
    let binding: ReaderHistoryBinding
    let metrics: LocalResumeMetrics
    private let memory: LocalResumeMemory
    private let store: ReaderResumeStore
    private var capturedInput: (@MainActor () -> Bool)?
    private var inputSequence = 0

    var prose: String {
        "<h2>En fortælling i eget tempo</h2>" + (1...24).map {
            "<p>Afsnit \($0). Revision \(revision). Byen bliver stille, mens vi følger fortællingen. En god artikel giver plads til detaljerne, til eftertanken og til at vende tilbage. Ordene skal stå roligt, også når telefonen bliver lagt væk et øjeblik.</p>"
        }.joined()
    }
    init() {
        let metrics = LocalResumeMetrics()
        self.metrics = metrics
        let memory = LocalResumeMemory(didWrite: { entries in
            Task { @MainActor in
                metrics.storedEntries = entries
                metrics.writes += 1
            }
        })
        self.memory = memory
        let store = ReaderResumeStore(storage: .init(read: { memory.read() }, write: { try memory.write($0) }))
        self.store = store
        controller = ReaderResumeController(store: store)
        history = ReadingHistoryModel(storage: .init(read: { _ in nil }, write: { _, _ in }),
            schedule: { _, _ in {} })
        binding = ReaderHistoryBinding(model: history, markRead: { _ in })
        open()
    }
    private func open() {
        history.changeContext(to: .confirmed(userID: "resume-fixture-" + owner))
        session = binding.beginArticle(articleID: "resume-fixture-article", onOpen: {}, onProgress: { _ in })
    }
    func reopen(owner next: String? = nil, changed: Bool = false) async {
        await controller.waitForPendingWork()
        controller.invalidate()
        if let session { binding.endSession(session) }
        session = nil
        if let next { owner = next }
        if changed { revision += 1 }
        motion = ArticleReadingMotionController()
        controller = ReaderResumeController(store: store)
        open()
        presentation = UUID()
    }
    func setFailure(_ value: Bool) { failWrites = value; memory.setFailure(value) }
    func input(_ label: String, action: (@MainActor () -> Bool)?) {
        inputSequence += 1
        inputResult = "\(inputSequence) · \(label): \(action?() == true ? "udført" : "afvist")"
    }
    func captureInput() {
        capturedInput = motion.userScrollAction(for: .pageForward)
        inputResult = capturedInput == nil ? "Testhandling ikke klar" : "Testhandling indfanget"
    }
    func applyCapturedInput() { input("Gammel handling", action: capturedInput) }
    func inspectParagraph() {
        motion.inspectVisibleParagraph { [weak self] value in
            self?.visibleParagraph = value ?? "Måling afvist"
        }
    }
}

struct LocalReaderResumeSmokeView: View {
    @StateObject private var fixture = LocalResumeFixture()
    var body: some View { LocalResumeContent(fixture: fixture, metrics: fixture.metrics) }
}

private struct LocalResumeContent: View {
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @ObservedObject var fixture: LocalResumeFixture
    @ObservedObject var metrics: LocalResumeMetrics
    private var storedAnchorIndex: Int? {
        guard let source = ReaderResumeIdentity(articleID: "resume-fixture-article",
            sourceRevision: "revision-\(fixture.revision)", html: fixture.prose) else { return nil }
        return metrics.storedEntries.first {
            $0.owner == fixture.history.context.namespace?.recordBinding &&
            $0.source == source
        }?.anchor.index
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .accessibilityIdentifier("resume.fixture.firebase")
                Text("Konto \(fixture.owner) · revision \(fixture.revision) · gemninger \(metrics.writes)")
                    .accessibilityIdentifier("resume.fixture.status")
                    .accessibilityValue("Gemt afsnit: \(storedAnchorIndex ?? -1)")
                HStack {
                    Button("Genåbn") { Task { await fixture.reopen() } }.accessibilityIdentifier("resume.fixture.reopen")
                    Button("Konto A") { Task { await fixture.reopen(owner: "A") } }.accessibilityIdentifier("resume.fixture.a")
                    Button("Konto B") { Task { await fixture.reopen(owner: "B") } }.accessibilityIdentifier("resume.fixture.b")
                }
                Text("Systemtekst: \(systemTextSize.isAccessibilitySize ? "tilgængelighed" : "standard")")
                    .accessibilityIdentifier("resume.fixture.textSize")
                HStack {
                    Button("Test side ↓") { fixture.input("Side frem", action: fixture.motion.userScrollAction(for: .pageForward)) }
                        .accessibilityIdentifier("resume.fixture.pageForward")
                    Button("Test linje ↓") { fixture.input("Linje frem", action: fixture.motion.userScrollAction(for: .lineForward)) }
                        .accessibilityIdentifier("resume.fixture.lineForward")
                    Button("Indfang test") { fixture.captureInput() }
                        .accessibilityIdentifier("resume.fixture.captureInput")
                }
                HStack {
                    Button("Test side ↑") { fixture.input("Side tilbage", action: fixture.motion.userScrollAction(for: .pageBackward)) }
                        .accessibilityIdentifier("resume.fixture.pageBackward")
                    Button("Test linje ↑") { fixture.input("Linje tilbage", action: fixture.motion.userScrollAction(for: .lineBackward)) }
                        .accessibilityIdentifier("resume.fixture.lineBackward")
                    Button("Test gammel") { fixture.applyCapturedInput() }
                        .accessibilityIdentifier("resume.fixture.applyCapturedInput")
                }
                Text("Programmatisk inputtest · \(fixture.inputResult)")
                    .accessibilityIdentifier("resume.fixture.inputResult")
                HStack {
                    Button("Ny tekst") { Task { await fixture.reopen(changed: true) } }.accessibilityIdentifier("resume.fixture.revision")
                    Button("Mål afsnit") { fixture.inspectParagraph() }
                        .accessibilityIdentifier("resume.fixture.inspectParagraph")
                    Button(fixture.failWrites ? "Lagring ok" : "Lagringsfejl") { fixture.setFailure(!fixture.failWrites) }
                        .accessibilityIdentifier("resume.fixture.fail")
                }
                Text(fixture.visibleParagraph)
                    .lineLimit(1)
                    .accessibilityIdentifier("resume.fixture.visibleParagraph")
            }
            .font(.caption).padding(8).dynamicTypeSize(.large)
            .buttonStyle(.bordered)
            .overlay(alignment: .bottom) { ArticleReadingProgressLine(controller: fixture.motion).frame(height: 1.5) }
            .background(Color(uiColor: .systemBackground)).zIndex(1)
            LocalResumeArticle(fixture: fixture).id(fixture.presentation)
        }
        .tint(.primary)
    }
}

private struct LocalResumeArticle: View {
    @ObservedObject var fixture: LocalResumeFixture
    @State private var height: CGFloat = 240
    @State private var ready = false
    @State private var checkingReady = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tid til at læse").font(.largeTitle.bold()).padding(.horizontal, 16)
                Text("En lokal artikel. Læs et stykke, genåbn og fortsæt selv.").padding(.horizontal, 16)
                ReaderResumeNotice(controller: fixture.controller, motion: fixture.motion).padding(.horizontal, 16)
                HTMLTextView(html: fixture.prose, articleId: "resume-fixture-article", articleRevision: "revision-\(fixture.revision)",
                    dynamicHeight: $height, readingMotion: fixture.motion,
                    onReadingProgress: { _ in markReadyWhenSettled() },
                    historyBinding: fixture.binding, historySession: fixture.session,
                    resumeController: fixture.controller, resumeOwner: fixture.history.context.namespace?.recordBinding,
                    prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
                    .frame(height: max(height, 240))
                Color.clear.frame(height: 120)
            }
            .background(ArticleReaderScrollProbe(controller: fixture.motion))
        }
        .readerScrollInput(controller: fixture.motion)
        .accessibilityIdentifier("resume.fixture.scroll")
        .overlay(alignment: .bottomTrailing) {
            if ready {
                Text("Artikel klar · konto \(fixture.owner) · revision \(fixture.revision)")
                    .padding(4)
                    .font(.caption)
                    .dynamicTypeSize(.large)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityIdentifier("resume.fixture.ready")
            }
        }
    }

    private func markReadyWhenSettled() {
        guard !ready, !checkingReady,
              fixture.motion.userScrollAction(for: .pageForward) != nil else { return }
        checkingReady = true
        let original = fixture.controller
        let presentation = fixture.presentation
        Task { @MainActor in
            await original.waitForPendingWork()
            guard fixture.controller === original, fixture.presentation == presentation else { return }
            ready = true
        }
    }
}
#endif
