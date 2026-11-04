import Foundation

/// A deadline ends the UI wait, not an already queued Firestore write. Late
/// acknowledgements must neither resume twice nor alter a newer account's UI.
@MainActor
enum ReaderWriteAcknowledgement {
    typealias Schedule = (@escaping () -> Void) -> (() -> Void)

    @MainActor private final class Ticket {
        var continuation: CheckedContinuation<Void, Error>?
        var cancelDeadline: (() -> Void)?
        func finish(_ error: Error?) {
            guard let continuation else { return }
            self.continuation = nil
            let cancel = cancelDeadline
            cancelDeadline = nil
            cancel?()
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }

    /// Drain authority for a serial transport slot. Unlike `perform`, only an
    /// actual provider callback completes this await; UI timeout is separate.
    static func performDraining(
        start: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ticket = Ticket()
            ticket.continuation = continuation
            start { error in Task { @MainActor in ticket.finish(error) } }
        }
    }

    static func perform(
        schedule: Schedule? = nil,
        start: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        let schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { return }
                action()
            }
            return { task.cancel() }
        }
        try await withCheckedThrowingContinuation { continuation in
            let ticket = Ticket()
            ticket.continuation = continuation
            ticket.cancelDeadline = schedule { ticket.finish(URLError(.timedOut)) }
            guard ticket.continuation != nil else { ticket.cancelDeadline?(); return }
            start { error in Task { @MainActor in ticket.finish(error) } }
        }
    }
}
