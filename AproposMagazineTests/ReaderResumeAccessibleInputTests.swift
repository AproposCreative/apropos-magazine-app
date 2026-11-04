import UIKit
import SwiftUI
import WebKit
import XCTest
@testable import Apropos

/// Production commands and paragraph capture run against a real SwiftUI scroll
/// owner and local nonpersistent WebKit. These are controller/geometry tests;
/// direct commands do not prove OS VoiceOver or hardware-keyboard event routing.
@MainActor
final class ReaderResumeAccessibleInputTests: XCTestCase {
    func testProgrammaticOuterScrollStillDoesNotProduceAResumeSample() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        h.scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        h.motion.geometryDidChange()
        try await h.settle()
        XCTAssertEqual(h.scroll.contentOffset.y, 500, accuracy: 1)
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testPageCommandsMoveRealOuterScrollAndCaptureOriginalParagraph() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        XCTAssertTrue(try h.command(.pageForward)())
        XCTAssertTrue(try h.command(.pageForward)())
        let forwardOffset = h.scroll.contentOffset.y
        XCTAssertGreaterThan(forwardOffset, 500)
        try await h.waitForSamples(1)
        XCTAssertEqual(h.samples.count, 1, "Rapid commands coalesce to the latest reading position")
        let forward = try XCTUnwrap(h.samples.first)
        XCTAssertEqual(forward.documentID, h.documentID)
        XCTAssertTrue(forward.anchor.isValid)
        XCTAssertGreaterThan(forward.anchor.index, 0)
        XCTAssertFalse(forward.completed)
        XCTAssertFalse(h.scroll.isDragging)
        XCTAssertTrue(try h.command(.pageBackward)())
        XCTAssertLessThan(h.scroll.contentOffset.y, forwardOffset)
        try await h.waitForSamples(2)
        XCTAssertLessThan(h.samples[1].anchor.index, forward.anchor.index)
    }

    func testLineCommandsMoveBothDirectionsAndCaptureAfterSettling() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        h.scroll.setContentOffset(CGPoint(x: 0, y: 1_000), animated: false)
        XCTAssertTrue(try h.command(.lineForward)())
        let down = h.scroll.contentOffset.y
        XCTAssertGreaterThan(down, 1_000)
        XCTAssertTrue(try h.command(.lineBackward)())
        XCTAssertLessThan(h.scroll.contentOffset.y, down)
        try await h.waitForSamples(1)
        XCTAssertEqual(h.samples.count, 1)
        XCTAssertEqual(h.samples[0].documentID, h.documentID)
        XCTAssertTrue(h.samples[0].anchor.isValid)
    }

    func testCommandsAtScrollBoundsDoNotInventUserMovementOrCapture() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        XCTAssertFalse(try h.command(.pageBackward)())
        XCTAssertFalse(try h.command(.lineBackward)())
        let bottom = max(-h.scroll.adjustedContentInset.top,
                         h.scroll.contentSize.height - h.scroll.bounds.height + h.scroll.adjustedContentInset.bottom)
        h.scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        XCTAssertFalse(try h.command(.pageForward)())
        XCTAssertFalse(try h.command(.lineForward)())
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testProgrammaticMoveAfterUserCommandCannotBecomeThatUsersSavedPosition() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        XCTAssertTrue(try h.command(.pageForward)())
        h.scroll.setContentOffset(CGPoint(x: 0, y: h.scroll.contentOffset.y + 300), animated: false)
        h.motion.geometryDidChange()
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testChangedMeasuredGeometryAfterUserCommandCannotBecomeASavedPosition() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let originalHeight = h.web.bounds.height
        XCTAssertTrue(try h.command(.pageForward)())
        _ = try await h.web.evaluateJavaScript("document.body.style.fontSize = '48px';")
        try await h.measure()
        XCTAssertGreaterThan(h.web.bounds.height, originalHeight + 100,
                             "The negative test requires a real new measured document geometry")
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testSynchronousScrollObserverChangingMeasuredHeightConsumesInputWithoutCapture() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let action = try h.command(.pageForward)
        let originalOffset = h.scroll.contentOffset.y
        let originalHeight = h.web.bounds.height
        var changedHeight = false
        let observation = h.scroll.observe(\.contentOffset, options: [.new]) { _, _ in
            MainActor.assumeIsolated {
                guard !changedHeight else { return }
                changedHeight = true
                h.motion.measuredContent(height: originalHeight + 300)
            }
        }
        let handled = action()
        observation.invalidate()
        XCTAssertTrue(changedHeight, "The real synchronous scroll observer must run")
        XCTAssertGreaterThan(h.scroll.contentOffset.y, originalOffset,
                             "The offset moved, but the reentrant measurement must reject capture ownership")
        XCTAssertTrue(handled, "Already moved input must not be forwarded to another keyboard handler")
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        try await h.measure()
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testSynchronousScrollObserverChangingDocumentConsumesInputWithoutCapture() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let action = try h.command(.pageForward)
        let originalOffset = h.scroll.contentOffset.y
        var changedDocument = false
        let observation = h.scroll.observe(\.contentOffset, options: [.new]) { _, _ in
            MainActor.assumeIsolated {
                guard !changedDocument else { return }
                changedDocument = true
                h.motion.contentWillLoad(documentID: UUID().uuidString)
            }
        }
        let handled = action()
        observation.invalidate()
        XCTAssertTrue(changedDocument, "The real synchronous scroll observer must run")
        XCTAssertGreaterThan(h.scroll.contentOffset.y, originalOffset)
        XCTAssertTrue(handled, "Already moved input must not be forwarded to another keyboard handler")
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        try await h.rearmOriginalDocument()
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
        XCTAssertEqual(h.samples[0].documentID, h.documentID)
    }

    func testProbeFallbackBeforeDocumentMovesWithoutSavingAndLaterDocumentStillCaptures() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.prepareScrollOwner()
        h.motion.detach(h.web)
        h.installSampleCallback()
        let probe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        h.scroll.addSubview(probe)
        h.motion.bindInputScrollView(h.scroll, probe: probe)
        let before = h.scroll.contentOffset.y
        XCTAssertTrue(h.motion.accessibilityScroll(.pageForward))
        XCTAssertGreaterThan(h.scroll.contentOffset.y, before)
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty, "Loading-page fallback carries no paragraph-capture authority")
        try await h.load()
        XCTAssertTrue(h.motion.accessibilityScroll(.lineForward))
        try await h.waitForSamples(1)
        XCTAssertEqual(h.samples[0].documentID, h.documentID)
        XCTAssertTrue(h.samples[0].anchor.isValid)
    }

    func testOldProbeTeardownCannotRemoveNewerFallbackBinding() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        h.motion.contentWillLoad(documentID: UUID().uuidString)
        let oldProbe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        let newProbe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        h.scroll.addSubview(oldProbe)
        h.scroll.addSubview(newProbe)
        h.motion.bindInputScrollView(h.scroll, probe: oldProbe)
        h.motion.bindInputScrollView(h.scroll, probe: newProbe)
        h.motion.unbindInputScrollView(probe: oldProbe)
        let before = h.scroll.contentOffset.y
        XCTAssertTrue(h.motion.accessibilityScroll(.pageForward))
        XCTAssertGreaterThan(h.scroll.contentOffset.y, before)
        h.motion.unbindInputScrollView(probe: newProbe)
        let after = h.scroll.contentOffset.y
        XCTAssertFalse(h.motion.accessibilityScroll(.pageForward))
        XCTAssertEqual(h.scroll.contentOffset.y, after)
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testDetachedProbeCannotMoveOuterReaderDuringLoading() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        h.motion.contentWillLoad(documentID: UUID().uuidString)
        let probe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        h.scroll.addSubview(probe)
        h.motion.bindInputScrollView(h.scroll, probe: probe)
        probe.removeFromSuperview()
        let before = h.scroll.contentOffset.y
        XCTAssertFalse(h.motion.accessibilityScroll(.pageForward))
        XCTAssertEqual(h.scroll.contentOffset.y, before)
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testHeldActionCannotReviveWhenDocumentAChangesToBAndBackToA() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let oldAction = try h.command(.pageForward)
        h.motion.contentWillLoad(documentID: UUID().uuidString)
        try await h.rearmOriginalDocument()
        let before = h.scroll.contentOffset.y
        XCTAssertFalse(oldAction())
        XCTAssertEqual(h.scroll.contentOffset.y, before)
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForSamples(1)
    }

    func testHeldActionCannotMoveAReattachedViewAfterDetach() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let oldAction = try h.command(.pageForward)
        h.motion.detach(h.web)
        try await h.rearmOriginalDocument()
        XCTAssertFalse(oldAction())
        XCTAssertEqual(h.scroll.contentOffset.y, 0, accuracy: 1)
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForSamples(1)
    }

    func testDelayedCaptureFromOldDocumentGenerationCannotPublishAfterABA() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        try await h.holdNextScriptCapture()
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForHeldCapture()
        h.motion.contentWillLoad(documentID: UUID().uuidString)
        try await h.rearmOriginalDocument()
        try await h.releaseHeldCapture()
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testDelayedCaptureCannotPublishAfterProgrammaticViewportChange() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        try await h.holdNextScriptCapture()
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForHeldCapture()
        h.scroll.setContentOffset(CGPoint(x: 0, y: h.scroll.contentOffset.y + 300), animated: false)
        try await h.releaseHeldCapture()
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testDelayedCaptureCannotReachNewCallbackAfterDetachAndReattach() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        try await h.holdNextScriptCapture()
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForHeldCapture()
        h.motion.detach(h.web)
        try await h.rearmOriginalDocument()
        try await h.releaseHeldCapture()
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.waitForSamples(1)
    }

    func testFreshGenerationWaitsForPhysicalOldCaptureBeforeStartingAnother() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        try await h.holdNextScriptCapture()
        XCTAssertTrue(try h.command(.pageForward)())
        try await h.waitForHeldCapture()
        h.motion.contentWillLoad(documentID: UUID().uuidString)
        try await h.rearmOriginalDocument()
        _ = try await h.web.evaluateJavaScript("""
        window.__freshCaptureCount = 0;
        window.__freshOriginalCapture = window.aproposReaderResume.capture;
        window.aproposReaderResume.capture = function(id, top, bottom) {
            window.__freshCaptureCount += 1;
            return window.__freshOriginalCapture(id, top, bottom);
        };
        true;
        """)
        XCTAssertTrue(try h.command(.lineForward)())
        try await h.settle()
        let callsWhileOldIsHeld = try await h.web.evaluateJavaScript("window.__freshCaptureCount")
        XCTAssertEqual((callsWhileOldIsHeld as? NSNumber)?.intValue, 0,
                       "Changing generation must not release a physical WebKit capture")
        XCTAssertTrue(h.samples.isEmpty)
        try await h.releaseHeldCapture()
        try await h.waitForSamples(1)
        let callsAfterReturn = try await h.web.evaluateJavaScript("window.__freshCaptureCount")
        XCTAssertEqual((callsAfterReturn as? NSNumber)?.intValue, 1)
        XCTAssertEqual(h.samples.count, 1)
        XCTAssertEqual(h.samples[0].documentID, h.documentID)
    }

    func testExplicitRestoreCancelsPendingUserCaptureWithoutSavingRestoreOffset() async throws {
        let h = AccessibleResumeWebHarness(); defer { h.close() }
        try await h.load()
        let anchor = try await h.captureParagraph(6)
        XCTAssertTrue(try h.command(.pageForward)())
        let restored = await h.resume(anchor)
        XCTAssertTrue(restored)
        try await h.assertParagraphAtReaderTop(6)
        try await h.settle()
        XCTAssertTrue(h.samples.isEmpty)
    }
}

