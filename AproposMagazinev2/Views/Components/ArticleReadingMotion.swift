import SwiftUI
import WebKit

/// UIKit owns frame-by-frame work: scrolling never republishes the article's SwiftUI body.
@MainActor
final class ArticleReadingMotionController: NSObject {
    private weak var webView: WKWebView?
    private weak var line: ArticleReadingLineView?
    private weak var outerScrollView: UIScrollView?
    // The header/loading state exists before WebKit. This separate weak probe
    // permits page movement without creating document or capture authority.
    private weak var inputScrollView: UIScrollView?
    private weak var inputProbe: UIView?
    private var observations: [NSKeyValueObservation] = []
    private var accessibilityObservers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var generation = UUID()
    private var scriptReady = false
    private var measuredHeight: CGFloat?
    private var bridgeBusy = false
    private var lastSubmitted: Viewport?
    private var latestViewport: Viewport?
    private var lastBridgeTime: CFTimeInterval = 0
    private var reduceMotion = false
    var onProgress: ((Double) -> Void)?
    var onResumeSample: ((ReaderResumeAnchor, Bool, String) -> Void)?
    private var documentID = ""
    private var documentReady: (id: String, deliver: @MainActor () -> Void)?
    private var readyGeometry: ResumeReadyGeometry?
    private struct ResumeReadyGeometry: Equatable {
        let webSize: CGSize
        let contentSize: CGSize
        let viewportSize: CGSize
    }
    private var resumeCaptureTask: Task<Void, Never>?
    private var hasUserScroll = false
    private var interaction = UUID()
    private var resumeCaptureInFlight: UUID?
    private var explicitScrollGeometry: ExplicitScrollGeometry?
    private struct LayoutAnchor {
        let anchor: ReaderResumeAnchor
        let width: CGFloat
        let interaction: UUID
    }
    private var layoutAnchor: LayoutAnchor?
    private var layoutReadyGeometry: ResumeReadyGeometry?
    private var layoutResolveInFlight = false

    enum UserScrollCommand { case pageForward, pageBackward, lineForward, lineBackward }

    private struct ExplicitScrollGeometry: Equatable {
        let viewport: Viewport
        let webSize: CGSize
        let contentSize: CGSize
        let viewportSize: CGSize
        let offset: CGPoint
        let height: CGFloat
    }

    private struct Viewport: Equatable, Sendable {
        let top: Double
        let bottom: Double
        let reduceMotion: Bool
    }

