import SwiftUI

/// Functional local-history feedback. A retry is scoped to the owner generation
/// that produced the notice; the message never claims cloud acknowledgement.
struct ReadingHistoryNotice: View {
    @ObservedObject var model: ReadingHistoryModel

    var body: some View {
        if let message = model.snapshot.issueMessage {
            let generation = model.snapshot.generation
            VStack(alignment: .leading, spacing: 10) {
                Label("Læsehistorik", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text(LocalizedStringKey(message))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("history.issue")
                if model.snapshot.canRetry {
                    Button("Prøv igen") {
                        guard model.snapshot.generation == generation else { return }
                        model.retryStorage()
                    }
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("history.retry")
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
        }
    }
}