@MainActor
private final class AccessibleResumeWebHarness: NSObject, WKNavigationDelegate {
    struct Sample {
        let anchor: ReaderResumeAnchor
        let completed: Bool
        let documentID: String
    }
    let documentID = UUID().uuidString
    private(set) var samples: [Sample] = []
    let web: ArticleMotionWebView
    private var attachedScroll: UIScrollView?
    var scroll: UIScrollView { attachedScroll! }
    private let layout = AccessibleResumeLayout()
    let motion = ArticleReadingMotionController()
    private let window: UIWindow
    private var loading: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    enum Failure: Error { case timeout, missing }

    override init() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = ArticleMotionWebView(frame: CGRect(x: 0, y: 250, width: 390, height: 4_000), configuration: configuration)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene); window.frame = frame
        } else { window = UIWindow(frame: frame) }
        super.init()
        let controller = UIHostingController(rootView: AccessibleResumeDocument(web: web, layout: layout, motion: motion))
        controller.view.frame = frame
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = self
        web.readingMotion = motion
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        motion.attach(web)
        installSampleCallback()
    }

    func installSampleCallback() {
        motion.onResumeSample = { [weak self] anchor, completed, documentID in
            self?.samples.append(Sample(anchor: anchor, completed: completed, documentID: documentID))
        }
    }

    func command(_ command: ArticleReadingMotionController.UserScrollCommand) throws -> (@MainActor () -> Bool) {
        try XCTUnwrap(motion.userScrollAction(for: command))
    }

    func settle() async throws { try await Task.sleep(nanoseconds: 650_000_000) }

    func waitForSamples(_ count: Int) async throws {
        for _ in 0..<150 {
            if samples.count >= count { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Expected \(count) real paragraph sample(s); received \(samples.count)")
        throw Failure.timeout
    }

    func rearmOriginalDocument() async throws {
        motion.attach(web)
        installSampleCallback()
        motion.contentWillLoad(documentID: documentID)
        motion.contentDidFinish(web)
        try await measure()
    }

    func holdNextScriptCapture() async throws {
        _ = try await web.evaluateJavaScript("""
        window.__resumeOriginalCapture = window.aproposReaderResume.capture;
        window.__resumeCapturePending = false;
        window.aproposReaderResume.capture = function(id, top, bottom) {
            // The production script computes the actual paragraph first. Only
            // delivery of its first physical result is delayed by the test.
            const value = window.__resumeOriginalCapture(id, top, bottom);
            window.aproposReaderResume.capture = window.__resumeOriginalCapture;
            return new Promise(function(resolve) {
                window.__resumeCapturePending = true;
                window.__releaseResumeCapture = function() {
                    window.__resumeCapturePending = false;
                    resolve(value);
                };
            });
        };
        true;
        """)
    }

    func waitForHeldCapture() async throws {
        for _ in 0..<150 {
            let pending = try await web.evaluateJavaScript("window.__resumeCapturePending === true")
            if pending as? Bool == true { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The first real capture did not reach its held JavaScript completion")
        throw Failure.timeout
    }

    func releaseHeldCapture() async throws {
        let released = try await web.evaluateJavaScript("""
        (function() {
            if (!window.__resumeCapturePending || typeof window.__releaseResumeCapture !== 'function') return false;
            const release = window.__releaseResumeCapture;
            window.__releaseResumeCapture = null;
            release();
            return true;
        })()
        """)
        XCTAssertEqual(released as? Bool, true)
    }

    func prepareScrollOwner() async throws {
        for _ in 0..<100 {
            window.rootViewController?.view.layoutIfNeeded()
            var ancestor = web.superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            if let actualScroll = ancestor as? UIScrollView, web.window != nil {
                attachedScroll = actualScroll
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard attachedScroll != nil else { throw Failure.missing }
    }

    func load(measureHeight: Bool = true) async throws {
        try await prepareScrollOwner()
        motion.attach(web)
        installSampleCallback()
        motion.geometryDidChange()
        motion.contentWillLoad(documentID: documentID)
        let prose = (0..<14).map { index in
            "<p id='p\(index)'>Afsnit \(index). En rolig artikel giver plads til at tænke og følge detaljerne i fortællingen. Ordene bliver stående, mens man læser i sit eget tempo. Det er en lokal test uden billeder eller netværk.</p>"
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
        let result = try await web.evaluateJavaScript("document.body.scrollHeight")
        guard let number = result as? NSNumber else { throw Failure.missing }
        let height = CGFloat(number.doubleValue)
        layout.height = height
        for _ in 0..<100 {
            window.rootViewController?.view.layoutIfNeeded()
            if abs(web.bounds.height - height) < 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard abs(web.bounds.height - height) < 1 else { throw Failure.timeout }
        motion.measuredContent(height: height)
        motion.geometryDidChange()
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
        let paragraphTop = try await top(index)
        let bodyTop = web.convert(web.bounds, to: window).minY
        let clip = scroll.convert(scroll.bounds, to: window).intersection(window.safeAreaLayoutGuide.layoutFrame)
        XCTAssertEqual(Double(bodyTop) + paragraphTop, Double(clip.minY), accuracy: 1)
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

@MainActor
private final class AccessibleResumeLayout: ObservableObject {
    @Published var height: CGFloat = 4_000
}

@MainActor
private struct AccessibleResumeDocument: View {
    let web: ArticleMotionWebView
    @ObservedObject var layout: AccessibleResumeLayout
    let motion: ArticleReadingMotionController
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 250)
                AccessibleResumeWebSurface(web: web).frame(height: layout.height)
                Color.clear.frame(height: 100)
            }
        }
        .readerScrollInput(controller: motion)
        .ignoresSafeArea()
    }
}

@MainActor
private struct AccessibleResumeWebSurface: UIViewRepresentable {
    let web: ArticleMotionWebView
    func makeUIView(context: Context) -> ArticleMotionWebView { web }
    func updateUIView(_ uiView: ArticleMotionWebView, context: Context) {}
}
