import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual observation ownership and editorial policy with synchronous local
/// hooks. No application facade, defaults, SDK reference or network is started.
@MainActor
final class ArticleAvailabilityModelStartupTests: XCTestCase {
    private typealias Model = ArticleAvailabilityModel
    private enum Injected: Error { case offline }

    @MainActor private final class Fixture {
        struct Subscription {
            let id: String
            let permission: Model.CurrentGuard
            let reply: (Result<Model.Update, Error>) -> Void
        }
        let identity = CanonicalSessionState()
        var allowed = true
        var subscriptions: [Subscription] = []
        var cancelled: [Int] = []
        var deadlines: [() -> Void] = []
        var cancelledDeadlines: [Int] = []
        var saved: [Model.Snapshot] = []
        var permissionHook: (() -> Void)?
        var cancelHook: ((Int) -> Void)?
        var subscribeHook: ((Int) -> Void)?
        var scheduleHook: ((Int) -> Void)?
        var saveHook: (() -> Void)?
        lazy var model = Model(save: { [unowned self] value in
            self.saved.append(value); self.saveHook?()
        }, schedule: { [unowned self] fire in
            let index = self.deadlines.count
            self.deadlines.append(fire); self.scheduleHook?(index)
            return { [weak self] in self?.cancelledDeadlines.append(index) }
        })

