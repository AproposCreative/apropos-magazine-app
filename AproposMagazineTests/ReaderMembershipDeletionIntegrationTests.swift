import Combine
import Foundation
import XCTest
@testable import Apropos

/// The actual membership/deletion chain with local provider and transport seams.
/// No Firebase, credentials, persistence, or production traffic is initialized.
@MainActor
final class ReaderMembershipDeletionIntegrationTests: XCTestCase {
    private typealias Deletion = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Membership = ReaderMembershipContract

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        lazy var membership = ReaderMembershipAuthority(canonical: canonical)
        var providerActions: [Deletion.ActionTicket] = []
        var sent: [Contract.Request] = []
        var providerWait: CheckedContinuation<Deletion.ReauthenticationResult, Never>?
        var senderWait: CheckedContinuation<Data, Never>?
        var holdProvider = false
        var holdSender = false
        var freezeWhenSending = false
        var observation: AnyCancellable?
        lazy var deletion = Deletion(canonical: canonical,
            currentMembershipEpoch: { [weak self] in self?.membership.deletionEpoch(for: $0) },
            reauthenticate: { [weak self] action in
                guard let self else { throw CancellationError() }
                self.providerActions.append(action)
                if self.holdProvider {
                    return await withCheckedContinuation { self.providerWait = $0 }
                }
                return Self.proof(action)
            }, send: { [weak self] request, _ in
                guard let self else { throw CancellationError() }
                self.sent.append(request)
                if self.freezeWhenSending { try self.accept(epoch: request.membershipEpoch, frozen: true) }
                if self.holdSender { return await withCheckedContinuation { self.senderWait = $0 } }
                return try Self.receipt(request)
            }, nowMilliseconds: { 1_800_000_000_000 }, scheduleTimeout: { _, _ in {} })

