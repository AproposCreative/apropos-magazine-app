import XCTest
import Security
@testable import Apropos

final class PushAcknowledgedInstallationVaultTests: XCTestCase {
    private let id = "4da6c391-e048-4e4f-9c75-80c248ca258b"
    private let key = String(repeating: "a", count: 64)
    private let hashA = String(repeating: "1", count: 64)
    private let start = Date(timeIntervalSince1970: 1_000)

    func testAbsentReadDoesNotGenerateIdentityWriteOrRevision() async throws {
        let store = AcknowledgedMemoryStore()
        let vault = vault(store)
        let result = try await vault.readExisting()
        XCTAssertNil(result)
        XCTAssertEqual(store.readCount, 1)
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertNil(store.snapshot())
    }

    func testOldRecordWithoutAcknowledgmentStaysExactAndDoesNotAcquireAuthority() async throws {
        let original = try encoded(record())
        let store = AcknowledgedMemoryStore(original)
        let value = try await vault(store).readExisting()
        XCTAssertEqual(value, record())
        XCTAssertNil(value?.acknowledgedBinding)
        XCTAssertEqual(store.snapshot(), original)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testReadRejectsCorruptRecordWithoutReplacingIt() async {
        let data = Data("not-an-installation".utf8)
        let store = AcknowledgedMemoryStore(data)
        await expect(.invalidRecord) { _ = try await self.vault(store).readExisting() }
        XCTAssertEqual(store.snapshot(), data)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testPendingAcknowledgmentPersistsExactOriginalTupleAndSurvivesObjectReconstruction() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let ack = binding()
        let saved = try await vault(store).acknowledge(ack, original: record(), lease: .init())
        XCTAssertEqual(saved.acknowledgedBinding, ack)
        XCTAssertEqual(saved.key, key)
        XCTAssertEqual(saved.intentHash, hashA)
        XCTAssertEqual(saved.revisionStartedAt, start)
        let reconstructed = try await vault(store).readExisting()
        XCTAssertEqual(reconstructed, saved)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(store.readCount, 3, "Write read, actual readback, then reconstruction read")
    }

    func testIdenticalAcknowledgmentIsIdempotentAndPendingCanAdvanceToActive() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let service = vault(store)
        let pending = try await service.acknowledge(binding(), original: record(), lease: .init())
        let repeated = try await service.acknowledge(binding(), original: record(), lease: .init())
        XCTAssertEqual(repeated, pending)
        XCTAssertEqual(store.writeCount, 1)
        let active = try await service.acknowledge(binding(status: .active), original: record(), lease: .init())
        XCTAssertEqual(active.acknowledgedBinding?.status, .active)
        XCTAssertEqual(store.writeCount, 2)
    }

