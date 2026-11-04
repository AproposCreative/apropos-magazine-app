import Combine
import XCTest
@testable import Apropos

final class IncomingLinkRuntimeTests: XCTestCase {
    @MainActor func testOnlyAcceptedIncomingIntentDefersAutomaticIntroduction() {
        let runtime = IncomingLinkRuntime(disabled: false)
        let initialRevision = runtime.acceptedIntentRevision
        XCTAssertFalse(runtime.hasAcceptedIncomingLink)
        XCTAssertFalse(runtime.accept(URL(string: "https://example.com/invalid")!))
        XCTAssertFalse(runtime.hasAcceptedIncomingLink)
        XCTAssertTrue(runtime.accept(.article(id: "cold")))
        XCTAssertNotEqual(runtime.acceptedIntentRevision, initialRevision)
        let firstRevision = runtime.acceptedIntentRevision
        XCTAssertTrue(runtime.accept(.article(id: "next")))
        XCTAssertNotEqual(runtime.acceptedIntentRevision, firstRevision)
        XCTAssertTrue(runtime.hasAcceptedIncomingLink)
        runtime.suspendForAccountChange()
        XCTAssertTrue(runtime.hasAcceptedIncomingLink)
        let disabled = IncomingLinkRuntime(disabled: true)
        XCTAssertFalse(disabled.accept(.article(id: "cold")))
        XCTAssertFalse(disabled.hasAcceptedIncomingLink)
    }
    @MainActor private func ready(_ runtime: IncomingLinkRuntime) {
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: "a");runtime.setUIReady(true)
    }
    @MainActor private func drain() async { for _ in 0..<40 { await Task.yield() } }
    @MainActor private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 { if condition() { return };await Task.yield() }
        XCTFail("Expected owned local resolution", file: file, line: line)
    }
    @MainActor func testDisabledRuntimeNeverDeliversOrCancels() async {
        let runtime = IncomingLinkRuntime(disabled: true)
        var effects = 0
        runtime.bindResolver({ _ in effects += 1 }, cancelPendingSeek: { effects += 1 })
        ready(runtime)
        XCTAssertFalse(runtime.accept(URL(string: "aproposmagazine://article/a?t=0")!))
        XCTAssertFalse(runtime.accept(.article(id: "a")))
        await drain();XCTAssertEqual(effects, 0)
    }
    @MainActor func testColdUnknownWaitsForActualPreparationResolverUIAndCanonicalConfirmation() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var requests: [IncomingLinkCoordinator.Request] = []
        XCTAssertTrue(runtime.accept(.article(id: "cold")))
        runtime.setUIReady(true);runtime.prepareIfNeeded()
        await drain();XCTAssertTrue(requests.isEmpty)
        runtime.bindResolver({ requests.append($0) }, cancelPendingSeek: {})
        await drain();XCTAssertTrue(requests.isEmpty)
        runtime.changeAccountContext(userID: nil)
        await wait { requests.count == 1 }
        await drain();XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(runtime.isCurrent(requests[0].ticket))
    }
    @MainActor func testHeldOldResolverCannotCommitOrReleaseLatestPendingRoute() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var requests: [IncomingLinkCoordinator.Request] = [], completed: [String] = []
        var release: CheckedContinuation<Void, Never>?
        runtime.bindResolver({ request in
            requests.append(request)
            if request.link.identifier == "old" { await withCheckedContinuation { release = $0 } }
            if runtime.isCurrent(request.ticket) { completed.append(request.link.identifier) }
        }, cancelPendingSeek: {})
        ready(runtime)
        runtime.accept(.article(id: "old"));await wait { release != nil }
        runtime.accept(.article(id: "intermediate"));runtime.accept(.article(id: "latest"))
        await drain();XCTAssertEqual(requests.count, 1)
        release?.resume();release = nil
        await wait { completed == ["latest"] }
        XCTAssertEqual(requests.map { $0.link.identifier }, ["old", "latest"])
        XCTAssertFalse(runtime.isCurrent(requests[0].ticket))
        XCTAssertTrue(runtime.isCurrent(requests[1].ticket))
    }
    @MainActor func testAccountRoundTripRevokesOldResolutionAndFreshUnresolvedLinkBindsLater() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var requests: [IncomingLinkCoordinator.Request] = [], committed: [String] = []
        var release: CheckedContinuation<Void, Never>?
        runtime.bindResolver({ request in
            requests.append(request)
            if request.link.identifier == "old" { await withCheckedContinuation { release = $0 } }
            if runtime.isCurrent(request.ticket) { committed.append(request.link.identifier) }
        }, cancelPendingSeek: {})
        ready(runtime)
        runtime.accept(.article(id: "old"));await wait { release != nil }
        runtime.suspendForAccountChange();runtime.accept(.article(id: "fresh"))
        runtime.changeAccountContext(userID: nil);runtime.changeAccountContext(userID: "a")
        // The fresh route bound to guest is revoked by the next account change.
        runtime.accept(.article(id: "final"))
        release?.resume();release = nil
        await wait { committed == ["final"] }
        XCTAssertFalse(runtime.isCurrent(requests[0].ticket))
    }
    @MainActor func testReplacingResolverRevokesOldWorkBeforeSwappingPresentation() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var oldRequest: IncomingLinkCoordinator.Request?, commits = 0
        var release: CheckedContinuation<Void, Never>?
        runtime.bindResolver({ request in
            oldRequest = request
            await withCheckedContinuation { release = $0 }
            if runtime.isCurrent(request.ticket) { commits += 100 }
        }, cancelPendingSeek: {})
        ready(runtime)
        runtime.accept(.article(id: "old"));await wait { release != nil }
        runtime.bindResolver({ _ in commits += 1 }, cancelPendingSeek: {})
        XCTAssertFalse(runtime.isCurrent(oldRequest!.ticket))
        runtime.accept(.article(id: "new"));await drain();XCTAssertEqual(commits, 0)
        release?.resume();release = nil
        await wait { commits == 1 }
    }
    @MainActor func testCanonicalStartupAndArticleOnlyInvalidationDoNotConstructPlayerEffects() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var playerCancels = 0, requests: [IncomingLinkCoordinator.Request] = []
        runtime.bindResolver({ requests.append($0) }, cancelPendingSeek: { playerCancels += 1 })
        ready(runtime)
        runtime.accept(.article(id: "first"));await wait { requests.count == 1 }
        runtime.accept(.category(name: "Musik"));await wait { requests.count == 2 }
        runtime.suspendForAccountChange();runtime.changeAccountContext(userID: "a")
        XCTAssertEqual(playerCancels, 0)
    }
    @MainActor func testCompletedResolverKeepsPlayerValidatorUntilNextIntentThenCancelsExactlyOnce() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var playerCancels = 0, request: IncomingLinkCoordinator.Request?
        runtime.bindResolver({ value in
            request = value
            if case .podcast = value.link { XCTAssertTrue(runtime.willStartPlayerWork(ticket: value.ticket)) }
        }, cancelPendingSeek: { playerCancels += 1 })
        ready(runtime)
        runtime.accept(.podcast(id: "article", startSeconds: 0));await wait { request != nil }
        let original = request!.ticket
        await drain();XCTAssertTrue(runtime.isCurrent(original))
        runtime.accept(.article(id: "new"));await drain()
        XCTAssertFalse(runtime.isCurrent(original));XCTAssertEqual(playerCancels, 1)
        runtime.suspendForAccountChange();XCTAssertEqual(playerCancels, 1)
    }
    @MainActor func testStaleIdenticalMessageDismissalCannotDismissNewOwnerMessage() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var request: IncomingLinkCoordinator.Request?
        runtime.bindResolver({ request = $0 }, cancelPendingSeek: {})
        ready(runtime)
        runtime.accept(.article(id: "one"));await wait { request != nil }
        runtime.showMessage("Unavailable", ticket: request!.ticket)
        let originalID = runtime.messageID!
        runtime.accept(.article(id: "two"));await wait { request?.link.identifier == "two" }
        XCTAssertNil(runtime.message)
        runtime.showMessage("Unavailable", ticket: request!.ticket)
        let currentID = runtime.messageID!
        XCTAssertNotEqual(currentID, originalID)
        runtime.dismissMessage(id: originalID);XCTAssertEqual(runtime.message, "Unavailable")
        runtime.dismissMessage(id: currentID);XCTAssertNil(runtime.message)
    }
    @MainActor func testNotificationKeepsPrimaryFallbackAndNilResumeWhileURLKeepsExplicitZero() async {
        let runtime = IncomingLinkRuntime(disabled: false)
        var requests: [IncomingLinkCoordinator.Request] = []
        runtime.bindResolver({ requests.append($0) }, cancelPendingSeek: {})
        ready(runtime)
        XCTAssertTrue(runtime.acceptNotification(.init(articleIdentifier: "primary", articleSlug: "slug", type: "new_podcast", podcastTitle: nil)))
        await wait { requests.count == 1 }
        XCTAssertEqual(requests[0].link, .podcast(id: "primary", startSeconds: nil))
        XCTAssertEqual(requests[0].fallbackIdentifier, "slug")
        XCTAssertTrue(runtime.accept(URL(string: "https://aproposmagazine.com/article/primary?t=0")!))
        await wait { requests.count == 2 }
        XCTAssertEqual(requests[1].link, .podcast(id: "primary", startSeconds: 0))
    }
}
