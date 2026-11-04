import FirebaseCore
import XCTest
@testable import Apropos

/// Uses the actual facade/snapshot handling with an injected subscription and
/// Podcast mirror hook. No Firestore, application runtime or defaults are used.
@MainActor
final class ArticleAvailabilityServiceStartupTests: XCTestCase {
    private typealias Service = ArticleAvailabilityService
    private typealias Document = Service.Document
    private enum Injected: Error { case offline }

    @MainActor private final class Fixture {
        struct Subscription {
            let id: String
            let permission: Service.CurrentGuard
            let reply: @MainActor (Result<Document, Error>) -> Void
        }
        let identity = CanonicalSessionState()
        var actualUID: String? = "A"
        var allowed = true
        var subscriptions: [Subscription] = []
        var cancelled: [Int] = []
        var mirroredIDs: [String] = []
        var saved: [ArticleAvailabilityModel.Snapshot] = []
        var mirrorHook: (() -> Void)?
        var cancelHook: (() -> Void)?
        lazy var model = ArticleAvailabilityModel(save: { [unowned self] in self.saved.append($0) }, schedule: { _ in {} })

        init() { select("A") }
        func select(_ uid: String?) {
            actualUID = uid
            _ = identity.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
        @discardableResult
        func watch(_ id: String = "article") -> ArticleAvailabilityModel.ObservationTicket? {
            guard let original = ReaderSDKStartupState.application.captureReaderWork(identity: identity,
                actualUserID: { [unowned self] in self.actualUID }) else { return nil }
            return Service.observe(id, stillCurrent: { [unowned self] in self.allowed && original() }, model: model,
                subscribe: { [unowned self] id, permission, reply in
                    XCTAssertTrue(permission())
                    let index = self.subscriptions.count
                    self.subscriptions.append(.init(id: id, permission: permission, reply: reply))
                    return { [weak self] in self?.cancelled.append(index); self?.cancelHook?() }
                }, recordPodcastMirror: { [unowned self] id, _ in
                    self.mirroredIDs.append(id); self.mirrorHook?()
                })
        }
        func send(_ value: Document, at index: Int = 0) { subscriptions[index].reply(.success(value)) }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func document(id: String = "article", revision: String = "2026-10-24T10:00:00Z",
                          cached: Bool = false, pending: Bool = false, withdrawn: Bool = false) -> Document {
        var data: [String: Any] = [
            "id": id, "lastPublished": revision,
            "fieldData": ["name": "Lokal artikel", "slug": id, "content": "<p>Tekst</p>"]
        ]
        if withdrawn { data["publicationState"] = "withdrawn" }
        return .init(exists: true, isFromCache: cached, hasPendingWrites: pending, data: data)
    }
    private func missing(cached: Bool = false, pending: Bool = false) -> Document {
        .init(exists: false, isFromCache: cached, hasPendingWrites: pending, data: [:])
    }

    func testClosedEntryDoesNotSubscribeOrMirrorOrInitializeFirebase() {
        let f = Fixture(); f.allowed = false
        XCTAssertNil(f.watch())
        XCTAssertNil(Service.observe("article", stillCurrent: { false }))
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
    }

    func testInvalidDocumentIdentifiersCannotStartInjectedOrLiveSubscription() {
        let f = Fixture()
        for id in ["", "a/b", ".", "..", "__reserved__", "a\u{0}b"] {
            XCTAssertNil(f.watch(id))
            XCTAssertNil(Service.observe(id, stillCurrent: { true }))
        }
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.mirroredIDs.isEmpty)
    }

    func testServerMissingDocumentRecordsMirrorAndWithdrawal() {
        let f = Fixture(); XCTAssertNotNil(f.watch())
        f.send(missing())
        XCTAssertEqual(f.mirroredIDs, ["article"])
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertEqual(f.saved.last?.withdrawnIDs, ["article"])
        XCTAssertNil(f.model.checkingID)
    }

    func testCachedOrPendingMissingDocumentIsNotServerEvidence() {
        let f = Fixture(); f.watch()
        f.send(missing(cached: true)); f.send(missing(pending: true))
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        XCTAssertTrue(f.saved.isEmpty); XCTAssertEqual(f.model.checkingID, "article")
        f.send(missing())
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
    }