    func attach(_ view: WKWebView) {
        if webView !== view {
            if let old = webView { detach(old) }
            webView = view
            for name in [UIAccessibility.reduceMotionStatusDidChangeNotification,
                         UIAccessibility.voiceOverStatusDidChangeNotification] {
                accessibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.schedule() }
                })
            }
        }
        connectScrollView()
        schedule()
    }

    func detach(_ view: WKWebView) {
        guard webView === view else { return }
        generation = UUID()
        view.evaluateJavaScript("window.aproposReaderReveal?.teardown()", completionHandler: nil)
        displayLink?.invalidate()
        displayLink = nil
        observations.removeAll()
        outerScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(userPanChanged(_:)))
        resumeCaptureTask?.cancel()
        explicitScrollGeometry = nil
        layoutAnchor = nil; layoutReadyGeometry = nil; layoutResolveInFlight = false
        hasUserScroll = false
        interaction = UUID()
        accessibilityObservers.forEach(NotificationCenter.default.removeObserver)
        accessibilityObservers.removeAll()
        outerScrollView = nil
        webView = nil
        onProgress = nil
        onResumeSample = nil
        documentID = ""
        documentReady = nil; readyGeometry = nil
        scriptReady = false
        measuredHeight = nil
        line?.setProgress(0)
    }

    fileprivate func attachLine(_ view: ArticleReadingLineView) {
        line = view
        schedule()
    }

    fileprivate func detachLine(_ view: ArticleReadingLineView) {
        if line === view { line = nil }
    }

    func updateAccessibility(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        schedule()
    }

    func contentWillLoad(documentID: String = "") {
        generation = UUID()
        self.documentID = documentID
        layoutAnchor = nil; layoutReadyGeometry = nil; layoutResolveInFlight = false
        documentReady = nil; readyGeometry = nil
        interaction = UUID()
        hasUserScroll = false
        explicitScrollGeometry = nil
        resumeCaptureTask?.cancel()
        scriptReady = false
        measuredHeight = nil
        bridgeBusy = false
        lastSubmitted = nil
        latestViewport = nil
        line?.setProgress(0)
    }

    /// The offer becomes actionable only after both WebKit and the actual
    /// outer-scroll layout can resolve an anchor. A measured height alone is
    /// insufficient: SwiftUI may still be displaying the 240pt placeholder.
    func whenDocumentReady(_ id: String, perform: @escaping @MainActor () -> Void) {
        guard id == documentID, UUID(uuidString: id) != nil else { return }
        documentReady = (id, perform); readyGeometry = nil
        schedule()
    }

    private func deliverDocumentReadiness() {
        guard let pending = documentReady, pending.id == documentID,
              scriptReady, let height = measuredHeight, height > 0,
              let web = webView, web.window != nil, !web.isHidden,
              let scroll = outerScrollView, web.bounds.width > 0,
              web.bounds.height + 1 >= height,
              scroll.bounds.height > 0,
              scroll.contentSize.height + 1 >= web.convert(web.bounds, to: scroll).maxY else {
            readyGeometry = nil; return
        }
        let geometry = ResumeReadyGeometry(webSize: web.bounds.size,
            contentSize: scroll.contentSize, viewportSize: scroll.bounds.size)
        guard readyGeometry == geometry else {
            readyGeometry = geometry; schedule(); return
        }
        documentReady = nil; readyGeometry = nil
        pending.deliver()
    }

    func contentDidFinish(_ view: WKWebView) {
        guard webView === view else { return }
        let ticket = generation
        view.evaluateJavaScript(ArticleTextRevealScript.source + "\n" + ReaderResumeScript.source) { [weak self, weak view] _, error in
            guard let self, self.generation == ticket, self.webView === view, error == nil else { return }
            self.scriptReady = true
            self.schedule()
        }
    }

    func measuredContent(height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        measuredHeight = height
        schedule()
    }

    func geometryDidChange() {
        connectScrollView()
        schedule()
    }

    private func connectScrollView() {
        var ancestor = webView?.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView, scroll !== outerScrollView else { return }
        observations.removeAll()
        outerScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(userPanChanged(_:)))
        outerScrollView = scroll
        scroll.panGestureRecognizer.addTarget(self, action: #selector(userPanChanged(_:)))
        observations = [
            scroll.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.schedule()
                    if change.oldValue != change.newValue && (scroll.isDragging || scroll.isDecelerating) {
                        self?.hasUserScroll = true
                        self?.scheduleResumeCapture()
                    }
                }
            },
            scroll.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
            scroll.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
        ]
    }

    @objc private func userPanChanged(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began {
            interaction = UUID(); explicitScrollGeometry = nil
            layoutAnchor = nil; layoutReadyGeometry = nil
        }
        if recognizer.state == .changed || recognizer.state == .ended { scheduleResumeCapture() }
    }

    /// Explicit input from the outer reader's accessibility/keyboard actions.
    /// The captured action belongs to this document instance, even if a caller
    /// holds it through A → B → A. Observed offsets alone confer no user intent.
    func userScrollAction(for command: UserScrollCommand) -> (@MainActor () -> Bool)? {
        guard scriptReady, UUID(uuidString: documentID) != nil,
              let web = webView, web.window != nil, !web.isHidden,
              let scroll = outerScrollView, let height = measuredHeight, height > 0,
              web.bounds.height + 1 >= height, currentViewport() != nil else { return nil }
        let ticket = generation, originalDocument = documentID
        return { [weak self, weak web, weak scroll] in
            guard let self, let web, let scroll,
                  self.generation == ticket, self.documentID == originalDocument,
                  self.webView === web, self.outerScrollView === scroll,
                  self.scriptReady, web.window != nil, !web.isHidden,
                  !scroll.isDragging, !scroll.isDecelerating, !scroll.isTracking,
                  let height = self.measuredHeight, height > 0,
                  web.bounds.height + 1 >= height,
                  let viewport = self.currentViewport() else { return false }
            let page = max(1, CGFloat(viewport.bottom - viewport.top) * 0.85)
            let line = min(page, UIFont.preferredFont(forTextStyle: .body).lineHeight * 2)
            let delta: CGFloat
            switch command {
            case .pageForward: delta = page
            case .pageBackward: delta = -page
            case .lineForward: delta = line
            case .lineBackward: delta = -line
            }
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let offset = min(max(scroll.contentOffset.y + delta, minimum), maximum)
            guard offset.isFinite, abs(offset - scroll.contentOffset.y) > 0.5 else { return false }
            let originalWebSize = web.bounds.size, originalContentSize = scroll.contentSize
            let originalViewportSize = scroll.bounds.size, originalInsets = scroll.adjustedContentInset
            self.interaction = UUID()
            self.layoutAnchor = nil; self.layoutReadyGeometry = nil
            let originalInteraction = self.interaction
            self.hasUserScroll = false
            self.explicitScrollGeometry = nil
            self.resumeCaptureTask?.cancel()
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            // setContentOffset notifies observers synchronously. A reentrant
            // reload/detach must not label its replacement as this interaction.
            guard self.generation == ticket, self.documentID == originalDocument,
                  self.interaction == originalInteraction, self.webView === web,
                  self.outerScrollView === scroll, web.window != nil, !web.isHidden,
                  self.measuredHeight == height, web.bounds.size == originalWebSize,
                  scroll.contentSize == originalContentSize, scroll.bounds.size == originalViewportSize,
                  scroll.adjustedContentInset == originalInsets,
                  abs(scroll.contentOffset.y - offset) <= 0.5,
                  let geometry = self.explicitGeometry() else { return true }
            self.explicitScrollGeometry = geometry
            self.hasUserScroll = true
            self.scheduleResumeCapture()
            self.schedule()
            return true
        }
    }

    func bindInputScrollView(_ scroll: UIScrollView, probe: UIView) {
        inputProbe = probe
        inputScrollView = scroll
    }

    func unbindInputScrollView(probe: UIView) {
        guard inputProbe === probe else { return }
        inputProbe = nil; inputScrollView = nil
    }

    /// SwiftUI's accessibility action has no ignored/handled return. Preserve
    /// outer page scrolling while the document is unavailable, without saving
    /// those movements as a position in an unloaded or replacement document.
    @discardableResult
    func accessibilityScroll(_ command: UserScrollCommand) -> Bool {
        let ticket = generation
        if let action = userScrollAction(for: command) {
            let handled = action()
            if handled, generation == ticket {
                UIAccessibility.post(notification: .pageScrolled, argument: nil)
            }
            return handled
        }
        guard let probe = inputProbe, let scroll = inputScrollView,
              let window = probe.window, scroll.window === window,
              !scroll.isDragging, !scroll.isDecelerating, !scroll.isTracking else { return false }
        let clip = scroll.convert(scroll.bounds, to: window).intersection(window.safeAreaLayoutGuide.layoutFrame)
        guard !clip.isNull, clip.height > 0 else { return false }
        let delta: CGFloat
        switch command {
        case .pageForward: delta = clip.height * 0.85
        case .pageBackward: delta = -clip.height * 0.85
        case .lineForward, .lineBackward: return false
        }
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let offset = min(max(scroll.contentOffset.y + delta, minimum), maximum)
        guard offset.isFinite, abs(offset - scroll.contentOffset.y) > 0.5 else { return false }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
        if generation == ticket, inputProbe === probe, inputScrollView === scroll,
           probe.window === window, scroll.window === window {
            UIAccessibility.post(notification: .pageScrolled, argument: nil)
        }
        return true
    }

    private func explicitGeometry() -> ExplicitScrollGeometry? {
        guard let viewport = currentViewport(), let web = webView,
              let scroll = outerScrollView, let height = measuredHeight else { return nil }
        return ExplicitScrollGeometry(viewport: viewport, webSize: web.bounds.size,
            contentSize: scroll.contentSize, viewportSize: scroll.bounds.size,
            offset: scroll.contentOffset, height: height)
    }

    private func scheduleResumeCapture() {
        guard hasUserScroll, onResumeSample != nil else { return }
        resumeCaptureTask?.cancel()
        let ticket = generation, originalInteraction = interaction
        resumeCaptureTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            guard let self, self.generation == ticket, self.interaction == originalInteraction,
                  let scroll = self.outerScrollView else { return }
            if scroll.isDragging || scroll.isDecelerating || scroll.isTracking { self.scheduleResumeCapture(); return }
            self.captureResumePosition()
        }
    }

    private func captureResumePosition() {
        if let expected = explicitScrollGeometry, explicitGeometry() != expected {
            // A layout, restore or unrelated programmatic move during debounce
            // cannot borrow the preceding explicit accessibility/key action.
            hasUserScroll = false; explicitScrollGeometry = nil
            return
        }
        guard hasUserScroll, resumeCaptureInFlight == nil, scriptReady, let web = webView, web.window != nil,
              let viewport = currentViewport(), viewport.top >= 0, let height = measuredHeight,
              let progress = ArticleReadingGeometry(top: viewport.top, bottom: viewport.bottom, bodyHeight: Double(height)).fraction,
              UUID(uuidString: documentID) != nil else { return }
        hasUserScroll = false
        explicitScrollGeometry = nil
        let ticket = generation, originalDocument = documentID, originalInteraction = interaction
        let captureWidth = web.bounds.width
        let request = UUID(); resumeCaptureInFlight = request
        web.callAsyncJavaScript("return window.aproposReaderResume?.capture(id, top, bottom) ?? null;",
            arguments: ["id": originalDocument, "top": viewport.top, "bottom": viewport.bottom],
            in: nil, in: .page, completionHandler: { [weak self] result in
                guard let self, self.resumeCaptureInFlight == request else { return }
                self.resumeCaptureInFlight = nil
                defer { if self.hasUserScroll { self.scheduleResumeCapture() } }
                guard self.generation == ticket, self.documentID == originalDocument,
                      self.interaction == originalInteraction, self.currentViewport() == viewport,
                      self.webView?.bounds.width == captureWidth,
                      self.measuredHeight == height,
                      case .success(let value) = result, let payload = value as? [String: Any],
                      payload["documentID"] as? String == originalDocument,
                      let index = payload["index"] as? Int, let fingerprint = payload["fingerprint"] as? String else { return }
                let anchor = ReaderResumeAnchor(index: index, fingerprint: fingerprint)
                guard anchor.isValid else { return }
                self.layoutAnchor = LayoutAnchor(anchor: anchor, width: captureWidth, interaction: originalInteraction)
                self.onResumeSample?(anchor, progress >= 0.995, originalDocument)
            })
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Read-only native/DOM diagnostic. It never grants interaction authority
    /// or calls the resume recorder, including when layout changes mid-query.
    func inspectVisibleParagraph(completion: @escaping @MainActor (String?) -> Void) {
        guard scriptReady, let web = webView, let scroll = outerScrollView,
              let viewport = currentViewport(), viewport.top >= 0,
              UUID(uuidString: documentID) != nil else { completion(nil); return }
        let ticket = generation, id = documentID
        let webSize = web.bounds.size, scrollSize = scroll.bounds.size
        let offset = scroll.contentOffset, contentSize = scroll.contentSize
        web.callAsyncJavaScript("return window.aproposReaderResume?.capture(id, top, bottom) ?? null;",
            arguments: ["id": id, "top": viewport.top, "bottom": viewport.bottom],
            in: nil, in: .page) { [weak self, weak web, weak scroll] result in
                guard let self, let web, let scroll, self.generation == ticket,
                      self.documentID == id, self.webView === web, self.outerScrollView === scroll,
                      self.currentViewport() == viewport, web.bounds.size == webSize,
                      scroll.bounds.size == scrollSize, scroll.contentOffset == offset,
                      scroll.contentSize == contentSize,
                      case .success(let value) = result, var payload = value as? [String: Any],
                      payload["documentID"] as? String == id else { completion(nil); return }
                payload["viewportTop"] = viewport.top
                payload["viewportBottom"] = viewport.bottom
                payload["webWidth"] = webSize.width
                payload["scrollWidth"] = scrollSize.width
                payload["offsetY"] = offset.y
                payload["contentHeight"] = contentSize.height
                guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                    completion(nil); return
                }
                completion(String(data: data, encoding: .utf8))
            }
    }
    #endif

    /// Explicit button action for the durable offer. Document loading never
    /// restores it automatically; live width changes use only the separate
    /// transient position of this already-open document.
    func resume(anchor: ReaderResumeAnchor, documentID: String,
                stillCurrent: @escaping @MainActor () -> Bool,
                completion: @escaping @MainActor (Bool) -> Void) {
        guard anchor.isValid, self.documentID == documentID, scriptReady, stillCurrent(),
              let web = webView, web.window != nil, let scroll = outerScrollView,
              let height = measuredHeight, height > 0,
              !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { completion(false); return }
        layoutAnchor = nil; layoutReadyGeometry = nil
        interaction = UUID(); hasUserScroll = false; resumeCaptureTask?.cancel()
        explicitScrollGeometry = nil
        resolvePosition(anchor: anchor, documentID: documentID, requiresCurrentDOMHeight: false,
            stillCurrent: stillCurrent, completion: completion)
    }

    /// A live width change preserves only this document's last settled user
    /// position. It never reads the durable store or produces a save sample.
    private func preservePositionAfterWidthChange() {
        guard let saved = layoutAnchor, saved.interaction == interaction,
              let web = webView, let scroll = outerScrollView,
              abs(web.bounds.width - saved.width) > 0.5,
              !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating,
              // ArticleHTMLBody keeps a 240pt minimum renderer. A newly
              // accepted DOM height must also have reached the native frame.
              let height = measuredHeight, abs(web.bounds.height - max(height, 240)) <= 1,
              scroll.contentSize.height + 1 >= web.convert(web.bounds, to: scroll).maxY else { return }
        let geometry = ResumeReadyGeometry(webSize: web.bounds.size,
            contentSize: scroll.contentSize, viewportSize: scroll.bounds.size)
        guard layoutReadyGeometry == geometry else {
            layoutReadyGeometry = geometry; schedule(); return
        }
        guard !layoutResolveInFlight else { return }
        layoutResolveInFlight = true
        let ticket = generation, id = documentID, originalInteraction = interaction
        let originalOffset = scroll.contentOffset
        resolvePosition(anchor: saved.anchor, documentID: id, requiresCurrentDOMHeight: true,
            stillCurrent: { [weak self] in
                guard let self else { return false }
                return self.generation == ticket && self.documentID == id && self.interaction == originalInteraction
            }, completion: { [weak self] _ in
                guard let self, self.generation == ticket else { return }
                self.layoutResolveInFlight = false
                // A final native layout event can be consumed while JS is
                // outstanding. Retry only that changed geometry, never an
                // unchanged DOM/height mismatch.
                if self.layoutAnchor?.interaction == originalInteraction,
                   (self.layoutReadyGeometry != geometry || self.measuredHeight != height ||
                    self.outerScrollView?.contentOffset != originalOffset) {
                    self.schedule()
                }
            })
    }

    private func resolvePosition(anchor: ReaderResumeAnchor, documentID: String,
                requiresCurrentDOMHeight: Bool,
                stillCurrent: @escaping @MainActor () -> Bool,
                completion: @escaping @MainActor (Bool) -> Void) {
        guard anchor.isValid, self.documentID == documentID, scriptReady,
              let web = webView, web.window != nil, let scroll = outerScrollView,
              let originalHeight = measuredHeight, originalHeight > 0,
              !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { completion(false); return }
        let ticket = generation, originalInteraction = interaction
        let originalWebSize = web.bounds.size, originalViewportSize = scroll.bounds.size
        let originalOffset = scroll.contentOffset, originalContentSize = scroll.contentSize
        web.callAsyncJavaScript("""
            const value = window.aproposReaderResume?.resolve(id, index, fingerprint);
            if (!value) return null;
            const last = document.body?.lastElementChild;
            value.layoutHeight = last ? Math.ceil(last.offsetTop + last.offsetHeight) : null;
            value.layoutWidth = document.documentElement.clientWidth;
            return value;
            """,
            arguments: ["id": documentID, "index": anchor.index, "fingerprint": anchor.fingerprint],
            in: nil, in: .page, completionHandler: { [weak self, weak scroll] result in
                guard let self, let scroll, self.generation == ticket, self.documentID == documentID,
                      self.webView === web,
                      self.interaction == originalInteraction, self.outerScrollView === scroll, stillCurrent(),
                      self.measuredHeight == originalHeight, self.webView?.bounds.size == originalWebSize,
                      scroll.bounds.size == originalViewportSize,
                      !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating, let viewport = self.currentViewport(),
                      case .success(let value) = result, let payload = value as? [String: Any],
                      payload["documentID"] as? String == documentID, let top = payload["top"] as? Double else {
                    completion(false); return
                }
                if requiresCurrentDOMHeight {
                    guard let domHeight = payload["layoutHeight"] as? Double,
                          let domWidth = payload["layoutWidth"] as? Double,
                          scroll.contentOffset == originalOffset, scroll.contentSize == originalContentSize,
                          abs(domWidth - Double(originalWebSize.width)) <= 1,
                          abs(domHeight - Double(originalHeight)) < 10 else { completion(false); return }
                }
                guard
                      let offset = ReaderResumeGeometry.offset(paragraphTop: top, viewportTop: viewport.top,
                        currentOffset: Double(scroll.contentOffset.y), contentHeight: Double(scroll.contentSize.height),
                        viewportHeight: Double(scroll.bounds.height), topInset: Double(scroll.adjustedContentInset.top),
                        bottomInset: Double(scroll.adjustedContentInset.bottom)), stillCurrent(),
                      self.generation == ticket, self.interaction == originalInteraction else { completion(false); return }
                self.hasUserScroll = false
                self.resumeCaptureTask?.cancel()
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                guard self.generation == ticket, self.documentID == documentID,
                      self.interaction == originalInteraction, self.webView === web,
                      self.outerScrollView === scroll, stillCurrent() else { completion(false); return }
                self.layoutAnchor = LayoutAnchor(anchor: anchor, width: originalWebSize.width, interaction: originalInteraction)
                self.layoutReadyGeometry = nil
                self.schedule()
                completion(true)
            })
    }

    private func schedule() {
        guard webView?.window != nil, displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frame() {
        displayLink?.invalidate()
        displayLink = nil
        guard let viewport = currentViewport() else { return }
        latestViewport = viewport
        preservePositionAfterWidthChange()
        deliverDocumentReadiness()
        if let height = measuredHeight,
           let fraction = ArticleReadingGeometry(top: viewport.top, bottom: viewport.bottom, bodyHeight: Double(height)).fraction {
            line?.setProgress(fraction)
            onProgress?(fraction)
        }
        submitViewport()
    }

    /// Sample at the actual bridge boundary as well as on display frames. A
    /// just-adjusted inset/offset must never be mixed with an earlier frame.
    private func currentViewport() -> Viewport? {
        guard let web = webView, let window = web.window, let scroll = outerScrollView else { return nil }
        let clip = scroll.convert(scroll.bounds, to: window).intersection(window.safeAreaLayoutGuide.layoutFrame)
        guard !clip.isNull, clip.height > 0 else { return nil }
        let barBottom = line?.window === window ? line!.convert(line!.bounds, to: window).maxY : clip.minY
        let top = max(clip.minY, barBottom)
        let bodyTop = web.convert(web.bounds, to: window).minY
        guard clip.maxY > top else { return nil }
        return Viewport(top: Double(((top - bodyTop) * 2).rounded() / 2),
                                bottom: Double(((clip.maxY - bodyTop) * 2).rounded() / 2),
                                reduceMotion: reduceMotion || UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning)
    }

    private func submitViewport() {
        guard scriptReady, !bridgeBusy, let web = webView, let viewport = latestViewport, viewport != lastSubmitted else { return }
        // The line tracks each frame; the WebKit bridge is capped at 30 updates/second.
        guard CACurrentMediaTime() - lastBridgeTime >= 1.0 / 30 else { schedule(); return }
        let payload: [String: Any] = ["top": viewport.top, "bottom": viewport.bottom, "reduceMotion": viewport.reduceMotion]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let ticket = generation
        bridgeBusy = true
        lastSubmitted = viewport
        lastBridgeTime = CACurrentMediaTime()
        web.evaluateJavaScript("window.aproposReaderReveal?.update(\(json))") { [weak self] _, _ in
            guard let self, self.generation == ticket else { return }
            self.bridgeBusy = false
            if self.latestViewport != self.lastSubmitted { self.schedule() }
        }
    }
}

