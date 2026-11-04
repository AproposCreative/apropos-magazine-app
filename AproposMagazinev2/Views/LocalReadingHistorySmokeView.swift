#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

@MainActor
private final class LocalReadingHistoryFixture: ObservableObject {
    @Published var failWrites = false { didSet { box.failWrites = failWrites } }
    @Published private(set) var owner = "Uafklaret"
    let model: ReadingHistoryModel
    let binding: ReaderHistoryBinding
    private let box: MemoryBox
    private var oldScroll: (@MainActor (Double) -> Void)?

    @MainActor private final class MemoryBox {
        enum Failure: Error { case write }
        var records: [String: Data] = [:]
        var scheduled: [@MainActor () -> Void] = []
        var failWrites = false
        func fire() {
            let callbacks = scheduled
            scheduled = []
            callbacks.forEach { $0() }
        }
    }

    init() {
        let box = MemoryBox()
        self.box = box
        let model = ReadingHistoryModel(storage: .init(read: { box.records[$0.storageKey] }, write: {
            if box.failWrites { throw MemoryBox.Failure.write }
            box.records[$0.storageKey] = $1
        }), schedule: { _, callback in
            box.scheduled.append(callback)
            return {} // The manual fixture may deliver an already queued old deadline.
        })
        self.model = model
        binding = ReaderHistoryBinding(model: model, markRead: { model.markRead($0) })
    }

    func select(_ value: String) {
        switch value {
        case "Konto A": model.changeContext(to: .confirmed(userID: "fixture-account-a"))
        case "Konto B": model.changeContext(to: .confirmed(userID: "fixture-account-b"))
        case "Gæst": model.changeContext(to: .guest)
        default: model.changeContext(to: .unresolved)
        }
        owner = value
    }

    func simulateDocument() {
        guard let session = binding.beginArticle(articleID: "local-article", onOpen: {}, onProgress: { _ in }),
              let document = binding.beginDocument(session, documentID: UUID().uuidString) else { return }
        binding.markDocumentReady(document)
        let scroll = binding.progressHandler(for: document)
        if owner == "Konto A", oldScroll == nil { oldScroll = scroll }
        scroll(0.45)
        box.fire()
    }

    func releaseOldScroll() { oldScroll?(0.99);box.fire() }
}

@MainActor
struct LocalReadingHistorySmokeView: View {
    @StateObject private var fixture = LocalReadingHistoryFixture()
    var body: some View { LocalReadingHistoryContent(fixture: fixture, model: fixture.model) }
}

@MainActor
private struct LocalReadingHistoryContent: View {
    @ObservedObject var fixture: LocalReadingHistoryFixture
    @ObservedObject var model: ReadingHistoryModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Historikmodel, dokumentbinding og fejlfelt er de samme som i læseren. Målinger simuleres manuelt; intet WebKit-dokument, iCloud, login eller netværk startes.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("history.fixture.firebase")
                    Text("Aktiv læser: \(fixture.owner)")
                        .accessibilityIdentifier("history.fixture.owner")
                    ForEach(["Uafklaret", "Gæst", "Konto A", "Konto B"], id: \.self) { owner in
                        Button(owner) { fixture.select(owner) }
                            .tint(.primary).foregroundStyle(.primary)
                            .accessibilityIdentifier("history.owner.\(owner)")
                    }
                }
                Section("Læsehistorik") {
                    Text(model.snapshot.progress["local-article"].map { "Målt fremdrift: \(Int(($0 * 100).rounded())) procent" } ?? "Ingen målt fremdrift")
                        .accessibilityIdentifier("history.fixture.position")
                    Text(model.snapshot.readArticleIDs.contains("local-article") ? "Artiklen står som læst" : "Artiklen er ikke i historikken")
                        .accessibilityIdentifier("history.fixture.playTitle")
                    Text(model.snapshot.state == .ready ? "Ændringen er gemt i testens hukommelseslager" : "Lagring ikke bekræftet")
                        .accessibilityIdentifier("history.fixture.storageStatus")
                    Button("Simulér nyt dokument på 45 procent") { fixture.simulateDocument() }
                        .tint(.primary).foregroundStyle(.primary)
                        .accessibilityIdentifier("history.fixture.save")
                    Button("Aflevér gammelt scroll fra A") { fixture.releaseOldScroll() }
                        .tint(.primary).foregroundStyle(.primary)
                        .accessibilityIdentifier("history.fixture.oldSave")
                    Toggle("Simulér gemmefejl", isOn: $fixture.failWrites)
                        .accessibilityIdentifier("history.fixture.failWrites")
                }
                Section { ReadingHistoryNotice(model: model) }
            }
            .accessibilityIdentifier("history.fixture.form")
            .navigationTitle("Lokal læsehistorik")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
