import FirebaseCore
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import Apropos

@MainActor
final class ArticleInlineMediaTests: XCTestCase {
    /// Baseline reproducer: a late error must preserve the reader's position,
    /// credit association and the reserved full-width media rectangle.
    func testLateImageFailurePreservesMediaCreditAndFollowingTextGeometry() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        try await f.load(html: f.article(image: "<img id='media' src='\(f.validImage)'>"))
        let before = try await f.metrics()
        XCTAssertEqual(before["mediaHeight"], 360)
        let after = try await f.failImage()
        let report = ["before": before, "after": after]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]), uniformTypeIdentifier: "public.json")
        attachment.name = "Inline media actual WebKit geometry"; attachment.lifetime = .keepAlways; add(attachment)
        for key in ["mediaTop", "mediaHeight", "creditTop", "afterTop", "documentHeight"] {
            XCTAssertEqual(try XCTUnwrap(after[key]), try XCTUnwrap(before[key]), accuracy: 1,
                           "Late image failure moved \(key): before \(before), after \(after)")
        }
        XCTAssertEqual(after["fallbackCount"], 1)
        XCTAssertEqual(after["creditCount"], 1)
        XCTAssertEqual(after["creditTextMatches"], 1)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testImageThatAlreadyFailedBeforeHandlersGetsReadableStableFallback() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        try await f.load(html: f.article(image: "<img id='media' src='data:image/png;base64,broken-eager'>"), installHandlers: false)
        let failedBeforeSetup = try await f.web.evaluateJavaScript("document.getElementById('media').complete && document.getElementById('media').naturalWidth === 0")
        XCTAssertEqual(failedBeforeSetup as? Bool, true)
        let before = try await f.metrics()
        try await f.installHandlers()
        let after = try await f.metrics()
        XCTAssertEqual(after["fallbackCount"], 1)
        XCTAssertEqual(after["mediaHeight"], 360)
        XCTAssertEqual(try XCTUnwrap(after["afterTop"]), try XCTUnwrap(before["afterTop"]), accuracy: 1)
        let label = try await f.web.evaluateJavaScript("document.querySelector('.apropos-offline-media')?.textContent.trim()")
        XCTAssertEqual(label as? String, "Billedet kunne ikke indlæses")
        XCTAssertEqual(after["creditCount"], 1)
    }

    func testSuccessfulImageRetainsItsRealSourceAndCredit() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        try await f.load(html: f.article(image: "<img id='media' alt='Lokalt testbillede' src='\(f.validImage)'>"))
        let result = try await f.metrics()
        XCTAssertEqual(result["fallbackCount"], 0); XCTAssertEqual(result["mediaHeight"], 360)
        let loaded = try await f.web.evaluateJavaScript("document.getElementById('media').naturalWidth === 2 && document.getElementById('media').alt === 'Lokalt testbillede'")
        XCTAssertEqual(loaded as? Bool, true)
        XCTAssertEqual(result["creditTextMatches"], 1)
    }

    func testFailedLazyPlaceholderWaitsForActivationThenRealImageSucceeds() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        let image = "<img id='media' class='apropos-lazy' src='data:image/png;base64,broken-placeholder' data-src='\(f.validImage)'>"
        let html = f.article(image: image).replacingOccurrences(of: "id='before'", with: "id='before' style='height:1600px'")
        try await f.load(html: html)
        let before = try await f.metrics()
        XCTAssertEqual(before["fallbackCount"], 0)
        let pending = try await f.web.evaluateJavaScript("document.getElementById('media')?.hasAttribute('data-src')")
        XCTAssertEqual(pending as? Bool, true)
        let success = try await f.web.callAsyncJavaScript("""
        const image = document.getElementById('media');
        await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => reject(Error('Real lazy image did not activate')), 4000);
            image.addEventListener('load', () => { clearTimeout(timeout); resolve(); }, { once: true });
            document.getElementById('before').style.height = '0px';
        });
        return image.isConnected && image.naturalWidth === 2 && !image.hasAttribute('data-src') && !image.classList.contains('apropos-lazy');
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(success as? Bool, true)
        let after = try await f.metrics()
        XCTAssertEqual(after["fallbackCount"], 0); XCTAssertEqual(after["mediaHeight"], 360)
    }

    func testActivatedBrokenLazySourceGetsOneStableFallback() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        let image = "<img id='media' class='apropos-lazy' src='\(f.validImage)' data-src='data:image/png;base64,broken-real-lazy'>"
        let html = f.article(image: image).replacingOccurrences(of: "id='before'", with: "id='before' style='height:1600px'")
        try await f.load(html: html)
        let before = try await f.metrics(); XCTAssertEqual(before["fallbackCount"], 0)
        let activated = try await f.web.callAsyncJavaScript("""
        await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => { observer.disconnect(); reject(Error('Missing real lazy error fallback')); }, 4000);
            const observer = new MutationObserver(() => {
                if (!document.querySelector('.apropos-offline-media')) return;
                observer.disconnect(); clearTimeout(timeout); requestAnimationFrame(() => requestAnimationFrame(resolve));
            });
            observer.observe(document.body, { childList: true, subtree: true });
            document.getElementById('before').style.height = '0px';
        });
        return document.querySelectorAll('.apropos-offline-media').length;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual((activated as? NSNumber)?.intValue, 1)
        let after = try await f.metrics()
        XCTAssertEqual(after["mediaHeight"], 360); XCTAssertEqual(after["creditTextMatches"], 1)
    }

    func testCleanupStopsOldListenersAndFreshInstallationHandlesFutureFailure() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        try await f.load(html: f.article(image: "<img id='media' src='\(f.validImage)'>"))
        _ = try await f.web.evaluateJavaScript("const cleanup = window.aproposHeightCleanup; cleanup(); cleanup();")
        let afterCleanup = try await f.failImage()
        XCTAssertEqual(afterCleanup["fallbackCount"], 0, "Disposed listeners must not mutate the document")
        try await f.installHandlers()
        let afterReinstall = try await f.metrics()
        XCTAssertEqual(afterReinstall["fallbackCount"], 1, "A fresh setup handles the already failed image exactly once")
        XCTAssertEqual(afterReinstall["mediaHeight"], 360)
        try await f.installHandlers()
        let repeated = try await f.metrics()
        XCTAssertEqual(repeated["fallbackCount"], 1); XCTAssertEqual(repeated["creditCount"], 1)
        let lazy = "<img id='media' class='apropos-lazy' src='\(f.validImage)' data-src='data:image/png;base64,unrequested-real-image'>"
        try await f.load(html: f.article(image: lazy).replacingOccurrences(of: "id='before'", with: "id='before' style='height:1600px'"))
        let stillPending = try await f.web.callAsyncJavaScript("""
        window.aproposHeightCleanup();
        document.getElementById('before').style.height = '0px';
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return document.getElementById('media').hasAttribute('data-src') && !document.querySelector('.apropos-offline-media');
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(stillPending as? Bool, true, "Cleanup must disconnect the actual lazy observer before viewport activation")
    }

    func testCapturedOldDocumentErrorCallbackCannotMutateNewNonce() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        try await f.load(html: f.article(image: "<img id='media' src='\(f.validImage)'>"), installHandlers: false)
        _ = try await f.web.evaluateJavaScript("""
        window.fixtureOriginalAdd = EventTarget.prototype.addEventListener;
        window.fixtureCapturedErrors = [];
        EventTarget.prototype.addEventListener = function(type, callback, options) {
            if (this.id === 'media' && type === 'error') window.fixtureCapturedErrors.push(callback);
            return window.fixtureOriginalAdd.call(this, type, callback, options);
        };
        true;
        """)
        try await f.installHandlers()
        let count = try await f.web.evaluateJavaScript("window.fixtureCapturedErrors.length")
        XCTAssertGreaterThan((count as? NSNumber)?.intValue ?? 0, 0)
        let nextDocument = UUID().uuidString
        _ = try await f.web.callAsyncJavaScript("""
        EventTarget.prototype.addEventListener = window.fixtureOriginalAdd;
        document.querySelector('meta[name="apropos-document"]').content = nextDocument;
        return true;
        """, arguments: ["nextDocument": nextDocument], in: nil, contentWorld: .page)
        let originalNavigation = f.coordinator.expectedNavigation
        f.coordinator.acceptDocument(nextDocument); f.coordinator.expectedNavigation = originalNavigation
        let before = try await f.metrics()
        let afterRealFailure = try await f.failImage()
        XCTAssertEqual(afterRealFailure, before, "The original A listener must reject a real error after the document nonce becomes B")
        try await f.installHandlers()
        let freshB = try await f.metrics()
        XCTAssertEqual(freshB["fallbackCount"], 1, "Only the newly installed B listener may handle B's failed image")
        _ = try await f.web.evaluateJavaScript("window.fixtureCapturedErrors.forEach(callback => callback.call(null, new Event('error')))")
        let afterLateCallback = try await f.metrics()
        XCTAssertEqual(afterLateCallback, freshB, "A retained A callback must not alter the current B fallback")
    }

    func testWrappedMediaFailurePreservesActualResumeAnchorAndRevealExclusion() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        let image = "<p id='mediaWrapper'><a href='about:blank'><img id='media' src='\(f.validImage)'></a></p>"
        try await f.load(html: f.article(image: image))
        _ = try await f.web.evaluateJavaScript(ReaderResumeScript.source + "\n" + ArticleTextRevealScript.source)
        let before = try await f.resumeSnapshot()
        XCTAssertEqual(before["index"] as? Int, 1)
        XCTAssertEqual(before["wrapperExcluded"] as? Bool, true)
        _ = try await f.failImage()
        let after = try await f.resumeSnapshot()
        XCTAssertEqual(after["index"] as? Int, before["index"] as? Int)
        XCTAssertEqual(after["fingerprint"] as? String, before["fingerprint"] as? String)
        XCTAssertEqual(try XCTUnwrap(after["top"] as? Double), try XCTUnwrap(before["top"] as? Double), accuracy: 1)
        XCTAssertEqual(after["wrapperExcluded"] as? Bool, true, "Media wrapper must never become a newly animated prose block")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testMaximumBodyFontAndLinkedFigurePreserveCreditAndReadingGeometry() async throws {
        let f = InlineMediaFixture(); defer { f.close() }
        let html = "<p id='before'>Læs videre i dit eget tempo.</p><figure style='margin:0'><a href='about:blank'><img id='media' src='\(f.validImage)'></a><figcaption id='credit'>Foto: Lokal test</figcaption></figure><p id='after'>" + String(repeating: "Teksten efter billedet må ikke flytte sig. ", count: 20) + "</p>"
        try await f.load(html: html, fontSize: 53)
        let before = try await f.metrics(), after = try await f.failImage()
        for key in ["mediaTop", "mediaHeight", "creditTop", "afterTop", "documentHeight"] {
            XCTAssertEqual(try XCTUnwrap(after[key]), try XCTUnwrap(before[key]), accuracy: 1, "Large-type linked figure changed \(key)")
        }
        let readable = try await f.web.evaluateJavaScript("""
        (() => { const box = document.querySelector('.apropos-offline-media'); const range = document.createRange(); range.selectNodeContents(box);
            return box.getBoundingClientRect().width <= document.documentElement.clientWidth + 1
              && range.getBoundingClientRect().bottom <= box.getBoundingClientRect().bottom
              && document.querySelectorAll('figcaption').length === 1; })()
        """)
        XCTAssertEqual(readable as? Bool, true)
        XCTAssertNil(FirebaseApp.allApps)
    }
}

@MainActor
private final class InlineMediaFixture: NSObject, WKNavigationDelegate {
    let web: ArticleMotionWebView
    let coordinator: HTMLTextView.Coordinator
    let validImage: String
    var documentID = UUID().uuidString
    private var loaded: XCTestExpectation?
    private var loadError: Error?
    private var installAtFinish = true
    private let window: UIWindow

    override init() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        web = ArticleMotionWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let imageFormat = UIGraphicsImageRendererFormat(); imageFormat.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: imageFormat).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        validImage = "data:image/png;base64," + image.base64EncodedString()
        let renderer = HTMLTextView(html: "", dynamicHeight: .constant(844), prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
        coordinator = renderer.makeCoordinator()
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene); window.frame = frame
        } else { window = UIWindow(frame: frame) }
        super.init()
        let controller = UIViewController(); controller.view.frame = frame
        controller.view.addSubview(web); window.rootViewController = controller; window.isHidden = false
        web.navigationDelegate = self
        web.configuration.userContentController.add(coordinator, name: "heightHandler")
    }
    func article(image: String) -> String {
        "<p id='before'>En historie giver plads til detaljerne.</p>" + image +
        "<div id='credit' class='apropos-image-credit'><span>Foto: Lokal test</span></div>" +
        "<p id='after'>" + String(repeating: "Efter billedet fortsætter fortællingen. Denne tekst skal blive på sin plads, når billedet ikke kan vises. ", count: 8) + "</p>"
    }
    func load(html: String, fontSize: Double = 18, installHandlers: Bool = true) async throws {
        installAtFinish = installHandlers
        documentID = UUID().uuidString; loadError = nil
        coordinator.acceptDocument(documentID)
        let document = ArticleHTMLPreparation.document(html: html, bodyFontSize: fontSize, documentID: documentID)
            .replacingOccurrences(of: "<head>", with: "<head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; script-src 'unsafe-inline'; style-src 'unsafe-inline'\">")
        let loaded = XCTestExpectation(description: "Actual production document and media handlers installed")
        self.loaded = loaded
        coordinator.expectedNavigation = web.loadHTMLString(document, baseURL: URL(string: "about:blank"))
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 8)
        XCTAssertEqual(result, .completed)
        if let loadError { throw loadError }
        if installHandlers { try await verifyHandlers() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if installAtFinish { coordinator.webView(webView, didFinish: navigation) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { _ = try await self.web.evaluateJavaScript("document.querySelector('#media')?.complete === true") }
            catch { self.loadError = error }
            self.loaded?.fulfill(); self.loaded = nil
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadError = error; loaded?.fulfill(); loaded = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func installHandlers() async throws {
        coordinator.webView(web, didFinish: coordinator.expectedNavigation)
        try await verifyHandlers()
    }
    private func verifyHandlers() async throws {
        // WK evaluation commands preserve order; this runs after the actual
        // coordinator's injection, without sleeping or mocking its handlers.
        let installed = try await web.evaluateJavaScript("typeof window.aproposHeightCleanup === 'function'")
        XCTAssertEqual(installed as? Bool, true)
    }
    func metrics() async throws -> [String: Double] {
        try await numbers("return (\(Self.measurement))();")
    }
    func failImage() async throws -> [String: Double] {
        try await numbers("""
        const image = document.getElementById('media');
        if (!image || !image.complete || image.naturalWidth <= 0) throw Error('Expected an actually loaded image');
        await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => reject(Error('Real local image error did not arrive')), 4000);
            image.addEventListener('error', () => {
                clearTimeout(timeout); requestAnimationFrame(() => requestAnimationFrame(resolve));
            }, { once: true });
            image.src = 'data:image/png;base64,broken-local-image';
        });
        return (\(Self.measurement))();
        """)
    }
    func resumeSnapshot() async throws -> [String: Any] {
        let result = try await web.callAsyncJavaScript("""
        window.aproposReaderReveal.update({ top: 0, bottom: 1, reduceMotion: false });
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const top = document.getElementById('after').offsetTop;
        const anchor = window.aproposReaderResume.capture(id, top, top + 600);
        if (!anchor) throw Error('Expected original paragraph anchor');
        const resolved = window.aproposReaderResume.resolve(id, anchor.index, anchor.fingerprint);
        if (!resolved) throw Error('Expected original anchor to resolve');
        return { index: anchor.index, fingerprint: anchor.fingerprint, top: resolved.top,
          wrapperExcluded: !document.getElementById('mediaWrapper').hasAttribute('data-apropos-reader-motion') };
        """, arguments: ["id": documentID], in: nil, contentWorld: .page)
        return try XCTUnwrap(result as? [String: Any])
    }
    private func numbers(_ script: String) async throws -> [String: Double] {
        let value = try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        let dictionary = try XCTUnwrap(value as? [String: NSNumber])
        return dictionary.mapValues(\.doubleValue)
    }
    private static let measurement = """
    function() {
        const media = document.querySelector('#media') || document.querySelector('.apropos-offline-media');
        const credit = document.getElementById('credit');
        const after = document.getElementById('after');
        if (!media || !credit || !after) throw Error('Article fixture elements missing');
        const rect = media.getBoundingClientRect();
        return { mediaTop: rect.top, mediaHeight: rect.height,
          creditTop: credit.getBoundingClientRect().top, afterTop: after.getBoundingClientRect().top,
          documentHeight: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
          fallbackCount: document.querySelectorAll('.apropos-offline-media').length,
          creditCount: document.querySelectorAll('#credit').length,
          creditTextMatches: credit.textContent === 'Foto: Lokal test' ? 1 : 0 };
    }
    """
    func close() {
        HTMLTextView.dismantleUIView(web, coordinator: coordinator)
        web.removeFromSuperview(); window.isHidden = true; window.rootViewController = nil
    }
}
