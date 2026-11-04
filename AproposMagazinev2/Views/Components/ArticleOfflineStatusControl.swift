import SwiftUI

/// Body availability is independent of the favorite choice and audio downloads.
/// The caller captures the original access ticket in its retry action.
struct ArticleOfflineStatusControl: View {
    let state: FavoritesOfflineCoordinator.BodyState
    var retry: (() -> Void)? = nil
    var audioState: FavoritesOfflineCoordinator.AudioState? = nil
    var audioProgress: Double? = nil
    var requiresAudio = false

    private var ready: Bool { state == .available && (audioState == .available || (!requiresAudio && audioState == nil)) }
    private var canRetry: Bool {
        state == .failed || state == .notDownloaded || (state == .available &&
            (audioState == .failed || audioState == .storageLimit))
    }

    private var title: String {
        switch state {
        case .checking: "Kontrollerer offlineindhold…"
        case .notDownloaded: "Tekst ikke downloadet"
        case .pending: "Henter artikeltekst…"
        case .failed: "Teksten kunne ikke downloades"
        case .available:
            switch audioState {
            case nil: requiresAudio ? "Kontrollerer gemt lyd…" : "GEMT"
            case .available: "GEMT"
            case .waitingForPublication: "Tekst gemt · lyd ikke hentet"
            case .waiting: "Lyd venter på download"
            case .checking: "Kontrollerer gemt lyd…"
            case .downloading: "Henter lyd…"
            case .failed: "Lyden kunne ikke hentes"
            case .storageLimit: "Grænsen for gemt lyd er nået"
            case .disabled: "Hentning af lyd er slået fra"
            }
        }
    }

    private var percentage: Int? {
        guard (state == .available || state == .pending), audioState == .downloading else { return nil }
        return Self.downloadPercentage(audioProgress)
    }

    static func downloadPercentage(_ value: Double?) -> Int? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        // Received bytes can reach the total before hashing and the atomic save
        // finish. Only the existing two-component ready branch may say GEMT.
        // One representable step recovers exact byte-ratio boundaries such as
        // 29/100 without rounding ordinary fractional percentages upward.
        return min(99, Int((value * 100).nextUp.rounded(.down)))
    }

    @ViewBuilder private var statusTitle: some View {
        if let percentage { Text("Henter \(percentage) %").monospacedDigit() }
        else { Text(LocalizedStringKey(title)) }
    }

    var body: some View {
        Group {
            if ready {
                ArticleTagChip(text: title)
                    .accessibilityIdentifier("offline.body.status")
                    .accessibilityHint(LocalizedStringKey(audioState == nil
                        ? "Artikelteksten er gemt på denne enhed. Billeder og lyd har separat downloadstatus."
                        : "Artikelteksten og lyden er hentet på denne enhed. Billeder kan kræve netværk."))
            } else {
                VStack(spacing: 2) {
                    statusTitle
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#262626"), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("offline.body.status")
                    if canRetry, let retry {
                        Button(action: retry) {
                            Label(LocalizedStringKey(audioState != nil ? "Prøv hentningen igen" : state == .failed ? "Prøv igen" : "Hent tekst"), systemImage: "arrow.down.circle")
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .accessibilityLabel(LocalizedStringKey(audioState != nil ? "Hent tekst og lyd til offlinebrug" : state == .failed ? "Prøv at hente artikelteksten igen" : "Hent artikeltekst til offlinelæsning"))
                        .accessibilityHint(LocalizedStringKey(audioState != nil
                            ? "Dit gemte valg bevares. Hentningen forsøges igen, når du er online."
                            : "Ændrer ikke dit valg af gemte artikler. Denne status gælder kun artikelteksten."))
                        .accessibilityIdentifier("offline.body.retry")
                    }
                }
            }
        }
        .frame(maxWidth: ready ? nil : .infinity)
    }
}

/// The query is memory-only. Filesystem validation starts from view lifecycle,
/// with the original lease captured before the callback can cross a task hop.
struct ArticleOfflineBodyStatusView: View {
    let ticket: FavoritesOfflineCoordinator.AccessTicket
    let state: FavoritesOfflineCoordinator.BodyState
    let prepare: (FavoritesOfflineCoordinator.AccessTicket) -> Void
    let retry: () -> Void
    var audioState: FavoritesOfflineCoordinator.AudioState? = nil
    var audioProgress: Double? = nil
    var requiresAudio = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        ArticleOfflineStatusControl(state: state, retry: retry, audioState: audioState,
            audioProgress: audioProgress, requiresAudio: requiresAudio)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: ticket.leaseID) {
                guard !Task.isCancelled else { return }
                prepare(ticket)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isVisible { prepare(ticket) }
            }
    }
}
