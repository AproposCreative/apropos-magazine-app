import FirebaseCore
import XCTest
@testable import Apropos

/// Exercises the production listener ownership and lightweight decoder using
/// local subscription callbacks. No Firebase app, SDK reference or network.
@MainActor
final class FirestoreFavoriteListenerStartupTests: XCTestCase {
    private typealias Service = FirestoreService
    private typealias Document = Service.FavoriteDocument
    private typealias Snapshot = Service.FavoriteSnapshot
    private enum Injected: Error { case offline }

    @MainActor private final class Fixture {
        struct Subscription {
            let owner: String
            let permission: Service.FavoriteCurrentGuard
            let reply: @MainActor (Result<Snapshot, Error>) -> Void
        }
        let identity = CanonicalSessionState()
        var actualUID: String? = "A"
        var allowed = true
        var operation = UUID()
        var uidLookups = 0
        var uidHook: (() -> Void)?
        var subscribeHook: ((Int) -> Void)?
        var onChangeHook: (() -> Void)?
        var cancelHook: ((Int) -> Void)?
        var subscriptions: [Subscription] = []
        var cancelled: [Int] = []
        var listeners: [Service.FavoriteListener] = []
        var results: [Result<FavoritesModel.RemoteSnapshot, Error>] = []

        init() { select("A") }
        func select(_ uid: String?) {
            actualUID = uid
            identity.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
        @discardableResult
        func watch(expectedUID: String = "A") -> Service.FavoriteListener? {
            let context = identity.contextTicket()
            let originalOperation = UUID()
            operation = originalOperation
            let listener = Service.shared.listenFavorites(expectedUserID: expectedUID,
                stillCurrent: { [unowned self] in
                    self.allowed && self.operation == originalOperation && self.identity.isCurrent(context)
                }, actualUserID: { [unowned self] in
                    self.uidLookups += 1
                    self.uidHook?()
                    return self.actualUID
                }, subscribe: { [unowned self] owner, permission, reply in
                    let index = self.subscriptions.count
                    self.subscriptions.append(.init(owner: owner, permission: permission, reply: reply))
                    self.subscribeHook?(index)
                    return { [weak self] in
                        self?.cancelled.append(index)
                        self?.cancelHook?(index)
                    }
                }, onChange: { [unowned self] result in
                    self.results.append(result)
                    self.onChangeHook?()
                })
            if let listener { listeners.append(listener) }
            return listener
        }
        func send(_ value: Snapshot, at index: Int = 0) { subscriptions[index].reply(.success(value)) }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func document(id: String = "article") -> Document {
        .init(id: id, fields: ["id": id, "name": "Musik og kultur", "slug": id,
            "content": "<p>Legacy body must not reach the model</p>", "intro": "Legacy intro",
            "trailer": "https://example.invalid/embed", "pressAccreditation": true,
            "isPremium": true, "isDraft": false, "isArchived": false, "stjerne": 5,
            "topicID": "music", "topicsIDs": ["music", "culture"], "sectionID": "reviews",
            "authorID": "author", "subtitle": "En lokal anmeldelse", "fotoCredit": "Fotograf",
            "mobileImageURL": "https://example.invalid/image.jpg", "contentRevision": "revision-1",
            "lastPublished": "2026-10-24T10:00:00Z"])
    }
    private func snapshot(_ documents: [Document]? = nil, cached: Bool = false, pending: Bool = false) -> Snapshot {
        .init(documents: documents ?? [document()], isFromCache: cached, hasPendingWrites: pending)
    }
    private func success(_ fixture: Fixture, at index: Int = 0,
                         file: StaticString = #filePath, line: UInt = #line) -> FavoritesModel.RemoteSnapshot? {
        guard fixture.results.indices.contains(index), case .success(let value) = fixture.results[index] else {
            XCTFail("Expected a decoded favorite snapshot", file: file, line: line); return nil
        }
        return value
    }
    private func assertFailure(_ fixture: Fixture, _ expected: Service.FavoriteFailure,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard fixture.results.count == 1, case .failure(let error) = fixture.results[0],
              let actual = error as? Service.FavoriteFailure else {
            XCTFail("Expected one typed favorite failure", file: file, line: line); return
        }
        switch (actual, expected) {
        case (.invalidMetadata, .invalidMetadata), (.unavailable, .unavailable), (.wrongOwner, .wrongOwner): break
        default: XCTFail("Unexpected favorite failure", file: file, line: line)
        }
    }

    func testClosedGateDoesNotEvenReadProviderOrConstructLiveSubscription() {
        let f = Fixture(); f.allowed = false
        XCTAssertNil(f.watch()); XCTAssertEqual(f.uidLookups, 0)
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.results.isEmpty)
        XCTAssertNil(Service.shared.listenFavorites(expectedUserID: "A", stillCurrent: { false }, onChange: { _ in
            XCTFail("Closed live facade must not publish")
        }))
    }