    func testActiveAcknowledgmentCannotBeDowngradedByLatePendingResult() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let service = vault(store)
        _ = try await service.acknowledge(binding(status: .active), original: record(), lease: .init())
        let before = store.snapshot()
        await expect(.acknowledgedBindingConflict) {
            _ = try await service.acknowledge(self.binding(), original: self.record(), lease: .init())
        }
        XCTAssertEqual(store.snapshot(), before)
        XCTAssertEqual(store.writeCount, 1)
    }

    func testExistingAcknowledgmentRejectsOtherAccountGuestAppAndServerCounters() async throws {
        let previous = binding()
        let original = record(ack: previous)
        let alternatives = [binding(owner: "account_b"), binding(owner: nil), binding(app: "other-app"),
                            binding(epoch: 2), binding(serverRevision: 4), binding(status: .disabled)]
        for candidate in alternatives {
            let data = try encoded(original)
            let store = AcknowledgedMemoryStore(data)
            await expect(.acknowledgedBindingConflict) {
                _ = try await self.vault(store).acknowledge(candidate, original: original, lease: .init())
            }
            XCTAssertEqual(store.snapshot(), data)
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testGuestAcknowledgmentRemainsGuestAndCannotBeRelabeledAsAccount() async throws {
        let original = record(ack: binding(owner: nil))
        let store = AcknowledgedMemoryStore(try encoded(original))
        let saved = try await vault(store).acknowledge(binding(status: .active, owner: nil), original: original, lease: .init())
        XCTAssertNil(saved.acknowledgedBinding?.ownerUID)
        await expect(.acknowledgedBindingConflict) {
            _ = try await self.vault(store).acknowledge(self.binding(status: .active), original: original, lease: .init())
        }
        XCTAssertEqual(store.writeCount, 1)
    }

    func testChangedRevisionOrAnyImmutableOriginalFieldCannotReceiveOldAcknowledgment() async throws {
        var alternatives: [PushInstallationRecord] = []
        var changed = record(); changed.installationId = "6da6c391-e048-4e4f-9c75-80c248ca258b"; alternatives.append(changed)
        changed = record(); changed.key = String(repeating: "b", count: 64); alternatives.append(changed)
        changed = record(); changed.revision = 2; alternatives.append(changed)
        changed = record(); changed.intentHash = String(repeating: "2", count: 64); alternatives.append(changed)
        changed = record(); changed.revisionStartedAt = start.addingTimeInterval(1); alternatives.append(changed)
        for current in alternatives {
            let data = try encoded(current)
            let store = AcknowledgedMemoryStore(data)
            await expect(.acknowledgedBindingConflict) {
                _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: .init())
            }
            XCTAssertEqual(store.snapshot(), data)
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testMismatchedAcknowledgmentClientRevisionAndInstallationAreRejectedBeforeStorage() async {
        for candidate in [binding(clientRevision: 2), binding(installation: "6da6c391-e048-4e4f-9c75-80c248ca258b")] {
            let store = AcknowledgedMemoryStore()
            await expect(.acknowledgedBindingConflict) {
                _ = try await self.vault(store).acknowledge(candidate, original: self.record(), lease: .init())
            }
            XCTAssertEqual(store.readCount, 0)
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testAcknowledgmentCannotCreateMissingInstallation() async {
        let store = AcknowledgedMemoryStore()
        await expect(.acknowledgedBindingConflict) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: .init())
        }
        XCTAssertNil(store.snapshot())
        XCTAssertEqual(store.writeCount, 0)
    }

    func testUnchangedPreparePreservesAcknowledgmentAndNewRevisionClearsIt() async throws {
        let original = record(ack: binding(status: .active))
        let store = AcknowledgedMemoryStore(try encoded(original))
        let service = vault(store)
        let same = try await service.prepare(intentHash: hashA, at: start.addingTimeInterval(1))
        XCTAssertEqual(same, original)
        XCTAssertEqual(store.writeCount, 0)
        let next = try await service.prepare(intentHash: hashA, at: start.addingTimeInterval(2), forceNewRevision: true)
        XCTAssertEqual(next.revision, 2)
        XCTAssertNil(next.acknowledgedBinding)
        await expect(.acknowledgedBindingConflict) {
            _ = try await service.acknowledge(self.binding(status: .active), original: original, lease: .init())
        }
    }

    func testChangedIntentClearsAcknowledgmentWithoutRotatingIdentity() async throws {
        let original = record(ack: binding())
        let store = AcknowledgedMemoryStore(try encoded(original))
        let next = try await vault(store).prepare(intentHash: String(repeating: "2", count: 64), at: start.addingTimeInterval(1))
        XCTAssertEqual(next.installationId, original.installationId)
        XCTAssertEqual(next.key, original.key)
        XCTAssertEqual(next.revision, 2)
        XCTAssertNil(next.acknowledgedBinding)
    }

    func testMalformedNestedBindingAndUnknownPrivateFieldsDoNotGetSilentlyDropped() async throws {
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(record(ack: binding()))) as? [String: Any])
        for field in ["token", "nonce"] {
            var root = source
            var nested = try XCTUnwrap(root["acknowledgedBinding"] as? [String: Any])
            nested[field] = "must-not-be-retained"; root["acknowledgedBinding"] = nested
            let data = try JSONSerialization.data(withJSONObject: root)
            let store = AcknowledgedMemoryStore(data)
            await expect(.invalidRecord) { _ = try await self.vault(store).readExisting() }
            XCTAssertEqual(store.snapshot(), data)
            XCTAssertEqual(store.writeCount, 0)
        }
        let invalid = record(ack: binding(clientRevision: 2))
        var unstarted = record(ack: binding())
        unstarted.revision = 0; unstarted.intentHash = nil; unstarted.revisionStartedAt = nil
        for value in [invalid, unstarted] {
            let store = AcknowledgedMemoryStore(try encoded(value))
            await expect(.invalidRecord) { _ = try await self.vault(store).readExisting() }
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testRevokedLeaseFailsBeforeStorageAndCannotBeRevivedByNewLease() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let old = PushRegistrationBindingLease(); old.revoke()
        _ = PushRegistrationBindingLease()
        await expect(.bindingLeaseExpired) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: old)
        }
        XCTAssertEqual(store.readCount, 0)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testRevokedOriginalGenerationAlsoClosesItsAcknowledgmentChildLease() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let generation = PushRegistrationBindingLease()
        let acknowledgment = PushRegistrationBindingLease(parent: generation)
        generation.revoke()
        await expect(.bindingLeaseExpired) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: acknowledgment)
        }
        XCTAssertEqual(store.readCount, 0)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testLeaseRevokedInsideStorageReadPreventsPhysicalWrite() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let lease = PushRegistrationBindingLease()
        store.beforeUpdate = { lease.revoke() }
        await expect(.bindingLeaseExpired) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: lease)
        }
        XCTAssertEqual(store.writeCount, 0)
    }

    func testRevocationAfterEnteredWriteKeepsHistoricalBytesButDeniesPublication() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let lease = PushRegistrationBindingLease()
        store.afterWrite = { lease.revoke() }
        await expect(.bindingLeaseExpired) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: lease)
        }
        let historical = try await vault(store).readExisting()
        XCTAssertEqual(historical?.acknowledgedBinding, binding())
        XCTAssertEqual(store.writeCount, 1, "Do not roll back a physical historical write using a new owner")
    }

    func testCancellationBeforeStorageDoesNotWrite() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let service = vault(store), ack = binding(), original = record()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.acknowledge(ack, original: original, lease: .init())
        }
        do { _ = try await task.value; XCTFail("Cancelled task must not return acknowledgment") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.readCount, 0)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testCancellationDuringEnteredWriteDoesNotReturnOrRollbackHistoricalAcknowledgment() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        store.afterWrite = { withUnsafeCurrentTask { $0?.cancel() } }
        let service = vault(store), ack = binding(), original = record()
        let task = Task { try await service.acknowledge(ack, original: original, lease: .init()) }
        do { _ = try await task.value; XCTFail("Late physical success is not current publication authority") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(store.writeCount, 1)
        let historical = try await service.readExisting()
        XCTAssertEqual(historical?.acknowledgedBinding, ack)
    }

    func testStorageWriteFailureDoesNotReturnAckAndFreshRetryUsesOriginalRevision() async throws {
        let original = record(), data = try encoded(original)
        let store = AcknowledgedMemoryStore(data)
        store.failWrites = true
        do { _ = try await vault(store).acknowledge(binding(), original: original, lease: .init()); XCTFail("Expected write failure") }
        catch { XCTAssertEqual(error as? AcknowledgedFixtureError, .writeFailed) }
        XCTAssertEqual(store.snapshot(), data)
        store.failWrites = false
        let retry = try await vault(store).acknowledge(binding(), original: original, lease: .init())
        XCTAssertEqual(retry.revision, original.revision)
        XCTAssertEqual(retry.acknowledgedBinding, binding())
    }

    func testReadbackFailureKeepsHistoricalWriteAndFreshRetryDoesNotWriteAgain() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        store.failReadAt = 2
        do { _ = try await vault(store).acknowledge(binding(), original: record(), lease: .init()); XCTFail("Expected actual readback failure") }
        catch { XCTAssertEqual(error as? AcknowledgedFixtureError, .readFailed) }
        XCTAssertEqual(store.writeCount, 1)
        store.failReadAt = nil
        let retry = try await vault(store).acknowledge(binding(), original: record(), lease: .init())
        XCTAssertEqual(retry.acknowledgedBinding, binding())
        XCTAssertEqual(store.writeCount, 1)
    }

    func testExactReadbackRejectsEvenSemanticallyEqualReplacementBytes() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        store.replacementAfterWrite = Data(" \n".utf8) + (try encoded(record(ack: binding())))
        await expect(.readbackMismatch) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: .init())
        }
        XCTAssertEqual(store.writeCount, 1)
        let historical = try await vault(store).readExisting()
        XCTAssertEqual(historical?.acknowledgedBinding, binding())
    }

    func testPendingAndActiveRacingOnTwoVaultsNeverDowngradePersistedActiveTuple() async throws {
        let store = AcknowledgedMemoryStore(try encoded(record()))
        let first = vault(store), second = vault(store), original = record()
        let pending = binding(), active = binding(status: .active)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await first.acknowledge(pending, original: original, lease: .init()) }
            group.addTask { _ = try? await second.acknowledge(active, original: original, lease: .init()) }
        }
        let persisted = try await first.readExisting()
        XCTAssertEqual(persisted?.acknowledgedBinding, active)
        XCTAssertTrue((1...2).contains(store.writeCount))
    }

    func testRealKeychainAdapterUsesReadWriteReadbackAndNoRealSecurityCalls() async throws {
        let harness = AcknowledgedKeychainHarness(try encoded(record()))
        let store = PushInstallationKeychainStore(operations: harness.operations)
        let result = try await vault(store).acknowledge(binding(), original: record(), lease: .init())
        XCTAssertEqual(result.acknowledgedBinding, binding())
        XCTAssertEqual(harness.calls, ["read", "write", "read"])
        XCTAssertEqual(harness.storedData, try encoded(result))
    }

    func testRealKeychainAdapterRejectsFailedReadbackAndPreservesWrittenHistory() async throws {
        let harness = AcknowledgedKeychainHarness(try encoded(record()))
        harness.failSecondRead = true
        let store = PushInstallationKeychainStore(operations: harness.operations)
        await expect(.keychainRead(errSecInteractionNotAllowed)) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: .init())
        }
        XCTAssertEqual(harness.calls, ["read", "write", "read"])
        XCTAssertEqual(harness.storedData, try encoded(record(ack: binding())))
    }

    func testRealKeychainReadbackRevocationDeniesPublicationWithoutRollingBackHistory() async throws {
        let harness = AcknowledgedKeychainHarness(try encoded(record()))
        let lease = PushRegistrationBindingLease()
        harness.afterRead = { count in if count == 2 { lease.revoke() } }
        let store = PushInstallationKeychainStore(operations: harness.operations)
        await expect(.bindingLeaseExpired) {
            _ = try await self.vault(store).acknowledge(self.binding(), original: self.record(), lease: lease)
        }
        XCTAssertEqual(harness.calls, ["read", "write", "read"])
        XCTAssertEqual(harness.storedData, try encoded(record(ack: binding())))
    }

    func testRealKeychainReadOfAbsentRecordNeverCallsAddOrGeneratesIdentity() async throws {
        let harness = AcknowledgedKeychainHarness(nil)
        let value = try await vault(PushInstallationKeychainStore(operations: harness.operations)).readExisting()
        XCTAssertNil(value)
        XCTAssertEqual(harness.calls, ["read"])
    }

    private func vault(_ store: any PushInstallationRecordStore) -> PushInstallationVault {
        PushInstallationVault(store: store, makeIdentity: { throw AcknowledgedFixtureError.identityForbidden })
    }
    private func record(ack: PushAcknowledgedInstallationBinding? = nil) -> PushInstallationRecord {
        .init(installationId: id, key: key, revision: 1, intentHash: hashA, revisionStartedAt: start, acknowledgedBinding: ack)
    }
    private func binding(status: PushRegistrationReceipt.Status = .pending, owner: String? = "account_a",
                         app: String = "approved-ios-app", epoch: Int64 = 1, serverRevision: Int64 = 3,
                         clientRevision: Int64 = 1, installation: String? = nil) -> PushAcknowledgedInstallationBinding {
        .init(schemaVersion: 1, installationId: installation ?? id, appId: app, ownerUID: owner,
              ownerEpoch: epoch, revision: serverRevision, clientRevision: clientRevision, status: status)
    }
    private func encoded(_ record: PushInstallationRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(record)
    }
    private func expect(_ expected: PushInstallationVaultError, file: StaticString = #filePath, line: UInt = #line,
                        _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? PushInstallationVaultError, expected, file: file, line: line) }
    }
}

