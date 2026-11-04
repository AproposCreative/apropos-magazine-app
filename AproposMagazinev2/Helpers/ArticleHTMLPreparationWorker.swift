import Foundation

/// Shared with the detached worker without an actor hop at queue admission.
private final class ArticlePreparationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// One physically active preparation and one replaceable newest request per
/// renderer. Invalidating a result does not pretend its detached work finished.
@MainActor
final class ArticleHTMLPreparationWorker<Input: Sendable, Output: Sendable> {
    private struct Job {
        let id: UUID
        let input: Input
        let work: @Sendable (Input, @escaping @Sendable () -> Bool) async -> Output?
        let cancellation: ArticlePreparationCancellation
        let isCurrent: @MainActor () -> Bool
        let discard: @MainActor () -> Void
        let commit: @MainActor (Output, @escaping @MainActor () -> Bool) -> Void
    }
    private var current: UUID?
    private var active: Job?
    private var pending: Job?
    var isWorking: Bool { active != nil }
    var hasPending: Bool { pending != nil }

    func submit(_ input: Input, work: @escaping @Sendable (Input, @escaping @Sendable () -> Bool) async -> Output?,
                isCurrent: @escaping @MainActor () -> Bool,
                discard: @escaping @MainActor () -> Void = {},
                commit: @escaping @MainActor (Output, @escaping @MainActor () -> Bool) -> Void) {
        active?.cancellation.cancel(); pending?.cancellation.cancel()
        let job = Job(id: UUID(), input: input, work: work, cancellation: ArticlePreparationCancellation(), isCurrent: isCurrent, discard: discard, commit: commit)
        current = job.id
        if active != nil { pending = job } else { start(job) }
    }
    func invalidate() {
        current = nil; active?.cancellation.cancel(); pending?.cancellation.cancel(); pending = nil
    }

    private func start(_ job: Job) {
        active = job
        // Detached work owns immutable input only. Keeping the physical slot
        // until return bounds CPU/disk work even after navigation or teardown.
        let input = job.input, work = job.work, cancellation = job.cancellation
        Task { [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                await work(input, { cancellation.isCancelled })
            }.value
            guard let self, self.active?.id == job.id else { return }
            let stillCurrent: @MainActor () -> Bool = { [weak self] in
                guard let self, self.current == job.id, !cancellation.isCancelled else { return false }
                return job.isCurrent() && self.current == job.id && !cancellation.isCancelled
            }
            if let output, stillCurrent() { job.commit(output, stillCurrent) }
            else if self.current == job.id { job.discard() }
            self.active = nil
            if let next = self.pending {
                self.pending = nil
                if self.current == next.id { self.start(next) }
            }
        }
    }
}
