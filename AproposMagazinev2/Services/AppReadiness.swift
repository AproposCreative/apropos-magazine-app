import Foundation

/// Coordinates notification/deep-link navigation once the main UI is on screen.
@MainActor
enum AppReadiness {
    private static var isUIReady = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func markUIReady() {
        guard !isUIReady else { return }
        isUIReady = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    /// Wait until ContentView has appeared, or until `timeout` elapses.
    static func waitUntilUIReady(timeout: TimeInterval = 8) async {
        if isUIReady { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if isUIReady {
                        continuation.resume()
                    } else {
                        waiters.append(continuation)
                    }
                }
            }
            group.addTask {
                let ns = UInt64(max(0.1, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}