    func testProviderMismatchAndInvalidOwnerCannotSubscribe() {
        for expected in ["A", "", "a/b", ".", "..", "__reserved__", " a"] {
            let f = Fixture(); f.actualUID = expected == "A" ? "B" : expected
            XCTAssertNil(f.watch(expectedUID: expected))
            XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.results.isEmpty)
        }
    }

    func testProviderLookupReentryCannotAdmitOriginalGeneration() {
        let f = Fixture()
        f.uidHook = { [unowned f] in
            f.uidHook = nil
            f.select(nil); f.select("A")
        }
        XCTAssertNil(f.watch()); XCTAssertTrue(f.subscriptions.isEmpty)
        XCTAssertTrue(f.results.isEmpty)
    }

    func testActualDecoderPreservesMetadataAndDiscardsLegacyBodyFields() {
        let f = Fixture(); XCTAssertNotNil(f.watch()); f.send(snapshot())
        guard let value = success(f), let article = value.articles.first else { return }
        XCTAssertEqual(f.subscriptions.map(\.owner), ["A"])
        XCTAssertEqual(article.id, "article"); XCTAssertEqual(article.name, "Musik og kultur")
        XCTAssertEqual(article.content, ""); XCTAssertEqual(article.intro, ""); XCTAssertNil(article.trailer)
        XCTAssertEqual(article.topicsIDs, ["music", "culture"]); XCTAssertEqual(article.sectionID, "reviews")
        XCTAssertEqual(article.authorID, "author"); XCTAssertEqual(article.fotoCredit, "Fotograf")
        XCTAssertEqual(article.subtitle, "En lokal anmeldelse"); XCTAssertEqual(article.stjerne, 5)
        XCTAssertEqual(article.contentRevision, "revision-1")
        XCTAssertTrue(article.pressAccreditation); XCTAssertEqual(article.isPremium, true)
        XCTAssertEqual(article.mobileImageURL?.absoluteString, "https://example.invalid/image.jpg")
    }

    func testCachedAndPendingMetadataRemainDistinctFromServerSnapshot() {
        let f = Fixture(); f.watch()
        f.send(snapshot(cached: true)); f.send(snapshot(pending: true)); f.send(snapshot([]))
        XCTAssertEqual(f.results.count, 3)
        XCTAssertEqual(success(f, at: 0)?.isFromCache, true)
        XCTAssertEqual(success(f, at: 0)?.hasPendingWrites, false)
        XCTAssertEqual(success(f, at: 1)?.isFromCache, false)
        XCTAssertEqual(success(f, at: 1)?.hasPendingWrites, true)
        XCTAssertEqual(success(f, at: 2)?.articles.count, 0)
        XCTAssertEqual(success(f, at: 2)?.isFromCache, false)
        XCTAssertEqual(success(f, at: 2)?.hasPendingWrites, false)
    }

    func testLegacyMissingStoredIDUsesOriginalDocumentID() {
        let f = Fixture(); f.watch()
        f.send(snapshot([.init(id: "legacy", fields: ["name": "Legacy", "content": "discard"])]))
        XCTAssertEqual(success(f)?.articles.first?.id, "legacy")
        XCTAssertEqual(success(f)?.articles.first?.content, "")
    }

