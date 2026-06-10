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

    static func waitUntilUIReady() async {
        if isUIReady { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
