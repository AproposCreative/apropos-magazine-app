import Combine
import FirebaseCore
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import Apropos

@MainActor
final class ArticleHTMLLoadStateTests: XCTestCase {
    func testInitialRetryIsInertAndReadyPublicationIsDeferred() async {
        let state = ArticleHTMLLoadState()
        let original = state.retryID
        XCTAssertEqual(state.phase, .preparing)
        state.retry(); XCTAssertEqual(state.retryID, original)
        let attempt = state.begin(); state.ready(attempt)
        XCTAssertEqual(state.phase, .preparing)
        await phase(state, .ready)
        state.retry(); XCTAssertEqual(state.retryID, original)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testFailedAttemptIsTerminalAndRetryChangesIdentityExactlyOnce() async {
        let state = ArticleHTMLLoadState(), attempt = stateAttempt()
        XCTAssertFalse(state.owns(attempt))
        let current = state.begin(), original = state.retryID
        state.fail(current); state.ready(current)
        await phase(state, .failed)
        state.retry(); let retry = state.retryID
        XCTAssertNotEqual(retry, original); XCTAssertEqual(state.phase, .preparing)
        state.retry(); XCTAssertEqual(state.retryID, retry)
        state.fail(current); state.ready(current)
        let replacement = state.begin(); state.ready(replacement)
        await phase(state, .ready)
    }

    func testAtoBtoADoesNotReuseOriginalAttempt() async {
        let state = ArticleHTMLLoadState()
        let a = state.begin(), b = state.begin(), freshA = state.begin()
        state.fail(a); state.ready(b); state.ready(freshA)
        await phase(state, .ready)
        state.fail(a); state.fail(b)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.owns(a)); XCTAssertTrue(state.owns(freshA))
    }

    func testObserverReentryCannotPublishOldReadyOverNewAttempt() async {
        let state = ArticleHTMLLoadState(), old = state.begin()
        var entered = false
        let observation = state.objectWillChange.sink {
            MainActor.assumeIsolated {
                guard !entered else { return }; entered = true
                let new = state.begin(); state.fail(new)
            }
        }
        state.ready(old)
        await phase(state, .failed)
        XCTAssertTrue(entered); XCTAssertFalse(state.owns(old))
        withExtendedLifetime(observation) {}
    }

    func testInvalidatedDeferredPublicationCannotChangeReplacementController() async {
        let state = ArticleHTMLLoadState(), other = ArticleHTMLLoadState()
        let old = state.begin(); state.ready(old); state.invalidate(old)
        let next = other.begin(); other.ready(next)
        await phase(other, .ready)
        XCTAssertEqual(state.phase, .preparing)
        XCTAssertFalse(state.owns(old))
    }

    func testCurrentNavigationFailureHidesDocumentAndResetsOriginalHeight() async throws {
        let f = HTMLLoadFixture(); defer { f.close() }
        f.height.value = 7_000
        let attempt = f.begin(), navigation = try XCTUnwrap(f.load())
        // Parent updates must not lend the failure a different height binding.
        let unrelated = HTMLLoadHeight(); unrelated.value = 999
        f.coordinator.parent.dynamicHeight = 7_000
        f.coordinator.parent = HTMLTextView(html: "other", dynamicHeight: Binding(get: { unrelated.value }, set: { unrelated.value = $0 }), prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
        f.coordinator.webView(f.web, didFail: navigation, withError: localError)
        await phase(f.state, .failed)
        XCTAssertEqual(f.height.value, 240); XCTAssertEqual(unrelated.value, 999)
        XCTAssertFalse(f.coordinator.ownsLoad(attempt)); XCTAssertTrue(f.web.isHidden)
        XCTAssertEqual(f.coordinator.documentID, ""); XCTAssertNil(f.coordinator.expectedNavigation)
    }

    func testProvisionalFailureThenExplicitRetryAndTerminationAfterReady() async throws {
        let f = HTMLLoadFixture(); defer { f.close() }
        _ = f.begin(); let navigation = try XCTUnwrap(f.load())
        f.coordinator.webView(f.web, didFailProvisionalNavigation: navigation, withError: localError)
        await phase(f.state, .failed)
        let originalRetry = f.state.retryID
        f.state.retry(); XCTAssertNotEqual(f.state.retryID, originalRetry)
        _ = f.begin(); _ = f.load()
        f.coordinator.documentBecameReady(f.document)
        await phase(f.state, .ready)
        f.coordinator.webViewWebContentProcessDidTerminate(f.web)
        await phase(f.state, .failed)
        XCTAssertTrue(f.web.isHidden); XCTAssertEqual(f.coordinator.documentID, "")
    }

    func testOldNavigationAndForeignProcessCallbacksCannotFailNewA() async throws {
        let f = HTMLLoadFixture(); defer { f.close() }
        _ = f.begin(); let original = try XCTUnwrap(f.load())
        f.generation = UUID(); _ = f.begin(); _ = f.load()
        f.generation = UUID(); let latest = f.begin(); _ = f.load()
        f.coordinator.webView(f.web, didFail: original, withError: localError)
        f.coordinator.webViewWebContentProcessDidTerminate(WKWebView())
        XCTAssertTrue(f.coordinator.ownsLoad(latest))
        f.coordinator.documentBecameReady(f.document)
        await phase(f.state, .ready)
    }

    func testRevokedOwnershipStillTimesOutToGenericFailure() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        let attempt = f.begin()
        f.generation = UUID()
        f.deadlines.last?()
        await phase(f.state, .failed)
        XCTAssertFalse(f.coordinator.ownsLoad(attempt)); XCTAssertTrue(f.web.isHidden)
    }

