import SwiftUI

/// Used in the real reader's article scroll, as well as the local smoke fixture.
struct ArticleBodyLoadingState: View {
    let isLoading: Bool
    let isOffline: Bool
    var preparesExistingContent = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView(LocalizedStringKey(preparesExistingContent ? "Klargør artiklen…" : "Henter artiklen…"))
                    .accessibilityIdentifier("reader.bodyPreparing")
            } else {
                Text(LocalizedStringKey(preparesExistingContent ? "Artiklen kunne ikke vises." : "Artiklen skal hentes på ny.")).font(.headline)
                Text(LocalizedStringKey(preparesExistingContent ? "Prøv at åbne teksten igen." : isOffline ? "Du er offline. Forbind til nettet for at hente artikelteksten." :
                        "Vi kunne ikke hente artikelteksten. Prøv igen."))
                    .foregroundStyle(.secondary)
                Button(LocalizedStringKey(preparesExistingContent ? "Prøv igen" : "Prøv at hente artiklen igen"), action: retry)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("reader.bodyRetry")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .tint(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.bodyLoadingState")
    }
}
