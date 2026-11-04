#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalAudioPreparationFixture: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let ticket: PodcastPlaybackSessionCoordinator.PreparationTicket
        let title: String
    }
    @Published var presentation: Presentation?
    @Published private(set) var cancelled = 0
    @Published private(set) var ignored = 0
    @Published private(set) var accepted = 0
    private var started = 0
    private var held: [Presentation] = []
    private let store: PodcastPlaybackProgressStore
    private lazy var coordinator = PodcastPlaybackSessionCoordinator(store: store, effects: .init(
        cancelCallbacks: {}, stopPlayback: {}, clearPresentation: {}, clearNowPlaying: {}, deactivateAudio: {}))
    init() {
        store = PodcastPlaybackProgressStore(storage: .init(read: { _ in nil }, write: { _, _ in }))
        store.changeContext(to: .guest)
    }
    func begin() {
        started += 1
        guard let asset = PodcastAudioAsset(episodeID: "fixture-episode", canonicalArticleID: "fixture-article",
            kind: .human, sourceRevision: "fixture-r\(started)", remoteURL: URL(string: "https://audio.example.test/local.m4a")!),
              let ticket = coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }) else { return }
        let title = "\(started == 1 ? "Første" : "Ny") kontrol: En længere journalistisk fortælling om musik, mennesker og de steder, vi mødes"
        let value = Presentation(ticket: ticket, title: title)
        held.append(value); presentation = value
    }
    func cancel(_ original: Presentation) {
        guard presentation?.id == original.id, coordinator.discardPreparation(original.ticket) else { return }
        presentation = nil; cancelled += 1
    }
    func releaseOldest() {
        guard !held.isEmpty else { return }
        let original = held.removeFirst()
        guard coordinator.consumePreparation(original.ticket) else { ignored += 1; return }
        if presentation?.id == original.id { presentation = nil }
        accepted += 1 // A memory decision only; no AVPlayer or audio exists.
    }
}

/// Actual preparation ownership and shared UI with manually held memory work.
/// This does not verify a file, media playback, SDKs or a provider connection.
struct LocalAudioAssetSmokeView: View {
    @StateObject private var fixture = LocalAudioPreparationFixture()
    var body: some View {
        NavigationStack {
            Form {
                Text("Kun hukommelsesdata og manuelle svar. Ingen lyd eller tjenester startes.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                    .accessibilityIdentifier("audio.fixture.firebase")
                Button("Start kontrol") { fixture.begin() }.accessibilityIdentifier("audio.fixture.start")
                Text("Annulleringer: \(fixture.cancelled)").accessibilityIdentifier("audio.fixture.cancelled")
                Text("Godkendte lokale svar: \(fixture.accepted)").accessibilityIdentifier("audio.fixture.accepted")
                Text("Afviste gamle svar: \(fixture.ignored)").accessibilityIdentifier("audio.fixture.ignored")
            }
            .tint(.primary).navigationTitle("Lokal lydkontrol").navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $fixture.presentation) { original in
            NavigationStack {
                VStack(spacing: 0) {
                    PodcastOfflinePreparationView(title: original.title) { fixture.cancel(original) }
                    Divider()
                    Button { fixture.releaseOldest() } label: {
                        Text("Aflevér ældste svar")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("audio.fixture.release")
                    .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("Afvist: \(fixture.ignored)").font(.caption)
                            .accessibilityIdentifier("audio.fixture.liveIgnored")
                    }
                }
            }
            .tint(.primary).presentationDetents([.large]).interactiveDismissDisabled()
        }
    }
}
#endif
