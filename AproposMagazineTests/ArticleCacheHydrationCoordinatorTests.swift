import XCTest
@testable import Apropos

@MainActor
final class ArticleCacheHydrationCoordinatorTests: XCTestCase {
    func testConstructionIsInertAndMissingBytesDoNotStartAWorker() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.clockReads, 0)
        h.source = nil
        let capture = h.model.capture()
        XCTAssertEqual(h.reads, 1)
        let outcome = await h.model.load(capture)
        XCTAssertEqual(outcome, .missing); XCTAssertTrue(h.jobs.isEmpty)
    }
    func testOriginalStorageGetterReentryCannotBorrowNewerCacheBytes() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        h.onRead = { h.onRead = nil; h.model.invalidate(); h.source = .encoded(Data("new".utf8)) }
        let original = h.model.capture()
        let outcome = await h.model.load(original)
        XCTAssertEqual(outcome, .stale); XCTAssertTrue(h.jobs.isEmpty)
    }
    func testClockGetterReentryDuringCaptureInvalidatesOriginalBeforeWorker() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        h.onClock = { h.onClock = nil; h.model.invalidate() }
        let original = h.model.capture()
        let outcome = await h.model.load(original)
        XCTAssertEqual(outcome, .stale); XCTAssertTrue(h.jobs.isEmpty)
    }
    func testOriginalCallerPermissionCannotAcquireLaterCacheGeneration() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let capture = h.model.capture()
        let outcome = await h.model.load(capture, stillPermitted: { h.model.invalidate(); return true })
        XCTAssertEqual(outcome, .stale); XCTAssertTrue(h.jobs.isEmpty)
    }
    func testForeignCaptureCannotInvokePermissionOrWorker() async {
        let h = ArticleCacheHarness(), other = ArticleCacheHarness(); defer { h.close(); other.close() }
        let capture = other.model.capture(); var guards = 0
        let outcome = await h.model.load(capture, stillPermitted: { guards += 1; return true })
        XCTAssertEqual(outcome, .stale); XCTAssertEqual(guards, 0); XCTAssertTrue(h.jobs.isEmpty)
    }
    func testWidgetAndStartupJoinSameActualDecodeAndUnchangedEpochUsesMemo() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let startup = h.model.capture()
        let first = Task { await h.model.load(startup) }; await h.waitForStarts(1)
        let widget = h.model.capture()
        let second = await h.pendingLoad(widget)
        XCTAssertEqual(h.jobs.count, 1); XCTAssertEqual(h.model.activity.waiterCount, 2)
        let prepared = h.prepared("cached")
        h.finish(0, .ready(prepared))
        let a = await first.value, b = await second.value
        XCTAssertEqual(a, .ready(prepared)); XCTAssertEqual(b, .ready(prepared))
        let later = await h.model.load(h.model.capture())
        XCTAssertEqual(later, .ready(prepared)); XCTAssertEqual(h.jobs.count, 1)
    }
    func testOneCallerCancellationDoesNotCancelOtherSameEpochOwner() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let capture = h.model.capture()
        let first = Task { await h.model.load(capture) }; await h.waitForStarts(1)
        let second = await h.pendingLoad(h.model.capture())
        first.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .stale); XCTAssertTrue(h.model.activity.active)
        XCTAssertEqual(h.jobs.count, 1); XCTAssertEqual(h.model.activity.waiterCount, 1)
        let prepared = h.prepared("still-owned")
        h.finish(0, .ready(prepared))
        let accepted = await second.value
        XCTAssertEqual(accepted, .ready(prepared))
    }
    func testLatestPendingCacheWaitsForActualOldWorkerReturn() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let old = Task { await h.model.load(h.model.capture()) }; await h.waitForStarts(1)
        h.model.invalidate()
        let stale = await old.value; XCTAssertEqual(stale, .stale)
        XCTAssertTrue(h.model.activity.active, "Invalidation does not refund actual CPU work")
        h.source = .encoded(Data("middle".utf8))
        let middle = await h.pendingLoad(h.model.capture())
        h.model.invalidate()
        let middleResult = await middle.value; XCTAssertEqual(middleResult, .stale)
        h.source = .encoded(Data("latest".utf8))
        let newest = await h.pendingLoad(h.model.capture())
        XCTAssertEqual(h.jobs.count, 1); XCTAssertTrue(h.model.activity.pending)
        h.finish(0, .ready(h.prepared("old")))
        await h.waitForStarts(2)
        XCTAssertEqual(h.jobs[1].source, .encoded(Data("latest".utf8)))
        h.finish(1, .ready(h.prepared("latest")))
        let latestResult = await newest.value
        XCTAssertEqual(latestResult.articles?.map(\.id), ["latest"])
        XCTAssertEqual(h.jobs.count, 2)
    }
    func testCancelledLastCallerKeepsActualSlotOccupiedUntilReturn() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let old = Task { await h.model.load(h.model.capture()) }; await h.waitForStarts(1)
        old.cancel(); let cancelled = await old.value
        XCTAssertEqual(cancelled, .stale); XCTAssertTrue(h.model.activity.active)
        h.model.invalidate(); h.source = .encoded(Data("fresh".utf8))
        let newest = await h.pendingLoad(h.model.capture())
        XCTAssertEqual(h.jobs.count, 1)
        h.finish(0, .ready(h.prepared("cancelled"))); await h.waitForStarts(2)
        h.finish(1, .ready(h.prepared("fresh")))
        let accepted = await newest.value; XCTAssertEqual(accepted.articles?.first?.id, "fresh")
    }
    func testClearThenNewWriteCannotAdmitHeldOldDecodeOrDiscardNewGoodBytes() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let original = h.model.capture()
        let task = Task { await h.model.load(original) }; await h.waitForStarts(1)
        // These are the actual adapter's synchronous clear/write invalidations.
        h.model.invalidate(); h.source = nil
        h.model.invalidate(); h.source = .encoded(Data("new-good".utf8))
        h.finish(0, .rejected(.corrupt))
        let result = await task.value
        XCTAssertEqual(result, .stale); XCTAssertFalse(h.model.isCurrent(original))
        let current = await h.pendingLoad(h.model.capture()); await h.waitForStarts(2)
        h.finish(1, .ready(h.prepared("new-good")))
        let accepted = await current.value
        XCTAssertEqual(accepted.articles?.first?.id, "new-good")
    }
    func testLaterNetworkSuccessEvenEmptyRevokesOldCacheAdmission() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        var startupCurrent = true
        let original = h.model.capture()
        let task = Task { await h.model.load(original, stillPermitted: { startupCurrent }) }
        await h.waitForStarts(1)
        startupCurrent = false
        h.model.invalidate() // Both nonempty and [] network success use this seam.
        let result = await task.value
        XCTAssertEqual(result, .stale)
        h.finish(0, .ready(h.prepared("old-cache")))
    }
    func testLateCallerDenialCannotDeliverReadyDataButOtherCallerStillCan() async {
        let h = ArticleCacheHarness(); defer { h.close() }; var callerCurrent = true
        let a = Task { await h.model.load(h.model.capture(), stillPermitted: { callerCurrent }) }
        await h.waitForStarts(1)
        let b = await h.pendingLoad(h.model.capture())
        callerCurrent = false; h.finish(0, .ready(h.prepared("public-cache")))
        let denied = await a.value, accepted = await b.value
        XCTAssertEqual(denied, .stale); XCTAssertEqual(accepted.articles?.first?.id, "public-cache")
    }
    func testFirstWaiterGuardReentryCannotDeliverOldDataToLaterWaiter() async {
        let h = ArticleCacheHarness(); defer { h.close() }; var finishing = false
        let a = Task { await h.model.load(h.model.capture(), stillPermitted: {
            if finishing { h.model.invalidate() }; return true
        }) }
        await h.waitForStarts(1)
        let b = await h.pendingLoad(h.model.capture())
        finishing = true; h.finish(0, .ready(h.prepared("old")))
        let first = await a.value, second = await b.value
        XCTAssertEqual(first, .stale); XCTAssertEqual(second, .stale)
    }
    func testFinalClockGetterReentryCannotReturnReadyOrBorrowReplacementEpoch() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let task = Task { await h.model.load(h.model.capture()) }; await h.waitForStarts(1)
        h.onClock = { h.onClock = nil; h.model.invalidate() }
        h.finish(0, .ready(h.prepared("old")))
        let outcome = await task.value
        XCTAssertEqual(outcome, .stale)
    }
    func testExpiryIsCheckedAgainAfterHeldWorkerAndForMemoizedResult() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let stamp = h.clock
        let task = Task { await h.model.load(h.model.capture()) }; await h.waitForStarts(1)
        h.clock = stamp.addingTimeInterval(7 * 24 * 60 * 60)
        h.finish(0, .ready(h.prepared("expired-during-work", timestamp: stamp)))
        let outcome = await task.value
        XCTAssertEqual(outcome, .rejected(.expired))
        let again = await h.model.load(h.model.capture())
        XCTAssertEqual(again, .rejected(.expired)); XCTAssertEqual(h.jobs.count, 1)
    }
    func testCancelledBeforeLoadStartsCannotCreateWorkerWork() async {
        let h = ArticleCacheHarness(); defer { h.close() }
        let capture = h.model.capture()
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return await h.model.load(capture) }
        let outcome = await task.value
        XCTAssertEqual(outcome, .stale); XCTAssertTrue(h.jobs.isEmpty)
    }
}