        init() { select("A") }
        func select(_ uid: String?) {
            _ = identity.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
        @discardableResult
        func watch(_ id: String = "article") -> Model.ObservationTicket {
            let original = identity.contextTicket()
            return model.observe(id: id, stillCurrent: { [unowned self] in
                self.permissionHook?()
                return self.allowed && self.identity.isCurrent(original)
            }) { [unowned self] id, permission, reply in
                XCTAssertTrue(permission())
                let index = self.subscriptions.count
                self.subscriptions.append(.init(id: id, permission: permission, reply: reply))
                self.subscribeHook?(index)
                return { [weak self] in
                    self?.cancelled.append(index); self?.cancelHook?(index)
                }
            }
        }
        func send(_ index: Int = 0, withdrawn: Bool, cached: Bool = false, revision: String? = nil) {
            subscriptions[index].reply(.success(.init(withdrawn: withdrawn, isFromCache: cached, revision: revision)))
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func article(_ id: String = "article", revision: String = "v1") -> Article {
        Article(id: id, name: "Lokal historie", slug: id, content: "<p>Tekst</p>", intro: "", topicID: "culture",
                isDraft: false, lastPublished: revision)
    }

    func testDeniedOrInvalidNewObservationDoesNotCancelCurrentListener() {
        let f = Fixture(), original = f.watch()
        let denied = f.model.observe(id: "next", stillCurrent: { false }) { _, _, _ in
            XCTFail("Closed entry subscribed"); return {}
        }
        XCTAssertFalse(f.model.isCurrent(denied)); XCTAssertTrue(f.model.isCurrent(original))
        for id in ["", ".", "..", "a/b", "__reserved__"] {
            let invalid = f.watch(id)
            XCTAssertFalse(f.model.isCurrent(invalid))
        }
        XCTAssertEqual(f.subscriptions.count, 1); XCTAssertTrue(f.cancelled.isEmpty)
        XCTAssertEqual(f.model.checkingID, "article")
    }

    func testFirstPermissionHookCannotOverwriteNewerNestedObservation() {
        let f = Fixture()
        var nested: Model.ObservationTicket?
        f.permissionHook = { f.permissionHook = nil; nested = f.watch("new") }
        let outer = f.watch("old")
        XCTAssertFalse(f.model.isCurrent(outer))
        XCTAssertTrue(nested.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.subscriptions.map(\.id), ["new"])
        XCTAssertEqual(f.model.checkingID, "new"); XCTAssertTrue(f.cancelled.isEmpty)
    }

    func testFirstPermissionHookCannotReviveOuterAfterNestedStartAndStop() {
        let f = Fixture()
        f.permissionHook = {
            f.permissionHook = nil
            let nested = f.watch("new")
            f.model.stop(observation: nested)
        }
        let outer = f.watch("old")
        XCTAssertFalse(f.model.isCurrent(outer)); XCTAssertNil(f.model.checkingID)
        XCTAssertEqual(f.subscriptions.map(\.id), ["new"]); XCTAssertEqual(f.cancelled, [0])
    }

    func testWillChangeReplacementBeforeSubscribeStartsOnlyNewestListener() {
        let f = Fixture()
        var nested: Model.ObservationTicket?, once = false
        let observer = f.model.objectWillChange.sink {
            guard !once else { return }; once = true
            nested = f.watch("new")
        }
        let outer = f.watch("old")
        XCTAssertFalse(f.model.isCurrent(outer)); XCTAssertTrue(nested.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.subscriptions.map(\.id), ["new"]); XCTAssertEqual(f.model.checkingID, "new")
        withExtendedLifetime(observer) {}
    }

    func testWillChangeAccountRevocationBeforeSubscribePerformsNoTransport() {
        let f = Fixture()
        var once = false
        let observer = f.model.objectWillChange.sink {
            guard !once else { return }; once = true; f.select("B")
        }
        let original = f.watch()
        XCTAssertFalse(f.model.isCurrent(original)); XCTAssertTrue(f.subscriptions.isEmpty)
        XCTAssertTrue(f.deadlines.isEmpty); XCTAssertNil(f.model.checkingID)
        XCTAssertTrue(f.saved.isEmpty)
        withExtendedLifetime(observer) {}
    }

    func testReplacementCancellationHookCannotClobberItsNewerListener() {
        let f = Fixture(), first = f.watch("first")
        var newest: Model.ObservationTicket?
        f.cancelHook = { index in
            guard index == 0 else { return }; f.cancelHook = nil; newest = f.watch("newest")
        }
        let superseded = f.watch("middle")
        XCTAssertFalse(f.model.isCurrent(first)); XCTAssertFalse(f.model.isCurrent(superseded))
        XCTAssertTrue(newest.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.subscriptions.map(\.id), ["first", "newest"])
        XCTAssertEqual(f.cancelled, [0]); XCTAssertEqual(f.model.checkingID, "newest")
        f.model.stop(observation: superseded)
        XCTAssertEqual(f.cancelled, [0])
        if let newest { f.model.stop(observation: newest) }
        XCTAssertEqual(f.cancelled, [0, 1])
    }

    func testStopCancellationHookKeepsReplacementForSameArticleAndItsDeadline() {
        let f = Fixture(), old = f.watch()
        var current: Model.ObservationTicket?
        f.cancelHook = { index in
            guard index == 0 else { return }; f.cancelHook = nil; current = f.watch()
        }
        f.model.stop(observation: old)
        XCTAssertTrue(current.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancelled, [0])
        XCTAssertEqual(f.cancelledDeadlines, [0]); XCTAssertEqual(f.model.checkingID, "article")
        f.deadlines[0](); f.send(0, withdrawn: true)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertEqual(f.model.checkingID, "article")
        f.deadlines[1]()
        XCTAssertNil(f.model.checkingID); XCTAssertNotNil(f.model.errorMessage)
        if let current { f.model.stop(observation: current) }
        XCTAssertEqual(f.cancelled, [0, 1])
    }

    func testScopedOldOrForeignStopCannotStopNewSameArticleObservation() {
        let f = Fixture(), foreign = Fixture()
        let old = f.watch(), current = f.watch(), foreignTicket = foreign.watch()
        f.model.stop(observation: old); f.model.stop(observation: foreignTicket)
        XCTAssertTrue(f.model.isCurrent(current)); XCTAssertEqual(f.cancelled, [0])
        XCTAssertEqual(f.model.checkingID, "article")
        f.send(1, withdrawn: false, revision: "v2")
        XCTAssertEqual(f.model.approvedRevision(for: "article"), "v2")
        XCTAssertNil(f.model.errorMessage)
    }

    func testSynchronousServerReplyBeforeCancelAssignmentRetainsExactCancellation() {
        let f = Fixture()
        f.subscribeHook = { index in f.send(index, withdrawn: true) }
        let original = f.watch()
        XCTAssertTrue(f.model.isCurrent(original)); XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertNil(f.model.checkingID); XCTAssertTrue(f.deadlines.isEmpty)
        XCTAssertEqual(f.saved.last?.withdrawnIDs, ["article"])
        f.model.stop(observation: original)
        XCTAssertEqual(f.cancelled, [0])
    }

    func testSynchronousReplyReplacementCancelsReturnedOldHandleExactlyOnce() {
        let f = Fixture()
        var newest: Model.ObservationTicket?, once = false
        let observer = f.model.changes.sink { _ in
            guard !once else { return }; once = true; newest = f.watch("new")
        }
        f.subscribeHook = { index in if index == 0 { f.send(index, withdrawn: true) } }
        let old = f.watch()
        XCTAssertFalse(f.model.isCurrent(old)); XCTAssertTrue(newest.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.subscriptions.map(\.id), ["article", "new"])
        XCTAssertEqual(f.cancelled, [0]); XCTAssertEqual(f.model.checkingID, "new")
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        withExtendedLifetime(observer) {}
    }

    func testSynchronousDeadlineBeforeHandleReturnCannotRemainChecking() {
        let f = Fixture()
        f.scheduleHook = { index in f.deadlines[index]() }
        let original = f.watch()
        XCTAssertTrue(f.model.isCurrent(original)); XCTAssertNil(f.model.checkingID)
        XCTAssertNotNil(f.model.errorMessage); XCTAssertEqual(f.cancelledDeadlines, [0])
        f.send(withdrawn: false, revision: "v2")
        XCTAssertNil(f.model.errorMessage); XCTAssertEqual(f.model.approvedRevision(for: "article"), "v2")
    }

    func testObservedPermissionDenialPermanentlyRevokesOriginalListener() {
        let f = Fixture(), original = f.watch()
        f.allowed = false
        XCTAssertFalse(f.model.isCurrent(original))
        f.allowed = true // A transient provider value is not a new observation.
        XCTAssertFalse(f.model.isCurrent(original)); XCTAssertFalse(f.subscriptions[0].permission())
        f.send(withdrawn: true)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.cancelled, [0]); XCTAssertNil(f.model.checkingID)
        let fresh = f.watch()
        XCTAssertTrue(f.model.isCurrent(fresh)); f.send(1, withdrawn: true)
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
    }

    func testSchedulerRevocationRetiresReturnedDeadlineAndListener() {
        let f = Fixture()
        f.scheduleHook = { _ in f.scheduleHook = nil; f.allowed = false }
        let original = f.watch()
        XCTAssertFalse(f.model.isCurrent(original)); XCTAssertNil(f.model.checkingID)
        XCTAssertEqual(f.cancelled, [0]); XCTAssertEqual(f.cancelledDeadlines, [0])
        f.allowed = true; f.deadlines[0](); f.send(withdrawn: true)
        XCTAssertTrue(f.saved.isEmpty); XCTAssertNil(f.model.errorMessage)
        let fresh = f.watch()
        XCTAssertTrue(f.model.isCurrent(fresh)); XCTAssertEqual(f.model.checkingID, "article")
    }

    func testSchedulerReplacementCannotInstallOldDeadlineOverNewSameArticle() {
        let f = Fixture()
        var newest: Model.ObservationTicket?
        f.scheduleHook = { _ in f.scheduleHook = nil; newest = f.watch() }
        let old = f.watch()
        XCTAssertFalse(f.model.isCurrent(old)); XCTAssertTrue(newest.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.cancelled, [0]); XCTAssertEqual(f.cancelledDeadlines, [0])
        f.deadlines[0]()
        XCTAssertEqual(f.model.checkingID, "article"); XCTAssertNil(f.model.errorMessage)
        f.deadlines[1]()
        XCTAssertNil(f.model.checkingID); XCTAssertNotNil(f.model.errorMessage)
    }

    func testOldCallbackAndDeadlineAfterAccountRoundTripCannotAlterFreshObservation() {
        let f = Fixture(), old = f.watch()
        f.select("B"); f.select("A")
        let current = f.watch()
        f.send(0, withdrawn: true); f.subscriptions[0].reply(.failure(Injected.offline)); f.deadlines[0]()
        XCTAssertFalse(f.model.isCurrent(old)); XCTAssertTrue(f.model.isCurrent(current))
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.model.checkingID, "article"); XCTAssertNil(f.model.errorMessage)
        f.send(1, withdrawn: true)
        XCTAssertEqual(f.model.withdrawnIDs, ["article"]); XCTAssertNil(f.model.checkingID)
    }

