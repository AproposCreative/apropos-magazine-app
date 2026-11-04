import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class FavoritesCloudStartupTests: XCTestCase {
    func testClosedRecoveryRetainsLocalIntentWithoutProviderOrSpin() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        h.capturable = false; h.owner("A")
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupSettle()
        let captures = h.captures
        for _ in 0..<20 { h.cloud.refresh() }
        XCTAssertEqual(h.captures, captures)
        XCTAssertTrue(h.drains.isEmpty); XCTAssertTrue(h.calls.isEmpty)
        XCTAssertTrue(h.model.isCurrent(mutation))
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
        XCTAssertFalse(h.cloud.activity.draining)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testReadyWithoutPendingDoesNotCaptureAnotherPermission() async {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready(); let captures = h.captures
        for _ in 0..<20 { h.cloud.refresh() }
        XCTAssertEqual(h.captures, captures)
        XCTAssertTrue(h.calls.isEmpty)
    }

    func testClosedDispatchKeepsQueuedPayloadAndOnlyExplicitRetryRecaptures() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready(); h.capturable = false
        let mutation = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupSettle()
        let captures = h.captures
        h.capturable = true
        for _ in 0..<20 { h.cloud.refresh() }
        XCTAssertEqual(h.captures, captures); XCTAssertTrue(h.calls.isEmpty)
        XCTAssertEqual(h.record?.pending.first?.intentID, mutation.id)
        XCTAssertEqual(h.record?.pending.first?.phase, .queued)
        h.cloud.submit(mutation, expectedUserID: "A")
        await favoriteStartupWait { h.calls.count == 1 }
        XCTAssertEqual(h.calls[0].ticket.mutation.id, mutation.id)
    }

    func testRecoveryPermissionCapturedBeforeTaskAndDenialDoesNotRecapture() async {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        h.owner("A"); XCTAssertEqual(h.captures, 1)
        h.allowed = false
        await favoriteStartupWait { !h.cloud.activity.draining }
        XCTAssertTrue(h.drains.isEmpty)
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.model.snapshot.state, .recoveryFailed)
        h.allowed = true
        for _ in 0..<20 { h.cloud.refresh() }
        XCTAssertEqual(h.captures, 1)
        h.cloud.retryRecovery(generation: h.model.snapshot.generation)
        await favoriteStartupWait { h.drains.count == 1 }
    }

    func testLateDrainSuccessAfterRevocationCannotApproveReadiness() async {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        h.owner("A"); await favoriteStartupWait { h.drains.count == 1 }
        h.allowed = false; h.finishDrain(0)
        await favoriteStartupWait { !h.cloud.activity.draining }
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.model.snapshot.state, .recoveryFailed)
        XCTAssertTrue(h.calls.isEmpty)
    }

    func testObservedDenialCannotReviveOnSameUIDAndPermissionTrueAgain() async {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        h.owner("A"); await favoriteStartupWait { h.drains.count == 1 }
        h.allowed = false; XCTAssertFalse(h.drains[0].current())
        h.allowed = true; h.finishDrain(0)
        await favoriteStartupWait { !h.cloud.activity.draining }
        XCTAssertFalse(h.model.snapshot.recoveryReady)
        XCTAssertEqual(h.drains.count, 1)
    }

    func testCaptureReentryChangesOwnerBeforeOldDrainCanStart() async {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        var changed = false
        h.captureHook = {
            if !changed { changed = true; h.owner("B") }
        }
        h.owner("A")
        await favoriteStartupWait { h.drains.count == 1 }
        XCTAssertEqual(h.drains.map(\.uid), ["B"])
        XCTAssertEqual(h.model.context, .confirmed(userID: "B"))
        h.finishDrain(0); await favoriteStartupWait { h.model.snapshot.recoveryReady }
    }

    func testNilCaptureReentrantRefreshIsBounded() {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        h.capturable = false
        h.captureHook = { h.cloud.refresh() }
        h.owner("A")
        XCTAssertEqual(h.captures, 1)
        XCTAssertTrue(h.drains.isEmpty)
        XCTAssertFalse(h.cloud.activity.draining)
    }

    func testDispatchCaptureReentryCannotSendOldOwnersMutation() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready(); var changed = false
        h.captureHook = {
            if !changed { changed = true; h.owner("B") }
        }
        _ = h.model.setFavorite(favoriteStartupArticle(), enabled: true)
        await favoriteStartupWait { h.drains.count == 2 }
        XCTAssertTrue(h.calls.isEmpty)
        XCTAssertEqual(h.drains.map(\.uid), ["A", "B"])
        XCTAssertEqual(h.cloud.activity.activeWrites, 0)
    }

    func testDenialDuringStartedJournalWritePerformsLocalCleanupBeforeReleasingSlot() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready(); h.holdWrites = true
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        h.releaseWrite() // Initial local queued intent; dispatch then persists started.
        await favoriteStartupWait { h.heldWrites.count == 1 && h.cloud.activity.activeWrites == 1 }
        h.allowed = false
        XCTAssertTrue(h.calls.isEmpty)
        h.releaseWrite()
        await favoriteStartupWait { h.heldWrites.count == 1 }
        XCTAssertEqual(h.cloud.activity.activeWrites, 1)
        XCTAssertEqual(h.heldWrites[0].record.pending.first?.phase, .failed)
        h.releaseWrite()
        await favoriteStartupWait { h.cloud.activity.activeWrites == 0 }
        XCTAssertEqual(h.record?.pending.first?.phase, .failed)
        XCTAssertTrue(h.calls.isEmpty)
    }

    func testLateProviderSuccessAfterDenialDoesNotAcknowledge() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready()
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupWait { h.calls.count == 1 }
        h.allowed = false; h.finishWrite(0)
        await favoriteStartupWait { h.cloud.activity.activeWrites == 0 }
        XCTAssertEqual(h.record?.pending.first?.phase, .failed)
        XCTAssertEqual(h.model.snapshot.pendingArticleIDs, ["article"])
    }

    func testPhysicalOldOwnerWriteStillBlocksSameKeyAfterABA() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready()
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupWait { h.calls.count == 1 }
        h.owner(nil); h.owner("A")
        await favoriteStartupWait { h.drains.count == 2 }
        h.finishDrain(1); await favoriteStartupWait { h.model.snapshot.recoveryReady }
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: false))
        await favoriteStartupSettle()
        XCTAssertEqual(h.calls.count, 1)
        XCTAssertFalse(h.calls[0].current())
        h.finishWrite(0); await favoriteStartupWait { h.calls.count == 2 }
        XCTAssertFalse(h.calls[1].ticket.mutation.enabled)
        XCTAssertEqual(h.peak, 1)
    }

    func testReceiptIOKeepsPhysicalSlotAndHistoricalACKDoesNotRetireAfterDenial() async throws {
        let h = FavoriteStartupHarness(maximumConcurrentWrites: 1); defer { h.stop() }
        await h.ready()
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupWait { h.calls.count == 1 }
        let observation = try XCTUnwrap(h.model.observationTicket())
        XCTAssertTrue(h.model.applyRemote(.init(articles: [favoriteStartupArticle()], isFromCache: false,
            hasPendingWrites: false), ticket: observation))
        h.holdWrites = true; h.finishWrite(0)
        await favoriteStartupWait { h.heldWrites.count == 1 }
        XCTAssertEqual(h.heldWrites[0].record.pending.first?.phase, .acknowledged)
        h.allowed = false; h.releaseWrite()
        await favoriteStartupWait { h.cloud.activity.activeWrites == 0 }
        XCTAssertEqual(h.record?.pending.first?.phase, .acknowledged, "Already registered historical disk receipt is not undone")
        XCTAssertEqual(h.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertTrue(h.heldWrites.isEmpty, "Denied completion must not start a retirement write")
    }

    func testNormalServerMatchedACKRetirementPublishesAfterRemovingItsOwnIntent() async throws {
        let h = FavoriteStartupHarness(); defer { h.stop() }
        await h.ready()
        _ = try XCTUnwrap(h.model.setFavorite(favoriteStartupArticle(), enabled: true))
        await favoriteStartupWait { h.calls.count == 1 }
        let observation = try XCTUnwrap(h.model.observationTicket())
        XCTAssertTrue(h.model.applyRemote(.init(articles: [favoriteStartupArticle()], isFromCache: false,
            hasPendingWrites: false), ticket: observation))
        h.finishWrite(0)
        await favoriteStartupWait { h.cloud.activity.activeWrites == 0 }
        XCTAssertTrue(h.model.snapshot.pendingArticleIDs.isEmpty)
        XCTAssertEqual(h.model.snapshot.state, .ready)
        XCTAssertTrue(h.record?.pending.isEmpty == true)
        XCTAssertEqual(h.calls.count, 1)
    }
}

