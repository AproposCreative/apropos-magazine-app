import Combine
import Foundation

/// Waits for the actual preference model's accepted load before an explicit
/// interest save. It never manufactures a loaded state or releases model I/O.
@MainActor
final class ReaderInterestCommitPreparation {
    typealias Schedule = (@escaping @MainActor () -> Void) -> (() -> Void)

    private let canonical: CanonicalSessionState
    private let preferences: ReaderPreferencesModel
    private let actions: ReaderAccountActions
    private let owner: ReaderAccountActions.OwnerAction
    private let schedule: Schedule
    private var observations = Set<AnyCancellable>()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var cancelDeadline: (() -> Void)?
    private var loadTask: Task<Void, Never>?
    private var started = false
    private var completed = false
    private var observedLoading = false
    private var loadReturned = false

    init(canonical: CanonicalSessionState, preferences: ReaderPreferencesModel,
         actions: ReaderAccountActions, owner: ReaderAccountActions.OwnerAction, schedule: Schedule? = nil) {
        self.canonical = canonical
        self.preferences = preferences
        self.actions = actions
        self.owner = owner
        self.schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        }
    }

    func prepare() async -> Bool {
        guard !started, !Task.isCancelled else { return false }
        started = true
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                canonical.changes.sink { [weak self] _ in self?.evaluate() }.store(in: &observations)
                preferences.changes.sink { [weak self] _ in self?.evaluate() }.store(in: &observations)
                evaluate()
                guard !completed else { return }
                let cancel = schedule { [weak self] in self?.finish(false) }
                // Injected deadlines may fire or change accounts synchronously.
                if completed { cancel(); return }
                cancelDeadline = cancel
                evaluate()
                guard !completed, !preferences.snapshot.isLoading else { return }
                // Recheck on execution: an Auth load may have started between
                // the button event and this task. Join it instead of replacing it.
                let preferences = preferences, context = owner.preferences
                loadTask = Task { @MainActor [weak self] in
                    guard !Task.isCancelled, self?.shouldStartLoad() == true else { return }
                    guard let permission = self?.owner.readerPermission else { return }
                    await preferences.load(context, stillCurrent: permission)
                    self?.loadReturned = true
                    self?.evaluate()
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.finish(false) }
        })
    }

    private func shouldStartLoad() -> Bool {
        guard !completed, actions.isCurrentReader(owner) else { finish(false); return false }
        evaluate()
        guard !completed else { return false }
        if preferences.snapshot.isLoading { observedLoading = true; return false }
        return true
    }

    private func evaluate() {
        guard !completed else { return }
        guard actions.isCurrentReader(owner) else { finish(false); return }
        let current = preferences.snapshot
        if current.loaded && !current.isLoading { finish(true) }
        else if current.isLoading { observedLoading = true }
        else if observedLoading || loadReturned { finish(false) }
    }

    private func finish(_ ready: Bool) {
        guard !completed else { return }
        completed = true
        let continuation = continuation, cancel = cancelDeadline, task = loadTask
        self.continuation = nil
        cancelDeadline = nil
        loadTask = nil
        observations.removeAll()
        task?.cancel()
        cancel?()
        continuation?.resume(returning: ready && actions.isCurrentReader(owner))
    }
}
