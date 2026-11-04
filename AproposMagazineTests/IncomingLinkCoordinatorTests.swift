import XCTest
@testable import Apropos

@MainActor
final class IncomingLinkCoordinatorTests: XCTestCase {
    @MainActor private final class Harness {
        var delivered: [IncomingLinkCoordinator.Request] = []
        var cancelled: [IncomingLinkCoordinator.Ticket] = []
        var invalidations = 0
        var onDeliver: ((IncomingLinkCoordinator.Request) -> Void)?
        var onCancel: ((IncomingLinkCoordinator.Ticket) -> Void)?
        var onInvalidate: (() -> Void)?
        lazy var coordinator = IncomingLinkCoordinator(onInvalidate: { [unowned self] in
            invalidations += 1;onInvalidate?()
        }, deliver: { [unowned self] request in
            delivered.append(request);onDeliver?(request)
            return { [unowned self] in cancelled.append(request.ticket);onCancel?(request.ticket) }
        })
        func ready(_ userID: String? = nil) {
            coordinator.changeContext(to: .confirmed(userID: userID));coordinator.setUIReady(true)
        }
    }
    func testConstructionAndUnknownContextAreInertUntilActualReadinessAndCanonicalConfirmation() throws {
        let h = Harness();XCTAssertTrue(h.delivered.isEmpty)
        XCTAssertTrue(h.coordinator.accept(.article(id: "cold")));XCTAssertTrue(h.delivered.isEmpty)
        h.coordinator.setUIReady(true);XCTAssertTrue(h.delivered.isEmpty)
        h.coordinator.changeContext(to: .confirmed(userID: "A"))
        XCTAssertEqual(h.delivered.map(\.link), [.article(id: "cold")])
        XCTAssertTrue(h.coordinator.isCurrent(try XCTUnwrap(h.delivered.first).ticket))
        h.coordinator.setUIReady(true);h.coordinator.changeContext(to: .confirmed(userID: "A"))
        XCTAssertEqual(h.delivered.count, 1)
    }
    func testCanonicalContextAloneDoesNotTreatTimeoutOrLaunchAsUIReadiness() {
        let h = Harness();h.coordinator.changeContext(to: .guest)
        h.coordinator.accept(.article(id: "cold"));XCTAssertTrue(h.delivered.isEmpty)
        // The API has no timeout-as-ready path or timer construction.
        h.coordinator.setUIReady(true);XCTAssertEqual(h.delivered.count, 1)
    }
    func testColdStartCoalescesToOneLatestPendingIntent() {
        let h = Harness();h.coordinator.accept(.article(id: "one"));h.coordinator.accept(.article(id: "two"))
        h.coordinator.accept(.podcast(id: "three", startSeconds: 0));h.ready()
        XCTAssertEqual(h.delivered.map(\.link), [.podcast(id: "three", startSeconds: 0)])
    }
    func testNewestIntentRevokesOldCallbackImmediatelyButWaitsForActualResolverRetirement() throws {
        let h = Harness();h.ready("A");h.coordinator.accept(.article(id: "one"))
        let first = try XCTUnwrap(h.delivered.first).ticket
        h.coordinator.accept(.article(id: "two"));h.coordinator.accept(.article(id: "three"))
        XCTAssertFalse(h.coordinator.isCurrent(first));XCTAssertEqual(h.delivered.count, 1)
        XCTAssertEqual(h.cancelled, [first])
        h.coordinator.complete(first)
        XCTAssertEqual(h.delivered.map(\.link), [.article(id: "one"), .article(id: "three")])
        let latest = try XCTUnwrap(h.delivered.last).ticket
        h.coordinator.complete(first);XCTAssertTrue(h.coordinator.isCurrent(latest));XCTAssertEqual(h.delivered.count, 2)
    }
    func testThousandIncomingLinksKeepOnlyOneActiveResolverAndLastPending() throws {
        let h = Harness();h.ready();h.coordinator.accept(.article(id: "first"))
        let original = try XCTUnwrap(h.delivered.first).ticket
        for index in 0..<1000 { XCTAssertTrue(h.coordinator.accept(.article(id: "pending-\(index)"))) }
        XCTAssertEqual(h.delivered.count, 1);XCTAssertEqual(h.cancelled.count, 1)
        h.coordinator.complete(original)
        XCTAssertEqual(h.delivered.last?.link, .article(id: "pending-999"));XCTAssertEqual(h.delivered.count, 2)
    }
    func testCompletedResolverTicketStillValidatesPendingPlayerSeekUntilNewIntent() throws {
        let h = Harness();h.ready();h.coordinator.accept(.podcast(id: "a", startSeconds: 125))
        let ticket = try XCTUnwrap(h.delivered.first).ticket;h.coordinator.complete(ticket)
        XCTAssertTrue(h.coordinator.isCurrent(ticket))
        h.coordinator.accept(.article(id: "b"));XCTAssertFalse(h.coordinator.isCurrent(ticket))
        XCTAssertEqual(h.delivered.count, 2)
    }
    func testAccountSwitchAndSameUIDReturnCannotReviveOriginalWork() throws {
        let h = Harness();h.ready("A");h.coordinator.accept(.podcast(id: "a", startSeconds: 0))
        let original = try XCTUnwrap(h.delivered.first).ticket
        h.coordinator.changeContext(to: .unresolved);h.coordinator.changeContext(to: .guest)
        h.coordinator.changeContext(to: .confirmed(userID: "A"))
        XCTAssertFalse(h.coordinator.isCurrent(original));h.coordinator.complete(original)
        XCTAssertEqual(h.delivered.count, 1)
    }
    func testFreshURLWhileLaterUnresolvedCanBindNextOwnerButPriorAccountIntentCannot() throws {
        let h = Harness();h.ready("A");h.coordinator.accept(.article(id: "old-A"))
        let original = try XCTUnwrap(h.delivered.first).ticket
        h.coordinator.accept(.article(id: "queued-A"));h.coordinator.changeContext(to: .unresolved)
        h.coordinator.accept(.article(id: "fresh-unowned"));h.coordinator.changeContext(to: .confirmed(userID: "B"))
        XCTAssertEqual(h.delivered.count, 1);XCTAssertFalse(h.coordinator.isCurrent(original))
        h.coordinator.complete(original)
        XCTAssertEqual(h.delivered.map(\.link), [.article(id: "old-A"), .article(id: "fresh-unowned")])
        XCTAssertTrue(h.coordinator.isCurrent(try XCTUnwrap(h.delivered.last).ticket))
    }
    func testUnownedColdIntentBindsOnceAndCannotFollowAnotherContextTransition() throws {
        let h = Harness();h.coordinator.accept(.article(id: "cold"))
        h.coordinator.changeContext(to: .confirmed(userID: "A"))
        h.coordinator.changeContext(to: .confirmed(userID: "B"));h.coordinator.setUIReady(true)
        XCTAssertTrue(h.delivered.isEmpty)
    }
    func testInvalidURLOrTypedFallbackCannotReplaceValidPendingRequest() {
        let h = Harness();h.coordinator.accept(.article(id: "valid"))
        XCTAssertFalse(h.coordinator.accept(URL(string: "https://evil.test/article/a")!))
        XCTAssertFalse(h.coordinator.accept(.article(id: "bad/id")))
        XCTAssertFalse(h.coordinator.accept(.article(id: "a"), fallbackIdentifier: "bad/id"))
        XCTAssertFalse(h.coordinator.accept(.author(id: "author"), fallbackIdentifier: "slug"))
        h.ready();XCTAssertEqual(h.delivered.map(\.link), [.article(id: "valid")])
    }
    func testNotificationFallbackAndDefaultResumeArePreservedImmutably() throws {
        let h = Harness();h.ready("A")
        h.coordinator.accept(.podcast(id: "canonical-id", startSeconds: nil), fallbackIdentifier: "published-slug")
        let request = try XCTUnwrap(h.delivered.first)
        XCTAssertEqual(request.link, .podcast(id: "canonical-id", startSeconds: nil))
        XCTAssertEqual(request.fallbackIdentifier, "published-slug")
        h.coordinator.complete(request.ticket);h.coordinator.accept(.article(id: "same"), fallbackIdentifier: "same")
        XCTAssertNil(h.delivered.last?.fallbackIdentifier)
    }
    func testCancellationCallbackObservesRevokedOwnerAndCanRetireBeforeLatestStarts() throws {
        let h = Harness();h.ready();h.coordinator.accept(.article(id: "one"))
        let original = try XCTUnwrap(h.delivered.first).ticket
        h.onCancel = { ticket in
            XCTAssertFalse(h.coordinator.isCurrent(ticket));h.coordinator.complete(ticket)
            XCTAssertEqual(h.delivered.count, 1)
        }
        h.coordinator.accept(.article(id: "two"))
        XCTAssertEqual(h.cancelled, [original]);XCTAssertEqual(h.delivered.last?.link, .article(id: "two"))
    }
    func testReentrantInvalidateCallbackSelectsOnlyItsLatestReplacement() {
        let h = Harness();h.ready();h.coordinator.accept(.article(id: "one"))
        var replaced = false
        h.onInvalidate = {
            if !replaced { replaced = true;h.coordinator.accept(.article(id: "three")) }
        }
        h.onCancel = { h.coordinator.complete($0) }
        h.coordinator.accept(.article(id: "two"))
        XCTAssertEqual(h.delivered.map(\.link), [.article(id: "one"), .article(id: "three")])
    }
    func testReentrantDeliverCompletionDoesNotReviveOrCancelNewRequestWithOldHandle() throws {
        let h = Harness();h.ready()
        var reentered = false
        h.onDeliver = { request in
            if !reentered {
                reentered = true;h.coordinator.accept(.article(id: "two"));h.coordinator.complete(request.ticket)
            }
        }
        h.coordinator.accept(.article(id: "one"))
        XCTAssertEqual(h.delivered.map(\.link), [.article(id: "one"), .article(id: "two")])
        let newest = try XCTUnwrap(h.delivered.last).ticket
        XCTAssertTrue(h.coordinator.isCurrent(newest));XCTAssertEqual(h.cancelled.count, 1)
        XCTAssertNotEqual(h.cancelled.first, newest)
    }
    func testLosingUIReadinessAndExplicitInvalidationPreventOldTicketRevival() throws {
        let h = Harness();h.ready();h.coordinator.accept(.article(id: "a"))
        let original = try XCTUnwrap(h.delivered.first).ticket;h.coordinator.complete(original)
        h.coordinator.setUIReady(false);h.coordinator.setUIReady(true)
        XCTAssertFalse(h.coordinator.isCurrent(original));XCTAssertEqual(h.delivered.count, 1)
        h.coordinator.accept(.article(id: "b"));let next = try XCTUnwrap(h.delivered.last).ticket
        h.coordinator.invalidate();h.coordinator.complete(next);XCTAssertFalse(h.coordinator.isCurrent(next))
    }
    func testForeignCoordinatorTicketCannotValidateOrReleaseActiveSlot() throws {
        let a = Harness(), b = Harness();a.ready();b.ready()
        a.coordinator.accept(.article(id: "a"));b.coordinator.accept(.article(id: "b"))
        let foreign = try XCTUnwrap(a.delivered.first).ticket
        XCTAssertFalse(b.coordinator.isCurrent(foreign));b.coordinator.complete(foreign)
        b.coordinator.accept(.article(id: "b-next"));XCTAssertEqual(b.delivered.count, 1)
    }
    func testInvalidConfirmedIdentityStaysUnresolvedAndNamespacesDoNotExposeRawUID() {
        let h = Harness();h.coordinator.accept(.article(id: "cold"));h.coordinator.setUIReady(true)
        h.coordinator.changeContext(to: .confirmed(userID: " \n"));XCTAssertTrue(h.delivered.isEmpty)
        h.coordinator.changeContext(to: .account("raw-uid"));XCTAssertTrue(h.delivered.isEmpty)
        h.coordinator.changeContext(to: .confirmed(userID: "private-person"));XCTAssertEqual(h.delivered.count, 1)
        if case .account(let binding) = h.coordinator.context { XCTAssertFalse(binding.contains("private-person"));XCTAssertEqual(binding.count, 64) }
        else { XCTFail("Expected hashed account") }
    }
}
