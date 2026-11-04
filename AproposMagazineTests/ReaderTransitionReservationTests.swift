import XCTest
@testable import Apropos

@MainActor
final class ReaderTransitionReservationTests: XCTestCase {
    func testOnlyOneOriginalReservationCanBeClaimedAndWrongOwnerCannotReleaseIt() throws {
        let h = Fixture(), other = Fixture()
        XCTAssertNil(h.runtime.reserveTransition(context: other.context))
        let original = try XCTUnwrap(h.runtime.reserveTransition(context: h.context))
        XCTAssertTrue(h.runtime.ownsTransition(original))
        XCTAssertNil(h.runtime.reserveTransition(context: h.context))
        var guardCalled = false
        XCTAssertFalse(h.runtime.releaseTransition(owner: UUID(), stillIdle: { guardCalled = true; return true }))
        XCTAssertFalse(guardCalled)
        XCTAssertFalse(h.runtime.releaseTransition(owner: original, stillIdle: { false }))
        XCTAssertTrue(h.runtime.ownsTransition(original))
        XCTAssertTrue(h.runtime.releaseTransition(owner: original, stillIdle: { true }))
        let next = try XCTUnwrap(h.runtime.reserveTransition(context: h.context))
        XCTAssertNotEqual(original, next)
    }

    func testGuestAndUnresolvedCannotClaimAndAccountChangeNeverAutomaticallyReleasesOwner() throws {
        let h = Fixture()
        h.select(nil)
        XCTAssertNil(h.runtime.reserveTransition(context: h.context))
        h.canonical.suspend()
        XCTAssertNil(h.runtime.reserveTransition(context: h.context))
        h.select("A")
        let original = try XCTUnwrap(h.runtime.reserveTransition(context: h.context))
        h.select(nil); h.select("A")
        XCTAssertTrue(h.runtime.ownsTransition(original))
        XCTAssertNil(h.runtime.reserveTransition(context: h.context))
        // The original physical operation may drain after its account changed.
        XCTAssertTrue(h.runtime.releaseTransition(owner: original, stillIdle: { true }))
        XCTAssertNotNil(h.runtime.reserveTransition(context: h.context))
    }

    func testReentrantReleaseAndNewClaimCannotBeClearedByOuterRelease() throws {
        let h = Fixture(), original = try XCTUnwrap(h.runtime.reserveTransition(context: h.context))
        var replacement: UUID?
        let released = h.runtime.releaseTransition(owner: original, stillIdle: {
            XCTAssertTrue(h.runtime.releaseTransition(owner: original, stillIdle: { true }))
            replacement = h.runtime.reserveTransition(context: h.context)
            return true
        })
        XCTAssertFalse(released)
        XCTAssertTrue(h.runtime.ownsTransition(try XCTUnwrap(replacement)))
        XCTAssertFalse(h.runtime.ownsTransition(original))
    }

    func testSealPreservesDrainReceiptAndReservationReleaseNeverReopensOrUnseals() async throws {
        let h = Fixture(), reservation = try XCTUnwrap(h.runtime.reserveTransition(context: h.context))
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        let receipt = try await h.runtime.drain(stop)
        XCTAssertTrue(h.runtime.sealStop(stop))
        XCTAssertTrue(h.runtime.sealStop(stop))
        XCTAssertTrue(h.runtime.isCurrent(receipt))
        XCTAssertFalse(h.runtime.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(h.runtime.releaseTransition(owner: reservation, stillIdle: { true }))
        XCTAssertNotNil(h.runtime.reserveTransition(context: h.context))
        XCTAssertFalse(h.runtime.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(h.runtime.isCurrent(receipt))
        var started = false
        do {
            try await h.runtime.performWrite(expectedUserID: "A", stillCurrent: { true }) { _, completion in
                started = true; completion(nil)
            }
            XCTFail("A released transition reservation reopened sealed writers")
        } catch {}
        XCTAssertFalse(started)
    }

    func testSealSurvivesReplacementStopForAnotherAccountAndSameUIDNewGeneration() throws {
        let h = Fixture(), first = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        XCTAssertTrue(h.runtime.sealStop(first))
        h.select("B")
        let second = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        XCTAssertFalse(h.runtime.abortStop(second, stillBeforeTransition: { true }))
        h.select(nil); h.select("A")
        let third = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        XCTAssertFalse(h.runtime.abortStop(third, stillBeforeTransition: { true }))
        XCTAssertTrue(h.runtime.sealStop(third))
    }

    func testUIDMismatchCannotSealAndDoesNotPoisonAnOtherwiseAbortableStop() throws {
        let h = Fixture(), stop = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        h.uid = "B"
        XCTAssertFalse(h.runtime.sealStop(stop))
        h.uid = "A"
        XCTAssertTrue(h.runtime.abortStop(stop, stillBeforeTransition: { true }))
    }

    func testIdentityGetterReentryCannotSealAReplacementStop() throws {
        let h = Fixture(), original = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        var replacement: ReaderWriterDrainCoordinator.StopTicket?
        h.identityHook = {
            h.identityHook = nil
            XCTAssertTrue(h.runtime.abortStop(original, stillBeforeTransition: { true }))
            replacement = h.runtime.stopWrites(context: h.context)
        }
        XCTAssertFalse(h.runtime.sealStop(original))
        XCTAssertTrue(h.runtime.abortStop(try XCTUnwrap(replacement), stillBeforeTransition: { true }))
    }

    func testForeignStopCannotSealAnotherRuntime() throws {
        let h = Fixture(), other = Fixture()
        let foreign = try XCTUnwrap(other.runtime.stopWrites(context: other.context))
        let original = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        XCTAssertFalse(h.runtime.sealStop(foreign))
        XCTAssertTrue(h.runtime.abortStop(original, stillBeforeTransition: { true }))
    }

    func testPhysicalWriterAndDrainMustReturnBeforeSealing() async throws {
        let h = Fixture(), writeStarted = expectation(description: "Physical writer registered")
        var callback: ReaderWriterDrainCoordinator.Completion?
        let write = Task {
            try await h.runtime.performWrite(expectedUserID: "A", stillCurrent: { true }) { guardLast, completion in
                XCTAssertTrue(guardLast()); callback = completion; writeStarted.fulfill()
            }
        }
        await fulfillment(of: [writeStarted], timeout: 3)
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.context))
        XCTAssertFalse(h.runtime.sealStop(stop))
        try XCTUnwrap(callback)(nil)
        try await write.value
        let drainStarted = expectation(description: "Physical drain registered")
        h.holdDrain = true
        h.drainStarted = { drainStarted.fulfill() }
        let drain = Task { try await h.runtime.drain(stop) }
        await fulfillment(of: [drainStarted], timeout: 3)
        XCTAssertFalse(h.runtime.sealStop(stop))
        try XCTUnwrap(h.drainCallback)(nil)
        let receipt = try await drain.value
        XCTAssertTrue(h.runtime.sealStop(stop))
        XCTAssertTrue(h.runtime.isCurrent(receipt))
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var uid: String? = "A"
        var identityHook: (() -> Void)?
        var holdDrain = false
        var drainStarted: (() -> Void)?
        var drainCallback: ReaderWriterDrainCoordinator.Completion?
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [unowned self] in
            self.identityHook?(); return self.uid
        }, schedule: { _ in {} }, makeDrain: { [unowned self] in
            .init(wait: { [unowned self] completion in
                if self.holdDrain { self.drainCallback = completion; self.drainStarted?() }
                else { completion(nil) }
            })
        })
        init() { select("A") }
        func select(_ value: String?) {
            uid = value
            canonical.adopt(value.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
    }
}
