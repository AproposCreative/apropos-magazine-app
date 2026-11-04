import SwiftUI

/// Shared pending state; the caller captures the original request identity.
/// This surface never constructs a player, a cache or an account service.
struct PodcastOfflinePreparationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let cancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView().tint(.primary).accessibilityHidden(true)
                        heading
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView().tint(.primary).accessibilityHidden(true)
                        heading
                    }
                }
                Text(verbatim: title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("podcast.preparation.title")
                Text("Et øjeblik, mens vi kontrollerer den gemte fil. Afsnittet er ikke startet endnu.")
                    .font(.body).foregroundStyle(Color.primary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("podcast.preparation.explanation")
                Button(action: cancel) {
                    Text("Annuller åbning")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(.primary)
                .accessibilityIdentifier("podcast.preparation.cancel")
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var heading: some View {
        Text("Kontrollerer gemt lyd")
            .font(.title2.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("podcast.preparation.heading")
    }
}

/// Keeps a pending first episode reachable after dismissing the full player.
struct PodcastOfflinePreparationBar: View {
    let title: String
    let open: () -> Void
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 10) {
                    ProgressView().tint(.primary).accessibilityHidden(true)
                    Text("Åbner lyd").font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityLabel("Kontrollerer gemt lyd til \(title)")
            .accessibilityHint("Åbn afspilleren for at se detaljer")
            Button(action: cancel) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Annuller åbning af lyd")
        }
        .buttonStyle(.plain).tint(.primary).foregroundStyle(.primary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: PodcastMiniPlayerLayout.barHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
