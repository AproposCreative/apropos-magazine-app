import UIKit
import WebKit
import XCTest
@testable import Apropos

/// The shipped paragraph script and native outer-scroll bridge run against local
/// CSP-locked prose in a nonpersistent WebKit surface. No service is initialized.
@MainActor
final class ReaderResumeWebKitTests: XCTestCase {
    func testDocumentLoadLayoutAndProgrammaticScrollDoNotProduceSaveSamples() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        var samples = 0
        h.motion.onResumeSample = { _, _, _ in samples += 1 }
        try await h.load()
        XCTAssertEqual(h.scroll.contentOffset.y, 0)
        h.scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        h.motion.geometryDidChange()
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(samples, 0)
    }

    func testExplicitResumeUsesRealParagraphAndNativeOuterScrollView() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(6)
        XCTAssertEqual(anchor.index, 6)
        XCTAssertEqual(h.scroll.contentOffset.y, 0)
        let success = await h.resume(anchor)
        XCTAssertTrue(success)
        XCTAssertGreaterThan(h.scroll.contentOffset.y, 500)
        try await h.assertParagraphAtReaderTop(6)
    }

    func testScriptReadyWithoutAcceptedNativeHeightCannotClaimSuccessfulResume() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load(measureHeight: false)
        let anchor = try await h.captureParagraph(6)
        let premature = await h.resume(anchor)
        XCTAssertFalse(premature); XCTAssertEqual(h.scroll.contentOffset.y, 0)
        try await h.measure()
        let ready = await h.resume(anchor)
        XCTAssertTrue(ready)
        try await h.assertParagraphAtReaderTop(6)
    }

    func testSameParagraphResolvesAtNewTextSizeWithoutUsingOldPercentage() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(6)
        let oldTop = try await h.top(6)
        _ = try await h.web.evaluateJavaScript("document.body.style.fontSize = '32px';")
        try await h.measure()
        let largerTop = try await h.top(6)
        XCTAssertGreaterThan(largerTop, oldTop)
        let success = await h.resume(anchor)
        XCTAssertTrue(success)
        try await h.assertParagraphAtReaderTop(6)
    }

    func testChangedParagraphFingerprintAndOldDocumentNonceFailClosed() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(6)
        _ = try await h.web.evaluateJavaScript("document.getElementById('p6').textContent = 'Changed paragraph';")
        let changed = await h.resume(anchor)
        XCTAssertFalse(changed); XCTAssertEqual(h.scroll.contentOffset.y, 0)
        let old = try await h.web.callAsyncJavaScript(
            "return window.aproposReaderResume.capture(id, 600, 1200);",
            arguments: ["id": UUID().uuidString], in: nil, contentWorld: .page)
        XCTAssertTrue(old == nil || old is NSNull)
    }

    func testOwnerRevokedDuringResolveCannotScrollAndDetachedViewRejectsResume() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(6)
        var checks = 0
        let stale = await h.resume(anchor, permitted: { checks += 1; return checks == 1 })
        XCTAssertFalse(stale); XCTAssertEqual(h.scroll.contentOffset.y, 0)
        h.motion.detach(h.web)
        let detached = await h.resume(anchor)
        XCTAssertFalse(detached); XCTAssertEqual(h.scroll.contentOffset.y, 0)
    }

    func testCaptionsAndMediaDoNotBecomeParagraphAnchors() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(1)
        // Caption and placeholder paragraphs precede p1 in the HTML but are
        // excluded by the same policy used in the real renderer.
        XCTAssertEqual(anchor.index, 1)
        let beforeBody = try await h.web.callAsyncJavaScript(
            "return window.aproposReaderResume.capture(id, -1, 600);",
            arguments: ["id": h.documentID], in: nil, contentWorld: .page)
        XCTAssertTrue(beforeBody == nil || beforeBody is NSNull)
    }

    func testWidthReflowPreservesExplicitParagraphWithoutSavingPosition() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        var samples = 0
        h.motion.onResumeSample = { _, _, _ in samples += 1 }
        try await h.load(proseRepetitions: 4)
        let anchor = try await h.captureParagraph(6)
        let resumed = await h.resume(anchor)
        XCTAssertTrue(resumed)
        try await h.assertParagraphAtReaderTop(6)
        let originalTop = try await h.top(6)
        let originalOffset = h.scroll.contentOffset.y

        try await h.resize(width: 700)
        try await h.measure()
        let reflowedTop = try await h.top(6)
        XCTAssertGreaterThan(originalTop - reflowedTop, 100, "The real prose must reflow, not merely resize its native frame")
        try await h.waitForParagraphAtReaderTop(6)
        XCTAssertGreaterThan(originalOffset - h.scroll.contentOffset.y, 100)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(samples, 0, "Layout preservation must not become a new user save")
    }

    func testWidthReflowWaitsForCurrentDOMAndNativeHeightBeforeCorrectingOffset() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        var samples = 0
        h.motion.onResumeSample = { _, _, _ in samples += 1 }
        try await h.load(proseRepetitions: 4)
        let anchor = try await h.captureParagraph(6)
        let resumed = await h.resume(anchor)
        XCTAssertTrue(resumed)
        let originalHeight = h.web.bounds.height
        let originalOffset = h.scroll.contentOffset.y

        try await h.resize(width: 700)
        let currentHeight = try await h.contentHeight()
        XCTAssertGreaterThan(originalHeight - currentHeight, 100)
        // Width and DOM have changed, while both native sizing and the
        // controller's accepted content-height callback still describe portrait.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(h.scroll.contentOffset.y, originalOffset, accuracy: 1)
        let staleDistance = try await h.paragraphDistanceFromReaderTop(6)
        XCTAssertGreaterThan(abs(staleDistance), 100)

        // The current DOM measurement may arrive before the native WebKit
        // frame is resized. This crossed pair must still preserve the offset.
        h.motion.measuredContent(height: currentHeight)
        h.motion.geometryDidChange()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(h.web.bounds.height, originalHeight, accuracy: 1)
        XCTAssertEqual(h.scroll.contentOffset.y, originalOffset, accuracy: 1,
            "A current measured height must not authorize correction through the old native frame")

        h.applyNativeHeight(currentHeight)
        h.motion.measuredContent(height: originalHeight)
        h.motion.geometryDidChange()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(h.scroll.contentOffset.y, originalOffset, accuracy: 1,
            "A stale measured-height callback must not authorize the current DOM reflow")
        try await h.measure()
        try await h.waitForParagraphAtReaderTop(6)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(samples, 0)
    }

    func testReloadDetachNewDocumentAndReopenDoNotRestoreTransientLayoutPosition() async throws {
        for reset in ["same-document-reload", "detach-and-reattach", "new-document", "reopen"] {
            var h = ResumeWebHarness(); defer { h.close() }
            var samples = 0
            h.motion.onResumeSample = { _, _, _ in samples += 1 }
            try await h.load(proseRepetitions: 4)
            let originalDocument = h.documentID
            let anchor = try await h.captureParagraph(6)
            let resumed = await h.resume(anchor)
            XCTAssertTrue(resumed, reset)
            try await h.assertParagraphAtReaderTop(6)

            switch reset {
            case "detach-and-reattach":
                h.motion.detach(h.web)
                h.motion.attach(h.web)
                h.motion.onResumeSample = { _, _, _ in samples += 1 }
            case "reopen":
                h.close()
                h = ResumeWebHarness()
                h.motion.onResumeSample = { _, _, _ in samples += 1 }
            default: break
            }
            let nextDocument = reset == "new-document" ? UUID().uuidString : originalDocument
            // A real local document load invokes contentWillLoad even when its
            // nonce is unchanged. No stored or transient resume action is invoked.
            try await h.load(proseRepetitions: 4, documentID: nextDocument)
            h.scroll.setContentOffset(.zero, animated: false)
            try await h.resize(width: 700)
            try await h.measure()
            try await Task.sleep(nanoseconds: 550_000_000)
            XCTAssertEqual(h.scroll.contentOffset.y, 0, accuracy: 1, reset)
            XCTAssertEqual(samples, 0, reset)
            let distance = try await h.paragraphDistanceFromReaderTop(6)
            XCTAssertGreaterThan(distance, 100, reset)
            let freshAnchor = try await h.captureParagraph(6)
            let explicitlyResumed = await h.resume(freshAnchor)
            XCTAssertTrue(explicitlyResumed, "A fresh explicit action remains usable after \(reset)")
            try await h.assertParagraphAtReaderTop(6)
        }
    }

    func testLatestExplicitResumeReplacesEarlierParagraphBeforeWidthReflow() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        var samples = 0
        h.motion.onResumeSample = { _, _, _ in samples += 1 }
        try await h.load(proseRepetitions: 4)
        let sixth = try await h.captureParagraph(6)
        let eighth = try await h.captureParagraph(8)
        let first = await h.resume(sixth)
        XCTAssertTrue(first)
        let latest = await h.resume(eighth)
        XCTAssertTrue(latest)
        try await h.assertParagraphAtReaderTop(8)
        try await h.resize(width: 700)
        try await h.measure()
        try await h.waitForParagraphAtReaderTop(8)
        let oldAnchorDistance = try await h.paragraphDistanceFromReaderTop(6)
        XCTAssertGreaterThan(abs(oldAnchorDistance), 100)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(samples, 0)
    }

    func testFinalNativeHeightEventDuringOutstandingWebKitResolveStillPreservesParagraph() async throws {
        let h = ResumeWebHarness(); defer { h.close() }
        var samples = 0
        h.motion.onResumeSample = { _, _, _ in samples += 1 }
        try await h.load(proseRepetitions: 4)
        let anchor = try await h.captureParagraph(6)
        let resumed = await h.resume(anchor)
        XCTAssertTrue(resumed)
        let originalHeight = h.web.bounds.height
        var nativeEvents = 0
        let handler = ResumeLayoutMessageHandler { message in
            guard let height = message.body as? NSNumber else {
                XCTFail("The local WebKit event must carry its measured content height"); return
            }
            nativeEvents += 1
            h.applyNativeHeight(CGFloat(height.doubleValue))
            h.motion.measuredContent(height: CGFloat(height.doubleValue))
            h.motion.geometryDidChange()
        }
        h.web.configuration.userContentController.add(handler, name: "resumeLayoutTest")
        defer { h.web.configuration.userContentController.removeScriptMessageHandler(forName: "resumeLayoutTest") }
        _ = try await h.web.evaluateJavaScript("""
            (() => {
                const resolve = window.aproposReaderResume.resolve;
                let sent = false;
                window.aproposReaderResume.resolve = function(...args) {
                    const result = resolve.apply(this, args);
                    if (!sent && document.documentElement.clientWidth === 700) {
                        sent = true;
                        const last = document.body.lastElementChild;
                        window.webkit.messageHandlers.resumeLayoutTest.postMessage(Math.ceil(last.offsetTop + last.offsetHeight));
                        // Hold this one bridge result in the WebKit process so
                        // native display frames can consume the final event.
                        const deadline = performance.now() + 150;
                        while (performance.now() < deadline) {}
                    }
                    return result;
                };
            })();
            """)
        try await h.resize(width: 700)
        let currentHeight = try await h.contentHeight()
        XCTAssertGreaterThan(originalHeight - currentHeight, 100)
        // Keep both native and accepted height old until the actual JS message.
        try await h.waitForParagraphAtReaderTop(6)
        XCTAssertEqual(nativeEvents, 1)
        XCTAssertEqual(h.web.bounds.height, currentHeight, accuracy: 1)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(samples, 0)
    }
}

