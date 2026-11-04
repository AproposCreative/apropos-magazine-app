#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

@MainActor
private final class LocalOfflineSettingsFixture: ObservableObject {
    enum Scenario: String { case library, mixed, account, audio, audioFailure }
    enum Failure: Error { case write, probe }
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
        var bodyReads = 0, indexReads = 0, writes = 0, probeStarts = 0, maximumHeld = 0
        var failWrite = false
        var failNextProbe = false
        var probes: [(result: Result<Bool, Error>, complete: @MainActor (Result<Bool, Error>) -> Void)] = []
        var fetches: [(article: Article, complete: @MainActor (Result<Article, Error>) -> Void)] = []
        var changed: (() -> Void)?
        var storage: FavoritesModel.Storage {
            .init(read: { [unowned self] namespace, complete in complete(.success(records[namespace])) },
                write: { [unowned self] namespace, record, expected, complete in
                    guard records[namespace]?.recordRevision == expected else {
                        complete(.failure(FavoritesJournalFailure.staleRevision)); return
                    }
                    records[namespace] = record; complete(.success(()))
                })
        }
    }
    let scenario: Scenario
    let favorites: FavoritesModel
    let offline: FavoritesOfflineCoordinator
    let manager: OfflineManager
    let articles: [Article]
    let fixtureID = UUID()
    @Published var showsCard = true
    private(set) var redraws = 0
    private(set) var generationChanged = false
    private var seeded = false
    private var mixedStarted = false
    private let memory: Memory
    private let audioAsset: PodcastAudioAsset?
    private let audioCache: PodcastAudioCache?
    private let audioTransport: LocalOfflineSettingsAudioTransport?
    private let audioSignals: LocalOfflineSettingsAudioSignals?
    private var publicationScheduled = false
    private var observations: Set<AnyCancellable> = []
    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-OfflineSettingsScenario"), args.indices.contains(index + 1) {
            scenario = Scenario(rawValue: args[index + 1]) ?? .library
        } else { scenario = .library }
        let audioScenario = scenario == .audio || scenario == .audioFailure
        articles = (0..<(audioScenario ? 1 : scenario == .mixed ? 3 : 9)).map { index in
            Article(id: "offline-settings-\(index)", name: "Lokal artikel \(index + 1)", slug: "offline-settings-\(index)",
                content: "<p>Lokal artikeltekst uden billeder eller lyd.</p>", intro: "", topicID: "culture",
                isDraft: false, lastPublished: "2026-10-25T08:00:00Z", contentRevision: "offline-settings-r1")
        }
        let memory = Memory(); self.memory = memory
        memory.failNextProbe = scenario == .library
        let signals: LocalOfflineSettingsAudioSignals? = audioScenario ? .init() : nil
        let transport = signals.map { LocalOfflineSettingsAudioTransport(signals: $0) }
        let cache: PodcastAudioCache? = transport.map { transport in
            let signals = signals!
            return PodcastAudioCache(cacheDirectory: transport.directory.appendingPathComponent("cache", isDirectory: true),
                defaults: UserDefaults(suiteName: "OfflineSettingsAudio-" + UUID().uuidString)!,
                download: { try await transport.download($0) }, onEvent: { signals.record($0) },
                onIndexChange: { signals.changed() })
        }
        let asset = audioScenario ? PodcastAudioAsset(episodeID: "offline-settings-audio", canonicalArticleID: "offline-settings-0",
            kind: .human, sourceRevision: "offline-settings-r1", remoteURL: URL(string: "https://audio.example.invalid/settings.m4a")!) : nil
        audioAsset = asset; audioCache = cache; audioTransport = transport; audioSignals = signals
        let model = FavoritesModel(storage: memory.storage); favorites = model
        let coordinator = FavoritesOfflineCoordinator(model: model, storage: .init(read: { key in
            memory.bodyReads += 1; memory.changed?(); return memory.bodies[key]
        }, write: { key, article in
            memory.writes += 1; memory.changed?()
            if memory.failWrite { memory.failWrite = false; throw Failure.write }
            memory.bodies[key] = article
        }, contains: { key in
            memory.indexReads += 1; memory.changed?(); return memory.bodies[key] != nil
        }, probe: { key, complete in
            memory.probeStarts += 1
            let result: Result<Bool, Error> = memory.failNextProbe ? .failure(Failure.probe) : .success(memory.bodies[key] != nil)
            memory.failNextProbe = false
            memory.probes.append((result, complete))
            memory.maximumHeld = max(memory.maximumHeld, memory.probes.count)
            memory.changed?()
        }), permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { article in
            guard let asset, asset.canonicalArticleID == article.id, asset.sourceRevision == article.bodyRevision else { return nil }
            return asset
        }, audioIsCached: { cache?.isDownloaded(for: $0) == true }, pinAudio: { key, lease, asset in
            cache?.pinAndDownload(pinKey: key, leaseID: lease, asset: asset)
        }, releaseAudio: { key, lease, asset in
            cache?.releasePinKeepingBytes(pinKey: key, leaseID: lease, onlyIfAsset: asset)
        }, scheduleRetry: { _, _ in {} }, audioState: { asset in
            switch cache?.downloadState(for: asset) ?? .notDownloaded {
            case .notDownloaded, .waiting: .waiting
            case .checking: .checking
            case .downloading: .downloading
            case .available: .available
            case .failed: .failed
            case .storageLimit: .storageLimit
            case .disabled: .disabled
            }
        }))
        offline = coordinator
        manager = OfflineManager(coordinator: coordinator, recoverAudioDownloads: { cache?.retryPinnedDownloads() })
        memory.changed = { [weak self] in self?.schedulePublication() }
        signals?.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.manager.refreshAudioStatus()
                self?.schedulePublication()
            }
        }
        model.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &observations)
        manager.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &observations)
    }
    private func schedulePublication() {
        guard !publicationScheduled else { return }
        publicationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publicationScheduled = false; self.objectWillChange.send()
        }
    }
    func seed() {
        guard !seeded else { return }; seeded = true
        favorites.changeContext(to: .confirmed(userID: "offline-reader-A"))
        for article in articles {
            _ = favorites.setFavorite(article, enabled: true)
            if let ticket = offline.captureAccess(articleID: article.id), audioCache != nil {
                _ = manager.saveArticleForOffline(article, ticket: ticket)
            } else if let ticket = offline.captureAccess(articleID: article.id), scenario != .mixed {
                memory.bodies[ticket.contentKey] = article // Pre-existing local bytes, not an accepted display probe.
            }
        }
        if audioCache != nil { offline.synchronizeCurrentMembership() }
        schedulePublication()
    }
    func releaseAudio(failing: Bool = false) {
        guard let audioTransport else { return }
        Task { await audioTransport.releaseFirst(failing: failing) }
    }
    func recoverAudio() { manager.recoverSavedAudioDownloads(); schedulePublication() }
    func markOffline() { manager.isOnline = false; schedulePublication() }
    var audioTicket: FavoritesOfflineCoordinator.AccessTicket? {
        guard audioCache != nil, let article = articles.first else { return nil }
        return manager.captureAccess(articleID: article.id)
    }
    func releaseProbeBatch() {
        let original = memory.probes; memory.probes.removeAll()
        original.forEach { $0.complete($0.result) }
        schedulePublication()
    }
    func redraw() {
        redraws += 1
        manager.isOnline.toggle() // Actual observed input redraw; no collection lifecycle change.
        schedulePublication()
    }
    func evictStoredBodies() { memory.bodies.removeAll(); schedulePublication() }
    func beginMixedWrites() {
        guard scenario == .mixed, seeded, !mixedStarted else { return }; mixedStarted = true
        guard let first = manager.captureAccess(articleID: articles[0].id),
              let second = manager.captureAccess(articleID: articles[1].id),
              let third = manager.captureAccess(articleID: articles[2].id) else { return }
        _ = manager.requestBody(ticket: first, fetch: fetch)
        memory.failWrite = true
        _ = manager.saveArticleForOffline(articles[1], ticket: second)
        _ = manager.saveArticleForOffline(articles[2], ticket: third)
        schedulePublication()
    }
    private func fetch(_ id: String, complete: @escaping @MainActor (Result<Article, Error>) -> Void) {
        guard let article = articles.first(where: { $0.id == id }) else { complete(.failure(Failure.write)); return }
        memory.fetches.append((article, complete)); schedulePublication()
    }
    func releaseFetch() {
        guard !memory.fetches.isEmpty else { return }
        let original = memory.fetches.removeFirst(); original.complete(.success(original.article)); schedulePublication()
    }
    func retryFailed() {
        guard scenario == .mixed, let original = manager.captureAccess(articleID: articles[1].id) else { return }
        _ = manager.retryBody(ticket: original, fetch: fetch); schedulePublication()
    }
    func roundTrip() {
        guard scenario == .account, !generationChanged else { return }
        favorites.changeContext(to: .confirmed(userID: "offline-reader-B")); offline.synchronizeCurrentMembership()
        memory.bodies.removeAll()
        favorites.changeContext(to: .confirmed(userID: "offline-reader-A")); offline.synchronizeCurrentMembership()
        generationChanged = true; schedulePublication()
    }
    var report: String {
        let summary = manager.libraryBodySummary
        let combined = manager.libraryOfflineSummary
        var values: [String: Any] = ["loaded": summary?.isLoaded ?? false, "total": summary?.total ?? 0,
            "available": summary?.available ?? 0, "checking": summary?.checking ?? 0,
            "pending": summary?.pending ?? 0, "failed": summary?.failed ?? 0,
            "notDownloaded": summary?.notDownloaded ?? 0, "checkFailed": summary?.checkFailed ?? 0,
            "probes": memory.probeStarts, "heldProbes": memory.probes.count, "maximumHeld": memory.maximumHeld,
            "indexReads": memory.indexReads, "bodyReads": memory.bodyReads, "writes": memory.writes,
            "heldFetches": memory.fetches.count, "redraws": redraws, "generationChanged": generationChanged,
            "generation": favorites.snapshot.generation.uuidString, "favoriteCount": favorites.snapshot.articles.count,
            "showsCard": showsCard, "firebaseStarted": FirebaseApp.allApps != nil,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue]
        if let audioAsset, let audioCache, let audioSignals {
            let audio = audioSignals.snapshot
            let ticket = audioTicket
            values.merge(["fixtureID": fixtureID.uuidString, "audioEpisodeID": audioAsset.episodeID,
                "audioArticleID": audioAsset.canonicalArticleID, "audioRevision": audioAsset.sourceRevision ?? "none",
                "audioAssetKey": audioAsset.key, "audioState": String(describing: audioCache.downloadState(for: audioAsset)),
                "audioStarts": audio.starts, "heldAudio": audio.held, "audioSavedEvents": audio.saved,
                "audioFailedEvents": audio.failed, "audioDiscardedEvents": audio.discarded,
                "audioArtifactBytes": audio.artifactBytes, "audioFileURL": audioCache.resolvePlaybackURL(for: audioAsset).url.isFileURL,
                "combinedReady": combined?.ready ?? 0, "combinedAudioAvailable": combined?.audioAvailable ?? 0,
                "combinedFailed": combined?.failed ?? 0, "combinedTotal": combined?.total ?? 0,
                "audioAccessLease": ticket?.leaseID.uuidString ?? "none", "audioAccessRevision": ticket?.contentRevision ?? "none",
                "audioDownloadedForMember": offline.audioDownloaded(articleID: audioAsset.canonicalArticleID,
                    expectedRevision: audioAsset.sourceRevision, expectedAsset: audioAsset),
                "isOnline": manager.isOnline, "actualLocalAudioCache": true, "bodyStorageIsMemory": true,
                "audioTransportFailure": audio.failure ?? "none"], uniquingKeysWith: { _, new in new })
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}

/// The actual settings card, injected real manager/coordinator and memory-backed
/// storage. Probes are held locally; no network monitor or services are started.
struct LocalOfflineSettingsSmokeView: View {
    @StateObject private var fixture = LocalOfflineSettingsFixture()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        if fixture.showsCard {
                            OfflineSettingsView(offlineManager: fixture.manager, favorites: fixture.favorites)
                            if let ticket = fixture.audioTicket, let state = fixture.manager.bodyState(ticket: ticket) {
                                ArticleOfflineBodyStatusView(ticket: ticket, state: state,
                                    prepare: { _ = fixture.manager.prepareBodyStatus(ticket: $0) },
                                    retry: { fixture.recoverAudio() }, audioState: fixture.manager.audioState(ticket: ticket))
                            }
                        } else {
                            Text("Kortet er lukket").accessibilityIdentifier("offlineSettings.fixture.hidden")
                        }
                    }.padding(16)
                }.accessibilityIdentifier("offlineSettings.fixture.scroll")
                controls.padding(8).background(.regularMaterial)
                    .dynamicTypeSize(.small ... .medium)
            }
            .navigationTitle("Offlineindstillinger")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                .font(.caption).accessibilityIdentifier("offlineSettings.fixture.firebase")
            HStack {
                Button("Indlæs valg") { fixture.seed() }.accessibilityIdentifier("offlineSettings.fixture.seed")
                Button("Frigiv kontrol") { fixture.releaseProbeBatch() }.accessibilityIdentifier("offlineSettings.fixture.releaseProbes")
                Button("Gentegn") { fixture.redraw() }.accessibilityIdentifier("offlineSettings.fixture.redraw")
            }
            if fixture.scenario == .mixed {
                HStack {
                    Button("Start hentning") { fixture.beginMixedWrites() }.accessibilityIdentifier("offlineSettings.fixture.startWrites")
                    Button("Frigiv hentning") { fixture.releaseFetch() }.accessibilityIdentifier("offlineSettings.fixture.releaseFetch")
                    Button("Prøv igen") { fixture.retryFailed() }.accessibilityIdentifier("offlineSettings.fixture.retry")
                }
            }
            if fixture.scenario == .account {
                HStack {
                    Button("Skift A → B → A") { fixture.roundTrip() }.accessibilityIdentifier("offlineSettings.fixture.roundTrip")
                    Button(fixture.showsCard ? "Skjul kort" : "Vis kort") { fixture.showsCard.toggle() }
                        .accessibilityIdentifier("offlineSettings.fixture.toggle")
                }
            }
            if fixture.scenario == .library {
                HStack {
                    Button("Fjern lokale tekster") { fixture.evictStoredBodies() }.accessibilityIdentifier("offlineSettings.fixture.evict")
                    Button(fixture.showsCard ? "Skjul kort" : "Vis kort") { fixture.showsCard.toggle() }
                        .accessibilityIdentifier("offlineSettings.fixture.toggle")
                }
            }
            if fixture.scenario == .audio || fixture.scenario == .audioFailure {
                HStack {
                    Button("Frigiv lyd") { fixture.releaseAudio() }.accessibilityIdentifier("offlineSettings.fixture.releaseAudio")
                    Button("Fejl lyd") { fixture.releaseAudio(failing: true) }.accessibilityIdentifier("offlineSettings.fixture.failAudio")
                    Button("Prøv lyd igen") { fixture.recoverAudio() }.accessibilityIdentifier("offlineSettings.fixture.recoverAudio")
                }
                Button("Lokal offline") { fixture.markOffline() }.accessibilityIdentifier("offlineSettings.fixture.goOffline")
            }
            Text("Lokal teststatus").font(.caption)
                .accessibilityIdentifier("offlineSettings.fixture.report").accessibilityValue(fixture.report)
        }
        .font(.footnote).tint(.primary)
        .accessibilityElement(children: .contain).accessibilityIdentifier("offlineSettings.fixture.controls")
    }
}

