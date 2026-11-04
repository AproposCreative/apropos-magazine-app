import SwiftUI

/// Shared by the real reader and the isolated native UI smoke fixture.
struct ArticleAvailabilityGate<Content: View>: View {
    let articleID: String
    @ObservedObject var availability: ArticleAvailabilityModel
    let retry: () -> Void
    let back: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if availability.withdrawnIDs.contains(articleID) {
            ScrollView {
                VStack(spacing: 20) {
                    ContentUnavailableView("Artiklen er ikke tilgængelig", systemImage: "doc.text",
                                           description: Text("Artiklen kan ikke åbnes fra magasinets aktuelle indhold. Prøv igen for at kontrollere status."))
                    if availability.checkingID == articleID { ProgressView("Kontrollerer status…") }
                    if let error = availability.errorMessage { Text(LocalizedStringKey(error)).font(.callout).multilineTextAlignment(.center) }
                    Button("Prøv igen", action: retry).disabled(availability.checkingID == articleID)
                    Button("Tilbage", action: back)
                }
                .padding().tint(.primary)
                .frame(maxWidth: .infinity)
            }
            .navigationBarBackButtonHidden(true)
            .accessibilityIdentifier("reader.unavailable")
        } else {
            content()
        }
    }
}
