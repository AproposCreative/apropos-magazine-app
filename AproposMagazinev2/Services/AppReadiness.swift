import Foundation

/// Coordinates notification/deep-link navigation once the main UI is on screen.
@MainActor
enum AppReadiness {
    private static let gate = UIReadinessGate()

    static func markUIReady() {
        gate.markReady()
        IncomingLinkRuntime.shared.setUIReady(true)
    }

    /// Wait until ContentView has appeared, or until `timeout` elapses.
    static func waitUntilUIReady(timeout: TimeInterval = 8) async {
        await gate.wait(timeout: timeout)
    }
}

/// An instance can be tested without opening the app or initializing services.
@MainActor
final class UIReadinessGate {
    private var isReady = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    func markReady() {
        isReady = true
        for id in Array(waiters.keys) {
            finish(id)
        }
    }

    func wait(timeout: TimeInterval) async {
        guard !isReady, !Task.isCancelled else { return }
        let id = UUID()
        let duration = timeout.isFinite ? min(max(0, timeout), 86_400) : 8
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !isReady, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiters[id] = continuation
                deadlines[id] = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    } catch {
                        return
                    }
                    self?.finish(id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id) }
        }
    }

    private func finish(_ id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        waiters.removeValue(forKey: id)?.resume()
    }
}