/// The transport holds actual cache work and writes only one complete, tiny
/// fixture artifact per release. It creates no URLSession or media player.
private actor LocalOfflineSettingsAudioTransport {
    nonisolated let directory: URL
    private let signals: LocalOfflineSettingsAudioSignals
    private var held: [(URL, CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>)] = []
    init(signals: LocalOfflineSettingsAudioSignals) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineSettingsAudio-" + UUID().uuidString, isDirectory: true)
        self.signals = signals
    }
    func download(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        try await withCheckedThrowingContinuation { continuation in
            held.append((url, continuation)); signals.started(held: held.count)
        }
    }
    func releaseFirst(failing: Bool) {
        guard !held.isEmpty else { return }
        let original = held.removeFirst(); signals.setHeld(held.count)
        guard !failing else { original.1.resume(throwing: URLError(.notConnectedToInternet)); return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
            let file = directory.appendingPathComponent(UUID().uuidString + ".download")
            try bytes.write(to: file)
            let response = HTTPURLResponse(url: original.0, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4", "Content-Length": "8"])!
            signals.wroteArtifact(bytes.count)
            original.1.resume(returning: .init(temporaryURL: file, response: response))
        } catch { signals.recordFailure(error.localizedDescription); original.1.resume(throwing: error) }
    }
}

