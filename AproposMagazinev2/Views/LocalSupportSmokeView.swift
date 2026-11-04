#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

/// In-memory effects only. This fixture never opens Mail or uses the clipboard.
@MainActor
private final class LocalSupportSmokePlatform: ObservableObject {
    @Published var openFails = true
    @Published var canCompose = false
    @Published private(set) var openCount = 0
    @Published private(set) var copyCount = 0
    @Published private(set) var copiedText: String?

    func open(_ completion: SupportContactModel.Completion) {
        openCount += 1
        completion(!openFails)
    }

    func copy(_ text: String) -> Bool {
        copiedText = text
        copyCount += 1
        return true
    }
}

@MainActor
private final class LocalSupportSmokeFixture: ObservableObject {
    let platform: LocalSupportSmokePlatform
    let model: SupportContactModel

    init() {
        let platform = LocalSupportSmokePlatform()
        self.platform = platform
        model = SupportContactModel(canCompose: { platform.canCompose }, openURL: { _, completion in
            platform.open(completion)
        }, copy: { platform.copy($0) }, schedule: { _, _ in
            // Deadlines are inert: simulated handoffs finish synchronously and
            // composer results are explicit fixture button actions.
            return {}
        })
    }
}

@MainActor
struct LocalSupportSmokeView: View {
    @StateObject private var fixture = LocalSupportSmokeFixture()

    var body: some View {
        LocalSupportSmokeContent(platform: fixture.platform, model: fixture.model)
    }
}

@MainActor
private struct LocalSupportSmokeContent: View {
    @ObservedObject var platform: LocalSupportSmokePlatform
    @ObservedObject var model: SupportContactModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Kontrollerne er de samme som i appen. Mail og kopiering simuleres i hukommelsen; ingen besked sendes, og ingen systemudklipsholder ændres.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("support.fixture.firebase")
                    Text("Lokal supporttest klar")
                        .accessibilityIdentifier("support.fixture.ready")
                    Toggle("Simulér fejl ved åbning", isOn: $platform.openFails)
                        .accessibilityIdentifier("fixture.support.openFails")
                    Toggle("Simulér indbygget mailkladde", isOn: $platform.canCompose)
                        .accessibilityIdentifier("fixture.support.canCompose")
                    Text("Mail-app-åbninger: \(platform.openCount)")
                        .accessibilityIdentifier("support.fixture.openCount")
                    Text("Kopieringer i hukommelsen: \(platform.copyCount)")
                        .accessibilityIdentifier("support.fixture.copyCount")
                    Text(platform.copiedText == model.message && SupportContactPolicy.isMeaningfulMessage(model.message)
                         ? "Kopieret tekst matcher hele beskeden" : "Ingen kopi af den aktuelle besked")
                        .accessibilityIdentifier("support.fixture.copyResult")
                }

                SupportContactSections(model: model)

                if let draft = model.presentation {
                    Section("Simuleret mailkladde") {
                        Text("Ingen systemkladde åbnes. Disse knapper leverer kun et lokalt testresultat.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Simulér Afbryd") { model.finishComposer(id: draft.id, result: .cancelled) }
                            .accessibilityIdentifier("support.fixture.cancelComposer")
                            .tint(.primary)
                            .foregroundStyle(.primary)
                        Button("Simulér Send til Mail") { model.finishComposer(id: draft.id, result: .sent) }
                            .accessibilityIdentifier("support.fixture.sentComposer")
                            .tint(.primary)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .accessibilityIdentifier("support.fixture.form")
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Lokal supporttest")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