    func testForeignOrUnsafeDocumentIDRejectsWholeSnapshot() {
        let cases: [Document] = [
            .init(id: "a", fields: ["id": "b"]), .init(id: "a", fields: ["id": 7]),
            .init(id: "a/b", fields: [:]), .init(id: "..", fields: [:]),
            .init(id: "__reserved__", fields: [:]), .init(id: " a", fields: [:])
        ]
        for bad in cases {
            let f = Fixture(); f.watch(); f.send(snapshot([document(), bad]))
            assertFailure(f, .invalidMetadata)
        }
    }

    func testUnboundedMetadataIsRejectedInsteadOfPublishingPartialFavorites() {
        let invalid: [[String: Any]] = [
            ["name": String(repeating: "x", count: 2049)], ["stjerne": 11],
            ["topicsIDs": Array(repeating: "topic", count: 33)],
            ["mobileImageURL": "file:///private/image.jpg"], ["fotoCredit": "bad\u{0}credit"]
        ]
        for fields in invalid {
            let f = Fixture(); f.watch()
            f.send(snapshot([document(), .init(id: "bad", fields: fields)]))
            assertFailure(f, .invalidMetadata)
        }
    }

    func testCardinalityBoundAndDuplicateIDsRejectWholeSnapshot() {
        let f = Fixture(); f.watch()
        f.send(snapshot((0...FavoritesRecordCodec.maximumEntries).map { .init(id: "article-\($0)", fields: [:]) }))
        assertFailure(f, .invalidMetadata)
        let duplicate = Fixture(); duplicate.watch(); duplicate.send(snapshot([document(), document()]))
        assertFailure(duplicate, .invalidMetadata)
    }

    func testTerminalTransportFailureRetiresOnceAndDropsAllLaterCallbacks() {
        let f = Fixture(); let handle = f.watch(); f.subscriptions[0].reply(.failure(Injected.offline))
        assertFailure(f, .unavailable)
        f.send(snapshot())
        f.subscriptions[0].reply(.failure(Injected.offline))
        XCTAssertEqual(f.results.count, 1); XCTAssertEqual(f.cancelled, [0])
        XCTAssertEqual(handle?.isCurrent(), false)
        handle?.remove(); XCTAssertEqual(f.cancelled, [0])
    }

    func testInvalidMetadataDoesNotEndTransportOrBlockLaterValidSnapshot() {
        let f = Fixture(); let handle = f.watch()
        f.send(snapshot([.init(id: "bad", fields: ["stjerne": 11])]))
        assertFailure(f, .invalidMetadata)
        XCTAssertEqual(handle?.isCurrent(), true); XCTAssertTrue(f.cancelled.isEmpty)
        f.send(snapshot()); XCTAssertEqual(success(f, at: 1)?.articles.count, 1)
    }

    func testTerminalCancellationReentryCannotPublishForReplacedAccount() {
        let f = Fixture(); f.watch()
        f.cancelHook = { [unowned f] _ in
            f.cancelHook = nil; f.select("B"); f.select("A"); f.watch()
        }
        f.subscriptions[0].reply(.failure(Injected.offline))
        XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(f.cancelled, [0])
        XCTAssertEqual(f.subscriptions.count, 2)
        f.send(snapshot(), at: 1); XCTAssertEqual(success(f)?.articles.count, 1)
    }

    func testSynchronousTerminalFirstCallbackCancelsReturnedHandleExactlyOnce() {
        let f = Fixture()
        f.subscribeHook = { [unowned f] index in f.subscriptions[index].reply(.failure(Injected.offline)) }
        XCTAssertNil(f.watch()); assertFailure(f, .unavailable)
        XCTAssertEqual(f.cancelled, [0]); XCTAssertFalse(f.subscriptions[0].permission())
    }

    func testOldAccountSuccessAndErrorAreDroppedAndPhysicalHandleRemovedOnce() {
        let f = Fixture(); let handle = f.watch(); f.select("B")
        f.send(snapshot()); f.subscriptions[0].reply(.failure(Injected.offline))
        XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(f.cancelled, [0])
        XCTAssertEqual(handle?.isCurrent(), false); handle?.remove(); handle?.remove()
        XCTAssertEqual(f.cancelled, [0])
    }

