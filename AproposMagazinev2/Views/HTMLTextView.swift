import SwiftUI
import WebKit

struct HTMLTextView: UIViewRepresentable {
    var html: String
    var articleId: String? = nil
    var articleRevision: String? = nil
    @Binding var dynamicHeight: CGFloat
    var readingMotion: ArticleReadingMotionController? = nil
    var suppressMotion: Bool = false
    var onReadingProgress: ((Double) -> Void)? = nil
    var historyBinding: ReaderHistoryBinding? = nil
    var historySession: ReaderHistoryBinding.Session? = nil
    var resumeController: ReaderResumeController? = nil
    var resumeOwner: String? = nil
    var onHorizontalOverflow: ((Bool) -> Void)? = nil
    // Local fixture can use the same renderer without starting OfflineManager/services.
    var prepareHTML: ((String, String?) -> PreparedHTML)? = nil
    var offlineImageCache: OfflineArticleImageCache? = nil
    var loadState: ArticleHTMLLoadState? = nil
    // Value snapshot makes an explicit retry observable to SwiftUI's
    // representable diff while preserving the same WebKit/worker instance.
    var loadRequestID: UUID? = nil
    #if DEBUG && targetEnvironment(simulator)
    var loadTesting: ArticleHTMLLoadTesting? = nil
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 18

    struct PreparedHTML {
        var html: String
        var baseURL: URL?
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = ArticleMotionWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "heightHandler")
        