private enum AcknowledgedFixtureError: Error, Equatable { case readFailed, writeFailed, identityForbidden }

/// Old-style injected conformer deliberately uses protocol defaults for real
/// second-read verification. It never calls Keychain, Firebase or any service.
private final class AcknowledgedMemoryStore: @unchecked Sendable, PushInstallationRecordStore {
    private let lock = NSLock()
    private var data: Data?
    private(set) var readCount = 0
    private(set) var writeCount = 0
    var beforeUpdate: (() -> Void)?
    var afterWrite: (() -> Void)?
    var failWrites = false
    var failReadAt: Int?
    var replacementAfterWrite: Data?

    init(_ data: Data? = nil) { self.data = data }
    func snapshot() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        if failReadAt == readCount { throw AcknowledgedFixtureError.readFailed }
        beforeUpdate?()
        let next = try update(data)
        if next != data {
            if failWrites { throw AcknowledgedFixtureError.writeFailed }
            data = next
            writeCount += 1
            if let replacementAfterWrite { data = replacementAfterWrite }
            afterWrite?()
        }
        return next
    }
}

/// The actual adapter owns its process-wide transaction lock around these fake
/// operations. This harness performs no calls to Security.framework itself.
private final class AcknowledgedKeychainHarness: @unchecked Sendable {
    var storedData: Data?
    var calls: [String] = []
    var failSecondRead = false
    var afterRead: ((Int) -> Void)?
    init(_ data: Data?) { storedData = data }
    var operations: PushInstallationKeychainStore.Operations {
        .init(copyMatching: { [self] _ in
            calls.append("read")
            afterRead?(calls.filter { $0 == "read" }.count)
            if failSecondRead, calls.filter({ $0 == "read" }).count == 2 { return (errSecInteractionNotAllowed, nil) }
            guard let storedData else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, storedData as CFData)
        }, update: { [self] _, attributes in
            calls.append("write")
            storedData = (attributes as NSDictionary)[kSecValueData as String] as? Data
            return errSecSuccess
        }, add: { [self] attributes in
            calls.append("add")
            storedData = (attributes as NSDictionary)[kSecValueData as String] as? Data
            return errSecSuccess
        })
    }
}
