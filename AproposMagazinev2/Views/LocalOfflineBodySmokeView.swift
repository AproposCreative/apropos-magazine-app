#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

@MainActor
final class LocalOfflineBodyFixture: ObservableObject {
    enum Scenario: String { case held, fetchFailure, writeFailure, accountRoundTrip, coldStored, probeAccountRoundTrip, savedTags, publishedRecovery, downloadProgress }
    enum Failure: Error { case fetch, write }
    @Published private(set) var ready = false
    @Published private(set) var ticket: FavoritesOfflineCoordinator.AccessTicket?
    @Published private(set) var generationChanged = false
    @Published private(set) var redraws = 0
    @Published private(set) var bodyAvailable = false
    @Published private(set) var prepareCalls = 0
    @Published private(set) var sourceAdopted = false
    @Published private(set) var coldRestored = false
    @Published private(set) var recoveredArticle: Article?
    @Published private(set) var recoveryFailure: String?
    @Published private(set) var recoveryReceipt = "{}"
    let fixtureID = UUID()
    let scenario: Scenario
    let model: FavoritesModel
    let offline: FavoritesOfflineCoordinator
    let article = Article(id: "offline-body-fixture", name: "En fortælling til senere", slug: "offline-body-fixture",
        content: "<p>Denne lokale artikeltekst er gemt gennem den faktiske offlinekoordinator.</p>", intro: "", topicID: "culture",
        isDraft: false, lastPublished: "2026-10-24T12:00:00Z", contentRevision: "local-offline-r1")
    private let memory: Memory
    private let diskStorage: OfflineManager.BodyStorage?
    private var originalPublishedMember: FavoritesModel.MembershipTicket?
    private var originalContentKey: String?
    private var coldModel: FavoritesModel?
    private var coldOffline: FavoritesOfflineCoordinator?
    private var activeOffline: FavoritesOfflineCoordinator { coldOffline ?? offline }
    private var observation: AnyCancellable?
    private var started = false
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var codecBacked = false
        var encodedRecords: [FavoritesNamespace: Data] = [:]
        var bodies: [String: Article] = [:]
        var failWrite = false
        var failNextFetch = false
        var writes = 0
        var fetches = 0
        var held: [@MainActor (Result<Article, Error>) -> Void] = []
        var bodyReads = 0
        var indexReads = 0
        var probes = 0
        var holdProbes = false
        var heldProbes: [(result: Result<Bool, Error>, complete: @MainActor (Result<Bool, Error>) -> Void)] = []
        var onChange: (@MainActor () -> Void)?
        // Local presentation inputs only. Native checks never claim transport,
        // byte counters or a real audio file from these memory-only effects.
        var progressScenario = false
        var audioAsset: PodcastAudioAsset?
        var exposesAudioAsset = true
        var audioState: FavoritesOfflineCoordinator.AudioState = .downloading
        var audioProgress: Double? = 0
        var audioProof = false
        var missingCapturedAudioState = false
        var audioPins = 0
        var audioRetries = 0
        var storage: FavoritesModel.Storage {
            if codecBacked {
                return .init(read: { [weak self] namespace, complete in
                    complete(Result { try self?.encodedRecords[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) } })
                }, write: { [weak self] namespace, record, expected, complete in
                    complete(Result {
                        guard let self else { throw FavoritesJournalFailure.writeFailed }
                        let previous = try self.encodedRecords[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
                        guard previous?.recordRevision == expected else { throw FavoritesJournalFailure.staleRevision }
                        self.encodedRecords[namespace] = try FavoritesRecordCodec.encode(record, namespace: namespace)
                    })
                })
            }
            return .init(read: { [weak self] namespace, complete in complete(.success(self?.records[namespace])) },
                  write: { [weak self] namespace, record, expected, complete in
                guard let self, self.records[namespace]?.recordRevision == expected else {
                    complete(.failure(FavoritesJournalFailure.staleRevision)); return
                }
                self.records[namespace] = record; complete(.success(()))
            })
        }
    }
    init(scenario explicitScenario: Scenario? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let selectedScenario: Scenario
        if let explicitScenario { selectedScenario = explicitScenario }
        else if let index = args.firstIndex(of: "-OfflineBodyScenario"), args.indices.contains(index + 1) {
            selectedScenario = Scenario(rawValue: args[index + 1]) ?? .held
        } else { selectedScenario = .held }
        scenario = selectedScenario
        let memory = Memory(); self.memory = memory
        memory.codecBacked = selectedScenario == .publishedRecovery
        memory.progressScenario = selectedScenario == .downloadProgress
        if memory.progressScenario {
            memory.audioAsset = PodcastAudioAsset(episodeID: "offline-body-audio", canonicalArticleID: "offline-body-fixture",
                kind: .human, sourceRevision: "local-offline-r1",
                remoteURL: URL(string: "https://fixtures.example.invalid/offline-body.m4a")!)
        }
        let disk = selectedScenario == .publishedRecovery ? OfflineManager.BodyStorage(directory:
            FileManager.default.temporaryDirectory.appendingPathComponent("offline-recovery-" + UUID().uuidString, isDirectory: true)) : nil
        diskStorage = disk
        let model = FavoritesModel(storage: memory.storage); self.model = model
        offline = Self.makeCoordinator(model: model, memory: memory, disk: disk)
        memory.holdProbes = scenario == .coldStored || scenario == .probeAccountRoundTrip || scenario == .savedTags
        memory.onChange = { [weak self] in self?.objectWillChange.send() }
        observe(offline)
    }
    private static func makeCoordinator(model: FavoritesModel, memory: Memory,
                                        disk: OfflineManager.BodyStorage?) -> FavoritesOfflineCoordinator {
        FavoritesOfflineCoordinator(model: model,
            storage: .init(read: { key in
                memory.bodyReads += 1
                return try disk?.read(key) ?? memory.bodies[key]
            }, write: { key, article in
                memory.writes += 1
                if memory.failWrite { memory.failWrite = false; memory.onChange?(); throw Failure.write }
                if let disk { try disk.write(key, article: article) }
                else { memory.bodies[key] = article }
                memory.onChange?()
            }, contains: { key in
                memory.indexReads += 1
                return try disk?.contains(key) ?? (memory.bodies[key] != nil)
            }, probe: { key, complete in
                memory.probes += 1
                if let disk {
                    disk.probe(key) { result in complete(result); memory.onChange?() }
                    return
                }
                let result: Result<Bool, Error> = .success(memory.bodies[key] != nil)
                if memory.holdProbes { memory.heldProbes.append((result, complete)) }
                else { complete(result) }
                memory.onChange?()
            }), permitsBody: { _ in true },
            effects: .init(cacheImages: { _, _ in }, audioAsset: { article in
                guard memory.progressScenario, memory.exposesAudioAsset,
                      let asset = memory.audioAsset, asset.canonicalArticleID == article.id,
                      asset.sourceRevision == article.bodyRevision else { return nil }
                return asset
            }, audioIsCached: { asset in memory.audioAsset == asset && memory.audioProof },
                pinAudio: { _, _, _ in memory.audioPins += 1 }, releaseAudio: { _, _, _ in },
                scheduleRetry: { _, _ in {} }, audioState: { _ in memory.audioState },
                audioProgress: { _ in memory.audioProgress }))
    }
    private func observe(_ coordinator: FavoritesOfflineCoordinator) {
        observation = coordinator.bodyChanges.sink { [weak self] in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }
    var status: FavoritesOfflineCoordinator.BodyState? { ticket.flatMap { activeOffline.bodyState(ticket: $0) } }
    var audioStatus: FavoritesOfflineCoordinator.AudioState? {
        guard scenario == .downloadProgress, !memory.missingCapturedAudioState, let ticket else { return nil }
        return activeOffline.audioState(ticket: ticket)
    }
    var audioProgress: Double? {
        guard scenario == .downloadProgress, let ticket else { return nil }
        return activeOffline.audioProgress(ticket: ticket)
    }
    var progressReceipt: [String: Any] {
        ["fixtureID": fixtureID.uuidString, "articleID": article.id,
         "revision": ticket?.contentRevision ?? "", "leaseID": ticket?.leaseID.uuidString ?? "",
         "namespace": String(describing: model.context.namespace),
         "bodyState": status.map { String(describing: $0) } ?? "none",
         "audioState": audioStatus.map { String(describing: $0) } ?? "none",
         "audioProgress": audioProgress.map { $0 as Any } ?? NSNull(),
         "rawProgress": memory.audioProgress.map { $0 as Any } ?? NSNull(),
         "audioProof": memory.audioProof, "audioAssetExposed": memory.exposesAudioAsset,
         "missingCapturedAudioState": memory.missingCapturedAudioState,
         "audioRetries": memory.audioRetries, "audioPins": memory.audioPins,
         "bodyWrites": memory.writes, "bodyFetches": memory.fetches,
         "combinedReady": activeOffline.libraryOfflineSummary.ready,
         "fixtureAudioEffectsAreMemoryOnly": true, "firebaseStarted": FirebaseApp.allApps != nil]
    }
    var writes: Int { memory.writes }
    var fetches: Int { memory.fetches }
    var heldCount: Int { memory.held.count }
    var isProbeScenario: Bool { scenario == .coldStored || scenario == .probeAccountRoundTrip || scenario == .savedTags }
    var probes: Int { memory.probes }
    var heldProbeCount: Int { memory.heldProbes.count }
    var indexReads: Int { memory.indexReads }
    var bodyReads: Int { memory.bodyReads }
    func start() {
        guard !started else { return }; started = true
        if scenario == .publishedRecovery {
            startPublishedRecovery()
            return
        }
        model.changeContext(to: scenario == .accountRoundTrip || scenario == .probeAccountRoundTrip || scenario == .downloadProgress
            ? .confirmed(userID: "local-offline-A") : .guest)
        _ = model.setFavorite(article, enabled: true)
        memory.failWrite = scenario == .writeFailure
        ticket = offline.captureAccess(articleID: article.id)
        if let ticket {
            if isProbeScenario { memory.bodies[ticket.contentKey] = article }
            else { _ = offline.requestBody(ticket: ticket, fetch: fetch) }
        }
        refreshBodyAvailability()
        ready = true
    }
    func prepare(_ original: FavoritesOfflineCoordinator.AccessTicket) {
        prepareCalls += 1
        _ = activeOffline.prepareBodyStatus(ticket: original, force: true)
    }
    func redraw() { redraws += 1 }
    func releaseProbe() {
        guard !memory.heldProbes.isEmpty else { return }
        let held = memory.heldProbes.removeFirst()
        held.complete(held.result)
        objectWillChange.send()
    }
    func removeStoredBodyAndRevalidate() {
        guard scenario == .coldStored, let original = ticket else { return }
        memory.bodies.removeValue(forKey: original.contentKey)
        _ = offline.prepareBodyStatus(ticket: original, force: true)
        objectWillChange.send()
    }
    /// Deliberately lose this original fixture body, then fail its actual fetch.
    /// The same status view and lease remain mounted throughout the transition.
    func failSavedTagsReload() {
        guard scenario == .savedTags, let original = ticket, status == .available else { return }
        memory.bodies.removeValue(forKey: original.contentKey)
        memory.holdProbes = false
        _ = offline.prepareBodyStatus(ticket: original, force: true)
        memory.failNextFetch = true
        _ = offline.retryBody(ticket: original, fetch: fetch)
        objectWillChange.send()
    }
    func retry(_ original: FavoritesOfflineCoordinator.AccessTicket) {
        if scenario == .downloadProgress {
            guard activeOffline.captureAccess(articleID: article.id) == original else { return }
            memory.audioRetries += 1
            setAudioProgress(0)
            return
        }
        _ = activeOffline.retryBody(ticket: original, fetch: fetch)
        refreshBodyAvailability()
    }
    func setAudioProgress(_ value: Double?) {
        guard scenario == .downloadProgress, !memory.audioProof else { return }
        memory.exposesAudioAsset = true
        memory.missingCapturedAudioState = false
        memory.audioState = .downloading
        memory.audioProgress = value
        objectWillChange.send()
    }
    func completeAudioProof() {
        guard scenario == .downloadProgress else { return }
        memory.exposesAudioAsset = true
        memory.audioProgress = 1
        memory.audioState = .available
        memory.audioProof = true
        objectWillChange.send()
    }
    func captureMissingAudioState() {
        guard scenario == .downloadProgress, !memory.audioProof else { return }
        memory.missingCapturedAudioState = true
        // Supply a stale number alongside the absent captured status. The
        // actual requiresAudio presentation must fail closed, not show GEMT.
        memory.audioProgress = 0.42
        objectWillChange.send()
    }
    func awaitAudioPublication() {
        guard scenario == .downloadProgress, !memory.audioProof else { return }
        memory.missingCapturedAudioState = false
        memory.exposesAudioAsset = false
        // A stale last byte report is deliberately retained. The coordinator
        // must suppress it when this current article has no admitted asset.
        memory.audioProgress = 0.42
        objectWillChange.send()
    }
    func failAudio() {
        guard scenario == .downloadProgress, !memory.audioProof else { return }
        memory.missingCapturedAudioState = false
        memory.exposesAudioAsset = true
        memory.audioState = .failed
        memory.audioProgress = 0.42
        objectWillChange.send()
    }
    func release() {
        guard !memory.held.isEmpty else { return }
        let callback = memory.held.removeFirst(); callback(.success(article))
        refreshBodyAvailability()
        if scenario == .publishedRecovery { updateRecoveryReceipt() }
        objectWillChange.send()
    }
    func roundTrip() {
        guard scenario == .accountRoundTrip || scenario == .probeAccountRoundTrip, !generationChanged else { return }
        model.changeContext(to: .confirmed(userID: "local-offline-B")); offline.releaseCurrentAccess()
        if scenario == .probeAccountRoundTrip { memory.bodies.removeAll() }
        model.changeContext(to: .confirmed(userID: "local-offline-A")); offline.synchronizeCurrentMembership()
        ticket = offline.captureAccess(articleID: article.id)
        generationChanged = true
        refreshBodyAvailability()
    }
    // Preserve the actual decoded-read assertion, but perform it at the explicit
    // action boundary. A render getter must not publish invalidation while SwiftUI
    // is drawing. Probe scenarios intentionally never perform this diagnostic read.
    private func refreshBodyAvailability() {
        guard !isProbeScenario else { return }
        let body = ticket.flatMap { activeOffline.body($0) }
        bodyAvailable = body != nil
        if scenario == .publishedRecovery { recoveredArticle = body }
    }

    private func startPublishedRecovery() {
        guard let namespace = FavoritesContext.confirmed(userID: "local-offline-A").namespace else { return }
        let legacy = Article(id: article.id, name: article.name ?? "", slug: article.slug ?? article.id,
            content: "", intro: "", topicID: "culture", isDraft: false,
            lastPublished: article.lastPublished, lastUpdated: "2026-10-24T11:00:00Z")
        do {
            memory.encodedRecords[namespace] = try FavoritesRecordCodec.encode(FavoritesRecord(articles: [legacy]), namespace: namespace)
            model.changeContext(to: .confirmed(userID: "local-offline-A"))
            guard model.pendingMutations.isEmpty,
                  let member = model.membershipTicket(articleID: article.id),
                  let access = offline.captureAccess(articleID: article.id) else { throw Failure.fetch }
            originalPublishedMember = member
            originalContentKey = access.contentKey
            ticket = access
            refreshBodyAvailability()
            updateRecoveryReceipt()
            ready = true
        } catch { recoveryFailure = "Den lokale førtilstand kunne ikke oprettes" }
    }

    func adoptCurrentPublishedArticle() {
        guard scenario == .publishedRecovery, !sourceAdopted, !coldRestored,
              let original = originalPublishedMember,
              let accepted = model.adoptPublishedMetadata(article, ticket: original,
                stillCurrent: { [weak self] in
                    self?.scenario == .publishedRecovery && self?.coldRestored == false
                }, permitsPublication: { [weak self] value in
                    guard let self else { return false }
                    return value.id == self.article.id && value.bodyRevision == self.article.bodyRevision && value.isPubliclyPublished
                }), model.isCurrent(accepted), model.pendingMutations.isEmpty,
              let access = offline.captureAccess(articleID: article.id),
              access.contentRevision == article.bodyRevision, access.contentKey != originalContentKey else {
            recoveryFailure = "Aktuel lokal kilde blev ikke accepteret"; return
        }
        ticket = access
        sourceAdopted = true
        _ = offline.requestBody(ticket: access, fetch: fetch)
        refreshBodyAvailability()
        updateRecoveryReceipt()
    }

    func reopenStoredArticleOffline() {
        guard scenario == .publishedRecovery, sourceAdopted, !coldRestored, bodyAvailable,
              let disk = diskStorage else { return }
        let cold = FavoritesModel(storage: memory.storage)
        cold.changeContext(to: .confirmed(userID: "local-offline-A"))
        let coordinator = Self.makeCoordinator(model: cold, memory: memory, disk: disk)
        guard cold.pendingMutations.isEmpty, let access = coordinator.captureAccess(articleID: article.id),
              access.contentRevision == article.bodyRevision, access.contentKey != originalContentKey,
              let decoded = coordinator.body(access), ArticleDetailContentPolicy.hasBody(decoded),
              decoded.bodyRevision == article.bodyRevision, decoded.content == article.content else {
            recoveryFailure = "Den kolde lokale tekst kunne ikke læses"; return
        }
        coldModel = cold
        coldOffline = coordinator
        ticket = access
        observe(coordinator)
        recoveredArticle = decoded
        bodyAvailable = true
        coldRestored = true
        updateRecoveryReceipt()
    }

    private func updateRecoveryReceipt() {
        let current = coldModel ?? model
        let value: [String: Any] = ["fixtureID": fixtureID.uuidString, "articleID": article.id,
            "oldRevision": originalPublishedMember?.contentRevision ?? "", "newRevision": article.bodyRevision ?? "",
            "currentRevision": ticket?.contentRevision ?? "", "originalContentKey": originalContentKey ?? "",
            "currentContentKey": ticket?.contentKey ?? "", "sourceAdopted": sourceAdopted,
            "coldRestored": coldRestored, "hasDecodedBody": bodyAvailable,
            "decodedHTMLBytes": recoveredArticle?.content?.utf8.count ?? 0,
            "selectedArticleIDs": current.snapshot.articles.map(\.id), "pendingIntentCount": current.pendingMutations.count,
            "bodyWrites": memory.writes, "fetches": memory.fetches, "bodyReads": memory.bodyReads,
            "firebaseStarted": FirebaseApp.allApps != nil]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let encoded = String(data: data, encoding: .utf8) { recoveryReceipt = encoded }
    }
    private func fetch(_ articleID: String, complete: @escaping @MainActor (Result<Article, Error>) -> Void) {
        guard articleID == article.id else { complete(.failure(Failure.fetch)); return }
        memory.fetches += 1
        if memory.failNextFetch { memory.failNextFetch = false; complete(.failure(Failure.fetch)) }
        else if scenario == .fetchFailure && memory.fetches == 1 { complete(.failure(Failure.fetch)) }
        else if scenario == .held || scenario == .accountRoundTrip || scenario == .savedTags || scenario == .publishedRecovery { memory.held.append(complete) }
        else { complete(.success(article)) }
        objectWillChange.send()
    }
}

struct LocalOfflineBodySmokeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var fixture = LocalOfflineBodyFixture()
    @State private var progressFrames: [String: CGRect] = [:]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                            .accessibilityIdentifier("offline.fixture.firebase")
                        Text(fixture.ready ? "Klar" : "Klargør lokale data").accessibilityIdentifier("offline.fixture.ready")
                        Text(dynamicTypeSize.isAccessibilitySize ? "Tilgængelighedstekst" : "Normal tekst")
                            .accessibilityIdentifier("offline.fixture.textSize")
                            .accessibilityValue(UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory ? "System: tilgængelighed" : "System: standard")
                        Text("Status: \(fixture.status.map { String(describing: $0) } ?? "ingen adgang")")
                            .accessibilityIdentifier("offline.fixture.state")
                        if !fixture.isProbeScenario {
                            Text(fixture.bodyAvailable ? "Tekst: tilgængelig" : "Tekst: ikke gemt")
                                .accessibilityIdentifier("offline.fixture.body")
                        }
                        Text("Skrivninger: \(fixture.writes)").accessibilityIdentifier("offline.fixture.writes")
                        Text("Hentninger: \(fixture.fetches)").accessibilityIdentifier("offline.fixture.fetches")
                        Text("Afventer: \(fixture.heldCount)").accessibilityIdentifier("offline.fixture.held")
                        Text(fixture.generationChanged ? "Ny A-generation" : "Oprindelig læser")
                            .accessibilityIdentifier("offline.fixture.owner")
                        if fixture.scenario == .downloadProgress {
                            Text("Lokal downloadprøve").accessibilityIdentifier("offline.fixture.progressProof")
                                .accessibilityValue(progressReport)
                            HStack {
                                Button("0 %") { fixture.setAudioProgress(0) }.accessibilityIdentifier("offline.fixture.progressZero")
                                Button("42 %") { fixture.setAudioProgress(0.42) }.accessibilityIdentifier("offline.fixture.progress42")
                                Button("100 %") { fixture.setAudioProgress(1) }.accessibilityIdentifier("offline.fixture.progressFull")
                                Button("Afslut", action: fixture.completeAudioProof).accessibilityIdentifier("offline.fixture.progressComplete")
                            }
                            HStack {
                                Button("Ukendt") { fixture.setAudioProgress(nil) }.accessibilityIdentifier("offline.fixture.progressUnknown")
                                Button("Uafklaret", action: fixture.captureMissingAudioState).accessibilityIdentifier("offline.fixture.progressMissing")
                                Button("Venter", action: fixture.awaitAudioPublication).accessibilityIdentifier("offline.fixture.progressWaiting")
                                Button("Fejl", action: fixture.failAudio).accessibilityIdentifier("offline.fixture.progressFailure")
                            }
                            .frame(minHeight: 44)
                        }
                        if fixture.scenario == .publishedRecovery {
                            Text(fixture.coldRestored ? "Kold offlineartikel" : (fixture.sourceAdopted ? "Aktuel kilde accepteret" : "Ældre gemt artikel"))
                                .accessibilityIdentifier("offline.fixture.recoveryStage")
                            Text("Lokal revisionskvittering")
                                .accessibilityIdentifier("offline.fixture.recoveryProof")
                                .accessibilityValue(fixture.recoveryReceipt)
                            if let error = fixture.recoveryFailure {
                                Text(error).accessibilityIdentifier("offline.fixture.recoveryFailure")
                            }
                            Button("Opdatér den gemte artikel", action: fixture.adoptCurrentPublishedArticle)
                                .frame(minHeight: 44).accessibilityIdentifier("offline.fixture.adoptPublished")
                            Button("Genåbn lokal kopi offline", action: fixture.reopenStoredArticleOffline)
                                .frame(minHeight: 44).accessibilityIdentifier("offline.fixture.coldRead")
                        }
                        if fixture.isProbeScenario {
                            Text("Kontroller: \(fixture.probes)").accessibilityIdentifier("offline.fixture.probes")
                            Text("Afventer kontrol: \(fixture.heldProbeCount)").accessibilityIdentifier("offline.fixture.heldProbes")
                            Text("Synkrone indekslæsninger: \(fixture.indexReads)").accessibilityIdentifier("offline.fixture.indexReads")
                            Text("Tekstlæsninger: \(fixture.bodyReads)").accessibilityIdentifier("offline.fixture.bodyReads")
                            Text("Gentegninger: \(fixture.redraws)").accessibilityIdentifier("offline.fixture.redraws")
                            Button("Opdatér visningen", action: fixture.redraw)
                                .accessibilityIdentifier("offline.fixture.redraw")
                            Button("Aflevér lokal kontrol", action: fixture.releaseProbe)
                                .accessibilityIdentifier("offline.fixture.releaseProbe")
                            Button("Fjern lokale bytes og kontrollér igen", action: fixture.removeStoredBodyAndRevalidate)
                                .accessibilityIdentifier("offline.fixture.removeStoredBody")
                        } else if fixture.scenario != .downloadProgress {
                            Button("Aflevér lokal hentning", action: fixture.release)
                                .accessibilityIdentifier("offline.fixture.release")
                        }
                        Button("Skift A → B → A", action: fixture.roundTrip)
                            .accessibilityIdentifier("offline.fixture.roundTrip")
                    }
                    .font(.caption).dynamicTypeSize(.large).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
                    Text("En fortælling til senere").font(.title2.bold())
                    if fixture.scenario == .downloadProgress {
                        ArticleHeaderTagGroup(authorName: "Frederik Kragh", categories: ["Anmeldelser", "TV-serier"], openAuthor: {}) {
                            if let status = fixture.status, let original = fixture.ticket {
                                ArticleOfflineBodyStatusView(ticket: original, state: status,
                                    prepare: { fixture.prepare($0) }, retry: { fixture.retry(original) },
                                    audioState: fixture.audioStatus, audioProgress: fixture.audioProgress, requiresAudio: true)
                            }
                        }
                        .measuringFrames { key, frame in
                            if progressFrames[key] != frame { progressFrames[key] = frame }
                        }
                    } else if let status = fixture.status, let original = fixture.ticket {
                        ArticleOfflineBodyStatusView(ticket: original, state: status,
                            prepare: { fixture.prepare($0) }, retry: { fixture.retry(original) })
                    }
                    if fixture.scenario == .publishedRecovery, fixture.coldRestored,
                       let article = fixture.recoveredArticle {
                        LocalRecoveredOfflineArticleContent(article: article)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Offlineartikel")
            .navigationBarTitleDisplayMode(.inline)
            .task { fixture.start() }
        }
    }
    private var progressReport: String {
        var report = fixture.progressReceipt
        report["frames"] = progressFrames.mapValues {
            ["x": Double($0.minX), "y": Double($0.minY), "width": Double($0.width), "height": Double($0.height)]
        }
        report["systemCategory"] = UIApplication.shared.preferredContentSizeCategory.rawValue
        report["environmentAccessibility"] = dynamicTypeSize.isAccessibilitySize
        report["systemAccessibility"] = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Only the container is a fixture. Rendering and load feedback are the same
/// ArticleHTMLBody/WebKit path used by the product, with a local nil-base URL.
private struct LocalRecoveredOfflineArticleContent: View {
    let article: Article
    @State private var height: CGFloat = 240
    @StateObject private var loadState = ArticleHTMLLoadState()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Offline · lokal prøve", systemImage: "airplane")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("offline.fixture.offlineIndicator")
            ArticleHTMLBody(html: article.content ?? "", articleId: article.id, articleRevision: article.bodyRevision,
                dynamicHeight: $height, loadState: loadState,
                prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
            Text("Webtekst: \(String(describing: loadState.phase))")
                .font(.caption).dynamicTypeSize(.large)
                .accessibilityIdentifier("offline.fixture.webState")
        }
    }
}
#endif