extension View {
    /// Keep the existing outer ScrollView as the sole scroll owner. Keyboard
    /// input is handled only while focused; modified keys remain available to
    /// text selection and other controls. No automatic focus or delegate swap.
    func readerScrollInput(controller: ArticleReadingMotionController) -> some View {
        self
            .focusable()
            .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown]) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                let command: ArticleReadingMotionController.UserScrollCommand
                switch press.key {
                case .upArrow: command = .lineBackward
                case .downArrow: command = .lineForward
                case .pageUp: command = .pageBackward
                case .pageDown: command = .pageForward
                default: return .ignored
                }
                return controller.userScrollAction(for: command)?() == true ? .handled : .ignored
            }
            .accessibilityScrollAction { edge in
                let command: ArticleReadingMotionController.UserScrollCommand
                switch edge {
                case .top: command = .pageBackward
                case .bottom: command = .pageForward
                default: return
                }
                controller.accessibilityScroll(command)
            }
    }
}

/// Placed inside the existing ScrollView's content. It neither replaces the
/// scroll delegate nor takes over the WebKit motion observer's ownership.
struct ArticleReaderScrollProbe: UIViewRepresentable {
    let controller: ArticleReadingMotionController
    func makeUIView(context: Context) -> ReaderScrollInputProbeView {
        let view = ReaderScrollInputProbeView()
        view.controller = controller
        return view
    }
    func updateUIView(_ view: ReaderScrollInputProbeView, context: Context) {
        if view.controller !== controller {
            view.controller?.unbindInputScrollView(probe: view)
            view.controller = controller
        }
        view.connect()
    }
    static func dismantleUIView(_ view: ReaderScrollInputProbeView, coordinator: Void) {
        view.controller?.unbindInputScrollView(probe: view)
        view.controller = nil
    }
}

