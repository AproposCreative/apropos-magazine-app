import XCTest
import UIKit
import WebKit
@testable import Apropos

/// Runs the shipped enhancement against local prose. The fixture cannot load
/// external resources, and the test host does not create an application service.
@MainActor
final class ArticleTextRevealWebKitTests: XCTestCase {
    func testVisibleProseStaysPlainAndFutureProseFadesWithoutChangingLayoutOrMarkup() async throws {
        let harness = ArticleRevealWebHarness()
        defer { harness.close() }
        try await harness.load()
        let before = try await harness.snapshot()

        try await harness.install()
        let unprepared = try await harness.snapshot()
        XCTAssertEqual(try number("motionCount", in: unprepared), 0)
        XCTAssertEqual(try number("futureOpacity", in: unprepared), 1)

        let prepared = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:false});")
        XCTAssertEqual(prepared["firstMotion"] as? String, "")
        XCTAssertEqual(prepared["futureMotion"] as? String, "pending")
        XCTAssertEqual(prepared["captionMotion"] as? String, "")
        XCTAssertEqual(try number("futureOpacity", in: prepared), 0.55, accuracy: 0.001)
        XCTAssertEqual(prepared["futureTransform"] as? String, "matrix(1, 0, 0, 1, 0, 8)")
        try assertStableLayoutAndContent(before, prepared)
    }

    func testScrollingRevealsOnceAndReverseScrollingDoesNotRearmReadText() async throws {
        let harness = ArticleRevealWebHarness()
        defer { harness.close() }
        try await harness.load()
        try await harness.install()
        let prepared = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:false});")
        XCTAssertEqual(prepared["futureMotion"] as? String, "pending")

        let entered = try await harness.afterFrames(Self.enterFuture)
        XCTAssertEqual(entered["futureMotion"] as? String, "revealing")

        // Let WebKit dispatch its real animationend event or the script's own
        // 620 ms completion safeguard. No synthetic event changes script state.
        let completed = try await harness.afterDelay(milliseconds: 750)
        XCTAssertEqual(completed["futureMotion"] as? String, "")
        XCTAssertEqual(try number("futureOpacity", in: completed), 1)

        _ = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:false});")
        let revisited = try await harness.afterFrames(Self.enterFuture)
        XCTAssertEqual(revisited["futureMotion"] as? String, "")
        XCTAssertEqual(try number("futureOpacity", in: revisited), 1)
        try assertStableLayoutAndContent(prepared, revisited)
    }

    func testReduceMotionRestoresPendingTextImmediatelyAndCanPrecedeFirstViewportFrame() async throws {
        let harness = ArticleRevealWebHarness()
        defer { harness.close() }
        try await harness.load()
        try await harness.install()
        let prepared = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:false});")
        XCTAssertEqual(prepared["futureMotion"] as? String, "pending")

        // Restoration must happen synchronously, even while the next native
        // viewport is temporarily unmeasured during a layout change.
        let restored = try await harness.snapshot(after: "window.aproposReaderReveal.update({top:0,bottom:0,reduceMotion:true});")
        XCTAssertEqual(try number("motionCount", in: restored), 0)
        XCTAssertEqual(try number("futureOpacity", in: restored), 1)

        _ = try await harness.snapshot(after: "window.aproposReaderReveal.teardown();")
        try await harness.install()
        let initiallyReduced = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:true});")
        XCTAssertEqual(try number("motionCount", in: initiallyReduced), 0)
        XCTAssertEqual(try number("futureOpacity", in: initiallyReduced), 1)
        try assertStableLayoutAndContent(prepared, initiallyReduced)
    }

    func testTeardownRemovesPendingAndActiveMotionAndItsAPIWithoutLeavingLayoutChanges() async throws {
        let harness = ArticleRevealWebHarness()
        defer { harness.close() }
        try await harness.load()
        let before = try await harness.snapshot()
        try await harness.install()
        _ = try await harness.afterFrames("window.aproposReaderReveal.update({top:0,bottom:300,reduceMotion:false});")
        let active = try await harness.afterFrames(Self.enterFuture)
        XCTAssertEqual(active["futureMotion"] as? String, "revealing")
        XCTAssertEqual(active["lastMotion"] as? String, "pending")
        XCTAssertEqual(try number("motionStyleCount", in: active), 1)

        let restored = try await harness.afterFrames("window.aproposReaderReveal.teardown();")
        XCTAssertEqual(restored["apiExists"] as? Bool, false)
        XCTAssertEqual(try number("motionCount", in: restored), 0)
        XCTAssertEqual(try number("motionStyleCount", in: restored), 0)
        XCTAssertEqual(try number("futureOpacity", in: restored), 1)
        XCTAssertEqual(restored["futureTransform"] as? String, "none")
        try assertStableLayoutAndContent(before, restored)
    }

    private static let enterFuture = """
    var futureTop = document.getElementById('future').offsetTop;
    window.aproposReaderReveal.update({top:futureTop-100,bottom:futureTop+300,reduceMotion:false});
    """

    private func number(_ key: String, in snapshot: [String: Any]) throws -> Double {
        try XCTUnwrap((snapshot[key] as? NSNumber)?.doubleValue, "Missing numeric fixture result: \(key)")
    }

    private func assertStableLayoutAndContent(_ before: [String: Any], _ after: [String: Any],
                                             file: StaticString = #filePath, line: UInt = #line) throws {
        for key in ["futureTop", "futureHeight", "lastTop", "documentHeight", "firstChildCount", "futureChildCount", "linkCount"] {
            XCTAssertEqual(try number(key, in: before), try number(key, in: after), accuracy: 0.000_001,
                           key, file: file, line: line)
        }
        for key in ["firstHTML", "futureHTML", "linkHref", "captionHTML"] {
            XCTAssertEqual(try XCTUnwrap(before[key] as? String), try XCTUnwrap(after[key] as? String),
                           key, file: file, line: line)
        }
    }
}