@MainActor
private final class ArticleCacheHarness {
    struct Job {
        let source: ArticleCacheHydrationCoordinator.Source
        let policy: ArticleCacheHydrationCoordinator.Policy
        var continuation: CheckedContinuation<ArticleCacheHydrationCoordinator.Decoded, Never>?
    }
    var source: ArticleCacheHydrationCoordinator.Source? = .encoded(Data("fixture".utf8))
    var clock = Date(timeIntervalSince1970: 1_700_000_000)
    var reads = 0, clockReads = 0
    var onRead: (() -> Void)?, onClock: (() -> Void)?
    var jobs: [Job] = []
    private var observers: [(Int, XCTestExpectation)] = []
    lazy var model = ArticleCacheHydrationCoordinator(read: { [weak self] in
        guard let self else { return nil }
        self.reads += 1; self.onRead?(); return self.source
    }, prepare: { [weak self] source, policy in
        guard let self else { return .rejected(.corrupt) }
        return await self.prepare(source, policy: policy)
    }, now: { [weak self] in
        guard let self else { return Date(timeIntervalSince1970: 0) }
        self.clockReads += 1; self.onClock?(); return self.clock
    })
    private func prepare(_ source: ArticleCacheHydrationCoordinator.Source,
                         policy: ArticleCacheHydrationCoordinator.Policy) async -> ArticleCacheHydrationCoordinator.Decoded {
        await withCheckedContinuation { continuation in
            jobs.append(.init(source: source, policy: policy, continuation: continuation))
            let ready = observers.filter { $0.0 <= jobs.count }
            observers.removeAll { $0.0 <= jobs.count }; ready.forEach { $0.1.fulfill() }
        }
    }
    func prepared(_ id: String, timestamp: Date? = nil) -> ArticleCacheHydrationCoordinator.Prepared {
        .init(articles: [cacheArticle(id)], timestamp: timestamp ?? clock, articlesAreSorted: true)
    }
    func pendingLoad(_ capture: ArticleCacheHydrationCoordinator.Capture) async -> Task<ArticleCacheHydrationCoordinator.Outcome, Never> {
        let admitted = XCTestExpectation(description: "Original cache waiter admitted")
        var notified = false
        let task = Task { await model.load(capture, stillPermitted: {
            if !notified { notified = true; admitted.fulfill() }; return true
        }) }
        let result = await XCTWaiter.fulfillment(of: [admitted], timeout: 3)
        XCTAssertEqual(result, .completed)
        return task
    }
    func waitForStarts(_ count: Int) async {
        if jobs.count >= count { return }
        let expectation = XCTestExpectation(description: "Actual cache worker started")
        observers.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed)
    }
    func finish(_ index: Int, _ result: ArticleCacheHydrationCoordinator.Decoded) {
        let held = jobs[index].continuation; jobs[index].continuation = nil; held?.resume(returning: result)
    }
    func close() {
        onRead = nil; onClock = nil
        model.invalidate()
        for index in jobs.indices where jobs[index].continuation != nil { finish(index, .rejected(.corrupt)) }
    }
}

func cacheArticle(_ id: String, created: String? = nil, editorial: String? = nil,
                  draft: Bool = false, archived: Bool = false, published: String? = "2026-01-01T12:00:00Z") -> Article {
    Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "culture",
            isDraft: draft, isArchived: archived, date: editorial, createdOn: created, lastPublished: published)
}
