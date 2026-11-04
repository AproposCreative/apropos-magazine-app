import FirebaseCore
import XCTest
@testable import Apropos

/// Actual favorite/drain/bookmark adapters with a real shared writer runtime.
/// Only SDK identity, references and physical callbacks are replaced locally.
@MainActor
final class FavoriteWriteAdapterStartupTests: XCTestCase {
    private typealias Guard = ReaderWriterDrainRuntime.Guard
    private typealias Completion = ReaderWriterDrainRuntime.Completion
    private enum Failure: Error { case rejected }

    @MainActor private final class Fixture {
        struct Write {
            let kind: String, uid: String, articleID: String
            let enabled: Bool
            let article: Article?
            let original: Guard
            let completion: Completion
        }
        struct Drain { let original: Guard; let completion: Completion }
        let canonical = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        var uid: String? = "A"
        var permitted = true
        var identityReads = 0, referencePreparations = 0, writeAdmissions = 0, diagnostics = 0
        var identityHook: (() -> Void)?, referenceHook: (() -> Void)?, diagnosticHook: (() -> Void)?
        var records: [FavoritesNamespace: Data] = [:]
        var writes: [Write] = [], drains: [Drain] = []
        var deadlines: [@MainActor () -> Void] = []
        private var waiters: [(String, Int, XCTestExpectation)] = []
        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [weak self] in self?.uid },
            schedule: { [weak self] action in
                guard let self else { return {} }
                self.deadlines.append(action); self.notify("deadline", self.deadlines.count)
                return {}
            }, makeDrain: { throw Failure.rejected }, maximumActiveWrites: 1)
        lazy var model = FavoritesModel(storage: .init(read: { [weak self] in self?.records[$0] },
            write: { [weak self] in self?.records[$0] = $1 }))
        lazy var service = FirestoreService(favoriteWriteEffects: .init(identity: { [weak self] in
            self?.readUID()
        }, performWrite: { [weak self] uid, current, start in
            guard let self else { throw Failure.rejected }
            self.writeAdmissions += 1
            try await self.runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
        }, write: { [weak self] uid, article, enabled, current, completion in
            guard let self else { completion(Failure.rejected); return }
            self.startWrite(kind: "favorite", uid: uid, articleID: article.id, enabled: enabled,
                article: article, original: current, completion: completion)
        }, drain: { [weak self] current, completion in
            guard let self else { completion(Failure.rejected); return }
            self.referencePreparations += 1; self.referenceHook?()
            guard current() else { completion(CancellationError()); return }
            self.drains.append(.init(original: current, completion: completion)); self.notify("drain", self.drains.count)
        }))
        lazy var manager = makeManager(includeBookmarkEffects: true)

        init(guarded: Bool = false) {
            sdk = guarded ? ReaderSDKStartupState() : .application
            _ = canonical.adopt(Self.session("A"))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        }
        func select(_ uid: String?) {
            self.uid = uid; _ = canonical.adopt(uid.map(Self.session))
            model.changeContext(to: .confirmed(userID: uid))
        }
        func readUID() -> String? { identityReads += 1; identityHook?(); return uid }
        func capture() -> Guard {
            let captured = sdk.captureReaderWork(identity: canonical, actualUserID: { [weak self] in self?.uid })
            return { [weak self] in self?.permitted == true && captured?() == true }
        }
        func makeManager(includeBookmarkEffects: Bool) -> UserManager {
            let bookmarks = UserManager.BookmarkEffects(identity: { [weak self] in
                guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
                let actual = self.readUID()
                return .init(actualUID: actual, canonicalUID: self.canonical.snapshot.userID)
            }, performWrite: { [weak self] uid, current, start in
                guard let self else { throw Failure.rejected }
                self.writeAdmissions += 1
                try await self.runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
            }, updateExisting: { [weak self] uid, id, enabled, current, completion in
                guard let self else { completion(Failure.rejected); return }
                self.startWrite(kind: "bookmark", uid: uid, articleID: id, enabled: enabled,
                    article: nil, original: current, completion: completion)
            }, diagnostic: { [weak self] current in
                guard let self else { return }
                self.diagnosticHook?()
                if current() { self.diagnostics += 1 }
            })
            return UserManager(state: UserProfileState(), effects: .init(capturePermission: { nil },
                identity: { .init(actualUID: nil, canonicalUID: nil) },
                read: { _, _, _, _ in throw Failure.rejected }, write: { _, _, _ in throw Failure.rejected },
                subscribe: { _, _ in }, unsubscribe: { _, _ in }, updateFCM: { _, _ in }),
                currentProfileSeed: { nil }, bookmarkEffects: includeBookmarkEffects ? bookmarks : nil)
        }
        private func startWrite(kind: String, uid: String, articleID: String, enabled: Bool,
            article: Article?, original: @escaping Guard, completion: @escaping Completion) {
            referencePreparations += 1; referenceHook?()
            guard original() else { completion(CancellationError()); return }
            writes.append(.init(kind: kind, uid: uid, articleID: articleID, enabled: enabled,
                article: article, original: original, completion: completion))
            notify("write", writes.count)
        }
        private func notify(_ kind: String, _ count: Int) {
            let ready = waiters.filter { $0.0 == kind && $0.1 <= count }
            waiters.removeAll { $0.0 == kind && $0.1 <= count }; ready.forEach { $0.2.fulfill() }
        }
        func wait(_ kind: String, count: Int = 1) async {
            let currentCount = kind == "write" ? writes.count : (kind == "drain" ? drains.count : deadlines.count)
            if currentCount >= count { return }
            let value = XCTestExpectation(description: "Actual adapter physical \(kind) \(count)")
            waiters.append((kind, count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed)
        }
        func ticket(enabled: Bool = true) async throws -> FavoritesModel.DispatchTicket {
            model.changeContext(to: .confirmed(userID: "A"))
            let recovery = try XCTUnwrap(model.recoveryTicket())
            XCTAssertTrue(model.beginRecovery(recovery))
            let recovered = await model.finishRecovery(recovery, success: true); XCTAssertTrue(recovered)
            if !enabled { _ = model.setFavorite(Self.article(), enabled: true) }
            let mutation = try XCTUnwrap(model.setFavorite(Self.article(), enabled: enabled))
            let result = await model.beginDispatch(mutation)
            return try XCTUnwrap(result)
        }
        static func article() -> Article {
            .init(id: "article", name: "Original titel", slug: "article", content: "Private large body",
                intro: "Original intro", topicID: "culture", contentRevision: "r1")
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func succeeds(_ operation: () async throws -> Void) async -> Bool {
        do { try await operation(); return true } catch { return false }
    }

    func testInjectedConstructionAndClosedStartupRejectAllAdaptersBeforeIdentityOrReferenceLookup() async throws {
        let f = Fixture(guarded: true); _ = f.service; _ = f.manager; _ = f.runtime
        XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.referencePreparations, 0)
        let ticket = try await f.ticket(), original = f.capture()
        let write = await succeeds { try await f.service.setFavorite(Fixture.article(), enabled: true,
            expectedUserID: "A", stillCurrent: original) }
        let drain = await succeeds { try await f.service.drainPendingFavoriteWrites(expectedUserID: "A", stillCurrent: original) }
        let bookmark = await succeeds { try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A",
            model: f.model, stillCurrent: original) }
        XCTAssertFalse(write); XCTAssertFalse(drain); XCTAssertFalse(bookmark)
        XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.referencePreparations, 0); XCTAssertEqual(f.diagnostics, 0)
        XCTAssertEqual(f.writeAdmissions, 0)
    }

    func testFavoriteAddAndRemoveKeepOriginalLightweightPayloadAndAwaitPhysicalCallback() async {
        for enabled in [true, false] {
            let f = Fixture(), original = f.capture()
            var finished = false
            let task = Task { let ok = await self.succeeds {
                try await f.service.setFavorite(Fixture.article(), enabled: enabled, expectedUserID: "A", stillCurrent: original)
            }; finished = true; return ok }
            await f.wait("write")
            XCTAssertFalse(finished); XCTAssertFalse(f.runtime.isPhysicallyIdle)
            XCTAssertEqual(f.writes.first?.uid, "A"); XCTAssertEqual(f.writes.first?.articleID, "article")
            XCTAssertEqual(f.writes.first?.enabled, enabled); XCTAssertEqual(f.writes.first?.article?.name, "Original titel")
            XCTAssertTrue(f.writes.first?.article?.content?.isEmpty ?? true)
            XCTAssertTrue(f.writes.first?.article?.intro?.isEmpty ?? true)
            f.writes[0].completion(nil)
            let ok = await task.value; XCTAssertTrue(ok); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        }
    }

    func testBookmarkUsesOriginalDispatchWithoutLoadedProfileForAddAndRemove() async throws {
        for enabled in [true, false] {
            let f = Fixture(), ticket = try await f.ticket(enabled: enabled), original = f.capture()
            XCTAssertNil(f.manager.currentUser)
            let task = Task { await self.succeeds {
                try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original)
            } }
            await f.wait("write")
            XCTAssertEqual(f.writes.first?.kind, "bookmark"); XCTAssertEqual(f.writes.first?.uid, "A")
            XCTAssertEqual(f.writes.first?.articleID, ticket.mutation.articleID); XCTAssertEqual(f.writes.first?.enabled, enabled)
            f.writes[0].completion(nil)
            let ok = await task.value; XCTAssertTrue(ok); XCTAssertEqual(f.diagnostics, 0)
            XCTAssertTrue(f.model.isCurrent(ticket)) // Adapter success alone never ACKs the durable mutation.
        }
    }

    func testPartiallyInjectedProfileManagerCannotFallBackToLiveBookmarkServices() async throws {
        let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
        let partial = f.makeManager(includeBookmarkEffects: false)
        let ok = await succeeds { try await partial.setBookmark(ticket: ticket, expectedUserID: "A",
            model: f.model, stillCurrent: original) }
        XCTAssertFalse(ok); XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.referencePreparations, 0)
    }

    func testIdentityReentryClosesOriginalPermissionBeforeFavoriteDrainOrBookmarkReference() async throws {
        for adapter in ["favorite", "drain", "bookmark"] {
            let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
            f.identityHook = { f.identityHook = nil; f.permitted = false }
            let ok = await succeeds {
                switch adapter {
                case "favorite": try await f.service.setFavorite(Fixture.article(), enabled: true, expectedUserID: "A", stillCurrent: original)
                case "drain": try await f.service.drainPendingFavoriteWrites(expectedUserID: "A", stillCurrent: original)
                default: try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original)
                }
            }
            XCTAssertFalse(ok); XCTAssertEqual(f.referencePreparations, 0); XCTAssertEqual(f.writeAdmissions, 0)
            XCTAssertEqual(f.diagnostics, 0)
        }
    }

    func testLastReferenceGuardRejectsReentrantAccountChangeWithoutPhysicalEnqueue() async throws {
        for bookmark in [false, true] {
            let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
            f.referenceHook = { f.referenceHook = nil; f.select(nil); f.select("A") }
            let ok = await succeeds {
                if bookmark { try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original) }
                else { try await f.service.setFavorite(Fixture.article(), enabled: true, expectedUserID: "A", stillCurrent: original) }
            }
            XCTAssertFalse(ok); XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
            XCTAssertEqual(f.diagnostics, 0)
        }
    }

    func testCancelledFavoriteKeepsSharedPhysicalSlotUntilCallbackAndCannotAdmitBookmark() async throws {
        let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
        var finished = false
        let task = Task { let ok = await self.succeeds {
            try await f.service.setFavorite(Fixture.article(), enabled: true, expectedUserID: "A", stillCurrent: original)
        }; finished = true; return ok }
        await f.wait("write"); task.cancel()
        XCTAssertFalse(finished); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        let other = await succeeds { try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original) }
        XCTAssertFalse(other); XCTAssertEqual(f.writes.count, 1); XCTAssertFalse(finished)
        f.writes[0].completion(nil)
        let ok = await task.value; XCTAssertFalse(ok); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testHeldBookmarkAfterAccountRoundTripCannotCompleteOrDiagnoseForNewOwner() async throws {
        let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
        var finished = false
        let task = Task { let ok = await self.succeeds {
            try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original)
        }; finished = true; return ok }
        await f.wait("write"); f.select("B"); f.select("A")
        XCTAssertFalse(finished); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.writes[0].completion(Failure.rejected)
        let ok = await task.value; XCTAssertFalse(ok); XCTAssertEqual(f.diagnostics, 0)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testDrainDeadlineCannotReleaseActualFavoriteWriteOrAuthorizeItsMirror() async throws {
        let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
        var finished = false
        var favoriteCompleted = false, mirrorAttempts = 0
        let write = Task { let ok = await self.succeeds {
            try await FavoritesMutationTransport.perform(model: f.model, ticket: ticket, expectedUserID: "A",
                stillCurrent: original, writeFavorite: { mutation, uid, current in
                    try await f.service.setFavorite(mutation.article, enabled: mutation.enabled,
                        expectedUserID: uid, stillCurrent: current)
                    favoriteCompleted = true
                }, setBookmark: { ticket, uid, model, current in
                    mirrorAttempts += 1
                    try await f.manager.setBookmark(ticket: ticket, expectedUserID: uid,
                        model: model, stillCurrent: current)
                })
        }; finished = true; return ok }
        await f.wait("write")
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { () -> ReaderWriterDrainCoordinator.Failure? in
            do { _ = try await f.runtime.drain(stop); return nil }
            catch { return error as? ReaderWriterDrainCoordinator.Failure }
        }
        await f.wait("deadline")
        f.deadlines[0]()
        let error = await drain.value
        XCTAssertEqual(error, .timedOut)
        XCTAssertFalse(finished); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        XCTAssertFalse(favoriteCompleted); XCTAssertEqual(mirrorAttempts, 0)
        XCTAssertFalse(f.writes[0].original())
        let mirror = await succeeds { try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A",
            model: f.model, stillCurrent: original) }
        XCTAssertFalse(mirror); XCTAssertEqual(f.writes.count, 1)
        f.writes[0].completion(nil)
        let ok = await write.value
        XCTAssertFalse(ok); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertTrue(favoriteCompleted); XCTAssertEqual(mirrorAttempts, 1)
        XCTAssertEqual(f.writes.count, 1, "The stopped runtime must reject the second physical stage")
        XCTAssertTrue(f.model.isCurrent(ticket)) // The timeout/write never manufactured a combined durable ACK.
    }

    func testObservedDenialCannotReviveFavoriteOnLateCallbackAfterGateReopens() async {
        let f = Fixture(), original = f.capture()
        let task = Task { await self.succeeds {
            try await f.service.setFavorite(Fixture.article(), enabled: true, expectedUserID: "A", stillCurrent: original)
        } }
        await f.wait("write")
        f.permitted = false; XCTAssertFalse(f.writes[0].original()); f.permitted = true
        f.writes[0].completion(nil)
        let ok = await task.value; XCTAssertFalse(ok)
        XCTAssertFalse(f.writes[0].original()); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testDrainWaitsForPhysicalReturnAfterCancellationAndNeverBorrowsFreshPermission() async {
        let f = Fixture(), original = f.capture()
        var finished = false
        let task = Task { let ok = await self.succeeds {
            try await f.service.drainPendingFavoriteWrites(expectedUserID: "A", stillCurrent: original)
        }; finished = true; return ok }
        await f.wait("drain"); task.cancel()
        XCTAssertFalse(finished)
        f.drains[0].completion(nil)
        let ok = await task.value; XCTAssertFalse(ok)
        f.drains[0].completion(Failure.rejected) // Duplicate SDK return cannot resume twice.
    }

    func testDrainReferenceReentryAndLateSameUIDRoundTripBothRejectOriginalRecovery() async {
        let blocked = Fixture(), blockedGuard = blocked.capture()
        blocked.referenceHook = { blocked.permitted = false }
        let rejected = await succeeds { try await blocked.service.drainPendingFavoriteWrites(expectedUserID: "A", stillCurrent: blockedGuard) }
        XCTAssertFalse(rejected); XCTAssertTrue(blocked.drains.isEmpty)
        let f = Fixture(), original = f.capture()
        let task = Task { await self.succeeds { try await f.service.drainPendingFavoriteWrites(expectedUserID: "A", stillCurrent: original) } }
        await f.wait("drain"); f.select(nil); f.select("A"); f.drains[0].completion(nil)
        let ok = await task.value; XCTAssertFalse(ok)
    }

    func testBookmarkFailureDiagnosticKeepsOriginalGuardAtItsOwnBoundary() async throws {
        for invalidate in [false, true] {
            let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
            if invalidate { f.diagnosticHook = { f.permitted = false } }
            let task = Task { await self.succeeds {
                try await f.manager.setBookmark(ticket: ticket, expectedUserID: "A", model: f.model, stillCurrent: original)
            } }
            await f.wait("write"); f.writes[0].completion(Failure.rejected)
            let ok = await task.value; XCTAssertFalse(ok)
            XCTAssertEqual(f.diagnostics, invalidate ? 0 : 1)
            XCTAssertTrue(f.model.isCurrent(ticket))
        }
    }

    func testMirrorForwardsOriginalGuardAcrossHeldProviderWithoutRecapturing() async throws {
        let f = Fixture(), ticket = try await f.ticket(), original = f.capture()
        var captured: Guard?
        let ok = await succeeds {
            try await FavoritesProfileMirror.perform(model: f.model, ticket: ticket, expectedUserID: "A", stillCurrent: original,
                effects: .init(identity: { .init(actualUID: f.uid, canonicalUID: f.canonical.snapshot.userID) },
                    guardedUpdateExisting: { _, _, _, permission in
                        captured = permission
                        f.permitted = false; XCTAssertFalse(permission()); f.permitted = true
                    }))
        }
        XCTAssertFalse(ok); XCTAssertFalse(captured?() ?? true); XCTAssertTrue(f.model.isCurrent(ticket))
    }
}
