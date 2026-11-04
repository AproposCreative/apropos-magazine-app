import Combine
import Foundation

/// Renderer feedback only: no network, account or article authority is created.
/// Mutation is immediate, but publications leave UIViewRepresentable.updateUIView.
@MainActor
final class ArticleHTMLLoadState: ObservableObject {
    enum Phase: Equatable { case preparing, ready, failed }
    struct Attempt: Equatable {
        fileprivate let modelID: UUID
        fileprivate let id: UUID
        fileprivate let retryID: UUID
    }
    typealias Schedule = @MainActor (UInt64, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let modelID = UUID()
    private var current: Attempt?
    private var publicationIsCurrent: (@MainActor (Phase) -> Bool)?
    private var requested: Phase = .preparing
    private var published: Phase = .preparing
    private var publication = UUID()
    private var publishedAttempt: Attempt?
    private(set) var retryID = UUID()
    var phase: Phase { publishedAttempt == current ? published : .preparing }

    func begin(isCurrent: @escaping @MainActor (Phase) -> Bool = { _ in true }) -> Attempt {
        let attempt = Attempt(modelID: modelID, id: UUID(), retryID: retryID)
        current = attempt; requested = .preparing; publicationIsCurrent = isCurrent
        publish(.preparing, for: attempt)
        return attempt
    }
    func owns(_ attempt: Attempt) -> Bool { current == attempt && attempt.modelID == modelID && attempt.retryID == retryID }
    func ready(_ attempt: Attempt) {
        guard owns(attempt), requested != .failed, requested != .ready else { return }
        requested = .ready; publish(.ready, for: attempt)
    }
    func fail(_ attempt: Attempt) {
        guard owns(attempt) else { return }
        requested = .failed; publish(.failed, for: attempt)
    }
    func invalidate(_ attempt: Attempt) {
        guard owns(attempt) else { return }
        current = nil; publication = UUID(); requested = .preparing; publicationIsCurrent = nil
    }
    func retry() {
        guard phase == .failed else { return }
        let event = UUID(); publication = event
        objectWillChange.send()
        guard publication == event, phase == .failed else { return }
        current = nil; retryID = UUID(); requested = .preparing; publicationIsCurrent = nil
        published = .preparing; publishedAttempt = nil
    }
    private func publish(_ phase: Phase, for attempt: Attempt) {
        let event = UUID(); publication = event
        Task { @MainActor [weak self] in
            guard let self, self.mayPublish(phase, attempt: attempt, event: event) else { return }
            self.objectWillChange.send()
            guard self.mayPublish(phase, attempt: attempt, event: event) else { return }
            self.published = phase; self.publishedAttempt = attempt
        }
    }
    private func mayPublish(_ phase: Phase, attempt: Attempt, event: UUID) -> Bool {
        guard owns(attempt), publication == event, requested == phase,
              let isCurrent = publicationIsCurrent else { return false }
        guard isCurrent(phase) else { return false }
        return owns(attempt) && publication == event && requested == phase
    }
    static func scheduleDeadline(_ nanoseconds: UInt64, fire: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard !Task.isCancelled else { return }; fire()
        }
        return { task.cancel() }
    }
}

#if DEBUG && targetEnvironment(simulator)
import WebKit
/// Local smoke/test controls only; never selects a production network endpoint.
struct ArticleHTMLLoadTesting {
    let prepare: (@Sendable (ArticleHTMLPreparation.Input, @escaping @Sendable () -> Bool) async -> ArticleHTMLPreparation.Output?)?
    let schedule: ArticleHTMLLoadState.Schedule?
    let timeoutNanoseconds: UInt64
    let onWebViewReady: (@MainActor (WKWebView, HTMLTextView.Coordinator) -> Void)?
    init(prepare: (@Sendable (ArticleHTMLPreparation.Input, @escaping @Sendable () -> Bool) async -> ArticleHTMLPreparation.Output?)? = nil,
         schedule: ArticleHTMLLoadState.Schedule? = nil, timeoutNanoseconds: UInt64 = 20_000_000_000,
         onWebViewReady: (@MainActor (WKWebView, HTMLTextView.Coordinator) -> Void)? = nil) {
        self.prepare = prepare; self.schedule = schedule; self.timeoutNanoseconds = timeoutNanoseconds
        self.onWebViewReady = onWebViewReady
    }
}
#endif