@MainActor
private final class ResumeLayoutMessageHandler: NSObject, WKScriptMessageHandler {
    let receive: (WKScriptMessage) -> Void
    init(receive: @escaping (WKScriptMessage) -> Void) { self.receive = receive }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        receive(message)
    }
}

@MainActor
private final class ResumeWebHarness: NSObject, WKNavigationDelegate {
    private(set) var documentID = UUID().uuidString
    let web: WKWebView
    let scroll: UIScrollView
    let motion = ArticleReadingMotionController()
    private let window: UIWindow
    private var loading: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    enum Failure: Error { case timeout, missing }

    override init() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(x: 0, y: 250, width: 390, height: 4_000), configuration: configuration)
        scroll = UIScrollView(frame: frame)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene); window.frame = frame
        } else { window = UIWindow(frame: frame) }
        super.init()
        let controller = UIViewController()
        controller.view.frame = frame
        controller.view.addSubview(scroll)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.addSubview(web)
        scroll.contentSize = CGSize(width: 390, height: 4_400)
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = self
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        motion.attach(web)
    }

    func load(measureHeight: Bool = true, proseRepetitions: Int = 1, documentID nextDocumentID: String? = nil) async throws {
        if let nextDocumentID { documentID = nextDocumentID }
        motion.contentWillLoad(documentID: documentID)
        let paragraph = String(repeating: "En rolig artikel giver plads til at tænke og følge detaljerne i fortællingen. Ordene bliver stående, mens man læser i sit eget tempo. Det er en lokal test uden billeder eller netværk. ", count: proseRepetitions)
        let prose = (0..<14).map { index in
            "<p id='p\(index)'>Afsnit \(index). \(paragraph)</p>"
                + (index == 0 ? "<figcaption><p>Caption</p></figcaption><div class='apropos-offline-media'><p>Offline media</p></div>" : "")
        }.joined()
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="apropos-document" content="\(documentID)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
        <style>body{margin:0;padding:0 16px;font:18px/1.7 -apple-system}p{margin:0 0 24px}figcaption,.apropos-offline-media{height:30px;overflow:hidden}</style>
        </head><body>\(prose)</body></html>
        """
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                self?.finish(.failure(Failure.timeout))
            }
            web.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        }
        motion.contentDidFinish(web)
        if measureHeight { try await measure() }
        let ready = try await web.evaluateJavaScript("typeof window.aproposReaderResume === 'object'")
        XCTAssertEqual(ready as? Bool, true)
    }

    func measure() async throws {
        let height = try await contentHeight()
        applyNativeHeight(height)
        motion.measuredContent(height: height)
        motion.geometryDidChange()
    }
    func contentHeight() async throws -> CGFloat {
        // Match HTMLTextView's existing height-handler contract: the last
        // content element's bottom, excluding the final paragraph's margin.
        let result = try await web.evaluateJavaScript("Math.ceil(document.body.lastElementChild.offsetTop + document.body.lastElementChild.offsetHeight)")
        guard let number = result as? NSNumber else { throw Failure.missing }
        return CGFloat(number.doubleValue)
    }
    func applyNativeHeight(_ height: CGFloat) {
        web.frame.size.height = height
        scroll.contentSize.height = height + web.frame.minY + 100
    }
    func resize(width: CGFloat) async throws {
        scroll.frame.size.width = width
        web.frame.size.width = width
        scroll.contentSize.width = width
        scroll.layoutIfNeeded()
        web.layoutIfNeeded()
        motion.geometryDidChange()
        for _ in 0..<120 {
            let value = try await web.evaluateJavaScript("document.documentElement.clientWidth")
            if let number = value as? NSNumber, abs(number.doubleValue - Double(width)) <= 1 { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("The actual WebKit viewport did not adopt the new width")
        throw Failure.timeout
    }
    func top(_ index: Int) async throws -> Double {
        let value = try await web.evaluateJavaScript("document.getElementById('p\(index)').offsetTop")
        guard let value = value as? NSNumber else { throw Failure.missing }; return value.doubleValue
    }
    func captureParagraph(_ index: Int) async throws -> ReaderResumeAnchor {
        let y = try await top(index)
        let value = try await web.callAsyncJavaScript("return window.aproposReaderResume.capture(id, top, top + 600);",
            arguments: ["id": documentID, "top": y], in: nil, contentWorld: .page)
        guard let fields = value as? [String: Any], fields["documentID"] as? String == documentID,
              let index = fields["index"] as? Int, let fingerprint = fields["fingerprint"] as? String else { throw Failure.missing }
        return ReaderResumeAnchor(index: index, fingerprint: fingerprint)
    }
    func resume(_ anchor: ReaderResumeAnchor, permitted: @escaping @MainActor () -> Bool = { true }) async -> Bool {
        await withCheckedContinuation { continuation in
            motion.resume(anchor: anchor, documentID: documentID, stillCurrent: permitted) { continuation.resume(returning: $0) }
        }
    }
    func assertParagraphAtReaderTop(_ index: Int) async throws {
        let distance = try await paragraphDistanceFromReaderTop(index)
        XCTAssertEqual(distance, 0, accuracy: 1)
    }
    func paragraphDistanceFromReaderTop(_ index: Int) async throws -> Double {
        let paragraphTop = try await top(index)
        let bodyTop = web.convert(web.bounds, to: window).minY
        let clip = scroll.convert(scroll.bounds, to: window).intersection(window.safeAreaLayoutGuide.layoutFrame)
        return Double(bodyTop) + paragraphTop - Double(clip.minY)
    }
    func waitForParagraphAtReaderTop(_ index: Int) async throws {
        for _ in 0..<120 {
            if abs(try await paragraphDistanceFromReaderTop(index)) <= 1 { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try await assertParagraphAtReaderTop(index)
        throw Failure.timeout
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Void, Error>) {
        deadline?.cancel(); deadline = nil
        let continuation = loading; loading = nil
        continuation?.resume(with: result)
    }
    func close() {
        finish(.failure(CancellationError()))
        motion.detach(web); web.stopLoading(); web.navigationDelegate = nil
        web.removeFromSuperview(); window.isHidden = true; window.rootViewController = nil
    }
}
