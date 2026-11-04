import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class IncomingLinkStartupTests: XCTestCase {
    @MainActor private final class Fixture {
        var ready = false
        var reads = 0
        var hook: (() -> Void)?
        lazy var runtime = IncomingLinkRuntime(disabled: false, startupReady: { [unowned self] in
            self.reads += 1
            let observed = self.ready
            self.hook?()
            return observed
        })
        func prepare(uid: String? = "A") {
            runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: uid); runtime.setUIReady(true)
        }
    }
    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; entered.fulfill()
            }
        }
        func release() {
            guard let continuation else { XCTFail("Expected original physical resolver"); return }
            self.continuation = nil; continuation.resume()
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func deliveryTurn() async {
        // Cross the same MainActor task boundary used by real runtime delivery.
        let reached = expectation(description: "Queued resolver admission turn")
        Task { @MainActor in reached.fulfill() }
        await fulfillment(of: [reached], timeout: 3)
    }

    func testConstructionAndDisabledRuntimeNeverReadStartupOrConstructEffects() async {
        var reads = 0, effects = 0
        let runtime = IncomingLinkRuntime(disabled: true, startupReady: { reads += 1; return true })
        XCTAssertEqual(reads, 0)
        runtime.bindResolver({ _ in effects += 1 }, cancelPendingSeek: { effects += 1 })
        runtime.prepareIfNeeded(); runtime.setUIReady(true); runtime.changeAccountContext(userID: nil)
        runtime.refreshStartupReadiness(); runtime.suspendForAccountChange()
        XCTAssertFalse(runtime.accept(.article(id: "cold")))
        await deliveryTurn(); XCTAssertEqual(reads, 0); XCTAssertEqual(effects, 0)
        let f = Fixture(); _ = f.runtime; XCTAssertEqual(f.reads, 0)
    }

    func testClosedColdGuestQueueSurvivesPreparationBindingAndUIThenReleasesOnce() async {
        let f = Fixture(), resolved = expectation(description: "Original cold guest link")
        var requests: [IncomingLinkRuntime.Request] = []
        XCTAssertTrue(f.runtime.accept(.article(id: "cold")))
        f.runtime.prepareIfNeeded(); f.runtime.setUIReady(true)
        f.runtime.bindResolver({ request in requests.append(request); resolved.fulfill() }, cancelPendingSeek: {})
        f.runtime.changeAccountContext(userID: nil)
        f.runtime.setUIReady(true); f.runtime.refreshStartupReadiness()
        await deliveryTurn(); XCTAssertTrue(requests.isEmpty)
        f.ready = true; f.runtime.refreshStartupReadiness()
        await fulfillment(of: [resolved], timeout: 3)
        f.runtime.refreshStartupReadiness(); f.runtime.setUIReady(true); await deliveryTurn()
        XCTAssertEqual(requests.map { $0.link.identifier }, ["cold"])
        XCTAssertTrue(f.runtime.isCurrent(requests[0].ticket))
    }

    func testClosedAccountQueueKeepsLatestExplicitIntentAndFallback() async {
        let f = Fixture(), resolved = expectation(description: "Latest waiting account link")
        var requests: [IncomingLinkRuntime.Request] = []
        f.prepare()
        f.runtime.bindResolver({ request in requests.append(request); resolved.fulfill() }, cancelPendingSeek: {})
        XCTAssertTrue(f.runtime.accept(.article(id: "first")))
        XCTAssertTrue(f.runtime.accept(.article(id: "latest"), fallbackIdentifier: "editorial-slug"))
        await deliveryTurn(); XCTAssertTrue(requests.isEmpty)
        f.ready = true; f.runtime.refreshStartupReadiness()
        await fulfillment(of: [resolved], timeout: 3)
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].link.identifier, "latest")
        XCTAssertEqual(requests[0].fallbackIdentifier, "editorial-slug")
    }

    func testFreshTapAfterStartupClosesQueuesInsteadOfBeingConsumedByOldReadiness() async {
        let f = Fixture(), resolved = expectation(description: "Tap waits for restored admission")
        var requests: [IncomingLinkRuntime.Request] = []
        f.ready = true; f.prepare()
        f.runtime.bindResolver({ request in requests.append(request); resolved.fulfill() }, cancelPendingSeek: {})
        f.ready = false
        XCTAssertTrue(f.runtime.accept(URL(string: "https://aproposmagazine.com/article/waiting")!))
        f.runtime.setUIReady(true); await deliveryTurn(); XCTAssertTrue(requests.isEmpty)
        f.ready = true; f.runtime.refreshStartupReadiness()
        await fulfillment(of: [resolved], timeout: 3)
        XCTAssertEqual(requests.map { $0.link.identifier }, ["waiting"])
    }

    func testDeliveryRechecksStartupAfterTaskSchedulingAndDoesNotReviveRejectedTicket() async {
        let f = Fixture(), resolved = expectation(description: "New explicit link after admission")
        var identifiers: [String] = []
        f.ready = true; f.prepare()
        f.runtime.bindResolver({ request in identifiers.append(request.link.identifier); resolved.fulfill() }, cancelPendingSeek: {})
        XCTAssertTrue(f.runtime.accept(.article(id: "scheduled")))
        f.ready = false // Before the resolver task gets its actual execution turn.
        await deliveryTurn(); XCTAssertTrue(identifiers.isEmpty)
        f.ready = true; f.runtime.refreshStartupReadiness(); await deliveryTurn()
        XCTAssertTrue(identifiers.isEmpty)
        f.runtime.accept(.article(id: "fresh")); await fulfillment(of: [resolved], timeout: 3)
        XCTAssertEqual(identifiers, ["fresh"])
    }

    func testClosedStartupAfterAwaitRejectsMessageAndPlayerThenPreservesPhysicalSlot() async {
        let f = Fixture(), gate = Gate(expectation(description: "Original resolver is held"))
        let finished = expectation(description: "Fresh route follows original physical return")
        var requests: [IncomingLinkRuntime.Request] = [], committed: [String] = [], playerCancels = 0
        f.ready = true; f.prepare()
        f.runtime.bindResolver({ request in
            requests.append(request)
            if request.link.identifier == "old" { await gate.wait() }
            if f.runtime.isCurrent(request.ticket) {
                committed.append(request.link.identifier); finished.fulfill()
            }
        }, cancelPendingSeek: { playerCancels += 1 })
        f.runtime.accept(.podcast(id: "old", startSeconds: 0))
        await fulfillment(of: [gate.entered], timeout: 3)
        let old = requests[0].ticket
        XCTAssertTrue(f.runtime.willStartPlayerWork(ticket: old))
        f.ready = false
        XCTAssertFalse(f.runtime.isCurrent(old))
        f.runtime.showMessage("Stale", ticket: old)
        XCTAssertNil(f.runtime.message); XCTAssertFalse(f.runtime.willStartPlayerWork(ticket: old))
        XCTAssertEqual(playerCancels, 1)
        f.ready = true; f.runtime.refreshStartupReadiness()
        XCTAssertFalse(f.runtime.isCurrent(old))
        f.runtime.accept(.article(id: "fresh")); await deliveryTurn()
        XCTAssertEqual(requests.count, 1, "Logical revocation cannot release an occupied physical resolver")
        gate.release(); await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(requests.map { $0.link.identifier }, ["old", "fresh"])
        XCTAssertEqual(committed, ["fresh"]); XCTAssertEqual(playerCancels, 1)
    }

    func testAccountRoundTripWhileClosedCannotCommitOriginalAwaitedLink() async {
        let f = Fixture(), gate = Gate(expectation(description: "Old account read"))
        let finished = expectation(description: "New account intent")
        var requests: [IncomingLinkRuntime.Request] = [], committed: [String] = []
        f.ready = true; f.prepare()
        f.runtime.bindResolver({ request in
            requests.append(request)
            if request.link.identifier == "old" { await gate.wait() }
            if f.runtime.isCurrent(request.ticket) { committed.append(request.link.identifier); finished.fulfill() }
        }, cancelPendingSeek: {})
        f.runtime.accept(.article(id: "old")); await fulfillment(of: [gate.entered], timeout: 3)
        f.ready = false; f.runtime.suspendForAccountChange()
        f.runtime.changeAccountContext(userID: "B"); f.runtime.changeAccountContext(userID: "A")
        XCTAssertTrue(f.runtime.accept(.article(id: "new-A")))
        f.ready = true; f.runtime.refreshStartupReadiness()
        XCTAssertFalse(f.runtime.isCurrent(requests[0].ticket))
        gate.release(); await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(committed, ["new-A"])
    }

    func testStartupGetterReentryCannotDeliverUnderAnOlderAccountTicket() async {
        let f = Fixture(), resolved = expectation(description: "Initial route")
        var request: IncomingLinkRuntime.Request?
        f.ready = true; f.prepare()
        f.runtime.bindResolver({ value in request = value; resolved.fulfill() }, cancelPendingSeek: {})
        f.runtime.accept(.article(id: "old")); await fulfillment(of: [resolved], timeout: 3)
        let original = request!.ticket
        f.hook = {
            f.hook = nil; f.runtime.suspendForAccountChange(); f.runtime.changeAccountContext(userID: "B")
        }
        XCTAssertFalse(f.runtime.isCurrent(original))
        f.runtime.showMessage("Old A", ticket: original); XCTAssertNil(f.runtime.message)
    }

    func testReentrantStartupRefreshCannotOverwriteNewerClosedReadiness() async {
        let f = Fixture(), resolved = expectation(description: "Link retained across nested refresh")
        var identifiers: [String] = []
        f.prepare()
        f.runtime.bindResolver({ request in identifiers.append(request.link.identifier); resolved.fulfill() }, cancelPendingSeek: {})
        f.runtime.accept(.article(id: "waiting"))
        f.ready = true
        f.hook = { f.hook = nil; f.ready = false; f.runtime.refreshStartupReadiness() }
        f.runtime.refreshStartupReadiness(); await deliveryTurn()
        XCTAssertTrue(identifiers.isEmpty)
        f.ready = true; f.runtime.refreshStartupReadiness()
        await fulfillment(of: [resolved], timeout: 3)
        XCTAssertEqual(identifiers, ["waiting"])
    }
}
