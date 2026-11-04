import XCTest
@testable import Apropos

/// The callback-to-Task seam retains the account that existed at callback entry.
/// All physical callbacks and provider identities are local values.
@MainActor
final class ReaderCapturedWriteTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var uid: String? = "A"
        var identityReads = 0
        var starts = 0
        var callback: ReaderWriterDrainRuntime.Completion?
        let started = XCTestExpectation(description: "Physical write started")
        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical,
            actualUID: { [unowned self] in identityReads += 1; return uid },
            makeDrain: { XCTFail("No drain requested in captured-write tests"); throw CancellationError() })
        init() { select("A") }
        func select(_ value: String?) {
            uid = value
            _ = canonical.adopt(value.map {
                ReaderAccountSession(uid: $0, email: "reader@example.invalid", isEmailVerified: true)
            })
        }
        func capture(_ guardValue: @escaping ReaderWriterDrainRuntime.Guard = { true }) -> ReaderWriterDrainRuntime.CapturedWrite? {
            runtime.captureWrite(expectedUserID: "A", stillCurrent: guardValue) { [self] allowed, completion in
                guard allowed() else { completion(CancellationError()); return }
                starts += 1; callback = completion; started.fulfill()
            }
        }
    }

    func testCaptureIsInertAndCannotBorrowSameUIDAfterRoundTripBeforeTask() async throws {
        let f = Fixture()
        let write = try XCTUnwrap(f.capture())
        XCTAssertEqual(f.identityReads, 0)
        XCTAssertEqual(f.starts, 0)
        f.select("B"); f.select("A")
        do { try await write(); XCTFail("Old callback cannot start under a later A generation") } catch {}
        XCTAssertEqual(f.starts, 0)
        XCTAssertFalse(write.isCurrent())
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testCaptureRejectsIdentityReentryEvenWhenCallerReturnsTrue() {
        let f = Fixture()
        let write = f.capture { f.select("B"); f.select("A"); return true }
        XCTAssertNil(write)
        XCTAssertEqual(f.starts, 0)
        XCTAssertEqual(f.identityReads, 0)
    }

    func testObservedDenialCannotReviveAndRejectedActionCannotReplay() async throws {
        let f = Fixture()
        var permitted = true
        let write = try XCTUnwrap(f.capture { permitted })
        permitted = false
        XCTAssertFalse(write.isCurrent())
        permitted = true
        do { try await write(); XCTFail("Observed denial stays denied") } catch {}
        do { try await write(); XCTFail("A consumed callback is single-use") } catch {}
        XCTAssertFalse(write.isCurrent())
        XCTAssertEqual(f.starts, 0)
    }

    func testStopBeforeInvocationRejectsWithoutSDKAndCannotReplayAfterAbort() async throws {
        let f = Fixture()
        let write = try XCTUnwrap(f.capture())
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        do { try await write(); XCTFail("Stopped callback must not start") } catch {}
        XCTAssertEqual(f.starts, 0)
        XCTAssertTrue(f.runtime.abortStop(stop, stillBeforeTransition: { true }))
        do { try await write(); XCTFail("Abort does not resurrect a consumed callback") } catch {}
        XCTAssertEqual(f.starts, 0)
    }

    func testStartedWriteCanCompleteAfterStopButFeedbackRetainsOriginalGeneration() async throws {
        let f = Fixture()
        let write = try XCTUnwrap(f.capture())
        let task = Task { try await write() }
        let wait = await XCTWaiter.fulfillment(of: [f.started], timeout: 3)
        XCTAssertEqual(wait, .completed)
        XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        XCTAssertFalse(f.runtime.isPhysicallyIdle)
        XCTAssertTrue(write.isCurrent())
        try XCTUnwrap(f.callback)(nil)
        try await task.value
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertTrue(write.isCurrent())
        f.select("B"); f.select("A")
        XCTAssertFalse(write.isCurrent())
    }
}
