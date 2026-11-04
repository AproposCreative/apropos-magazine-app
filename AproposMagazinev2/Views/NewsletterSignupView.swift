import SwiftUI

/// Native opt-in uses the same owner-bound service as onboarding. No web form.
struct NewsletterSignupView: View {
    let email: String
    @ObservedObject private var canonical = AuthService.shared.state
    @ObservedObject private var model = ReaderNewsletterRuntime.model
    @State private var originalContext: CanonicalSessionState.ContextTicket

    init(email: String) {
        self.email = email
        _originalContext = State(initialValue: AuthService.shared.state.contextTicket())
    }

    var body: some View {
        ReaderNewsletterSignupContent(email: email, canonical: canonical,
            model: model, context: originalContext)
    }
}

/// The live form and service-free native checks use this exact presentation.
/// Its injected model retains all consent, identity and receipt authority.
struct ReaderNewsletterSignupContent: View {
    let email: String
    @ObservedObject var canonical: CanonicalSessionState
    @ObservedObject var model: ReaderNewsletterSignupModel
    let context: CanonicalSessionState.ContextTicket
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var optedIn = false
    @State private var attemptedRequestID: String?
    @State private var needsFreshChoice = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(email)
                        .accessibilityIdentifier("reader.newsletter.email")
                    if attemptedRequestID == nil || needsFreshChoice {
                        Toggle("Ja tak til Apropos’ nyhedsbrev", isOn: $optedIn)
                            .accessibilityIdentifier("reader.newsletter.optin")
                    }
                    Text("Historier og anbefalinger på e-mail. Du kan altid afmelde dig via linket i nyhedsbrevet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let url = NewsletterSignupPolicy.termsURL(for: AppLocalization.language(for: locale)) {
                        Link("Vilkår og privatliv", destination: url)
                    }
                }
                if attemptedRequestID == model.requestID, model.status != .idle { ReaderNewsletterStatusSection(model: model) }
            }
            .accessibilityIdentifier("reader.newsletter.form")
            .onChange(of: optedIn) { _, selected in
                guard selected, canonical.isCurrent(context), let session = canonical.snapshot.session,
                      session.email == email else { return }
                guard model.beginExplicitOptIn(session: session, context: context) else { return }
                attemptedRequestID = model.requestID
                needsFreshChoice = false
            }
            .onChange(of: model.status) { _, status in
                guard attemptedRequestID == model.requestID, status == .reconfirmationRequired, !model.canReconfirm else { return }
                optedIn = false; needsFreshChoice = true
            }
            .onChange(of: canonical.snapshot.generation) { _, _ in dismiss() }
            .navigationTitle("Nyhedsbrev")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Luk") { dismiss() }
                        .accessibilityIdentifier("reader.newsletter.close")
                }
            }
        }
    }
}
