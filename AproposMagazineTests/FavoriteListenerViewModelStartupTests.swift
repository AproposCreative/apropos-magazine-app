import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual VM -> FirestoreService projection -> FavoritesModel, with local
/// subscription callbacks and journal storage. No normal VM startup or SDK.
@MainActor
final class FavoriteListenerViewModelStartupTests: XCTestCase {
    private typealias VM = ArticleViewModel
    private typealias Service = FirestoreService
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract

    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var reads = 0
        var writes = 0
        var storage: FavoritesModel.Storage {
            .init(read: { [self] namespace, complete in
                self.reads += 1; complete(.success(self.records[namespace]))
            }, write: { [self] namespace, record, expected, complete in
                self.writes += 1
                guard self.records[namespace]?.recordRevision == expected else {
                    complete(.failure(FavoritesJournalFailure.staleRevision)); return
                }
                self.records[namespace] = record; complete(.success(()))
            })
        }
    }

    @MainActor private final class Fixture {
        struct Subscription {
            let uid: String
            let permission: Service.FavoriteCurrentGuard
            let reply: @MainActor (Result<Service.FavoriteSnapshot, Error>) -> Void
        }
        let identity = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        let memory = Memory()
        var actualUID: String?
        var canonicalUID: String?
        var subscriptions: [Subscription] = []
        var cancellations: [Int] = []
        var retries: [UUID] = []
        var subscribeHook: ((Int) -> Void)?
        var cancelHook: ((Int) -> Void)?
        var retryHook: (() -> Void)?
        var canonicalHook: (() -> Void)?
        var canonicalReads = 0
        var actualUIDHook: (() -> Void)?
        var sdkStarts = 0
        lazy var model = FavoritesModel(storage: memory.storage)
        lazy var vm = makeVM()

        init(guarded: Bool = false, uid: String? = "A") {
            sdk = guarded ? ReaderSDKStartupState() : .application
            actualUID = uid; canonicalUID = uid
            _ = identity.adopt(uid.map(Self.session))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        func makeVM() -> VM {
            VM(startup: sdk, identity: identity, actualUserID: { [unowned self] in
                self.actualUIDHook?(); return self.actualUID
            },
                readEffects: VM.ReadEffects(), favoriteObservationModel: model,
                favoriteSubscribe: { [unowned self] uid, permission, reply in
                    XCTAssertTrue(permission())
                    let index = self.subscriptions.count
                    self.subscriptions.append(.init(uid: uid, permission: permission, reply: reply))
                    self.subscribeHook?(index)
                    return { [weak self] in
                        guard let self else { return }
                        self.cancellations.append(index); self.cancelHook?(index)
                    }
                }, favoriteCanonicalUserID: { [unowned self] in
                    self.canonicalReads += 1; self.canonicalHook?(); return self.canonicalUID
                },
                favoriteRetry: { [unowned self] generation in
                    self.retries.append(generation); self.retryHook?()
                })
        }
        func select(_ uid: String?) {
            actualUID = uid; canonicalUID = uid
            _ = identity.adopt(uid.map(Self.session))
            model.changeContext(to: .confirmed(userID: uid))
        }
        func prepareModel() async throws {
            model.changeContext(to: .confirmed(userID: canonicalUID))
            if canonicalUID != nil { try await recoverModel() }
        }
        func recoverModel() async throws {
            let ticket = try XCTUnwrap(model.recoveryTicket())
            XCTAssertTrue(model.beginRecovery(ticket))
            let recovered = await model.finishRecovery(ticket, success: true)
            XCTAssertTrue(recovered); XCTAssertTrue(model.snapshot.recoveryReady)
        }
        func send(_ index: Int, ids: [String], cached: Bool = false, pending: Bool = false) {
            let documents = ids.map { id in
                Service.FavoriteDocument(id: id, fields: ["id": id, "name": "Lokal artikel", "slug": id,
                    "content": "<p>Must not enter the favorite journal</p>", "intro": "Legacy intro",
                    "trailer": "<iframe>Legacy embed</iframe>", "pressAccreditation": false,
                    "lastPublished": "2026-10-24T01:00:00Z"])
            }
            subscriptions[index].reply(.success(.init(documents: documents, isFromCache: cached, hasPendingWrites: pending)))
        }
        var ids: [String] { model.snapshot.articles.map(\.id) }

        func openGuardedStartup() async throws {
            let config = try Startup.Configuration(projectID: "local-favorite-listener", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echo = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let data = try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echo,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 4, "state": "active"],
                    "validUntilMs": 20_000
                ])
                return try Contract.decodeMembershipResponse(data: data, for: request)
            }
            let verify: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: config.writerFenceRevision, migrationRevision: config.migrationRevision,
                    validUntilMs: 20_000)
            }
            let start: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [unowned self] _, admit in
                try admit(); self.sdkStarts += 1
            }
            let coordinator = Startup(canonical: identity, sdkState: sdk, configuration: config,
                readMarker: { nil }, readMembership: membership, verify: verify, startSDK: start,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await coordinator.start(context: identity.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testForegroundRestartsTerminalFavoriteListenerWithoutManualRetry() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        f.send(0, ids: ["saved"])
        f.subscriptions[0].reply(.failure(NSError(domain: "local.terminal-listener", code: 1)))
        XCTAssertEqual(f.ids, ["saved"])
        // Existing actual foreground entry, before any new recovery API exists.
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2)
        guard f.subscriptions.count == 2 else { f.vm.stopFavoritesListener(); return }
        XCTAssertTrue(f.retries.isEmpty)
        f.send(1, ids: ["saved", "remote-change"])
        XCTAssertEqual(f.ids, ["remote-change", "saved"])
        f.vm.stopFavoritesListener()
    }

    func testSynchronousInitialTerminalFailureWaitsForExplicitRefreshThenRestartsOnce() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.subscribeHook = { index in
            guard index == 0 else { return }
            f.subscribeHook = nil
            f.subscriptions[index].reply(.failure(NSError(domain: "local.terminal-listener", code: 1)))
        }
        f.vm.startFavoritesListenerIfNeeded()
        XCTAssertEqual(f.subscriptions.count, 1)
        f.vm.startFavoritesListenerIfNeeded()
        XCTAssertEqual(f.subscriptions.count, 1) // Publication/start retries must not loop.
        f.vm.resumeReaderStartup(retryFailedFavorites: false)
        XCTAssertEqual(f.subscriptions.count, 1) // Feed work in the same event must not consume a second retry.
        f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 2)
        guard f.subscriptions.count == 2 else { f.vm.stopFavoritesListener(); return }
        f.send(1, ids: ["recovered"])
        f.vm.refreshFavoritesAfterInterruption(); f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.ids, ["recovered"])
        XCTAssertTrue(f.retries.isEmpty)
        f.vm.stopFavoritesListener()
    }

    func testInterruptionRefreshDeduplicatesActiveListenerAndPreservesPendingSelection() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded(); f.send(0, ids: ["keep", "removed-locally"])
        let article = try XCTUnwrap(f.model.snapshot.articles.first { $0.id == "removed-locally" })
        let mutation = try XCTUnwrap(f.model.setFavorite(article, enabled: false))
        XCTAssertEqual(f.ids, ["keep"]); XCTAssertEqual(f.model.snapshot.pendingArticleIDs, ["removed-locally"])
        for _ in 0..<8 { f.vm.refreshFavoritesAfterInterruption() }
        XCTAssertEqual(f.subscriptions.count, 1)
        f.subscriptions[0].reply(.failure(NSError(domain: "local.terminal-listener", code: 1)))
        f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 2)
        guard f.subscriptions.count == 2 else { f.vm.stopFavoritesListener(); return }
        f.send(1, ids: ["keep", "removed-locally", "remote"])
        for _ in 0..<8 { f.vm.refreshFavoritesAfterInterruption() }
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.ids, ["keep", "remote"])
        XCTAssertEqual(f.model.snapshot.pendingArticleIDs, ["removed-locally"])
        XCTAssertTrue(f.model.isCurrent(mutation)); XCTAssertTrue(f.retries.isEmpty)
        f.vm.stopFavoritesListener()
    }

    func testMetadataDecodeFailureRemainsLiveAndNextSnapshotRecoversWithoutNewSubscription() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded(); f.send(0, ids: ["saved"])
        f.subscriptions[0].reply(.success(.init(documents: [.init(id: "invalid/path", fields: [:])],
            isFromCache: false, hasPendingWrites: false)))
        XCTAssertEqual(f.ids, ["saved"]); XCTAssertEqual(f.model.snapshot.state, .cloudFailed)
        f.vm.refreshFavoritesAfterInterruption(); f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 1); XCTAssertTrue(f.cancellations.isEmpty)
        f.send(0, ids: ["corrected"])
        XCTAssertEqual(f.ids, ["corrected"]); XCTAssertNil(f.model.snapshot.issueMessage)
        f.vm.stopFavoritesListener()
    }

    func testOldCallbacksAfterReconnectAndAccountRoundTripCannotChangeNewObservation() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded(); f.send(0, ids: ["saved"])
        f.subscriptions[0].reply(.failure(NSError(domain: "local.terminal-listener", code: 1)))
        f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 2)
        guard f.subscriptions.count == 2 else { f.vm.stopFavoritesListener(); return }
        f.send(1, ids: ["reconnected"])
        let connected = f.model.snapshot
        f.send(0, ids: ["late-old-cache"], cached: true); f.send(0, ids: ["late-old-server"])
        f.subscriptions[0].reply(.failure(NSError(domain: "local.late-terminal", code: 1)))
        XCTAssertEqual(f.model.snapshot, connected)
        f.select("B"); f.select("A")
        let transitioned = f.model.snapshot
        f.send(1, ids: ["late-before-roundtrip"])
        f.subscriptions[1].reply(.failure(NSError(domain: "local.late-terminal", code: 1)))
        XCTAssertEqual(f.model.snapshot, transitioned)
        try await f.recoverModel(); f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 3)
        guard f.subscriptions.count == 3 else { f.vm.stopFavoritesListener(); return }
        f.send(2, ids: ["current"])
        f.send(0, ids: ["old-A"]); f.send(1, ids: ["old-A-again"])
        f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 3); XCTAssertEqual(f.ids, ["current"])
        XCTAssertTrue(f.subscriptions[2].permission()); f.vm.stopFavoritesListener()
    }

    func testInterruptionRefreshDoesNotStartUnrequestedGuestOrClosedObservation() async throws {
        let untouched = Fixture(); try await untouched.prepareModel()
        untouched.vm.refreshFavoritesAfterInterruption()
        XCTAssertTrue(untouched.subscriptions.isEmpty)
        let guest = Fixture(uid: nil); try await guest.prepareModel()
        guest.vm.startFavoritesListenerIfNeeded(); guest.vm.refreshFavoritesAfterInterruption()
        XCTAssertTrue(guest.subscriptions.isEmpty)
        let closed = Fixture(guarded: true); try await closed.prepareModel()
        closed.vm.startFavoritesListenerIfNeeded()
        closed.vm.refreshFavoritesAfterInterruption(); closed.vm.refreshFavoritesAfterInterruption()
        XCTAssertTrue(closed.subscriptions.isEmpty)
        try await closed.openGuardedStartup(); closed.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(closed.subscriptions.count, 1)
        closed.vm.stopFavoritesListener()
    }

    func testTerminalErrorPublicationReentryDoesNotAutomaticallyAttachUntilInterruption() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded(); f.send(0, ids: ["saved"])
        var errorPublications = 0
        let observation = f.model.changes.sink { snapshot in
            guard snapshot.state == .cloudFailed else { return }
            errorPublications += 1
            f.vm.startFavoritesListenerIfNeeded()
        }
        f.subscriptions[0].reply(.failure(NSError(domain: "local.terminal-listener", code: 1)))
        XCTAssertEqual(errorPublications, 1); XCTAssertEqual(f.subscriptions.count, 1)
        f.vm.refreshFavoritesAfterInterruption()
        XCTAssertEqual(f.subscriptions.count, 2)
        guard f.subscriptions.count == 2 else { f.vm.stopFavoritesListener(); return }
        f.send(1, ids: ["recovered"])
        XCTAssertEqual(f.ids, ["recovered"]); XCTAssertTrue(f.retries.isEmpty)
        f.vm.stopFavoritesListener(); withExtendedLifetime(observation) {}
    }

    func testClosedGatePreservesModelAndRequestedListenerResumesOnceAfterRealStartup() async throws {
        let f = Fixture(guarded: true)
        try await f.prepareModel()
        let before = f.model.snapshot, reads = f.memory.reads, writes = f.memory.writes
        _ = f.vm
        f.vm.startFavoritesListenerIfNeeded(); f.vm.resumeReaderStartup()
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.cancellations.isEmpty)
        XCTAssertEqual(f.model.snapshot, before)
        XCTAssertEqual(f.memory.reads, reads); XCTAssertEqual(f.memory.writes, writes)
        try await f.openGuardedStartup()
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertEqual(f.sdkStarts, 1); XCTAssertEqual(f.subscriptions.count, 1)
        XCTAssertEqual(f.subscriptions.first?.uid, "A")
        f.send(0, ids: ["fresh"])
        XCTAssertEqual(f.ids, ["fresh"]); XCTAssertTrue(f.model.snapshot.serverConfirmed)
        f.vm.stopFavoritesListener()
    }

    func testGuestAndPartialLocalInjectionCannotFallThroughToLiveSubscription() async throws {
        let guest = Fixture(uid: nil)
        try await guest.prepareModel()
        guest.vm.startFavoritesListenerIfNeeded(); guest.vm.resumeReaderStartup()
        XCTAssertTrue(guest.subscriptions.isEmpty)
        let f = Fixture(); try await f.prepareModel()
        let incomplete = VM(startup: f.sdk, identity: f.identity, actualUserID: { f.actualUID },
            readEffects: VM.ReadEffects(), favoriteObservationModel: f.model)
        incomplete.startFavoritesListenerIfNeeded(); incomplete.resumeReaderStartup()
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.ids.isEmpty)
        XCTAssertEqual(f.memory.writes, 0)
    }

    func testFirstProviderCaptureReentryCannotSubscribeAfterStopOrReplaceNewAttempt() async throws {
        for startReplacement in [false, true] {
            let f = Fixture(); try await f.prepareModel()
            _ = f.vm
            var getterReentries = 0
            f.actualUIDHook = {
                f.actualUIDHook = nil
                getterReentries += 1
                XCTAssertTrue(f.subscriptions.isEmpty)
                if startReplacement { f.vm.startFavoritesListenerIfNeeded() }
                else { f.vm.stopFavoritesListener() }
            }
            f.vm.startFavoritesListenerIfNeeded()
            XCTAssertEqual(getterReentries, 1)
            XCTAssertEqual(f.subscriptions.count, startReplacement ? 1 : 0)
            XCTAssertTrue(f.cancellations.isEmpty)
            // A stopped request can explicitly resume; an already attached
            // nested request must survive and remain deduplicated.
            f.vm.resumeReaderStartup()
            XCTAssertEqual(f.subscriptions.count, 1)
            XCTAssertTrue(f.subscriptions[0].permission())
            f.send(0, ids: ["current"])
            XCTAssertEqual(f.ids, ["current"])
            f.vm.stopFavoritesListener()
            XCTAssertEqual(f.cancellations, [0])
        }
    }

    func testActualSnapshotProjectionPreservesCachePendingAndServerProofWithoutBodyFields() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded(); f.vm.startFavoritesListenerIfNeeded()
        XCTAssertEqual(f.subscriptions.count, 1)
        f.send(0, ids: ["cached"], cached: true)
        XCTAssertEqual(f.ids, ["cached"]); XCTAssertFalse(f.model.snapshot.serverConfirmed)
        f.send(0, ids: ["pending"], pending: true)
        XCTAssertEqual(f.ids, ["pending"]); XCTAssertFalse(f.model.snapshot.serverConfirmed)
        f.send(0, ids: ["server"])
        XCTAssertEqual(f.ids, ["server"]); XCTAssertTrue(f.model.snapshot.serverConfirmed)
        let article = try XCTUnwrap(f.model.snapshot.articles.first)
        XCTAssertTrue(article.content?.isEmpty != false); XCTAssertTrue(article.intro?.isEmpty != false)
        XCTAssertNil(article.trailer)
        f.vm.stopFavoritesListener()
    }

    func testAccountRoundTripRejectsBothOldCacheAndServerBeforeFreshObservation() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        f.select("B"); f.select("A")
        XCTAssertEqual(f.cancellations, [0]); XCTAssertFalse(f.subscriptions[0].permission())
        f.send(0, ids: ["old-cache"], cached: true); f.send(0, ids: ["old-server"])
        XCTAssertTrue(f.ids.isEmpty); XCTAssertFalse(f.model.snapshot.serverConfirmed)
        try await f.recoverModel()
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2)
        f.send(1, ids: ["new"])
        XCTAssertEqual(f.ids, ["new"]); XCTAssertTrue(f.model.snapshot.serverConfirmed)
        f.vm.stopFavoritesListener()
    }

    func testRevokedModelTicketWithSameUIDAndGenerationRequiresNewPhysicalListener() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        let generation = f.model.snapshot.generation
        let intervening = try XCTUnwrap(f.model.observationTicket())
        XCTAssertEqual(f.model.snapshot.generation, generation)
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancellations, [0])
        f.model.endObservation(intervening)
        f.send(0, ids: ["old"]); f.send(1, ids: ["current"])
        XCTAssertEqual(f.ids, ["current"]); XCTAssertTrue(f.subscriptions[1].permission())
        f.vm.stopFavoritesListener()
    }

    func testSameUIDNewModelGenerationReattachesWithoutCanonicalAccountChange() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        let oldGeneration = f.model.snapshot.generation, canonical = f.identity.contextTicket()
        f.model.changeContext(to: .unresolved)
        f.model.changeContext(to: .confirmed(userID: "A"))
        try await f.recoverModel()
        XCTAssertNotEqual(f.model.snapshot.generation, oldGeneration)
        XCTAssertEqual(f.identity.contextTicket(), canonical)
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancellations, [0])
        f.send(0, ids: ["old"], cached: true); f.send(1, ids: ["current"])
        XCTAssertEqual(f.ids, ["current"])
        f.vm.stopFavoritesListener()
    }

    func testCancellationHookCanStartReplacementWithoutOuterStopRemovingIt() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        f.cancelHook = { index in
            guard index == 0 else { return }
            f.cancelHook = nil; f.vm.startFavoritesListenerIfNeeded()
        }
        f.vm.stopFavoritesListener()
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancellations, [0])
        f.send(0, ids: ["stale"]); f.send(1, ids: ["replacement"])
        XCTAssertEqual(f.ids, ["replacement"]); XCTAssertTrue(f.subscriptions[1].permission())
        f.vm.stopFavoritesListener()
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testSynchronousFirstSnapshotReplacementKeepsOnlyNewAttemptAfterSubscribeReturns() async throws {
        let f = Fixture(); try await f.prepareModel()
        var replaced = false
        let observation = f.model.changes.sink { snapshot in
            guard snapshot.serverConfirmed, !replaced else { return }
            replaced = true
            f.vm.stopFavoritesListener(); f.vm.startFavoritesListenerIfNeeded()
        }
        f.subscribeHook = { index in
            guard index == 0 else { return }
            f.subscribeHook = nil; f.send(0, ids: ["initial"])
        }
        f.vm.startFavoritesListenerIfNeeded()
        XCTAssertTrue(replaced); XCTAssertEqual(f.subscriptions.count, 2)
        XCTAssertEqual(f.cancellations, [0]); XCTAssertTrue(f.subscriptions[1].permission())
        f.send(0, ids: ["late"]); f.send(1, ids: ["replacement"])
        XCTAssertEqual(f.ids, ["replacement"])
        f.vm.stopFavoritesListener()
        withExtendedLifetime(observation) {}
    }

    func testRetryUsesOriginalGenerationAndCannotAttachAfterRetryHookChangesIt() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        f.vm.retryFavorites(generation: UUID())
        XCTAssertTrue(f.retries.isEmpty); XCTAssertEqual(f.subscriptions.count, 1)
        let generation = f.model.snapshot.generation
        f.vm.retryFavorites(generation: generation)
        XCTAssertEqual(f.retries, [generation]); XCTAssertEqual(f.subscriptions.count, 2)
        f.retryHook = {
            f.retryHook = nil
            f.model.changeContext(to: .unresolved)
            f.model.changeContext(to: .confirmed(userID: "A"))
        }
        f.vm.retryFavorites(generation: generation)
        XCTAssertEqual(f.subscriptions.count, 2)
        f.send(1, ids: ["old-retry"])
        XCTAssertTrue(f.ids.isEmpty)
        try await f.recoverModel()
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 3)
        f.send(2, ids: ["fresh"]); XCTAssertEqual(f.ids, ["fresh"])
        f.vm.stopFavoritesListener()
    }

    func testProviderOrCanonicalMismatchCannotReviveOldListenerWhenUIDReturns() async throws {
        for providerMismatch in [true, false] {
            let f = Fixture(); try await f.prepareModel()
            f.vm.startFavoritesListenerIfNeeded()
            if providerMismatch { f.actualUID = "B" } else { f.canonicalUID = "B" }
            f.send(0, ids: ["wrong-owner"])
            XCTAssertTrue(f.ids.isEmpty); XCTAssertEqual(f.cancellations, [0])
            f.vm.startFavoritesListenerIfNeeded()
            XCTAssertEqual(f.subscriptions.count, 1)
            f.actualUID = "A"; f.canonicalUID = "A"
            f.vm.resumeReaderStartup()
            XCTAssertEqual(f.subscriptions.count, 2); XCTAssertFalse(f.subscriptions[0].permission())
            f.send(0, ids: ["stale"]); f.send(1, ids: ["new"])
            XCTAssertEqual(f.ids, ["new"])
            f.vm.stopFavoritesListener()
        }
    }

    func testCanonicalGetterChangingProviderDuringCallbackRevokesOriginalAttemptPermanently() async throws {
        // Observe the actual normal-delivery path, then target its last getter
        // in a fresh identical fixture. No fixed service/VM call count is assumed.
        let control = Fixture(); try await control.prepareModel()
        control.vm.startFavoritesListenerIfNeeded()
        let initialReads = control.canonicalReads
        control.send(0, ids: ["candidate"])
        let callbackReads = control.canonicalReads - initialReads
        XCTAssertGreaterThan(callbackReads, 0); XCTAssertEqual(control.ids, ["candidate"])
        control.vm.stopFavoritesListener()

        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        let firstReads = f.canonicalReads, before = f.model.snapshot, writes = f.memory.writes
        var deniedAtFinalLookup = false
        f.canonicalHook = {
            guard f.canonicalReads - firstReads == callbackReads else { return }
            f.canonicalHook = nil
            deniedAtFinalLookup = true
            // The service's earlier checks passed. This final VM getter still
            // returns A, but changes the provider just before model.applyRemote.
            f.actualUID = "B"
        }
        f.send(0, ids: ["candidate"])
        f.canonicalHook = nil
        XCTAssertTrue(deniedAtFinalLookup)
        XCTAssertEqual(f.model.snapshot, before); XCTAssertEqual(f.memory.writes, writes)
        f.actualUID = "A"
        XCTAssertFalse(f.subscriptions[0].permission())
        XCTAssertEqual(f.cancellations, [0])
        f.send(0, ids: ["revived"])
        XCTAssertEqual(f.model.snapshot, before); XCTAssertEqual(f.memory.writes, writes)
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2)
        f.send(1, ids: ["fresh"])
        XCTAssertEqual(f.ids, ["fresh"])
        f.vm.stopFavoritesListener()
    }

    func testRetryHookStartingSameGenerationListenerPreservesItsNewAttempt() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        let generation = f.model.snapshot.generation
        f.retryHook = {
            f.retryHook = nil
            f.vm.startFavoritesListenerIfNeeded()
        }
        f.vm.retryFavorites(generation: generation)
        XCTAssertEqual(f.retries, [generation]); XCTAssertEqual(f.subscriptions.count, 2)
        XCTAssertEqual(f.cancellations, [0]); XCTAssertTrue(f.subscriptions[1].permission())
        f.send(0, ids: ["stale"]); f.send(1, ids: ["retry-hook"])
        XCTAssertEqual(f.ids, ["retry-hook"])
        f.vm.stopFavoritesListener()
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testRetryRemovalHookStartingReplacementPreventsOldRetryEffectsAndSecondAttach() async throws {
        let f = Fixture(); try await f.prepareModel()
        f.vm.startFavoritesListenerIfNeeded()
        f.cancelHook = { index in
            guard index == 0 else { return }
            f.cancelHook = nil
            f.vm.startFavoritesListenerIfNeeded()
        }
        f.vm.retryFavorites(generation: f.model.snapshot.generation)
        XCTAssertTrue(f.retries.isEmpty) // The newer start superseded the old retry before its effect.
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancellations, [0])
        XCTAssertTrue(f.subscriptions[1].permission())
        f.send(0, ids: ["stale"]); f.send(1, ids: ["remove-hook"])
        XCTAssertEqual(f.ids, ["remove-hook"])
        f.vm.stopFavoritesListener()
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testDeallocationCancelsOnceAndCannotEndNewVMsSameOwnerModelTicket() async throws {
        for replaceBeforeCleanup in [false, true] {
            let f = Fixture(); try await f.prepareModel()
            let removed = expectation(description: "Original favorite listener removed")
            f.cancelHook = { index in if index == 0 { removed.fulfill() } }
            var original: VM? = f.makeVM()
            original?.startFavoritesListenerIfNeeded()
            weak var released = original
            original = nil
            XCTAssertNil(released)
            var replacement: VM?
            if replaceBeforeCleanup {
                replacement = f.makeVM(); replacement?.startFavoritesListenerIfNeeded()
            }
            // The old callback is inert immediately, even before deinit cleanup.
            f.send(0, ids: ["released"])
            XCTAssertTrue(f.ids.isEmpty)
            await fulfillment(of: [removed], timeout: 3)
            for _ in 0..<8 { await Task.yield() }
            XCTAssertEqual(f.cancellations, [0])
            if let replacement {
                XCTAssertEqual(f.subscriptions.count, 2); XCTAssertTrue(f.subscriptions[1].permission())
                f.send(1, ids: ["replacement"])
                XCTAssertEqual(f.ids, ["replacement"])
                replacement.stopFavoritesListener()
                XCTAssertEqual(f.cancellations, [0, 1])
            }
        }
    }
}