        init() {
            canonical.adopt(.init(uid: "reader_a", email: "reader@example.invalid", isEmailVerified: true))
            let model = deletion
            observation = membership.changes.sink { [weak model] _ in model?.membershipDidChange() }
        }
        static func proof(_ action: Deletion.ActionTicket) -> Deletion.ReauthenticationResult {
            .init(action: action, authenticatedUID: action.request.expectedUID,
                  authTimeMs: action.startedAtMs, kind: .reauthenticated)
        }
        static func receipt(_ request: Contract.Request) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
                "scope": Contract.scope, "status": "pending", "accountDeletionComplete": false,
                "unresolved": Contract.unresolved])
        }
        func accept(epoch: Int64, frozen: Bool = false) throws {
            let context = canonical.contextTicket(), uid = try XCTUnwrap(context.userID)
            var row: [String: Any] = ["schemaVersion": 1, "ownerUID": uid, "epoch": epoch,
                                      "state": frozen ? "deletion_frozen" : "active"]
            if frozen { row["deletionRequestID"] = try Contract.Request(expectedUID: uid, membershipEpoch: epoch).requestID }
            let record = try Membership.decode(data: JSONSerialization.data(withJSONObject: row), expectedUID: uid)
            let read = try XCTUnwrap(membership.beginRead(for: context))
            XCTAssertTrue(membership.completeRead(read, record: record, isFromCache: false, hasPendingWrites: false))
        }
        @discardableResult func begin(_ epoch: Int64 = 1) -> Bool {
            deletion.begin(context: canonical.contextTicket(), membershipEpoch: epoch, userConfirmed: true)
        }
        func releaseProvider() {
            let action = providerActions.last!
            providerWait?.resume(returning: Self.proof(action)); providerWait = nil
        }
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local membership/deletion state was not reached", file: file, line: line)
    }

    func testLoginAndConfirmedMissingNeverStartReauthenticationOrDeletion() throws {
        let f = Fixture()
        XCTAssertFalse(f.begin())
        let read = try XCTUnwrap(f.membership.beginRead(for: f.canonical.contextTicket()))
        XCTAssertTrue(f.membership.completeRead(read, record: nil, isFromCache: false, hasPendingWrites: false))
        XCTAssertFalse(f.begin())
        XCTAssertTrue(f.providerActions.isEmpty)
        XCTAssertTrue(f.sent.isEmpty)
    }

    func testAtomicWorkerFreezeRevokesWritesButKeepsOriginalReceiptAndRetry() async throws {
        let f = Fixture(); try f.accept(epoch: 1)
        let context = f.canonical.contextTicket()
        let binding = try Membership.Binding(ownerUID: "reader_a", epoch: 1)
        let write = try XCTUnwrap(f.membership.captureWrite(for: context, binding: binding))
        f.freezeWhenSending = true
        XCTAssertTrue(f.begin())
        await eventually { f.deletion.status == .pending && !f.deletion.hasPhysicalFlight }
        XCTAssertFalse(f.membership.permits(write))
        XCTAssertNil(f.membership.captureWrite(for: context, binding: binding))
        XCTAssertEqual(f.membership.deletionEpoch(for: context), 1)
        XCTAssertFalse(f.deletion.accountDeletionComplete)
        XCTAssertTrue(f.deletion.retry(userConfirmed: true))
        await eventually { f.sent.count == 2 && !f.deletion.hasPhysicalFlight }
        XCTAssertEqual(f.sent[0].requestID, f.sent[1].requestID)
        XCTAssertEqual(f.providerActions.count, 2)
        XCTAssertEqual(f.deletion.status, .pending)
    }

    func testNewMembershipEpochRevokesSuspendedProofAndOldQueuedIntent() async throws {
        let f = Fixture(); try f.accept(epoch: 1); f.holdProvider = true
        XCTAssertTrue(f.begin())
        await eventually { f.providerWait != nil }
        try f.accept(epoch: 2)
        XCTAssertEqual(f.deletion.status, .cancelled)
        XCTAssertTrue(f.deletion.hasPhysicalFlight)
        XCTAssertFalse(f.begin(2))
        XCTAssertNil(f.membership.captureWrite(for: f.canonical.contextTicket(),
            binding: try Membership.Binding(ownerUID: "reader_a", epoch: 1)))
        f.releaseProvider()
        await eventually { !f.deletion.hasPhysicalFlight }
        XCTAssertTrue(f.sent.isEmpty)
        f.holdProvider = false
        XCTAssertTrue(f.begin(2))
        await eventually { f.sent.count == 1 && !f.deletion.hasPhysicalFlight }
        XCTAssertEqual(f.sent[0].membershipEpoch, 2)
        XCTAssertEqual(f.deletion.status, .pending)
    }

    func testSameUIDNewCanonicalGenerationCannotReuseOldProviderProof() async throws {
        let f = Fixture(); try f.accept(epoch: 1); f.holdProvider = true
        XCTAssertTrue(f.begin())
        await eventually { f.providerWait != nil }
        f.canonical.adopt(nil)
        f.canonical.adopt(.init(uid: "reader_a", email: "reader@example.invalid", isEmailVerified: true))
        XCTAssertNil(f.membership.deletionEpoch(for: f.canonical.contextTicket()))
        try f.accept(epoch: 1)
        f.releaseProvider()
        await eventually { !f.deletion.hasPhysicalFlight }
        XCTAssertTrue(f.sent.isEmpty)
        XCTAssertEqual(f.deletion.status, .cancelled)
    }

    func testMembershipReadFailureRevokesLateTransportReceiptWithoutFreeingFlight() async throws {
        let f = Fixture(); try f.accept(epoch: 1); f.holdSender = true
        XCTAssertTrue(f.begin())
        await eventually { f.senderWait != nil }
        let read = try XCTUnwrap(f.membership.beginRead(for: f.canonical.contextTicket()))
        XCTAssertTrue(f.membership.failRead(read))
        XCTAssertEqual(f.deletion.status, .cancelled)
        XCTAssertTrue(f.deletion.hasPhysicalFlight)
        f.senderWait?.resume(returning: try Fixture.receipt(f.sent[0])); f.senderWait = nil
        await eventually { !f.deletion.hasPhysicalFlight }
        XCTAssertNil(f.deletion.receipt)
        XCTAssertFalse(f.deletion.accountDeletionComplete)
    }

    func testFreshAuthorityCanRecoverFrozenRequestWithoutGrantingWriterAccess() async throws {
        let f = Fixture(); try f.accept(epoch: 7, frozen: true)
        let context = f.canonical.contextTicket()
        XCTAssertNil(f.membership.captureWrite(for: context,
            binding: try Membership.Binding(ownerUID: "reader_a", epoch: 7)))
        XCTAssertTrue(f.begin(7))
        await eventually { f.sent.count == 1 && !f.deletion.hasPhysicalFlight }
        XCTAssertEqual(f.sent[0].requestID, try Contract.Request(expectedUID: "reader_a", membershipEpoch: 7).requestID)
        XCTAssertEqual(f.deletion.status, .pending)
        XCTAssertFalse(f.deletion.accountDeletionComplete)
    }
}