@MainActor
private final class ArticleRevealWebHarness: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: UIWindow
    private var loading: CheckedContinuation<Void, Error>?
    private var loadDeadline: Task<Void, Never>?

    override init() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: frame, configuration: configuration)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        super.init()
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        let controller = UIViewController()
        controller.view.frame = frame
        controller.view.addSubview(webView)
        window.rootViewController = controller
        // A visible local surface lets WebKit run real animation frames without
        // starting the normal app, accessing services, or loading an HTTP page.
        window.isHidden = false
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            loadDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                catch { return }
                self?.finishLoading(.failure(FixtureError.loadTimedOut))
            }
            webView.loadHTMLString(Self.html, baseURL: URL(string: "about:blank"))
        }
    }

    func install() async throws {
        _ = try await webView.evaluateJavaScript(ArticleTextRevealScript.source)
    }

    func snapshot(after source: String = "") async throws -> [String: Any] {
        try dictionary(await webView.callAsyncJavaScript(source + "\nreturn (" + Self.snapshotFunction + ")();",
                                                          arguments: [:], in: nil, contentWorld: .page))
    }

    func afterFrames(_ source: String) async throws -> [String: Any] {
        let body = source + """
        \nawait new Promise((resolve, reject) => {
            var deadline = setTimeout(() => reject(new Error('Local WebKit animation frames timed out')), 4000);
            requestAnimationFrame(() => requestAnimationFrame(() => { clearTimeout(deadline); resolve(); }));
        });
        return (
        """ + Self.snapshotFunction + ")();"
        return try dictionary(await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page))
    }

    func afterDelay(milliseconds: Int) async throws -> [String: Any] {
        let body = "await new Promise(resolve => setTimeout(resolve, milliseconds)); return (" + Self.snapshotFunction + ")();"
        return try dictionary(await webView.callAsyncJavaScript(body, arguments: ["milliseconds": milliseconds],
                                                                 in: nil, contentWorld: .page))
    }

    func close() {
        loadDeadline?.cancel()
        loadDeadline = nil
        finishLoading(.failure(CancellationError()))
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(.failure(error))
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        loadDeadline?.cancel()
        loadDeadline = nil
        let continuation = loading
        loading = nil
        continuation?.resume(with: result)
    }

    private func dictionary(_ value: Any?) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any], "WebKit did not return the local fixture snapshot")
    }

    private enum FixtureError: Error { case loadTimedOut }

    private static let html = #"""
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; connect-src 'none'; img-src 'none'">
    <style>html,body{margin:0;padding:0}body{font:18px/24px -apple-system,sans-serif;padding:24px}p,figure,figcaption{margin:0} .spacer{height:1100px}</style>
    </head><body>
    <p id="first">Artiklens første <a href="#detail">link</a> og <strong>fremhævede ord</strong>.</p>
    <div class="spacer" aria-hidden="true"></div>
    <p id="future">Et senere afsnit med journalistisk tekst, der kommer ind, når læseren når hertil.</p>
    <figure><figcaption><p id="caption">Foto: Redaktionens billedtekst.</p></figcaption></figure>
    <div class="spacer" aria-hidden="true"></div>
    <p id="last">Artiklens sidste afsnit bevarer sin placering under læsningen.</p>
    </body></html>
    """#

    private static let snapshotFunction = #"""
    function () {
        var first = document.getElementById('first');
        var future = document.getElementById('future');
        var last = document.getElementById('last');
        var caption = document.getElementById('caption');
        var attribute = 'data-apropos-reader-motion';
        var style = getComputedStyle(future);
        return {
            firstMotion: first.getAttribute(attribute) || '',
            futureMotion: future.getAttribute(attribute) || '',
            lastMotion: last.getAttribute(attribute) || '',
            captionMotion: caption.getAttribute(attribute) || '',
            motionCount: document.querySelectorAll('[' + attribute + ']').length,
            futureOpacity: Number(style.opacity),
            futureTransform: style.transform,
            futureTop: future.offsetTop,
            futureHeight: future.offsetHeight,
            lastTop: last.offsetTop,
            documentHeight: document.body.offsetHeight,
            firstChildCount: first.childNodes.length,
            futureChildCount: future.childNodes.length,
            linkCount: document.querySelectorAll('a').length,
            firstHTML: first.innerHTML,
            futureHTML: future.innerHTML,
            captionHTML: caption.innerHTML,
            linkHref: first.querySelector('a').getAttribute('href'),
            apiExists: !!window.aproposReaderReveal,
            motionStyleCount: Array.from(document.querySelectorAll('style')).filter(function (element) {
                return element.textContent.indexOf('apropos-native-reader-arrive') !== -1;
            }).length
        };
    }
    """#
}