        context.coordinator.bindMotion(to: webView)
        context.coordinator.observeLocalGeometry(webView)
        #if DEBUG && targetEnvironment(simulator)
        loadTesting?.onWebViewReady?(webView, context.coordinator)
        #endif
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.bindMotion(to: uiView)
        readingMotion?.updateAccessibility(reduceMotion: reduceMotion || suppressMotion)
        let coordinator = context.coordinator
        guard !html.isEmpty else {
            coordinator.invalidateLoad()
            coordinator.preparation.invalidate()
            coordinator.lastPreparation = nil
            coordinator.invalidateDocument()
            uiView.stopLoading(); uiView.isHidden = true
            dynamicHeight = 100
            return
        }
        let imageWidth = ArticleHTMLProcessor.capturedImageWidth()
        let cache: OfflineArticleImageCache? = prepareHTML == nil ? (offlineImageCache ?? .shared) : nil
        let access = cache?.capturePreparationAccess(articleID: articleId, revision: articleRevision) ?? .remote
        let identity = PreparationIdentity(html: html, articleID: articleId, revision: articleRevision,
            fontSize: bodyFontSize, imageWidth: imageWidth, sessionID: historySession?.id,
            accessGeneration: access.generation, resumeOwner: resumeOwner,
            historyIdentity: historyBinding.map(ObjectIdentifier.init),
            loadStateIdentity: loadState.map(ObjectIdentifier.init), retryID: loadRequestID ?? loadState?.retryID)
        if coordinator.lastPreparation == identity { return }
        coordinator.lastPreparation = identity
        coordinator.invalidateDocument()
        uiView.stopLoading(); uiView.isHidden = true
        let documentID = UUID().uuidString
        let input = ArticleHTMLPreparation.Input(html: html, targetImageWidth: imageWidth,
            bodyFontSize: Double(bodyFontSize), documentID: documentID, contentKey: access.contentKey)
        let originalHistory = historyBinding, originalSession = historySession
        let originalFixturePreparation = prepareHTML, originalArticleID = articleId
        let ownerIsCurrent: @MainActor () -> Bool = {
            if let originalSession {
                guard originalHistory?.isCurrent(originalSession) == true else { return false }
            }
            guard access.isCurrent() else { return false }
            if let originalSession { return originalHistory?.isCurrent(originalSession) == true }
            return true
        }
        let attempt = coordinator.beginLoad(webView: uiView, state: loadState, ownership: ownerIsCurrent)
        guard coordinator.ownsLoad(attempt) else { return }
        var operation: @Sendable (ArticleHTMLPreparation.Input, @escaping @Sendable () -> Bool) async -> ArticleHTMLPreparation.Output? = { input, isCancelled in
            ArticleHTMLPreparation.prepare(input, cache: cache, isCancelled: isCancelled)
        }
        #if DEBUG && targetEnvironment(simulator)
        if let injected = loadTesting?.prepare { operation = injected }
        #endif
        coordinator.preparation.submit(input, work: operation, isCurrent: { [weak coordinator] in
            coordinator?.ownsLoad(attempt) ?? false
        }, discard: { [weak coordinator] in
            coordinator?.failLoad(attempt)
        }, commit: { [weak coordinator, weak uiView] output, stillCurrent in
            guard let coordinator, let uiView, coordinator.ownsLoad(attempt) else { return }
            let document: String, baseURL: URL?
            if let originalFixturePreparation {
                // Existing hermetic renderer fixtures may supply a tiny local
                // transform. Actual offline preparation always uses the worker.
                let local = originalFixturePreparation(output.html, originalArticleID)
                document = ArticleHTMLPreparation.document(html: local.html,
                    bodyFontSize: input.bodyFontSize, documentID: documentID)
                baseURL = local.baseURL
            } else { document = output.document; baseURL = output.baseURL }
            guard stillCurrent() else {
                return
            }
            coordinator.resetHeightTracking()
            coordinator.acceptDocument(documentID)
            coordinator.loadDocumentID = documentID
            coordinator.motion?.contentWillLoad(documentID: documentID)
            coordinator.motion?.whenDocumentReady(documentID) { [weak coordinator] in
                coordinator?.documentBecameReady(documentID)
            }
            guard stillCurrent(), coordinator.documentID == documentID else {
                coordinator.invalidateDocument()
                return
            }
            uiView.isHidden = false
            coordinator.expectedNavigation = uiView.loadHTMLString(document, baseURL: baseURL)
        })
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Critical memory fix: WKWebView is very heavy (own web content process), and
    /// `userContentController.add(_:name:)` keeps a strong reference to the coordinator.
    /// Without this teardown each opened article leaks a WKWebView, so memory climbs
    /// until the OS jetsams the app. Tear everything down when the view is dismantled.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidateLoad()
        coordinator.preparation.invalidate()
        coordinator.invalidateDocument()
        coordinator.motion?.detach(uiView)
        uiView.evaluateJavaScript("window.aproposHeightCleanup?.()", completionHandler: nil)
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "heightHandler")
        uiView.configuration.userContentController.removeAllUserScripts()
        coordinator.resetHeightTracking()
    }

    struct PreparationIdentity: Equatable {
        let html: String
        let articleID: String?
        let revision: String?
        let fontSize: CGFloat
        let imageWidth: Int
        let sessionID: UUID?
        let accessGeneration: UUID?
        let resumeOwner: String?
        let historyIdentity: ObjectIdentifier?
        var loadStateIdentity: ObjectIdentifier? = nil
        var retryID: UUID? = nil
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.articleID == rhs.articleID && lhs.revision == rhs.revision && lhs.fontSize == rhs.fontSize
                && lhs.imageWidth == rhs.imageWidth && lhs.sessionID == rhs.sessionID
                && lhs.accessGeneration == rhs.accessGeneration && lhs.resumeOwner == rhs.resumeOwner
                && lhs.historyIdentity == rhs.historyIdentity && lhs.loadStateIdentity == rhs.loadStateIdentity
                && lhs.retryID == rhs.retryID && lhs.html.utf8.elementsEqual(rhs.html.utf8)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLTextView
        let preparation = ArticleHTMLPreparationWorker<ArticleHTMLPreparation.Input, ArticleHTMLPreparation.Output>()
        var lastPreparation: PreparationIdentity?
        var documentID = ""
        var expectedNavigation: WKNavigation?
        weak var motion: ArticleReadingMotionController?
        private var loadAttemptID: UUID?
        private weak var loadController: ArticleHTMLLoadState?
        private var loadTicket: ArticleHTMLLoadState.Attempt?
        private var loadOwnership: (@MainActor () -> Bool)?
        private var loadFailed = false
        private var loadReady = false
        private var loadHeightBinding: Binding<CGFloat>?
        private var cancelLoadDeadline: (@MainActor () -> Void)?
        private weak var loadWebView: WKWebView?
        var loadDocumentID: String?
        private var localMeasuredHeight: CGFloat?
        private var geometryObservation: NSKeyValueObservation?

        func beginLoad(webView: WKWebView, state: ArticleHTMLLoadState?, ownership: @escaping @MainActor () -> Bool) -> UUID {
            let oldController = loadController, oldTicket = loadTicket, cancel = cancelLoadDeadline
            let id = UUID()
            loadAttemptID = id; loadController = state; loadTicket = nil
            loadOwnership = ownership; loadFailed = false; loadReady = false; loadWebView = webView
            loadHeightBinding = parent.$dynamicHeight
            loadTicket = state?.begin { [weak self] phase in
                guard let self else { return false }
                // A generic failure can terminate a revoked attempt; successful
                // content always needs its original account/access authority.
                if phase == .ready, !self.ownsLoad(id) {
                    self.failLoad(id)
                    return false
                }
                return self.identifiesLoad(id)
            }
            observeLocalGeometry(webView)
            loadDocumentID = nil; localMeasuredHeight = nil; cancelLoadDeadline = nil
            if let oldTicket { oldController?.invalidate(oldTicket) }
            cancel?()
            guard ownsLoad(id) else { failLoad(id); return id }
            var schedule: ArticleHTMLLoadState.Schedule = ArticleHTMLLoadState.scheduleDeadline
            var timeout: UInt64 = 20_000_000_000
            #if DEBUG && targetEnvironment(simulator)
            schedule = parent.loadTesting?.schedule ?? schedule
            timeout = parent.loadTesting?.timeoutNanoseconds ?? timeout
            #endif
            let cancellation = schedule(timeout) { [weak self] in self?.failLoad(id) }
            if ownsLoad(id) { cancelLoadDeadline = cancellation } else { failLoad(id); cancellation() }
            return id
        }

        private func identifiesLoad(_ id: UUID) -> Bool {
            guard loadAttemptID == id else { return false }
            if let ticket = loadTicket { return loadController?.owns(ticket) == true }
            return true
        }

        func ownsLoad(_ id: UUID) -> Bool {
            guard identifiesLoad(id), !loadFailed, let ownership = loadOwnership else { return false }
            guard ownership() else { return false }
            return identifiesLoad(id) && !loadFailed
        }

        private func ownsDocument(_ id: String) -> Bool {
            guard !isDismantled, documentID == id else { return false }
            if let attempt = loadAttemptID, !ownsLoad(attempt) { return false }
            return !isDismantled && documentID == id
        }

        func failLoad(_ id: UUID) {
            guard identifiesLoad(id), !loadFailed else { return }
            loadFailed = true
            let state = loadController, ticket = loadTicket, cancel = cancelLoadDeadline
            cancelLoadDeadline = nil
            preparation.invalidate(); invalidateDocument()
            loadWebView?.stopLoading(); loadWebView?.isHidden = true
            localMeasuredHeight = nil; loadDocumentID = nil
            let originalHeight = loadHeightBinding
            Task { @MainActor [weak self] in
                guard let self, self.identifiesLoad(id), self.loadFailed else { return }
                originalHeight?.wrappedValue = 240
            }
            if let ticket { state?.fail(ticket) }
            cancel?()
        }

        func invalidateLoad() {
            let state = loadController, ticket = loadTicket, cancel = cancelLoadDeadline
            loadAttemptID = nil; loadTicket = nil; loadController = nil; loadOwnership = nil; loadHeightBinding = nil
            cancelLoadDeadline = nil; loadDocumentID = nil; localMeasuredHeight = nil
            geometryObservation = nil
            (loadWebView as? ArticleMotionWebView)?.localGeometryDidChange = nil
            if let ticket { state?.invalidate(ticket) }
            cancel?()
        }

        func observeLocalGeometry(_ webView: WKWebView) {
            (webView as? ArticleMotionWebView)?.localGeometryDidChange = { [weak self, weak webView] in
                guard let webView else { return }; self?.checkLocalReadiness(webView)
            }
            geometryObservation = webView.observe(\.bounds, options: [.new]) { [weak self, weak webView] _, _ in
                MainActor.assumeIsolated {
                    guard let webView else { return }; self?.checkLocalReadiness(webView)
                }
            }
        }

        private func checkLocalReadiness(_ webView: WKWebView) {
            guard parent.readingMotion == nil, let id = loadAttemptID, ownsLoad(id),
                  let document = loadDocumentID, document == documentID, !isDismantled,
                  let height = localMeasuredHeight, height > 0, webView.window != nil,
                  !webView.isHidden, webView.bounds.width > 0, webView.bounds.height + 1 >= height else { return }
            documentBecameReady(document)
        }

        private var progressDelivery: ((Double) -> Void)?
        private weak var documentHistoryBinding: ReaderHistoryBinding?
        private var historyDocument: ReaderHistoryBinding.Document?
        private var pendingResumeBinding: (id: String, bind: @MainActor () -> Void)?
        private weak var documentResumeController: ReaderResumeController?
        private var resumeDelivery: ((ReaderResumeAnchor, Bool, String) -> Void)?
        private var isDismantled = false
        func bindMotion(to view: WKWebView) {
            if motion !== parent.readingMotion {
                motion?.detach(view)
                motion = parent.readingMotion
            }
            (view as? ArticleMotionWebView)?.readingMotion = motion
            motion?.attach(view)
            // Reuse only the closure captured when this document was accepted.
            // Frequent parent updates must not lend an old scroll a new owner.
            motion?.onProgress = progressDelivery
            motion?.onResumeSample = resumeDelivery
        }

        func acceptDocument(_ id: String) {
            invalidateDocument()
            isDismantled = false
            documentID = id
            documentHistoryBinding = parent.historyBinding
            if let session = parent.historySession {
                historyDocument = parent.historyBinding?.beginDocument(session, documentID: id)
            }
            let originalHistory = historyDocument.flatMap { document in
                documentHistoryBinding?.progressHandler(for: document)
            }
            let originalCallback = parent.onReadingProgress
            progressDelivery = { [weak self] value in
                guard let self, !self.isDismantled, self.documentID == id else { return }
                originalHistory?(value)
                originalCallback?(value)
            }
            motion?.onProgress = progressDelivery
            // Capture the original owner, source, session and controller now.
            // Readiness can arrive after parent updates; it must never adopt them.
            if let controller = parent.resumeController, let owner = parent.resumeOwner,
               let session = parent.historySession, let history = parent.historyBinding,
               parent.articleId == session.articleID,
               let source = ReaderResumeIdentity(articleID: session.articleID, sourceRevision: parent.articleRevision, html: parent.html) {
                pendingResumeBinding = (id, { [weak self, weak controller, weak history] in
                    guard let self, let controller, let history,
                          !self.isDismantled, self.documentID == id, history.isCurrent(session) else { return }
                    self.documentResumeController = controller
                    controller.bind(owner: owner, source: source, sessionID: session.id, documentID: id) { [weak self, weak history] in
                        guard let self, !self.isDismantled, self.documentID == id else { return false }
                        return history?.isCurrent(session) ?? false
                    }
                    guard !self.isDismantled, self.documentID == id, history.isCurrent(session) else { return }
                    self.resumeDelivery = { [weak self, weak controller] anchor, completed, documentID in
                        guard let self, !self.isDismantled, self.documentID == id, documentID == id else { return }
                        controller?.record(anchor, completed: completed, documentID: id)
                    }
                    self.motion?.onResumeSample = self.resumeDelivery
                })
            }
        }

        /// Called by the original motion bridge only after script and native
        /// scroll geometry are ready; loading must not expose an unusable offer.
        func documentBecameReady(_ id: String) {
            guard !isDismantled, documentID == id else { return }
            if let attempt = loadAttemptID {
                guard !loadReady, loadDocumentID == id, ownsLoad(attempt) else { return }
                let state = loadController, ticket = loadTicket, cancel = cancelLoadDeadline
                cancelLoadDeadline = nil
                cancel?()
                guard ownsLoad(attempt), documentID == id else { failLoad(attempt); return }
                loadReady = true
                if let ticket { state?.ready(ticket) }
            }
            guard let original = pendingResumeBinding, original.id == id else { return }
            pendingResumeBinding = nil
            original.bind()
        }

        func invalidateDocument() {
            pendingResumeBinding = nil
            documentResumeController?.invalidate(documentID: documentID)
            documentResumeController = nil
            resumeDelivery = nil
            motion?.onResumeSample = nil
            if let historyDocument { documentHistoryBinding?.endDocument(historyDocument) }
            historyDocument = nil
            documentHistoryBinding = nil
            isDismantled = true
            documentID = ""
            expectedNavigation = nil
            progressDelivery = nil
            motion?.onProgress = nil
            resetHeightTracking()
        }
        private var lastReportedHeight: CGFloat = 0
        private var pendingHeightTask: Task<Void, Never>?

        init(_ parent: HTMLTextView) {
            self.parent = parent
        }

        func resetHeightTracking() {
            lastReportedHeight = 0
            pendingHeightTask?.cancel()
            pendingHeightTask = nil
        }

        private func deliverHeight(_ height: CGFloat, documentID: String) {
            guard height.isFinite, height > 0, ownsDocument(documentID) else { return }
            guard abs(height - lastReportedHeight) >= 10 else { return }

            pendingHeightTask?.cancel()
            pendingHeightTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, self.ownsDocument(documentID) else { return }
                guard abs(height - self.lastReportedHeight) >= 10 else { return }
                self.lastReportedHeight = height
                self.parent.dynamicHeight = height
                guard self.ownsDocument(documentID) else { return }
                guard !self.isDismantled, self.documentID == documentID else { return }
                if let historyDocument = self.historyDocument {
                    self.documentHistoryBinding?.markDocumentReady(historyDocument)
                }
                self.localMeasuredHeight = height
                self.motion?.measuredContent(height: height)
                if let webView = self.loadWebView { self.checkLocalReadiness(webView) }
            }
        }
        
        // Handle link clicks
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // Only handle user-initiated navigation (clicks), not automatic loading
                if navigationAction.navigationType == .linkActivated {
                    // Open external links in Safari
                    if url.absoluteString.contains("spotify.com") || url.absoluteString.contains("open.spotify.com") {
                        UIApplication.shared.open(url)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === expectedNavigation, ownsDocument(documentID) else { return }
            let js = """
            (function() {
                const heightDocumentID = "\(documentID)";
                if (document.querySelector('meta[name="apropos-document"]')?.content !== heightDocumentID) return;
                if (window.aproposHeightCleanup) window.aproposHeightCleanup();
                let disposed = false;
                let heightTimer = null;
                let heightResizeObserver = null;
                let lazyObserver = null;
                const listeners = [];
                function active() {
                    return !disposed && document.querySelector('meta[name="apropos-document"]')?.content === heightDocumentID;
                }
                function listen(target, type, callback) {
                    target.addEventListener(type, callback);
                    listeners.push([target, type, callback]);
                }
                function cleanup() {
                    disposed = true;
                    if (heightTimer) clearTimeout(heightTimer);
                    if (heightResizeObserver) heightResizeObserver.disconnect();
                    if (lazyObserver) lazyObserver.disconnect();
                    listeners.forEach(function(item) { item[0].removeEventListener(item[1], item[2]); });
                    listeners.length = 0;
                    if (window.aproposHeightCleanup === cleanup) delete window.aproposHeightCleanup;
                }
                window.aproposHeightCleanup = cleanup;
                function sendHeight() {
                    if (!active()) return;
                    try {
                        const body = document.body;
                        let height = body ? body.scrollHeight : document.documentElement.scrollHeight;
                        if (body && body.lastElementChild) {
                            const last = body.lastElementChild;
                            const contentBottom = last.offsetTop + last.offsetHeight;
                            if (contentBottom > 0) height = Math.ceil(contentBottom);
                        }
                        if (height && height > 0) {
                            window.webkit.messageHandlers.heightHandler.postMessage({documentID: heightDocumentID, height: height, contentWidth: Math.max(body?.scrollWidth || 0, document.documentElement.scrollWidth), viewportWidth: document.documentElement.clientWidth});
                        }
                    } catch (e) {}
                }
                function sendHeightDebounced() {
                    if (!active()) return;
                    if (heightTimer) clearTimeout(heightTimer);
                    heightTimer = setTimeout(sendHeight, 220);
                }
                function ownsImage(img) {
                    return active() && img && img.ownerDocument === document && img.isConnected;
                }
                function pendingLazyImage(img) {
                    return img.matches('img.apropos-lazy[data-src]');
                }
                function replaceBrokenImage(img) {
                    // A pending transparent placeholder is not the article image. Also
                    // inspect already-failed eager images: their event may precede didFinish.
                    if (!ownsImage(img) || pendingLazyImage(img) || !img.complete || img.naturalWidth !== 0) return;
                    if (!(img.currentSrc || img.getAttribute('src') || img.getAttribute('srcset') || '').trim()) return;
                    const box = document.createElement('div');
                    box.className = 'apropos-offline-media';
                    const label = document.createElement('p');
                    label.className = 'apropos-offline-media__title';
                    label.textContent = 'Billedet kunne ikke indlæses';
                    box.appendChild(label);
                    // Replace only the image; its link, figure and editorial credit survive.
                    img.parentNode.replaceChild(box, img);
                    sendHeightDebounced();
                }
                function activateImage(img) {
                    if (!ownsImage(img) || !pendingLazyImage(img)) return;
                    const src = img.getAttribute('data-src');
                    if (!src || !src.trim()) return;
                    img.removeAttribute('data-src');
                    img.classList.remove('apropos-lazy');
                    img.src = src;
                    replaceBrokenImage(img);
                }
                function setupImages() {
                    Array.from(document.images).forEach(function(img) {
                        listen(img, 'load', sendHeightDebounced);
                        listen(img, 'error', function() { replaceBrokenImage(img); });
                        replaceBrokenImage(img);
                    });
                    const lazyImages = Array.from(document.querySelectorAll('img.apropos-lazy[data-src]'));
                    if (!lazyImages.length) return;
                    if (!window.IntersectionObserver) {
                        lazyImages.forEach(activateImage);
                        return;
                    }
                    lazyObserver = new IntersectionObserver(function(entries) {
                        if (!active()) return;
                        entries.forEach(function(entry) {
                            if (!entry.isIntersecting || !ownsImage(entry.target)) return;
                            activateImage(entry.target);
                            lazyObserver.unobserve(entry.target);
                        });
                    }, { rootMargin: '240px 0px', threshold: 0.01 });
                    lazyImages.forEach(function(img) { lazyObserver.observe(img); });
                }
                function ready() {
                    if (!active()) return;
                    setupImages();
                    sendHeightDebounced();
                    listen(window, 'resize', sendHeightDebounced);
                    if (window.ResizeObserver && document.body) {
                        heightResizeObserver = new ResizeObserver(sendHeightDebounced);
                        heightResizeObserver.observe(document.body);
                    }
                }
                if (document.readyState !== 'loading') ready();
                else listen(document, 'DOMContentLoaded', ready);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            motion?.contentDidFinish(webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !isDismantled, let navigation, navigation === expectedNavigation,
                  webView === loadWebView, let attempt = loadAttemptID else { return }
            failLoad(attempt)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.webView(webView, didFail: navigation, withError: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard webView === loadWebView, let attempt = loadAttemptID else { return }
            failLoad(attempt)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isDismantled, message.name == "heightHandler", message.frameInfo.isMainFrame,
                  let payload = message.body as? [String: Any],
                  payload["documentID"] as? String == documentID,
                  let number = payload["height"] as? NSNumber else { return }
            let originalDocumentID = documentID
            guard ownsDocument(originalDocumentID) else { return }
            if let width = payload["contentWidth"] as? NSNumber,
               let viewport = payload["viewportWidth"] as? NSNumber,
               viewport.doubleValue > 0 {
                parent.onHorizontalOverflow?(width.doubleValue > viewport.doubleValue + 1)
            }
            deliverHeight(CGFloat(truncating: number), documentID: originalDocumentID)
        }
    }
}
