import Foundation

/// The real auth adapter supplies effects; tests can exercise the same ordering
/// without starting Auth, playback, storage or account services.
@MainActor
enum CanonicalAccountSignOut {
    enum Failure: Error { case unconfirmed }

    static func perform(suspend: () -> Void, signOut: () throws -> Void,
                        isSignedOut: () -> Bool, republishCanonical: () -> Void) throws {
        suspend()
        do {
            try signOut()
            guard isSignedOut() else { throw Failure.unconfirmed }
        } catch {
            republishCanonical()
            throw error
        }
        republishCanonical()
    }
}
