import SwiftUI

/// Keeps the real renderer mounted while its original document is prepared.
/// The notice covers presentation only; WebKit can still measure its layout.
struct ArticleHTMLBody: View {
    var html: String
    var articleId: String?
    var articleRevision: String?
    @Binding var dynamicHeight: CGFloat
    @ObservedObject var loadState: ArticleHTMLLoadState
    var readingMotion: ArticleReadingMotionController? = nil
    var historyBinding: ReaderHistoryBinding? = nil
    var historySession: ReaderHistoryBinding.Session? = nil
    var resumeController: ReaderResumeController? = nil
    var resumeOwner: String? = nil
    var prepareHTML: ((String, String?) -> HTMLTextView.PreparedHTML)? = nil
    #if DEBUG && targetEnvironment(simulator)
    var loadTesting: ArticleHTMLLoadTesting? = nil
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            renderer
                .frame(height: max(dynamicHeight, 240))
                .accessibilityHidden(loadState.phase != .ready)
                .allowsHitTesting(loadState.phase == .ready)
            if loadState.phase != .ready {
                ArticleBodyLoadingState(isLoading: loadState.phase == .preparing,
                    isOffline: false, preparesExistingContent: true) {
                    loadState.retry()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(uiColor: .systemBackground))
            }
        }
    }

    private var renderer: HTMLTextView {
        var view = HTMLTextView(html: html, articleId: articleId, articleRevision: articleRevision,
            dynamicHeight: $dynamicHeight, readingMotion: readingMotion,
            historyBinding: historyBinding, historySession: historySession,
            resumeController: resumeController, resumeOwner: resumeOwner,
            prepareHTML: prepareHTML, loadState: loadState)
        view.loadRequestID = loadState.retryID
        #if DEBUG && targetEnvironment(simulator)
        view.loadTesting = loadTesting
        #endif
        return view
    }
}
