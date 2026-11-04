import SwiftUI

/// One original Google challenge; the provider starts only from an explicit tap.
struct ReaderGoogleReauthenticationSheet: View {
    @ObservedObject var prompt: ReaderGoogleReauthenticationPrompt
    let presentation: ReaderGoogleReauthenticationPrompt.Presentation

    var body: some View {
        NavigationStack {
            Group {
                if let current = prompt.presentation, current.id == presentation.id {
                    Form {
                        Section {
                            Text("Bekræft, at det er dig, for at fortsætte.")
                            GoogleSignInButton(reauthenticationPrompt: prompt, presentation: current)
                                .id(presentation.id)
                        }
                    }
                    .accessibilityIdentifier("reauth.google.form")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .navigationTitle("Bekræft identitet")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { prompt.cancel(action: presentation.action) }
                        .accessibilityIdentifier("reauth.google.cancel")
                }
            }
        }
        // Success retires the prompt first; old teardown cannot cancel HTTP or
        // a newer challenge. Provider cancellation still awaits its callback.
        .onDisappear { prompt.cancel(action: presentation.action) }
    }
}
