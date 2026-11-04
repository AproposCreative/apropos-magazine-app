import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderMembershipAuthorityTests: XCTestCase {
    private typealias Model = ReaderMembershipAuthority
    private typealias Contract = ReaderMembershipContract

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        lazy var model = Model(canonical: canonical)
        init(uid: String? = "reader-A") { select(uid) }
        func select(_ uid: String?, forceNewGeneration: Bool = false) {
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: forceNewGeneration)
        }
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
    }
    private func binding(_ uid: String = "reader-A", _ epoch: Int64 = 7) throws -> Contract.Binding {
        try Contract.Binding(ownerUID: uid, epoch: epoch)
    }
    private func record(_ uid: String = "reader-A", _ epoch: Int64 = 7, frozen: Bool = false) throws -> Contract.Record {
        var value: [String: Any] = ["schemaVersion": 1, "ownerUID": uid, "epoch": epoch,
                                    "state": frozen ? "deletion_frozen" : "active"]
        if frozen { value["deletionRequestID"] = try ReaderAccountDeletionContract.Request(expectedUID: uid, membershipEpoch: epoch).requestID }
        return try Contract.decode(data: JSONSerialization.data(withJSONObject: value), expectedUID: uid)
    }
    @discardableResult
    private func accept(_ f: Fixture, _ record: Contract.Record?, file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let ticket = try XCTUnwrap(f.model.beginRead(for: f.context), file: file, line: line)
        return f.model.completeRead(ticket, record: record, isFromCache: false, hasPendingWrites: false)
    }

    func testConstructionAndLoginNeverInventMembershipOrStartARead() throws {
        let canonical = CanonicalSessionState(), model = Model(canonical: CanonicalSessionState())
        XCTAssertEqual(model.status, .unresolved)
        XCTAssertNil(model.beginRead(for: canonical.contextTicket()))
        let f = Fixture(uid: nil)
        XCTAssertNil(f.model.beginRead(for: f.context))
        f.select("reader-A")
        XCTAssertEqual(f.model.status, .unresolved)
        XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
    }

    func testServerActiveRowAuthorizesOnlyOriginalNonLegacyIntentBinding() throws {
        let f = Fixture(), original = try binding()
        XCTAssertTrue(try accept(f, record()))
        let write = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: original))
        XCTAssertTrue(f.model.permits(write))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), 7)
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: nil), "Legacy backlog must not inherit the current epoch")
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding("reader-B", 7)))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding("reader-A", 6)))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding("reader-A", 8)))
    }

    func testCachePendingWritesAndCachedAbsenceNeverAuthorizeAndConsumeTheirRead() throws {
        for cache in [false, true] {
            for pending in [false, true] where cache || pending {
                for absent in [false, true] {
                    let f = Fixture(), ticket = try XCTUnwrap(f.model.beginRead(for: f.context))
                    let row = absent ? nil : try record()
                    XCTAssertFalse(f.model.completeRead(ticket, record: row, isFromCache: cache, hasPendingWrites: pending))
                    XCTAssertEqual(f.model.status, .unavailable)
                    XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
                    XCTAssertNil(f.model.deletionEpoch(for: f.context))
                    XCTAssertFalse(f.model.completeRead(ticket, record: try record(), isFromCache: false, hasPendingWrites: false))
                }
            }
        }
    }

    func testConfirmedMissingAndCurrentFailureRevokeWithoutEnrollment() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record()))
        let write = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding()))
        XCTAssertTrue(try accept(f, nil)); XCTAssertEqual(f.model.status, .missing)
        XCTAssertFalse(f.model.permits(write)); XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertTrue(try accept(f, record()))
        let read = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertTrue(f.model.failRead(read)); XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        XCTAssertNil(f.model.deletionEpoch(for: f.context))
    }

    func testEveryNewReadImmediatelyRevokesThePreviousWriteLease() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record()))
        let previous = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding()))
        let read = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertEqual(f.model.status, .loading); XCTAssertFalse(f.model.permits(previous))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        XCTAssertTrue(f.model.completeRead(read, record: try record(), isFromCache: false, hasPendingWrites: false))
        let current = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding()))
        XCTAssertTrue(f.model.permits(current)); XCTAssertFalse(f.model.permits(previous))
    }

    func testPendingReadRetainsOnlyPreviouslyCommittedDeletionOwnershipAndNeverWritePermission() throws {
        let f = Fixture()
        let initial = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertNil(f.model.deletionEpoch(for: f.context), "Login and an outstanding read are not membership")
        XCTAssertTrue(f.model.completeRead(initial, record: try record(), isFromCache: false, hasPendingWrites: false))
        let write = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding()))
        let refreshing = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), 7)
        XCTAssertFalse(f.model.permits(write)); XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        XCTAssertTrue(f.model.completeRead(refreshing, record: try record(frozen: true), isFromCache: false, hasPendingWrites: false))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), 7)
        let failed = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), 7)
        XCTAssertTrue(f.model.failRead(failed)); XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertNotNil(f.model.beginRead(for: f.context))
        XCTAssertNil(f.model.deletionEpoch(for: f.context), "A known freeze is not a retained committed authorization after failure")
    }

    func testInterruptedPublicationCannotRetainAnUncommittedDeletionBinding() throws {
        let f = Fixture()
        let read = try XCTUnwrap(f.model.beginRead(for: f.context))
        var entered = false
        let observer = f.model.objectWillChange.sink {
            guard !entered else { return }; entered = true
            XCTAssertNotNil(f.model.beginRead(for: f.context))
        }
        XCTAssertFalse(f.model.completeRead(read, record: try record(), isFromCache: false, hasPendingWrites: false))
        XCTAssertEqual(f.model.status, .loading)
        XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        withExtendedLifetime(observer) {}
    }

    func testOutOfOrderFailureOrSuccessCannotRevokeOrReplaceANewerGrant() throws {
        let f = Fixture()
        let old = try XCTUnwrap(f.model.beginRead(for: f.context))
        let current = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertTrue(f.model.completeRead(current, record: try record("reader-A", 8), isFromCache: false, hasPendingWrites: false))
        let lease = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding("reader-A", 8)))
        let snapshot = f.model.snapshot
        XCTAssertFalse(f.model.failRead(old))
        XCTAssertFalse(f.model.completeRead(old, record: try record(), isFromCache: false, hasPendingWrites: false))
        XCTAssertEqual(f.model.snapshot, snapshot); XCTAssertTrue(f.model.permits(lease))
    }

    func testReadIsOneShotAndForeignModelTicketsCannotTouchCurrentGrant() throws {
        let f = Fixture(), second = Model(canonical: f.canonical)
        let own = try XCTUnwrap(f.model.beginRead(for: f.context))
        let foreign = try XCTUnwrap(second.beginRead(for: f.context))
        XCTAssertTrue(f.model.completeRead(own, record: try record(), isFromCache: false, hasPendingWrites: false))
        XCTAssertTrue(second.completeRead(foreign, record: try record(), isFromCache: false, hasPendingWrites: false))
        let lease = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: binding()))
        let otherLease = try XCTUnwrap(second.captureWrite(for: f.context, binding: binding()))
        let snapshot = f.model.snapshot
        XCTAssertFalse(f.model.completeRead(own, record: nil, isFromCache: false, hasPendingWrites: false))
        XCTAssertFalse(f.model.completeRead(foreign, record: nil, isFromCache: false, hasPendingWrites: false))
        XCTAssertFalse(f.model.failRead(foreign)); XCTAssertFalse(f.model.permits(otherLease))
        XCTAssertEqual(f.model.snapshot, snapshot); XCTAssertTrue(f.model.permits(lease))
    }

    func testFrozenMembershipDeniesWritesButRetainsItsExactDeletionEpoch() throws {
        let f = Fixture(), original = try binding()
        XCTAssertTrue(try accept(f, record()))
        let write = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: original))
        XCTAssertTrue(try accept(f, record(frozen: true)))
        let request = try ReaderAccountDeletionContract.Request(expectedUID: original.ownerUID, membershipEpoch: original.epoch)
        XCTAssertEqual(f.model.status, .deletionFrozen(original, requestID: request.requestID))
        XCTAssertFalse(f.model.permits(write)); XCTAssertNil(f.model.captureWrite(for: f.context, binding: original))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), request.membershipEpoch)
    }

    func testFreezeSurvivesMissingFailureCacheAndExplicitInvalidationUntilStrictlyNewerServerEpoch() throws {
        for interruption in 0..<4 {
            let f = Fixture()
            XCTAssertTrue(try accept(f, record(frozen: true)))
            switch interruption {
            case 0: XCTAssertTrue(try accept(f, nil))
            case 1:
                let read = try XCTUnwrap(f.model.beginRead(for: f.context)); XCTAssertTrue(f.model.failRead(read))
            case 2:
                let read = try XCTUnwrap(f.model.beginRead(for: f.context))
                XCTAssertFalse(f.model.completeRead(read, record: try record(), isFromCache: true, hasPendingWrites: false))
            default: f.model.invalidate()
            }
            XCTAssertNil(f.model.deletionEpoch(for: f.context))
            XCTAssertFalse(try accept(f, record()), "Same-epoch active cannot thaw an observed freeze")
            XCTAssertFalse(try accept(f, record("reader-A", 6)))
            XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
            XCTAssertTrue(try accept(f, record("reader-A", 8)))
            XCTAssertNotNil(f.model.captureWrite(for: f.context, binding: try binding("reader-A", 8)))
            XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        }
    }

    func testHigherEpochCannotRegressAfterAnInterveningFailureOrMissingDocument() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record("reader-A", 9)))
        XCTAssertTrue(try accept(f, nil))
        XCTAssertFalse(try accept(f, record("reader-A", 8, frozen: true)))
        XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertTrue(try accept(f, record("reader-A", 9)))
        XCTAssertEqual(f.model.deletionEpoch(for: f.context), 9)
    }

    func testForeignRowForCurrentReadFailsClosedWithoutInventingItsOwner() throws {
        let f = Fixture()
        XCTAssertFalse(try accept(f, record("reader-B", 7)))
        XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertNil(f.model.deletionEpoch(for: f.context))
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding("reader-B", 7)))
    }

    func testAccountSwitchAndSameUIDNewGenerationRevokeReadAndWriteAuthority() throws {
        for sameUID in [false, true] {
            let f = Fixture(), original = f.context
            XCTAssertTrue(try accept(f, record()))
            let lease = try XCTUnwrap(f.model.captureWrite(for: original, binding: binding()))
            let read = try XCTUnwrap(f.model.beginRead(for: original))
            if sameUID { f.select("reader-A", forceNewGeneration: true) }
            else { f.select("reader-B"); f.select(nil); f.select("reader-A") }
            XCTAssertEqual(f.model.status, .unresolved)
            XCTAssertFalse(f.model.permits(lease)); XCTAssertNil(f.model.beginRead(for: original))
            XCTAssertNil(f.model.deletionEpoch(for: original))
            XCTAssertFalse(f.model.completeRead(read, record: try record(), isFromCache: false, hasPendingWrites: false))
            XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        }
    }

    func testProfileUpdateWithinTheSameCanonicalGenerationDoesNotInventOrRevokeMembership() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record()))
        let original = f.context, lease = try XCTUnwrap(f.model.captureWrite(for: original, binding: binding()))
        f.canonical.adopt(.init(uid: "reader-A", email: "updated@example.invalid", isEmailVerified: true))
        XCTAssertEqual(f.context, original); XCTAssertTrue(f.model.permits(lease))
    }

    func testRestartNeedsFreshServerAuthorityAndNeverRebindsOldOrUntaggedBacklog() throws {
        let f = Fixture(), oldBinding = try binding()
        XCTAssertTrue(try accept(f, record()))
        let oldLease = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: oldBinding))
        let restarted = Model(canonical: f.canonical)
        XCTAssertFalse(restarted.permits(oldLease))
        XCTAssertNil(restarted.captureWrite(for: f.context, binding: oldBinding))
        let read = try XCTUnwrap(restarted.beginRead(for: f.context))
        XCTAssertTrue(restarted.completeRead(read, record: try record("reader-A", 8), isFromCache: false, hasPendingWrites: false))
        XCTAssertNil(restarted.captureWrite(for: f.context, binding: oldBinding))
        XCTAssertNil(restarted.captureWrite(for: f.context, binding: nil))
        XCTAssertNotNil(restarted.captureWrite(for: f.context, binding: try binding("reader-A", 8)))
        XCTAssertEqual(oldBinding.epoch, 7, "Dispatch must not stamp persisted old work with the new epoch")
    }

    func testReadRevocationPrecedesWillChangeSoReentrantObserverCannotCaptureAnOldLease() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record()))
        let originalBinding = try binding(), lease = try XCTUnwrap(f.model.captureWrite(for: f.context, binding: originalBinding))
        var called = false
        let observer = f.model.objectWillChange.sink {
            guard !called else { return }; called = true
            XCTAssertFalse(f.model.permits(lease))
            XCTAssertNil(f.model.captureWrite(for: f.context, binding: originalBinding))
        }
        XCTAssertNotNil(f.model.beginRead(for: f.context)); XCTAssertTrue(called)
        withExtendedLifetime(observer) {}
    }

    func testFreezeIsRememberedBeforeReentrantReadAndLateOuterPublicationCannotRestoreActive() throws {
        let f = Fixture()
        XCTAssertTrue(try accept(f, record()))
        let read = try XCTUnwrap(f.model.beginRead(for: f.context)), oldActive = try record()
        var entered = false
        let observer = f.model.objectWillChange.sink {
            guard !entered else { return }; entered = true
            guard let nested = f.model.beginRead(for: f.context) else { return XCTFail("Expected nested read") }
            XCTAssertFalse(f.model.completeRead(nested, record: oldActive, isFromCache: false, hasPendingWrites: false))
        }
        XCTAssertFalse(f.model.completeRead(read, record: try record(frozen: true), isFromCache: false, hasPendingWrites: false))
        XCTAssertTrue(entered); XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertNil(f.model.captureWrite(for: f.context, binding: try binding()))
        withExtendedLifetime(observer) {}
    }

    func testCommittedPublisherFiltersStaleOuterEventAfterNestedAccountSwitch() throws {
        let f = Fixture(), active = try record()
        var entered = false
        var delivered: [[Model.Snapshot]] = [[], []]
        func consume(_ value: Model.Snapshot, index: Int) {
            XCTAssertEqual(value, f.model.snapshot)
            XCTAssertTrue(f.canonical.isCurrent(value.context))
            delivered[index].append(value)
            guard case .active = value.status, !entered else { return }; entered = true
            f.select("reader-B")
        }
        // Subscriber iteration order is not guaranteed. Whichever observer
        // receives the valid A event first must trigger the nested B change.
        let first = f.model.changes.sink { consume($0, index: 0) }
        let second = f.model.changes.sink { consume($0, index: 1) }
        let read = try XCTUnwrap(f.model.beginRead(for: f.context))
        XCTAssertFalse(f.model.completeRead(read, record: active, isFromCache: false, hasPendingWrites: false))
        XCTAssertTrue(entered); XCTAssertEqual(f.model.status, .unresolved)
        XCTAssertEqual(f.context.userID, "reader-B")
        for values in delivered {
            let replacement = values.firstIndex { $0.context.userID == "reader-B" }
            XCTAssertNotNil(replacement)
            if let replacement {
                XCTAssertFalse(values[replacement...].contains { $0.context.userID == "reader-A" })
            }
            XCTAssertEqual(values.last?.context, f.context)
        }
        withExtendedLifetime((first, second)) {}
    }
}
