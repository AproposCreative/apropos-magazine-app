import SwiftUI

struct OfflineSettingsView: View {
    @ObservedObject private var offlineManager: OfflineManager
    @ObservedObject private var favorites: FavoritesModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshHandle: FavoritesOfflineCoordinator.LibraryRefreshHandle?
    @State private var visible = false

    init() {
        _offlineManager = ObservedObject(wrappedValue: OfflineManager.shared)
        _favorites = ObservedObject(wrappedValue: FavoritesRuntime.model)
    }
    init(offlineManager: OfflineManager, favorites: FavoritesModel) {
        _offlineManager = ObservedObject(wrappedValue: offlineManager)
        _favorites = ObservedObject(wrappedValue: favorites)
    }

    var body: some View {
        let summary = offlineManager.libraryBodySummary
        let complete = offlineManager.libraryOfflineSummary
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline læsning").font(.headline)
            Label(LocalizedStringKey(offlineManager.isOnline ? "Online" : "Offline"),
                  systemImage: offlineManager.isOnline ? "wifi" : "wifi.slash")
                .font(.subheadline)
            Divider()
            if let summary, summary.isLoaded {
                if let complete, complete.isLoaded {
                    Text("Tekst og lyd klar offline: \(complete.ready) af \(complete.total)")
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("offlineSettings.complete")
                    Text("Lyd klar offline: \(complete.audioAvailable) af \(complete.total)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.audioAvailable")
                    if complete.audioPending > 0 {
                        Text("Henter lyd: \(complete.audioPending)")
                            .font(.subheadline).accessibilityIdentifier("offlineSettings.audioPending")
                    }
                    if complete.audioDisabled > 0 {
                        Text("Hentning af lyd er slået fra")
                            .font(.subheadline).accessibilityIdentifier("offlineSettings.audioDisabled")
                    }
                    if complete.awaitingAudio > 0 {
                        Text("Afventer lydversion: \(complete.awaitingAudio)")
                            .font(.subheadline).accessibilityIdentifier("offlineSettings.awaitingAudio")
                    }
                    if complete.failed > 0 {
                        Text("Hentning kunne ikke færdiggøres: \(complete.failed)")
                            .font(.subheadline).accessibilityIdentifier("offlineSettings.audioFailed")
                    }
                    if complete.storageLimited > 0 {
                        Text("Grænsen for gemt lyd er nået: \(complete.storageLimited)")
                            .font(.subheadline).accessibilityIdentifier("offlineSettings.storageLimited")
                    }
                }
                Text("Artikeltekst klar offline: \(summary.available) af \(summary.total)")
                    .font(.subheadline).accessibilityIdentifier("offlineSettings.available")
                if summary.checking > 0 {
                    Text("Afventer kontrol af artikeltekst: \(summary.checking)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.checking")
                }
                if summary.pending > 0 {
                    Text("Henter artikeltekst: \(summary.pending)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.pending")
                }
                if summary.failed > 0 {
                    Text("Artikeltekst kunne ikke gemmes: \(summary.failed)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.failed")
                }
                if summary.notDownloaded > 0 {
                    Text("Artikeltekst ikke hentet: \(summary.notDownloaded)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.notDownloaded")
                }
                if summary.checkFailed > 0 {
                    Text("Status kunne ikke kontrolleres: \(summary.checkFailed)")
                        .font(.subheadline).accessibilityIdentifier("offlineSettings.checkFailed")
                    Button { refresh(force: true) } label: {
                        Text("Kontrollér igen").font(.subheadline)
                            .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.primary)
                    .accessibilityIdentifier("offlineSettings.retry")
                    .accessibilityHint("Kontrollerer kun, om artikelteksten er gemt på enheden.")
                }
            } else {
                Text("Offline-status afventer indlæsning af dine gemte valg.")
                    .font(.subheadline).accessibilityIdentifier("offlineSettings.unknown")
            }
            Text("Tekst og lyd skal være hentet, før en artikel er klar offline. Billeder kan kræve netværk.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offlineSettings.scope")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offlineSettings.card")
        .onAppear { visible = true; refresh(force: true) }
        .onChange(of: offlineManager.libraryMembershipIdentity) { _, _ in
            guard visible else { return }
            refresh(force: false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard visible, phase == .active else { return }
            refresh(force: true)
        }
        .onDisappear {
            visible = false
            let original = refreshHandle; refreshHandle = nil
            if let original { offlineManager.cancelLibraryBodyStatus(original) }
        }
    }
    private func refresh(force: Bool) {
        guard visible else { return }
        // The coordinator joins a current scan and retires changed identities;
        // appearance and foreground must not cancel each other's physical work.
        refreshHandle = offlineManager.prepareLibraryBodyStatus(force: force)
    }
}