    func testWithdrawalSurvivesAccountChangeOfflineFailureAndCachedPublication() {
        let f = Fixture(); f.watch(); f.send(withdrawn: true)
        f.select("B"); f.model.stop(); f.watch()
        f.send(1, withdrawn: false, cached: true, revision: "old")
        f.subscriptions[1].reply(.failure(Injected.offline))
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertFalse(f.model.permitsBody(article())); XCTAssertNotNil(f.model.errorMessage)
        f.send(1, withdrawn: false, revision: "v2")
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.model.permitsBody(article(revision: "v2")))
        XCTAssertFalse(f.model.permitsBody(article(revision: "v1")))
    }

    func testCachedWithdrawalAfterServerPublicationDoesNotDowngradeSameObserver() {
        let f = Fixture(); f.watch(); f.send(withdrawn: false, revision: "v2")
        let saveCount = f.saved.count
        f.send(withdrawn: true, cached: true)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertEqual(f.saved.count, saveCount)
        XCTAssertTrue(f.model.permitsBody(article(revision: "v2"))); XCTAssertNil(f.model.errorMessage)
    }

    func testSaveHookReplacementCannotClearNewObservationStatus() {
        let f = Fixture(); f.watch()
        var newest: Model.ObservationTicket?
        f.saveHook = { f.saveHook = nil; newest = f.watch("new") }
        f.send(withdrawn: true)
        XCTAssertTrue(newest.map(f.model.isCurrent) == true)
        XCTAssertEqual(f.model.checkingID, "new"); XCTAssertNil(f.model.errorMessage)
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertEqual(f.saved.last?.withdrawnIDs, ["article"])
        f.deadlines[0]()
        XCTAssertEqual(f.model.checkingID, "new")
    }

