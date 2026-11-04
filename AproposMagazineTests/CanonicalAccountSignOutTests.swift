import XCTest
@testable import Apropos

final class CanonicalAccountSignOutTests: XCTestCase {
    @MainActor
    func testSuccessInvalidatesPlaybackBeforeAuthAndPublishesOnlyAfterConfirmation() throws {
        var calls: [String] = []
        try CanonicalAccountSignOut.perform(suspend: { calls.append("suspend") }, signOut: {
            XCTAssertEqual(calls, ["suspend"])
            calls.append("auth")
        }, isSignedOut: { calls.append("confirm");return true }, republishCanonical: { calls.append("publish") })
        XCTAssertEqual(calls, ["suspend", "auth", "confirm", "publish"])
    }

    @MainActor
    func testThrowRestoresCanonicalContextAndCannotReachCallerCleanup() {
        enum Failure: Error { case auth }
        var calls: [String] = []
        do {
            try CanonicalAccountSignOut.perform(suspend: { calls.append("suspend") }, signOut: {
                calls.append("auth");throw Failure.auth
            }, isSignedOut: { XCTFail("No success confirmation after failure");return true },
                republishCanonical: { calls.append("restore") })
            calls.append("cleanup")
        } catch {}
        XCTAssertEqual(calls, ["suspend", "auth", "restore"])
    }

    @MainActor
    func testSuccessfulSDKReturnWithRemainingAccountStillRejectsCleanup() {
        var restored = 0, cleanup = false
        do {
            try CanonicalAccountSignOut.perform(suspend: {}, signOut: {}, isSignedOut: { false }, republishCanonical: { restored += 1 })
            cleanup = true
        } catch { XCTAssertTrue(error is CanonicalAccountSignOut.Failure) }
        XCTAssertFalse(cleanup)
        XCTAssertEqual(restored, 1)
    }

    @MainActor
    func testFailedLogoutRestoresPositionButNeverOldPlaybackTicket() throws {
        enum Failure: Error { case auth }
        var records: [String: Data] = [:]
        let store = PodcastPlaybackProgressStore(storage: .init(read: { records[$0.storageKey] }, write: { records[$0.storageKey] = $1 }))
        store.changeContext(to: .confirmed(userID: "account-a"))
        let session = try XCTUnwrap(store.beginSession(episodeID: "episode", articleID: "article"))
        store.save(session.ticket, seconds: 42, duration: 600)
        XCTAssertThrowsError(try CanonicalAccountSignOut.perform(suspend: {
            store.changeContext(to: .unresolved)
        }, signOut: {
            XCTAssertFalse(store.isCurrent(session.ticket))
            throw Failure.auth
        }, isSignedOut: { false }, republishCanonical: {
            store.changeContext(to: .confirmed(userID: "account-a"))
        }))
        XCTAssertEqual(store.snapshot.position(for: "episode"), 42)
        store.save(session.ticket, seconds: 99, duration: 600)
        XCTAssertEqual(store.snapshot.position(for: "episode"), 42)
    }
}