private final class LocalOfflineSettingsAudioSignals: @unchecked Sendable {
    struct Snapshot {
        var starts = 0, held = 0, saved = 0, failed = 0, discarded = 0, artifactBytes = 0
        var failure: String?
    }
    private let lock = NSLock()
    private var state = Snapshot()
    private var change: (@Sendable () -> Void)?
    var onChange: (@Sendable () -> Void)? {
        get { lock.lock();defer { lock.unlock() };return change }
        set { lock.lock();change = newValue;lock.unlock() }
    }
    var snapshot: Snapshot { lock.lock();defer { lock.unlock() };return state }
    func changed() { lock.lock();let callback = change;lock.unlock();callback?() }
    func started(held: Int) { lock.lock();state.starts += 1;state.held = held;lock.unlock();changed() }
    func setHeld(_ count: Int) { lock.lock();state.held = count;lock.unlock();changed() }
    func wroteArtifact(_ count: Int) { lock.lock();state.artifactBytes += count;lock.unlock();changed() }
    func recordFailure(_ failure: String) { lock.lock();state.failure = failure;lock.unlock();changed() }
    func record(_ event: PodcastAudioCache.DownloadEvent) {
        lock.lock()
        switch event { case .saved: state.saved += 1;case .failed: state.failed += 1;case .discarded: state.discarded += 1 }
        lock.unlock();changed()
    }
}
#endif