    func testAccountABACannotReviveOriginalListenerWithoutAnIntermediateCallback() {
        let f = Fixture(); let old = f.watch(); f.select(nil); f.select("A")
        f.send(snapshot()); XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(old?.isCurrent(), false)
        let fresh = f.watch(); f.send(snapshot(), at: 1)
        XCTAssertEqual(f.results.count, 1); XCTAssertEqual(fresh?.isCurrent(), true)
        XCTAssertEqual(f.cancelled, [0])
    }

    func testObservedProviderMismatchLatchesEvenWhenUIDReturns() {
        let f = Fixture(); let handle = f.watch(); f.actualUID = "B"
        XCTAssertEqual(handle?.isCurrent(), false)
        f.actualUID = "A"; f.send(snapshot())
        XCTAssertEqual(handle?.isCurrent(), false); XCTAssertTrue(f.results.isEmpty)
        XCTAssertEqual(f.cancelled, [0])
    }

    func testObservedPermissionDenialCannotReopenSameListener() {
        let f = Fixture(); let handle = f.watch(); f.allowed = false
        XCTAssertFalse(f.subscriptions[0].permission()); f.allowed = true
        f.send(snapshot()); XCTAssertEqual(handle?.isCurrent(), false)
        XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(f.cancelled, [0])
    }

    func testSynchronousCancellationCallbackCannotPublishOrCancelTwice() {
        let f = Fixture(); let handle = f.watch(); let value = snapshot()
        f.cancelHook = { [unowned f] index in f.send(value, at: index) }
        handle?.remove(); handle?.remove()
        XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(f.cancelled, [0])
        XCTAssertFalse(f.subscriptions[0].permission())
    }

    func testProviderGetterRemovingHandleCannotReturnStaleCurrentResult() {
        let f = Fixture(); let handle = f.watch()
        f.uidHook = { [unowned f] in f.uidHook = nil; handle?.remove() }
        XCTAssertEqual(handle?.isCurrent(), false)
        f.send(snapshot()); XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(f.cancelled, [0])
    }

    func testSynchronousFirstCallbackRevocationCancelsReturnedSubscription() {
        let f = Fixture(); let value = snapshot()
        f.subscribeHook = { [unowned f] index in f.send(value, at: index) }
        f.onChangeHook = { [unowned f] in f.allowed = false }
        XCTAssertNil(f.watch())
        XCTAssertEqual(f.results.count, 1); XCTAssertEqual(f.cancelled, [0])
        f.allowed = true; f.send(value)
        XCTAssertEqual(f.results.count, 1)
    }

    func testNestedReplacementDuringSynchronousFirstCallbackRetiresOnlyOriginalHandle() {
        let f = Fixture(); let value = snapshot()
        f.subscribeHook = { [unowned f] index in if index == 0 { f.send(value, at: index) } }
        f.onChangeHook = { [unowned f] in f.onChangeHook = nil; f.watch() }
        XCTAssertNil(f.watch())
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertEqual(f.cancelled, [0])
        XCTAssertFalse(f.subscriptions[0].permission()); XCTAssertTrue(f.subscriptions[1].permission())
        f.send(value, at: 0); XCTAssertEqual(f.results.count, 1)
        f.send(value, at: 1); XCTAssertEqual(f.results.count, 2)
        f.listeners.first?.remove(); XCTAssertEqual(f.cancelled, [0, 1])
    }

    func testOnChangeMayRemoveCurrentListenerWithoutReceivingAnotherEvent() {
        let f = Fixture(); let handle = f.watch()
        f.onChangeHook = { handle?.remove() }
        f.send(snapshot()); f.send(snapshot())
        XCTAssertEqual(f.results.count, 1); XCTAssertEqual(f.cancelled, [0])
    }

    func testGuardIsRecheckedAfterCallbackProviderLookupBeforeDecodingAndPublishing() {
        let f = Fixture(); let handle = f.watch()
        f.uidHook = { [unowned f] in f.uidHook = nil; f.select("B") }
        f.send(snapshot())
        XCTAssertTrue(f.results.isEmpty); XCTAssertEqual(handle?.isCurrent(), false)
        XCTAssertEqual(f.cancelled, [0])
    }
}