    func testCachedWithdrawalCanBlockButCachedPublicationCannotRestore() {
        let f = Fixture(); f.watch()
        f.send(document(cached: true, withdrawn: true))
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        f.send(document(cached: true))
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertNil(f.model.approvedRevision(for: "article"))
        f.send(document())
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        XCTAssertNotNil(f.model.approvedRevision(for: "article"))
    }

    func testPendingPublicDocumentCannotRestoreConfirmedWithdrawal() {
        let f = Fixture(); f.watch(); f.send(missing())
        // A fresh observation still cannot treat a local pending publication as authoritative.
        f.watch(); f.send(document(pending: true), at: 1)
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
        XCTAssertNil(f.model.approvedRevision(for: "article"))
        f.send(document(), at: 1)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
    }

    func testMalformedOrForeignPublicMirrorCannotApprovePublication() {
        for value in [document(revision: "invalid-time"), document(id: "foreign")] {
            let f = Fixture(); f.watch(); f.send(value)
            XCTAssertNil(f.model.approvedRevision(for: "article"))
            XCTAssertNotNil(f.model.errorMessage)
            XCTAssertTrue(f.saved.isEmpty)
        }
    }

    func testAccountChangeRejectsSuccessAndFailureBeforePodcastSideEffects() {
        let f = Fixture(); f.watch(); f.select("B")
        XCTAssertFalse(f.subscriptions[0].permission())
        f.send(missing()); f.subscriptions[0].reply(.failure(Injected.offline))
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        XCTAssertNil(f.model.errorMessage); XCTAssertTrue(f.saved.isEmpty)
    }

    func testSameUIDAfterAccountABACannotReuseOldObservation() {
        let f = Fixture(); f.watch(); f.select("B"); f.select("A")
        f.send(missing())
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        XCTAssertFalse(f.subscriptions[0].permission())
        f.watch(); f.send(missing(), at: 1)
        XCTAssertEqual(f.mirroredIDs, ["article"])
        XCTAssertEqual(f.model.withdrawnIDs, ["article"])
    }

    func testReplacedSameArticleObservationRejectsOriginalCallback() {
        let f = Fixture(); f.watch(); f.watch()
        XCTAssertFalse(f.subscriptions[0].permission()); XCTAssertTrue(f.subscriptions[1].permission())
        f.send(missing(), at: 0)
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        f.send(document(), at: 1)
        XCTAssertEqual(f.mirroredIDs, ["article"])
        XCTAssertNotNil(f.model.approvedRevision(for: "article"))
        XCTAssertEqual(f.cancelled, [0])
    }

    func testPodcastHookReentryCannotPublishOldArticleResult() {
        let f = Fixture(); f.watch()
        f.mirrorHook = { [unowned f] in f.select("B") }
        f.send(missing())
        // The first effect was admitted. Reentry revokes the subsequent model
        // update instead of letting the old callback persist a withdrawal.
        XCTAssertEqual(f.mirroredIDs, ["article"])
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
    }

    func testPodcastHookReplacingSameArticleKeepsNewObserverChecking() {
        let f = Fixture(); f.watch()
        f.mirrorHook = { [unowned f] in f.mirrorHook = nil; f.watch() }
        f.send(missing())
        XCTAssertEqual(f.subscriptions.count, 2)
        XCTAssertEqual(f.model.checkingID, "article")
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        XCTAssertFalse(f.subscriptions[0].permission()); XCTAssertTrue(f.subscriptions[1].permission())
    }

    func testCurrentTransportFailureReachesModelWithoutPodcastMutation() {
        let f = Fixture(); f.watch()
        f.subscriptions[0].reply(.failure(Injected.offline))
        XCTAssertNil(f.model.checkingID); XCTAssertNotNil(f.model.errorMessage)
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
    }

    func testStoppedSubscriptionRejectsSynchronousCancellationCallback() {
        let f = Fixture(); f.watch()
        let response = missing()
        f.cancelHook = { [unowned f] in f.send(response) }
        f.model.stop(id: "article")
        XCTAssertFalse(f.subscriptions[0].permission())
        XCTAssertTrue(f.mirroredIDs.isEmpty); XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.cancelled, [0])
    }
}