    func testRevocationBeforeDeferredReadyPublicationBecomesFailure() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        _ = f.begin(); _ = f.load()
        f.coordinator.documentBecameReady(f.document)
        f.generation = UUID()
        await phase(f.state, .failed)
        XCTAssertTrue(f.web.isHidden)
    }

    func testDeadlineCancellationHookCannotAuthorizeRevokedReady() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        _ = f.begin(); _ = f.load()
        f.onCancel = { [weak f] in f?.generation = UUID() }
        f.coordinator.documentBecameReady(f.document)
        await phase(f.state, .failed)
        XCTAssertTrue(f.web.isHidden)
    }

    func testTimeoutKeepsPhysicalPreparationAndOnlyLatestRetryCanCommit() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        let gate = HTMLLoadGate(), entered = expectation(description: "Original physical work entered")
        let first = f.begin(), input = f.input()
        var oldCommits = 0, retryCommits = 0
        f.coordinator.preparation.submit(input, work: { value, _ in
            entered.fulfill(); await gate.wait()
            return ArticleHTMLPreparation.prepare(value, cache: nil)
        }, isCurrent: { f.coordinator.ownsLoad(first) }, discard: { f.coordinator.failLoad(first) }, commit: { _, _ in oldCommits += 1 })
        await fulfillment(of: [entered], timeout: 3)
        f.deadlines.last?(); await phase(f.state, .failed)
        XCTAssertTrue(f.coordinator.preparation.isWorking)
        f.state.retry(); let retry = f.begin()
        let committed = expectation(description: "Only explicit latest retry commits")
        f.coordinator.preparation.submit(f.input(), work: { value, _ in ArticleHTMLPreparation.prepare(value, cache: nil) },
            isCurrent: { f.coordinator.ownsLoad(retry) }, discard: { f.coordinator.failLoad(retry) }, commit: { _, guardCurrent in
                guard guardCurrent() else { return }
                retryCommits += 1; committed.fulfill()
            })
        XCTAssertTrue(f.coordinator.preparation.hasPending)
        XCTAssertEqual(retryCommits, 0)
        await gate.release()
        await fulfillment(of: [committed], timeout: 5)
        XCTAssertEqual(oldCommits, 0); XCTAssertEqual(retryCommits, 1)
    }

    func testRevokedWorkerOutputFailsCurrentAttemptWithoutCommitting() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        let gate = HTMLLoadGate(), entered = expectation(description: "Work held")
        let attempt = f.begin(); var commits = 0
        f.coordinator.preparation.submit(f.input(), work: { value, _ in
            entered.fulfill(); await gate.wait(); return ArticleHTMLPreparation.prepare(value, cache: nil)
        }, isCurrent: { f.coordinator.ownsLoad(attempt) }, discard: { f.coordinator.failLoad(attempt) }, commit: { _, _ in commits += 1 })
        await fulfillment(of: [entered], timeout: 3)
        f.generation = UUID(); await gate.release()
        await phase(f.state, .failed)
        XCTAssertEqual(commits, 0)
    }

    func testDismantleRejectsPendingFailureHeightAndReadiness() async {
        let f = HTMLLoadFixture(); defer { f.close() }
        let attempt = f.begin(); _ = f.load()
        f.coordinator.failLoad(attempt)
        HTMLTextView.dismantleUIView(f.web, coordinator: f.coordinator)
        f.height.value = 777
        f.deadlines.last?(); f.coordinator.documentBecameReady(f.document)
        // A separate valid publication is a bounded actor-turn barrier.
        let barrier = ArticleHTMLLoadState(), next = barrier.begin(); barrier.ready(next)
        await phase(barrier, .ready)
        XCTAssertEqual(f.state.phase, .preparing); XCTAssertEqual(f.height.value, 777)
        XCTAssertFalse(f.coordinator.ownsLoad(attempt))
    }

    func testLocalReadinessWaitsForActualWindowThenAcceptsUnchangedBounds() async throws {
        let f = HTMLLoadFixture(); defer { f.close() }
        let height = expectation(description: "Real JavaScript height applied before window attachment")
        f.height.onFirstChange = { height.fulfill() }
        _ = f.begin(); _ = f.load()
        await fulfillment(of: [height], timeout: 8)
        XCTAssertNil(f.web.window); XCTAssertEqual(f.state.phase, .preparing)
        let originalBounds = f.web.bounds
        f.attachWindow()
        await phase(f.state, .ready)
        XCTAssertEqual(f.web.bounds, originalBounds)
        XCTAssertNil(f.coordinator.motion, "Local readiness must not activate reveal animations")
        XCTAssertNil(FirebaseApp.allApps)
    }

    private var localError: NSError { NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData) }
    private func stateAttempt() -> ArticleHTMLLoadState.Attempt { ArticleHTMLLoadState().begin() }
    private func phase(_ state: ArticleHTMLLoadState, _ expected: ArticleHTMLLoadState.Phase, file: StaticString = #filePath, line: UInt = #line) async {
        if state.phase == expected { return }
        let observed = expectation(description: "Phase \(expected)")
        var finished = false
        let observation = state.objectWillChange.sink {
            Task { @MainActor in
                if !finished, state.phase == expected { finished = true; observed.fulfill() }
            }
        }
        await fulfillment(of: [observed], timeout: 8)
        XCTAssertEqual(state.phase, expected, file: file, line: line)
        withExtendedLifetime(observation) {}
    }
}

