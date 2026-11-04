import FirebaseCore
import UIKit
import WebKit
import XCTest
@testable import Apropos

@MainActor
final class ArticleHTMLPreparationReadinessTests: XCTestCase {
    func testActionableReadinessWaitsForActualLayoutAndImmediateResumeWorks() async throws {
        let fixture = PreparationReadinessFixture(); defer { fixture.close() }
        try await fixture.load()
        let ready = expectation(description: "Actual document and layout ready")
        var delivered = 0
        fixture.motion.whenDocumentReady(fixture.documentID) { delivered += 1; ready.fulfill() }
        let height = try await fixture.height()
        fixture.motion.measuredContent(height: height)
        await frames()
        XCTAssertEqual(delivered, 0, "The measured height must not authorize a still-small WebKit view")
        fixture.web.frame.size.height = height
        fixture.motion.geometryDidChange()
        await frames()
        XCTAssertEqual(delivered, 0, "The outer scroll content size must also have accepted the layout")
        fixture.scroll.contentSize.height = fixture.web.frame.maxY + 40
        fixture.motion.geometryDidChange()
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(delivered, 1)
        let payload = try await fixture.web.callAsyncJavaScript("return window.aproposReaderResume.capture(id, document.getElementById('p6').offsetTop, document.getElementById('p6').offsetTop + 600);",
            arguments: ["id": fixture.documentID], in: nil, contentWorld: .page) as? [String: Any]
        let anchor = ReaderResumeAnchor(index: try XCTUnwrap(payload?["index"] as? Int),
            fingerprint: try XCTUnwrap(payload?["fingerprint"] as? String))
        let resumed = await withCheckedContinuation { continuation in
            fixture.motion.resume(anchor: anchor, documentID: fixture.documentID, stillCurrent: { true }) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(resumed); XCTAssertGreaterThan(fixture.scroll.contentOffset.y, 500)
        await frames(); XCTAssertEqual(delivered, 1, "Readiness is delivered once for the original document")
        XCTAssertNil(FirebaseApp.allApps)
    }
    func testScriptAndLayoutWithoutAcceptedHeightDoNotExposeReady() async throws {
        let fixture = PreparationReadinessFixture(); defer { fixture.close() }
        try await fixture.load()
        let height = try await fixture.height()
        fixture.web.frame.size.height = height; fixture.scroll.contentSize.height = fixture.web.frame.maxY + 40
        var delivered = false
        fixture.motion.whenDocumentReady(fixture.documentID) { delivered = true }
        fixture.motion.geometryDidChange(); await frames()
        XCTAssertFalse(delivered)
        let ready = expectation(description: "Accepted native measurement")
        fixture.motion.whenDocumentReady(fixture.documentID) { delivered = true; ready.fulfill() }
        fixture.motion.measuredContent(height: height)
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertTrue(delivered)
    }
    func testOldDocumentAndDetachedReadinessCallbacksNeverBindReplacement() async throws {
        let fixture = PreparationReadinessFixture(); defer { fixture.close() }
        try await fixture.load()
        var stale = 0
        fixture.motion.whenDocumentReady(fixture.documentID) { stale += 1 }
        fixture.motion.contentWillLoad(documentID: UUID().uuidString)
        let height = try await fixture.height()
        fixture.web.frame.size.height = height; fixture.scroll.contentSize.height = fixture.web.frame.maxY + 40
        fixture.motion.measuredContent(height: height); fixture.motion.geometryDidChange()
        await frames(); XCTAssertEqual(stale, 0)
        fixture.motion.detach(fixture.web); fixture.motion.geometryDidChange()
        await frames(); XCTAssertEqual(stale, 0)
        XCTAssertNil(FirebaseApp.allApps)
    }
    private func frames() async {
        let reached = expectation(description: "Three actual display frames")
        let counter = PreparationFrameCounter { reached.fulfill() }
        counter.start()
        await fulfillment(of: [reached], timeout: 3)
        counter.stop()
    }
}

@MainActor
private final class PreparationFrameCounter: NSObject {
    private var link: CADisplayLink?
    private var count = 0
    let complete: () -> Void
    init(complete: @escaping () -> Void) { self.complete = complete }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(frame))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    @objc private func frame() { count += 1; if count == 3 { stop(); complete() } }
    func stop() { link?.invalidate(); link = nil }
}

@MainActor
private final class PreparationReadinessFixture: NSObject, WKNavigationDelegate {
    let documentID = UUID().uuidString
    let motion = ArticleReadingMotionController()
    let web: WKWebView
    let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    private let window: UIWindow
    private var loaded: XCTestExpectation?
    override init() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(x: 0, y: 100, width: 390, height: 240), configuration: config)
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene); window.frame = frame
        } else { window = UIWindow(frame: frame) }
        super.init()
        let controller = UIViewController(); controller.view.frame = frame
        controller.view.addSubview(scroll); scroll.addSubview(web)
        scroll.contentInsetAdjustmentBehavior = .never; scroll.contentSize = CGSize(width: 390, height: 600)
        web.scrollView.isScrollEnabled = false; web.navigationDelegate = self
        window.rootViewController = controller; window.isHidden = false
        controller.view.layoutIfNeeded(); motion.attach(web)
    }
    func load() async throws {
        motion.contentWillLoad(documentID: documentID)
        let prose = (0..<16).map { "<p id='p\($0)'>Afsnit \($0). En fortælling giver plads til eftertanke og detaljer. Ordene bliver stående, mens man læser videre i sit eget tempo.</p>" }.joined()
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="apropos-document" content="\(documentID)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
        <style>body{margin:0;padding:0 16px;font:18px/1.7 -apple-system}p{margin:0 0 24px}</style>
        </head><body>\(prose)</body></html>
        """
        let loaded = XCTestExpectation(description: "Local CSP-locked WebKit document")
        self.loaded = loaded; web.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 8)
        XCTAssertEqual(result, .completed)
        motion.contentDidFinish(web)
        let script = try await web.evaluateJavaScript("typeof window.aproposReaderResume === 'object'")
        XCTAssertEqual(script as? Bool, true)
    }
    func height() async throws -> CGFloat {
        let value = try await web.evaluateJavaScript("document.body.scrollHeight")
        return CGFloat(try XCTUnwrap(value as? NSNumber).doubleValue)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.fulfill(); loaded = nil }
    func close() {
        motion.detach(web); web.stopLoading(); web.navigationDelegate = nil
        web.removeFromSuperview(); window.isHidden = true; window.rootViewController = nil
    }
}
