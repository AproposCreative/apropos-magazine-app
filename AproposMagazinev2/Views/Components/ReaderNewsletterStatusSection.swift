import SwiftUI

struct ReaderNewsletterStatusSection: View {
    @ObservedObject var model: ReaderNewsletterSignupModel

    var body: some View {
        Section("Nyhedsbrev") {
            if model.isWorking { ProgressView("Tilmelder dig…") }
            if let message = model.message {
                Text(LocalizedStringKey(message)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reader.newsletter.status")
            }
            if model.canReconfirm {
                Button("Tilmeld igen") { model.reconfirm() }
                    .accessibilityIdentifier("reader.newsletter.reconfirm")
            } else if model.canRetry {
                Button("Prøv tilmelding igen") { model.retry() }
                    .accessibilityIdentifier("reader.newsletter.retry")
            }
        }
    }
}