@MainActor
private final class HTMLLoadHeight {
    var value: CGFloat = 240
    var onFirstChange: (() -> Void)?
}

private actor HTMLLoadGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor
private final class HTMLLoadFixture {
    let state = ArticleHTMLLoadState(), height = HTMLLoadHeight()
    let web: ArticleMotionWebView
    let coordinator: HTMLTextView.Coordinator
    var generation = UUID(), document = UUID().uuidString
    var deadlines: [@MainActor () -> Void] = []
    var onCancel: (@MainActor () -> Void)?
    private var window: UIWindow?
    init() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = ArticleMotionWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 240), configuration: config)
        self.web = web
        let height = self.height
        let renderer = HTMLTextView(html: "<p>Local article.</p>", dynamicHeight: Binding(get: { height.value }, set: { [weak web] value in
            height.value = value; web?.frame.size.height = value
            let callback = height.onFirstChange; height.onFirstChange = nil; callback?()
        }), prepareHTML: { html, _ in .init(html: html, baseURL: nil) }, loadState: state)
        coordinator = renderer.makeCoordinator()
        coordinator.parent.loadTesting = ArticleHTMLLoadTesting(schedule: { [weak self] _, fire in
            self?.deadlines.append(fire)
            return { [weak self] in self?.onCancel?() }
        })
        web.navigationDelegate = coordinator
        config.userContentController.add(coordinator, name: "heightHandler")
    }
    func begin() -> UUID {
        let original = generation
        return coordinator.beginLoad(webView: web, state: state, ownership: { [weak self] in self?.generation == original })
    }
    func input() -> ArticleHTMLPreparation.Input {
        .init(html: "<p>Local article.</p>", targetImageWidth: 390, bodyFontSize: 18, documentID: UUID().uuidString, contentKey: nil)
    }
    @discardableResult func load() -> WKNavigation? {
        document = UUID().uuidString
        coordinator.acceptDocument(document); coordinator.loadDocumentID = document
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="apropos-document" content="\(document)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
        <style>body{margin:0;font:18px/1.7 -apple-system}p{margin:0;padding:16px}</style>
        </head><body><p>Local article with enough words to measure a real native WebKit paragraph.</p></body></html>
        """
        web.isHidden = false
        let navigation = web.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        coordinator.expectedNavigation = navigation
        return navigation
    }
    func attachWindow() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene); window.frame = frame
        } else { window = UIWindow(frame: frame) }
        let controller = UIViewController(); controller.view.frame = frame
        controller.view.addSubview(web); window.rootViewController = controller
        self.window = window; window.isHidden = false
        controller.view.layoutIfNeeded()
    }
    func close() {
        onCancel = nil; HTMLTextView.dismantleUIView(web, coordinator: coordinator)
        web.removeFromSuperview(); window?.isHidden = true; window?.rootViewController = nil
    }
}
