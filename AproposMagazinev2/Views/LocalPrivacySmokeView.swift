#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

private enum LocalPrivacySmokeFailure: Error { case write }

private final class LocalPrivacySmokeStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var record: Data?
    private var failWrites = false

    func setFailure(_ enabled: Bool) {
        lock.lock();failWrites = enabled;lock.unlock()
    }
    func read() -> Data? {
        lock.lock();defer { lock.unlock() };return record
    }
    func write(_ data: Data) throws {
        lock.lock();defer { lock.unlock() }
        if failWrites { throw LocalPrivacySmokeFailure.write }
        record = data
    }
}

@MainActor
private final class LocalPrivacySmokeFixture: ObservableObject {
    @Published var failWrite = false {
        didSet { storage.setFailure(failWrite) }
    }
    private let storage: LocalPrivacySmokeStorage
    let controller: TelemetryConsentController

    init() {
        let storage = LocalPrivacySmokeStorage()
        self.storage = storage
        let model = TelemetryConsentModel(storage: .init(read: { storage.read() }, write: { try storage.write($0) }),
                                          now: { Date() }, sinks: .init(clearAnalytics: {}, clearDiagnostics: {}))
        model.changeContext(to: nil)
        model.load()
        controller = TelemetryConsentController(model: model, onChange: { _ in })
    }
}

struct LocalPrivacySmokeView: View {
    @StateObject private var fixture = LocalPrivacySmokeFixture()

    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Kontrollerne er de samme som i appen. Ingen statistik sendes, og ingen cloudrapportering eller baggrundstjeneste startes.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("privacy.firebase")
                    Text("Lokal privatlivstest klar")
                        .accessibilityIdentifier("privacy.ready")
                    Toggle("Simulér fejl ved gemning", isOn: $fixture.failWrite)
                        .accessibilityIdentifier("fixture.failWrite")
                }
                TelemetryPrivacySection(controller: fixture.controller)
            }
            .accessibilityIdentifier("privacy.form")
            .navigationTitle("Lokal privatlivstest")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
