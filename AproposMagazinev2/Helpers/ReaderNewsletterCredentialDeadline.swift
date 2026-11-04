import Foundation

/// Bounds credential acquisition even when an SDK ignores task cancellation.
/// A late SDK callback may finish its own work, but cannot resume this caller.
@MainActor
enum ReaderNewsletterCredentialDeadline {
    enum Failure: Error, Equatable { case timedOut }
    typealias Sleeper = @MainActor (UInt64) async throws -> Void

    static func run<Value: Sendable>(
        timeoutNanoseconds: UInt64 = 20_000_000_000,
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let pending = Pending<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await withCheckedThrowingContinuation { continuation in
                pending.start(continuation, timeoutNanoseconds: timeoutNanoseconds,
                              sleep: sleep, operation: operation)
            }
            try Task.checkCancellation()
            return value
        } onCancel: {
            Task { @MainActor in pending.resolve(.failure(CancellationError())) }
        }
    }

    @MainActor
    private final class Pending<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Error>?
        private var operationTask: Task<Void, Never>?
        private var deadlineTask: Task<Void, Never>?
        private var resolved = false

        func start(_ continuation: CheckedContinuation<Value, Error>, timeoutNanoseconds: UInt64,
                   sleep: @escaping Sleeper, operation: @escaping @MainActor () async throws -> Value) {
            self.continuation = continuation
            // Cancellation can arrive before the continuation is installed.
            guard !resolved else {
                self.continuation = nil
                continuation.resume(throwing: CancellationError())
                return
            }
            operationTask = Task { @MainActor [weak self] in
                do {
                    try Task.checkCancellation()
                    let value = try await operation()
                    try Task.checkCancellation()
                    self?.resolve(.success(value))
                } catch { self?.resolve(.failure(error)) }
            }
            deadlineTask = Task { @MainActor [weak self] in
                do {
                    try await sleep(timeoutNanoseconds)
                    try Task.checkCancellation()
                    self?.resolve(.failure(Failure.timedOut))
                } catch {
                    // Finishing the operation cancels this timer. An injected
                    // clock failure while still live is returned to its caller.
                    if !Task.isCancelled { self?.resolve(.failure(error)) }
                }
            }
        }

        func resolve(_ result: Result<Value, Error>) {
            guard !resolved else { return }
            resolved = true
            let waiting = continuation
            continuation = nil
            let operation = operationTask, deadline = deadlineTask
            operationTask = nil
            deadlineTask = nil
            operation?.cancel()
            deadline?.cancel()
            waiting?.resume(with: result)
        }
    }
}
