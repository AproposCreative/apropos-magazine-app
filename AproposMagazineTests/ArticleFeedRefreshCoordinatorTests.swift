import XCTest
@testable import Apropos

final class ArticleFeedRefreshCoordinatorTests: XCTestCase {
    private func article(_ id: String) -> Article {
        Article(id: id, name: id, slug: id, content: "", intro: "", topicID: "topic", isDraft: false)
    }

    @MainActor
    func testSilentAndManualCallersJoinOneRequestAndCommitOnce() async {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var loading: [Bool] = []
        var commits: [[String]] = []
        var visibleCompletions: [Bool] = []
        let coordinator = ArticleFeedRefreshCoordinator(
            fetch: transport.fetch, scheduleTimeout: deadlines.schedule,
            loadingChanged: { loading.append($0) },
            completed: { result, visible, _ in
                commits.append((try? result.get().map(\.id)) ?? [])
                visibleCompletions.append(visible)
            }
        )

        let silent = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 1)
        let manual = coordinator.refresh(showsLoading: true)
        let third = coordinator.refresh(showsLoading: true)
        XCTAssertTrue(coordinator.isRefreshing)
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(loading, [true])

        transport.complete(0, with: .success([article("fresh")]))
        await silent.value
        await manual.value
        await third.value
        XCTAssertEqual(commits, [["fresh"]])
        XCTAssertEqual(visibleCompletions, [true])
        XCTAssertEqual(loading, [true, false])
        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertEqual(deadlines.cancelled, [0])
    }

    @MainActor
    func testTimeoutReleasesWaitersAndLateResultCannotReplaceNextRequest() async {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var commits: [String] = []
        let coordinator = ArticleFeedRefreshCoordinator(
            fetch: transport.fetch, scheduleTimeout: deadlines.schedule,
            loadingChanged: { _ in }, completed: { result, _, _ in
                switch result {
                case .success(let articles): commits.append(articles.first?.id ?? "empty")
                case .failure(let error): commits.append("error:\((error as NSError).code)")
                }
            }
        )
        let timedOut = coordinator.refresh(showsLoading: true)
        await transport.waitForRequest(count: 1)
        deadlines.fire(0)
        await timedOut.value
        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertEqual(commits, ["error:\(NSURLErrorTimedOut)"])

        let retry = coordinator.refresh(showsLoading: true)
        await transport.waitForRequest(count: 2)
        transport.complete(0, with: .success([article("obsolete")]))
        transport.complete(1, with: .success([article("current")]))
        await retry.value
        XCTAssertEqual(commits, ["error:\(NSURLErrorTimedOut)", "current"])
        XCTAssertEqual(transport.requestCount, 2)
    }

    @MainActor
    func testCompletedRequestIgnoresDuplicateCallbackAndCancelledDeadline() async {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var commits = 0
        let coordinator = ArticleFeedRefreshCoordinator(
            fetch: transport.fetch, scheduleTimeout: deadlines.schedule,
            loadingChanged: { _ in }, completed: { _, _, _ in commits += 1 }
        )
        let first = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 1)
        transport.complete(0, with: .success([article("first")]))
        await first.value
        let next = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 2)
        // Deliberately violate transport cancellation to exercise request identity.
        deadlines.fire(0)
        transport.complete(0, with: .failure(URLError(.badServerResponse)))
        transport.complete(1, with: .success([article("next")]))
        await next.value
        XCTAssertEqual(commits, 2)
    }

    @MainActor
    func testQueryPermissionClosesAtTimeoutAndCannotBorrowReplacement() async throws {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var queryPermissions: [ArticleFeedRefreshCoordinator.Permission] = []
        var commitPermissions: [Bool] = []
        var completed: [String] = []
        let coordinator = ArticleFeedRefreshCoordinator(fetch: { permission, done in
            queryPermissions.append(permission)
            transport.fetch(permission, done)
        }, scheduleTimeout: deadlines.schedule, loadingChanged: { _ in },
        completed: { result, _, permission in
            commitPermissions.append(permission())
            completed.append((try? result.get().first?.id) ?? "failed")
        })

        let first = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 1)
        let originalQuery = try XCTUnwrap(queryPermissions.first)
        XCTAssertTrue(originalQuery())
        deadlines.fire(0)
        await first.value
        XCTAssertFalse(originalQuery(), "A finished observation must revoke the old query's downstream authority")

        let second = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 2)
        let replacementQuery = queryPermissions[1]
        XCTAssertTrue(replacementQuery())
        XCTAssertFalse(originalQuery(), "A new request cannot lend authority to an old SDK callback")
        var lateEffects = 0
        if originalQuery() { lateEffects += 1 }
        transport.complete(0, with: .success([article("obsolete")]))
        transport.complete(1, with: .success([article("current")]))
        await second.value

        XCTAssertEqual(lateEffects, 0)
        XCTAssertEqual(completed, ["failed", "current"])
        XCTAssertEqual(commitPermissions, [true, true], "Accepted completion retains its original account permission")
        XCTAssertFalse(replacementQuery(), "A successful query also closes its transport authority")
        XCTAssertFalse(coordinator.isRefreshing)
    }

    @MainActor
    func testQueryPermissionRechecksRequestAfterAccountPermissionReentry() async throws {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var queryPermission: ArticleFeedRefreshCoordinator.Permission?
        var shouldInvalidate = false
        var commits = 0
        var coordinator: ArticleFeedRefreshCoordinator!
        coordinator = ArticleFeedRefreshCoordinator(fetch: { permission, done in
            queryPermission = permission
            transport.fetch(permission, done)
        }, scheduleTimeout: deadlines.schedule, loadingChanged: { _ in },
        completed: { _, _, _ in commits += 1 })
        let task = coordinator.refresh(showsLoading: false, stillCurrent: {
            if shouldInvalidate {
                shouldInvalidate = false
                coordinator.invalidate()
            }
            return true
        })
        await transport.waitForRequest(count: 1)
        shouldInvalidate = true
        XCTAssertFalse(try XCTUnwrap(queryPermission)(), "A reentrant account check cannot reopen the invalidated request")
        await task.value
        transport.complete(0, with: .success([article("obsolete")]))
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    @MainActor
    func testInvalidationDiscardsResultAndAllowsNewRefresh() async {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var commits: [[String]] = []
        var loading: [Bool] = []
        let coordinator = ArticleFeedRefreshCoordinator(
            fetch: transport.fetch, scheduleTimeout: deadlines.schedule,
            loadingChanged: { loading.append($0) },
            completed: { result, _, _ in commits.append((try? result.get().map(\.id)) ?? []) }
        )
        let obsolete = coordinator.refresh(showsLoading: true)
        await transport.waitForRequest(count: 1)
        coordinator.invalidate()
        await obsolete.value
        let current = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 2)
        transport.complete(0, with: .success([article("obsolete")]))
        transport.complete(1, with: .success([article("current")]))
        await current.value
        XCTAssertEqual(commits, [["current"]])
        XCTAssertEqual(loading, [true, false])
    }

    @MainActor
    func testFailureFinishesCycleAndSuccessCanImmediatelyRetry() async {
        let transport = ControlledFeedTransport()
        let deadlines = ControlledFeedDeadlines()
        var successes = 0
        var failures = 0
        let coordinator = ArticleFeedRefreshCoordinator(
            fetch: transport.fetch, scheduleTimeout: deadlines.schedule,
            loadingChanged: { _ in }, completed: { result, _, _ in
                switch result {
                case .success: successes += 1
                case .failure: failures += 1
                }
            }
        )
        let failed = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 1)
        transport.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await failed.value
        let recovered = coordinator.refresh(showsLoading: false)
        await transport.waitForRequest(count: 2)
        transport.complete(1, with: .success([article("recovered")]))
        await recovered.value
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(successes, 1)
        XCTAssertFalse(coordinator.isRefreshing)
    }
    @MainActor
    func testClosedOriginalPermissionStartsNoTransport() async {
        let transport = ControlledFeedTransport()
        var commits = 0
        let coordinator = ArticleFeedRefreshCoordinator(fetch: transport.fetch,
            loadingChanged: { _ in XCTFail("Closed request must not publish loading") },
            completed: { _, _, _ in commits += 1 })
        await coordinator.refresh(showsLoading: true, stillCurrent: { false }).value
        XCTAssertEqual(transport.requestCount, 0)
        XCTAssertEqual(commits, 0)
    }

    @MainActor
    func testPermissionRevokedDuringWaitRejectsPhysicalResult() async {
        let transport = ControlledFeedTransport()
        var permitted = true
        var commits = 0
        let coordinator = ArticleFeedRefreshCoordinator(fetch: transport.fetch,
            loadingChanged: { _ in }, completed: { _, _, _ in commits += 1 })
        let task = coordinator.refresh(showsLoading: true, stillCurrent: { permitted })
        await transport.waitForRequest(count: 1)
        permitted = false
        transport.complete(0, with: .success([article("old")]))
        await task.value
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    @MainActor
    func testLoadingCallbackNewRequestDoesNotRebindOldCompletion() async {
        let transport = ControlledFeedTransport()
        var commits: [String] = []
        var replacement: Task<Void, Never>?
        var coordinator: ArticleFeedRefreshCoordinator!
        coordinator = ArticleFeedRefreshCoordinator(fetch: transport.fetch,
            loadingChanged: { visible in
                if !visible, replacement == nil {
                    replacement = coordinator.refresh(showsLoading: false)
                }
            }, completed: { result, _, permission in
                XCTAssertTrue(permission())
                commits += (try? result.get().map(\.id)) ?? []
            })
        let old = coordinator.refresh(showsLoading: true)
        await transport.waitForRequest(count: 1)
        transport.complete(0, with: .success([article("old")]))
        await old.value
        await transport.waitForRequest(count: 2)
        transport.complete(1, with: .success([article("new")]))
        await replacement?.value
        XCTAssertEqual(commits, ["new"])
    }

}

@MainActor
private final class ControlledFeedTransport {
    private var callbacks: [ArticleFeedRefreshCoordinator.ResultHandler] = []
    private var observers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var requestCount: Int { callbacks.count }

    func fetch(_ permission: @escaping ArticleFeedRefreshCoordinator.Permission, _ completion: @escaping ArticleFeedRefreshCoordinator.ResultHandler) {
        callbacks.append(completion)
        let ready = observers.filter { $0.count <= requestCount }
        observers.removeAll { $0.count <= requestCount }
        ready.forEach { $0.continuation.resume() }
    }

    func waitForRequest(count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func complete(_ index: Int, with result: Result<[Article], Error>) {
        callbacks[index](result)
    }
}

@MainActor
private final class ControlledFeedDeadlines {
    private var actions: [() -> Void] = []
    private(set) var cancelled: [Int] = []

    func schedule(_ action: @escaping () -> Void) -> () -> Void {
        let index = actions.count
        actions.append(action)
        return { [weak self] in self?.cancelled.append(index) }
    }

    func fire(_ index: Int) { actions[index]() }
}
