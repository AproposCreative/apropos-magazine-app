import SwiftUI

/// Renders one exact held-user challenge through the existing account form.
/// No login, provider SDK, credentials or account lookup is created by this view.
struct ReaderEmailReauthenticationSheet: View {
    @ObservedObject var prompt: ReaderEmailReauthenticationPrompt
    let presentation: ReaderEmailReauthenticationPrompt.Presentation

    var body: some View {
        NavigationStack {
            Group {
                if let current = prompt.presentation, current.id == presentation.id {
                    Form {
                        EmailAccountFormSections(form: current.form,
                            providersWorking: current.state == .failed)
                        if current.state == .failed {
                            Section {
                                Button("Prøv igen") { prompt.retry(action: presentation.action) }
                                    .accessibilityIdentifier("reauth.retry")
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("reauth.form")
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    // SwiftUI may retain the old sheet during its transition.
                    // Never render that retired account's form or email.
                    Color.clear.accessibilityHidden(true)
                }
            }
            .navigationTitle("Bekræft identitet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { prompt.cancel(action: presentation.action) }
                        .accessibilityIdentifier("reauth.cancel")
                }
            }
        }
        // Success retires the action before dismissal; this can only cancel
        // the exact original challenge if it is still active.
        .onDisappear { prompt.cancel(action: presentation.action) }
    }
}
