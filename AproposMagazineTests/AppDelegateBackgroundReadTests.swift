import FirebaseCore
import UIKit
import XCTest
@testable import Apropos

/// Exercises the helper used by both actual OS background entry points. All
/// provider/cache effects are memory-only; no Firebase configuration is present.
@MainActor
final class AppDelegateBackgroundReadTests: XCTestCase {
    private typealias Reply = (Result<[Article], Error>) -> Void
    private enum Injected: Error { case unavailable }

    @MainActor private final class Fixture {
        let delegate = AppDelegate()
        let identity = CanonicalSessionState()
        var actualUID: String? = "A"
        var allowed = true
        var primary: [Reply] = []
        var fallback: [Reply] = []
        var cachedIDs: [[String]] = []
        var results: [UIBackgroundFetchResult] = []
        var failures = 0
        var cacheHook: (() -> Void)?
        var fallbackStarted: XCTestExpectation?

        init() { select("A") }
        func select(_ uid: String?) {
            actualUID = uid
            _ = identity.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
        func start(fallbackFailure: UIBackgroundFetchResult = .noData, finished: XCTestExpectation? = nil) {
            guard let original = ReaderSDKStartupState.application.captureReaderWork(
                identity: identity, actualUserID: { [unowned self] in self.actualUID }) else {
                return XCTFail("Fixture must capture its original identity")
            }
            delegate.refreshBackgroundArticles(stillCurrent: { [unowned self] in self.allowed && original() },
                fallbackFailure: fallbackFailure,
                onFailure: { [unowned self] in self.failures += 1 },
                fetch: { [unowned self] permission, reply in
                    XCTAssertTrue(permission()); self.primary.append(reply)
                },
                fallback: { [unowned self] permission, reply in
                    XCTAssertTrue(permission()); self.fallback.append(reply); self.fallbackStarted?.fulfill()
                },
                cache: { [unowned self] articles in
                    self.cachedIDs.append(articles.map(\.id)); self.cacheHook?()
                },
                completion: { [unowned self] result in
                    self.results.append(result); finished?.fulfill()
                })
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func article(_ id: String) -> Article {
        Article(id: id, name: "Lokal historie", slug: id, content: "<p>Tekst</p>", intro: "Intro", topicID: "culture")
    }
    private func flushCallbacks() async { for _ in 0..<8 { await Task.yield() } }

    func testClosedEntryCompletesNoDataWithoutProviderOrCache() {
        let f = Fixture(); f.allowed = false
        f.start()
        XCTAssertTrue(f.primary.isEmpty); XCTAssertTrue(f.fallback.isEmpty)
        XCTAssertTrue(f.cachedIDs.isEmpty); XCTAssertEqual(f.results, [.noData]); XCTAssertEqual(f.failures, 0)
    }

    func testPrimarySuccessCachesOnceAndCompletesNewDataDespiteDuplicateCallback() async {
        let f = Fixture(), done = expectation(description: "OS completion")
        f.start(finished: done)
        XCTAssertEqual(f.primary.count, 1)
        f.primary[0](.success([article("first")]))
        f.primary[0](.success([article("duplicate")]))
        await fulfillment(of: [done], timeout: 1)
        await flushCallbacks()
        XCTAssertEqual(f.cachedIDs, [["first"]]); XCTAssertEqual(f.results, [.newData])
        XCTAssertTrue(f.fallback.isEmpty); XCTAssertEqual(f.failures, 0)
    }

    func testEmptySuccessfulPrimaryKeepsNoDataSemantics() async {
        let f = Fixture(), done = expectation(description: "OS completion")
        f.start(finished: done); f.primary[0](.success([]))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(f.cachedIDs, [[]]); XCTAssertEqual(f.results, [.noData]); XCTAssertTrue(f.fallback.isEmpty)
    }

    func testStalePrimaryCannotStartFallbackOrCacheAfterAccountABA() async {
        let f = Fixture(), done = expectation(description: "stale completion")
        f.start(finished: done)
        f.select("B"); f.select("A")
        f.primary[0](.failure(FirestoreArticleError.empty))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertTrue(f.fallback.isEmpty); XCTAssertTrue(f.cachedIDs.isEmpty)
        XCTAssertEqual(f.results, [.noData]); XCTAssertEqual(f.failures, 0)
    }

    func testLateFallbackAndDuplicateCallbacksCompleteNoDataExactlyOnce() async {
        let f = Fixture(), done = expectation(description: "stale fallback completion")
        let fallback = expectation(description: "fallback physically entered")
        f.fallbackStarted = fallback
        f.start(finished: done)
        f.primary[0](.failure(FirestoreArticleError.empty))
        await fulfillment(of: [fallback], timeout: 1)
        f.select("B")
        f.fallback[0](.success([article("old")]))
        f.fallback[0](.failure(Injected.unavailable))
        f.primary[0](.success([article("duplicate primary")]))
        await fulfillment(of: [done], timeout: 1)
        await flushCallbacks()
        XCTAssertEqual(f.fallback.count, 1); XCTAssertTrue(f.cachedIDs.isEmpty)
        XCTAssertEqual(f.results, [.noData]); XCTAssertEqual(f.failures, 0)
    }

    func testSuccessfulFallbackKeepsOriginalPermissionThroughCache() async {
        let f = Fixture(), done = expectation(description: "fallback completion")
        let fallback = expectation(description: "fallback entered")
        f.fallbackStarted = fallback
        f.start(finished: done); f.primary[0](.failure(FirestoreArticleError.empty))
        await fulfillment(of: [fallback], timeout: 1)
        f.fallback[0](.success([article("fallback")]))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(f.cachedIDs, [["fallback"]]); XCTAssertEqual(f.results, [.newData])
        XCTAssertEqual(f.failures, 0)
    }

    func testAccountChangeDuringAdmittedCachePreventsNewDataCompletion() async {
        let f = Fixture(), done = expectation(description: "reentrant completion")
        f.cacheHook = { [unowned f] in f.select("B") }
        f.start(finished: done); f.primary[0](.success([article("accepted-before-change")]))
        await fulfillment(of: [done], timeout: 1)
        // The cache effect was admitted before the change. Its completion does
        // not claim new data for the replacement account or launch more work.
        XCTAssertEqual(f.cachedIDs, [["accepted-before-change"]])
        XCTAssertEqual(f.results, [.noData]); XCTAssertTrue(f.fallback.isEmpty)
    }

    func testPrimaryFailureIsFailedForBothOSModes() async {
        for mode: UIBackgroundFetchResult in [.noData, .failed] {
            let f = Fixture(), done = expectation(description: "primary failure \(mode.rawValue)")
            f.start(fallbackFailure: mode, finished: done)
            f.primary[0](.failure(Injected.unavailable))
            await fulfillment(of: [done], timeout: 1)
            XCTAssertEqual(f.results, [.failed]); XCTAssertEqual(f.failures, 1)
            XCTAssertTrue(f.fallback.isEmpty); XCTAssertTrue(f.cachedIDs.isEmpty)
        }
    }

    func testFallbackFailurePreservesSilentPushVersusBackgroundFetchResults() async {
        for mode: UIBackgroundFetchResult in [.noData, .failed] {
            let f = Fixture(), done = expectation(description: "fallback failure \(mode.rawValue)")
            let fallback = expectation(description: "fallback entered \(mode.rawValue)")
            f.fallbackStarted = fallback
            f.start(fallbackFailure: mode, finished: done)
            f.primary[0](.failure(FirestoreArticleError.empty))
            await fulfillment(of: [fallback], timeout: 1)
            f.fallback[0](.failure(Injected.unavailable))
            await fulfillment(of: [done], timeout: 1)
            XCTAssertEqual(f.results, [mode]); XCTAssertEqual(f.failures, mode == .failed ? 1 : 0)
            XCTAssertTrue(f.cachedIDs.isEmpty)
        }
    }
}