@MainActor
func favoriteStartupArticle(_ id: String = "article") -> Article {
    Article(id: id, name: "Article", slug: id, content: "<p>Body</p>", intro: "Intro", topicID: "topic",
            lastPublished: "2026-10-20T12:00:00Z", contentRevision: "r1")
}
@MainActor
func favoriteStartupSettle() async { for _ in 0..<80 { await Task.yield() } }
@MainActor
func favoriteStartupWait(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<2000 { if predicate() { return }; await Task.yield() }
    XCTFail("Expected bounded local lifecycle transition", file: file, line: line)
}

/// Typed memory journal and held physical calls, shared by the focused model cases.
@MainActor
final class FavoriteStartupHarness {
    enum Failure: Error { case injected }
    struct DrainCall { let uid: String; let current: FavoritesCloudCoordinator.Guard; let continuation: CheckedContinuation<Void, Error> }
    struct Call { let ticket: FavoritesModel.DispatchTicket; let uid: String; let current: FavoritesCloudCoordinator.Guard; let continuation: CheckedContinuation<Void, Error> }
    struct HeldWrite {
        let namespace: FavoritesNamespace; let record: FavoritesRecord; let expected: UUID?
        let completion: @MainActor (Result<Void, Error>) -> Void
    }
    var records: [FavoritesNamespace: FavoritesRecord] = [:]
    var drains: [DrainCall] = [], calls: [Call] = [], heldWrites: [HeldWrite] = []
    var holdWrites = false, failWrites = false, capturable = true, allowed = true
    var captures = 0, liveWrites = 0, peak = 0
    var captureHook: (() -> Void)?
    var permissionHook: (() -> Void)?
    var uid: String?
    var model: FavoritesModel!
    var cloud: FavoritesCloudCoordinator!
    private let connected: Bool
    private var observation: AnyCancellable?
    private var liveDrainIDs = Set<Int>(), liveCallIDs = Set<Int>()
    var record: FavoritesRecord? { model.context.namespace.flatMap { records[$0] } }
    init(maximumConcurrentWrites: Int = 4, connected: Bool = true) {
        self.connected = connected
        model = FavoritesModel(storage: .init(read: { [weak self] namespace, completion in
            guard let self else { completion(.failure(FavoritesJournalFailure.readFailed)); return }
            completion(.success(self.records[namespace]))
        }, write: { [weak self] namespace, record, expected, completion in
            guard let self else { completion(.failure(FavoritesJournalFailure.writeFailed)); return }
            let work = HeldWrite(namespace: namespace, record: record, expected: expected, completion: completion)
            if self.holdWrites { self.heldWrites.append(work) } else { self.commit(work) }
        }))
        cloud = FavoritesCloudCoordinator(model: model, maximumConcurrentWrites: maximumConcurrentWrites,
            capturePermission: { [weak self] in
                guard let self else { return nil }
                self.captures += 1
                let generation = self.model.snapshot.generation
                self.captureHook?()
                guard self.capturable else { return nil }
                return { [weak self] in
                    guard let self else { return false }
                    self.permissionHook?()
                    return self.allowed && self.model.snapshot.generation == generation
                }
            }, drainPendingWrites: { [weak self] uid, current in
                guard let self, current() else { throw Failure.injected }
                let index = self.drains.count
                try await withCheckedThrowingContinuation { continuation in
                    self.liveDrainIDs.insert(index); self.drains.append(.init(uid: uid, current: current, continuation: continuation))
                }
            }, write: { [weak self] ticket, uid, current in
                guard let self, current() else { throw Failure.injected }
                self.liveWrites += 1; self.peak = max(self.peak, self.liveWrites)
                defer { self.liveWrites -= 1 }
                let index = self.calls.count
                try await withCheckedThrowingContinuation { continuation in
                    self.liveCallIDs.insert(index); self.calls.append(.init(ticket: ticket, uid: uid, current: current, continuation: continuation))
                }
            })
        if connected {
            observation = model.changes.sink { [weak self] snapshot in
                guard let self, snapshot.generation == self.model.snapshot.generation,
                      snapshot.revision == self.model.snapshot.revision else { return }
                self.cloud.setOwner(expectedUserID: self.uid, generation: snapshot.generation)
            }
        }
    }
    func owner(_ value: String?) {
        uid = value; model.changeContext(to: .confirmed(userID: value))
        if connected, model.context == .confirmed(userID: value) {
            cloud.setOwner(expectedUserID: value, generation: model.snapshot.generation)
        }
    }
    func ready() async {
        owner("A"); await favoriteStartupWait { self.drains.count == 1 }
        finishDrain(0); await favoriteStartupWait { self.model.snapshot.recoveryReady }
        await favoriteStartupSettle()
    }
    func manuallyReady() async throws {
        owner("A")
        let ticket = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(ticket))
        let result = await model.finishRecovery(ticket, success: true)
        XCTAssertTrue(result)
    }
    func finishDrain(_ index: Int, fail: Bool = false) {
        guard index >= 0, liveDrainIDs.remove(index) != nil else { return }
        if fail { drains[index].continuation.resume(throwing: Failure.injected) } else { drains[index].continuation.resume() }
    }
    func finishWrite(_ index: Int, fail: Bool = false) {
        guard liveCallIDs.remove(index) != nil else { return }
        if fail { calls[index].continuation.resume(throwing: Failure.injected) } else { calls[index].continuation.resume() }
    }
    func releaseWrite() { if !heldWrites.isEmpty { commit(heldWrites.removeFirst()) } }
    private func commit(_ work: HeldWrite) {
        if failWrites { work.completion(.failure(FavoritesJournalFailure.writeFailed)); return }
        guard records[work.namespace]?.recordRevision == work.expected else {
            work.completion(.failure(FavoritesJournalFailure.staleRevision)); return
        }
        records[work.namespace] = work.record; work.completion(.success(()))
    }
    func stop() {
        uid = nil; model.changeContext(to: .unresolved)
        cloud.setOwner(expectedUserID: nil, generation: model.snapshot.generation)
        holdWrites = false; failWrites = true
        while !heldWrites.isEmpty { releaseWrite() }
        for index in Array(liveDrainIDs) { finishDrain(index, fail: true) }
        for index in Array(liveCallIDs) { finishWrite(index, fail: true) }
    }
}
