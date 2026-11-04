import SwiftUI

/// Presents only the exact Apple challenge already owned by the deletion
/// coordinator. Presentation does not start a provider or create a login.
struct ReaderAppleReauthenticationSheet: View {
    @ObservedObject var prompt: ReaderAppleReauthenticationPrompt
    let presentation: ReaderAppleReauthenticationPrompt.Presentation
    var providerFactory: AppleAuthorizationButton.Coordinator.ProviderFactory? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let current = prompt.presentation, current.id == presentation.id {
                    Form {
                        Section {
                            Text("Bekræft, at det er dig, for at fortsætte.")
                            AppleAccountSignInButton(reauthenticationFlow: current.flow,
                                providerFactory: providerFactory)
                                .id(presentation.id)
                        }
                    }
                    .accessibilityIdentifier("reauth.apple.form")
                } else {
                    // A retiring sheet may remain onscreen during dismissal;
                    // its StateObject must never retain another action's flow.
                    Color.clear.accessibilityHidden(true)
                }
            }
            .navigationTitle("Bekræft identitet")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { prompt.cancel(action: presentation.action) }
                        .accessibilityIdentifier("reauth.apple.cancel")
                }
            }
        }
        // Successful SDK completion retires the prompt before dismissal. This
        // cannot cancel subsequent HTTP work or a newer action's presentation.
        .onDisappear { prompt.cancel(action: presentation.action) }
    }
}
