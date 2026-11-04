import SwiftUI

/// Shared with the local fixture. This view observes memory only; retry is an
/// explicit action, never a background overwrite of an unreadable record.
struct PodcastProgressNotice: View {
    @ObservedObject var store: PodcastPlaybackProgressStore

    var body: some View {
        if let message = store.snapshot.issueMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label("Lytteposition", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text(LocalizedStringKey(message))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("progress.issue")
                if store.snapshot.canRetry {
                    Button("Prøv igen", action: store.retryStorage)
                        .tint(.primary)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("progress.retry")
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
