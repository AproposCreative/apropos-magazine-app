#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

/// Uses the exact account form shipped in LoginSheetView, with no service singletons.
/// A fixture response is deliberately labelled; it never establishes a real account.
@MainActor
private final class LocalAccountSmokeFixture: ObservableObject {
    @Published var failNext = false
    @Published private(set) var requests = 0
    @Published private(set) var lastOperation = "Ingen testkald"
    lazy var form = EmailAccountFlowModel { [weak self] action, fields in
        guard let self else { throw CancellationError() }
        requests += 1
        lastOperation = action == .signUp ? "Oprettelse" : action == .signIn ? "Login" : "Nulstilling"
        let shouldFail = failNext
        failNext = false
        try await Task.sleep(for: .milliseconds(750))
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if action == .resetPassword { return nil }
        return ReaderAccountSession(uid: "local-fixture", email: fields.normalizedEmail, isEmailVerified: false)
    }
}

struct LocalAccountSmokeView: View {
    @StateObject private var fixture = LocalAccountSmokeFixture()

    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Ingen rigtige konti eller mails. Google, Apple, nyhedsbrev, push og baggrundstjenester startes ikke.")
                        .font(.footnote)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("smoke.firebase")
                    Toggle("Næste testkald fejler", isOn: $fixture.failNext)
                    Text("Testkald: \(fixture.requests) · \(fixture.lastOperation)")
                        .accessibilityIdentifier("smoke.requests")
                }
                EmailAccountFormSections(form: fixture.form)
                LocalSmokeSessionView(form: fixture.form)
            }
            .navigationTitle("Lokal kontotest")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct LocalSmokeSessionView: View {
    @ObservedObject var form: EmailAccountFlowModel
    var body: some View {
        if let session = form.authenticatedSession {
            Section("Simuleret resultat · ikke en rigtig konto") {
                Text(session.email)
                Text(form.form.password.isEmpty && form.form.confirmation.isEmpty
                     ? "Adgangskoder er ryddet" : "FEJL: adgangskoder er ikke ryddet")
            }
        }
    }
}
#endif