    func testWithdrawalEdgeStillInvalidatesActualLoaderBeforeImmediateRepublication() {
        let f = Fixture()
        var fetches: [(Result<Article, Error>) -> Void] = []
        var bodies: [Article] = []
        let loader = ArticleDetailLoader(scheduleDeadline: { _, _ in {} },
            fetchArticle: { _, callback in fetches.append(callback) }, fetchAuthor: { _, _ in },
            permitsBody: { f.model.permitsBody($0) }, onBody: { value, _ in bodies.append(value) },
            onAuthor: { _, _, _ in })
        var once = false, withdrawalEdges = 0
        let observer = f.model.changes.sink { change in
            for id in change.invalidatedBodyIDs { loader.invalidate(id: id) }
            if change.withdrawnIDs.contains("article") {
                withdrawalEdges += 1
                if !once { once = true; f.send(withdrawn: false, revision: "v2") }
            }
        }
        loader.select(id: "article"); f.watch(); f.send(withdrawn: true)
        XCTAssertEqual(withdrawalEdges, 1)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertEqual(f.model.approvedRevision(for: "article"), "v2")
        loader.select(id: "article")
        XCTAssertEqual(fetches.count, 1, "Invalidation cannot retire the occupied physical loader slot")
        fetches[0](.success(article(revision: "v1")))
        XCTAssertTrue(bodies.isEmpty); XCTAssertEqual(fetches.count, 2)
        fetches[1](.success(article(revision: "v2")))
        XCTAssertEqual(bodies.map(\.lastPublished), ["v2"])
        XCTAssertEqual(f.saved.last?.approvedRevisions["article"], "v2")
        withExtendedLifetime(observer) {}
    }
}