@MainActor
final class ReaderScrollInputProbeView: UIView {
    weak var controller: ArticleReadingMotionController?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); connect() }
    override func didMoveToSuperview() { super.didMoveToSuperview(); connect() }
    override func layoutSubviews() { super.layoutSubviews(); connect() }
    func connect() {
        guard window != nil else { controller?.unbindInputScrollView(probe: self); return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else {
            controller?.unbindInputScrollView(probe: self); return
        }
        controller?.bindInputScrollView(scroll, probe: self)
    }
}

@MainActor
final class ArticleMotionWebView: WKWebView {
    weak var readingMotion: ArticleReadingMotionController?
    var localGeometryDidChange: (@MainActor () -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); readingMotion?.geometryDidChange(); localGeometryDidChange?() }
    override func layoutSubviews() { super.layoutSubviews(); readingMotion?.geometryDidChange(); localGeometryDidChange?() }
}

struct ArticleReadingProgressLine: UIViewRepresentable {
    let controller: ArticleReadingMotionController
    func makeUIView(context: Context) -> ArticleReadingLineView {
        let view = ArticleReadingLineView()
        view.controller = controller
        controller.attachLine(view)
        return view
    }
    func updateUIView(_ uiView: ArticleReadingLineView, context: Context) { controller.attachLine(uiView) }
    static func dismantleUIView(_ uiView: ArticleReadingLineView, coordinator: Void) { uiView.controller?.detachLine(uiView) }
}

@MainActor
final class ArticleReadingLineView: UIView {
    weak var controller: ArticleReadingMotionController?
    private let fill = CALayer()
    private var fraction: Double = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Læsefremdrift"
        accessibilityIdentifier = "reader.progress"
        layer.addSublayer(fill)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ArticleReadingLineView, _: UITraitCollection) in view.updateColors() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateColors() {
        backgroundColor = UIColor.label.withAlphaComponent(0.09)
        fill.backgroundColor = UIColor.label.withAlphaComponent(0.88).resolvedColor(with: traitCollection).cgColor
    }
    func setProgress(_ value: Double) {
        let next = min(max(value, 0), 1)
        guard next != fraction || accessibilityValue == nil else { return }
        fraction = next
        accessibilityValue = "\(Int((fraction * 100).rounded())) procent"
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
        controller?.geometryDidChange()
    }
}
