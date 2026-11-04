import XCTest
import Security
@testable import Apropos

final class PushInstallationVaultTests: XCTestCase {
    private let installationId = "4da6c391-e048-4e4f-9c75-80c248ca258b"
    private let key = String(repeating: "a", count: 64)
    private let hashA = String(repeating: "1", count: 64)
    private let hashB = String(repeating: "2", count: 64)
    private let start = Date(timeIntervalSince1970: 1_000)

    func testFirstIntentPersistsPrivateIdentityAndRevisionBeforeReturning() async throws {
        let store = MemoryRecordStore()
        let vault = makeVault(store)
        let record = try await vault.prepare(intentHash: hashA, at: start)
        XCTAssertEqual(record.installationId, installationId)
        XCTAssertEqual(record.key, key)
        XCTAssertEqual(record.revision, 1)
        XCTAssertEqual(record.intentHash, hashA)
        XCTAssertEqual(record.revisionStartedAt, start)
        XCTAssertEqual(try decoded(try XCTUnwrap(store.snapshot())), record)
        XCTAssertEqual(store.writeCount, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(store.snapshot())) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "installationId", "key", "revision", "intentHash", "revisionStartedAt"])
        XCTAssertEqual(object["revisionStartedAt"] as? Double, 1_000_000)
    }

    func testSameIntentAfterRestartKeepsOriginalChallengeLifetimeAndIdentity() async throws {
        let store = MemoryRecordStore()
        let first = try await makeVault(store).prepare(intentHash: hashA, at: start)
        let restarted = PushInstallationVault(store: store, makeIdentity: { throw FixtureError.identityMustNotBeRegenerated })
        let later = try await restarted.prepare(intentHash: hashA, at: start.addingTimeInterval(360))
        XCTAssertEqual(later, first)
        XCTAssertEqual(store.writeCount, 1)
    }

    func testChangedIntentAndExplicitRenewalAdvanceWithoutRotatingIdentity() async throws {
        let store = MemoryRecordStore()
        let vault = makeVault(store)
        let first = try await vault.prepare(intentHash: hashA, at: start)
        let changed = try await vault.prepare(intentHash: hashB, at: start.addingTimeInterval(1))
        let renewed = try await vault.prepare(intentHash: hashB, at: start.addingTimeInterval(2), forceNewRevision: true)
        XCTAssertEqual([first.revision, changed.revision, renewed.revision], [1, 2, 3])
        XCTAssertEqual(renewed.installationId, first.installationId)
        XCTAssertEqual(renewed.key, first.key)
        XCTAssertEqual(changed.intentHash, hashB)
        XCTAssertEqual(renewed.revisionStartedAt, start.addingTimeInterval(2))
    }

    func testLockedStorageDoesNotGenerateAnAlternativeInstallation() async {
        let store = MemoryRecordStore()
        store.readError = FixtureError.locked
        let identities = IdentityCounter(id: installationId, key: key)
        let vault = PushInstallationVault(store: store, makeIdentity: { identities.make() })
        do {
            _ = try await vault.prepare(intentHash: hashA, at: start)
            XCTFail("Unavailable storage must fail closed")
        } catch {
            XCTAssertEqual(error as? FixtureError, .locked)
        }
        XCTAssertEqual(identities.count, 0)
        XCTAssertNil(store.snapshot())
        XCTAssertEqual(store.writeCount, 0)
    }

    func testMalformedStorageDoesNotResetIdentityOrRevision() async throws {
        let original = Data("not a private installation record".utf8)
        let store = MemoryRecordStore(data: original)
        let identities = IdentityCounter(id: installationId, key: key)
        let vault = PushInstallationVault(store: store, makeIdentity: { identities.make() })
        await expect(.invalidRecord) { _ = try await vault.prepare(intentHash: self.hashA, at: self.start) }
        XCTAssertEqual(identities.count, 0)
        XCTAssertEqual(store.snapshot(), original)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testUnsupportedSchemaAndUnknownPrivateFieldsAreNotSilentlyMigrated() async throws {
        for object in [
            ["schemaVersion": 2, "installationId": installationId, "key": key, "revision": 0] as [String: Any],
            ["schemaVersion": 1, "installationId": installationId, "key": key, "revision": 0, "token": "unapproved-old-token"]
        ] {
            let data = try JSONSerialization.data(withJSONObject: object)
            let store = MemoryRecordStore(data: data)
            await expect(.invalidRecord) { _ = try await self.makeVault(store).prepare(intentHash: self.hashA, at: self.start) }
            XCTAssertEqual(store.snapshot(), data)
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testWriteFailureNeverReturnsAnUnpersistedRevision() async throws {
        let store = MemoryRecordStore()
        let vault = makeVault(store)
        let first = try await vault.prepare(intentHash: hashA, at: start)
        let originalBytes = store.snapshot()
        store.writeError = FixtureError.writeFailed
        do {
            _ = try await vault.prepare(intentHash: hashB, at: start.addingTimeInterval(1))
            XCTFail("Caller must not send an unpersisted revision")
        } catch { XCTAssertEqual(error as? FixtureError, .writeFailed) }
        XCTAssertEqual(store.snapshot(), originalBytes)
        store.writeError = nil
        let retry = try await vault.prepare(intentHash: hashB, at: start.addingTimeInterval(2))
        XCTAssertEqual(retry.revision, first.revision + 1)
    }

    func testFailedInitialWriteDoesNotPublishAnIdentity() async throws {
        let store = MemoryRecordStore()
        store.writeError = FixtureError.writeFailed
        let vault = makeVault(store)
        do {
            _ = try await vault.prepare(intentHash: hashA, at: start)
            XCTFail("Identity must be durable before returning")
        } catch { XCTAssertEqual(error as? FixtureError, .writeFailed) }
        XCTAssertNil(store.snapshot())
        XCTAssertEqual(store.writeCount, 0)
    }

    func testInvalidIntentAndClockDoNotReadOrCreateStorage() async {
        let store = MemoryRecordStore()
        let vault = makeVault(store)
        for invalid in ["", String(repeating: "F", count: 64), hashA + "\n", "token-secret"] {
            await expect(.invalidIntentHash) { _ = try await vault.prepare(intentHash: invalid, at: self.start) }
        }
        for invalid in [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: -1),
                        Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                        Date(timeIntervalSince1970: Double.greatestFiniteMagnitude)] {
            await expect(.invalidClock) { _ = try await vault.prepare(intentHash: self.hashA, at: invalid) }
        }
        XCTAssertEqual(store.readCount, 0)
        XCTAssertNil(store.snapshot())
    }

    func testClockRollbackCannotExtendOrRestartARevision() async throws {
        let store = MemoryRecordStore()
        let vault = makeVault(store)
        let first = try await vault.prepare(intentHash: hashA, at: start)
        let same = try await vault.prepare(intentHash: hashA, at: start.addingTimeInterval(-10))
        XCTAssertEqual(same, first)
        await expect(.invalidClock) {
            _ = try await vault.prepare(intentHash: self.hashB, at: self.start.addingTimeInterval(-10))
        }
        await expect(.invalidClock) {
            _ = try await vault.prepare(intentHash: self.hashA, at: self.start.addingTimeInterval(-10), forceNewRevision: true)
        }
        XCTAssertEqual(try decoded(try XCTUnwrap(store.snapshot())), first)
    }

    func testMaximumRevisionCanBeRetriedButNeverOverflowedOrReset() async throws {
        let record = PushInstallationRecord(installationId: installationId, key: key,
                                            revision: PushInstallationRecord.maximumRevision,
                                            intentHash: hashA, revisionStartedAt: start)
        let original = try encoded(record)
        let store = MemoryRecordStore(data: original)
        let vault = makeVault(store)
        let same = try await vault.prepare(intentHash: hashA, at: start.addingTimeInterval(1))
        XCTAssertEqual(same, record)
        await expect(.revisionExhausted) { _ = try await vault.prepare(intentHash: self.hashB, at: self.start.addingTimeInterval(1)) }
        await expect(.revisionExhausted) {
            _ = try await vault.prepare(intentHash: self.hashA, at: self.start.addingTimeInterval(1), forceNewRevision: true)
        }
        XCTAssertEqual(try decoded(try XCTUnwrap(store.snapshot())), record)
    }

    func testUnstartedValidRecordGetsFirstRevisionWithoutRegeneratingIdentity() async throws {
        let store = MemoryRecordStore(data: try encoded(PushInstallationRecord(installationId: installationId, key: key)))
        let vault = PushInstallationVault(store: store, makeIdentity: { throw FixtureError.identityMustNotBeRegenerated })
        let record = try await vault.prepare(intentHash: hashA, at: start)
        XCTAssertEqual(record.revision, 1)
        XCTAssertEqual(record.installationId, installationId)
    }

    func testInvalidRecordsAreRejectedWithoutChangingPersistedBytes() async throws {
        let good = PushInstallationRecord(installationId: installationId, key: key, revision: 1,
                                          intentHash: hashA, revisionStartedAt: start)
        var invalid: [PushInstallationRecord] = []
        var value = good; value.schemaVersion = 0; invalid.append(value)
        value = good; value.installationId = installationId.uppercased(); invalid.append(value)
        value = good; value.installationId = installationId + "\n"; invalid.append(value)
        value = good; value.installationId = "00000000-0000-0000-0000-000000000000"; invalid.append(value)
        value = good; value.key = String(repeating: "a", count: 39); invalid.append(value)
        value = good; value.key = String(repeating: "a", count: 129); invalid.append(value)
        value = good; value.key = key + "\n"; invalid.append(value)
        value = good; value.key = key + "/"; invalid.append(value)
        value = good; value.revision = -1; invalid.append(value)
        value = good; value.revision = PushInstallationRecord.maximumRevision + 1; invalid.append(value)
        value = good; value.revision = 0; invalid.append(value)
        value = good; value.intentHash = nil; invalid.append(value)
        value = good; value.intentHash = "wrong"; invalid.append(value)
        value = good; value.revisionStartedAt = nil; invalid.append(value)
        value = good; value.revisionStartedAt = Date(timeIntervalSince1970: 0); invalid.append(value)
        for record in invalid {
            let original = try encoded(record)
            let store = MemoryRecordStore(data: original)
            await expect(.invalidRecord) { _ = try await self.makeVault(store).prepare(intentHash: self.hashB, at: self.start) }
            XCTAssertEqual(store.snapshot(), original)
            XCTAssertEqual(store.writeCount, 0)
        }
    }

    func testOversizedPrivateRecordIsRejectedWithoutReset() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "installationId": installationId,
                                                               "key": String(repeating: "a", count: 10_000), "revision": 0])
        let store = MemoryRecordStore(data: data)
        await expect(.invalidRecord) { _ = try await self.makeVault(store).prepare(intentHash: self.hashA, at: self.start) }
        XCTAssertEqual(store.snapshot(), data)
    }

    func testInvalidGeneratedIdentityIsNotPersisted() async {
        let store = MemoryRecordStore()
        let vault = PushInstallationVault(store: store, makeIdentity: { ("bad-identity", "short") })
        await expect(.invalidRecord) { _ = try await vault.prepare(intentHash: self.hashA, at: self.start) }
        XCTAssertNil(store.snapshot())
    }

    func testTwoVaultsSharingTransactionalStoreCannotClobberRevisions() async throws {
        let store = MemoryRecordStore()
        let first = makeVault(store)
        let second = makeVault(store)
        let hash = hashA
        let date = start
        let revisions = try await withThrowingTaskGroup(of: Int64.self) { group in
            for index in 0..<80 {
                let vault = index.isMultiple(of: 2) ? first : second
                group.addTask { try await vault.prepare(intentHash: hash, at: date, forceNewRevision: true).revision }
            }
            var values: [Int64] = []
            for try await revision in group { values.append(revision) }
            return values
        }
        XCTAssertEqual(revisions.sorted(), Array(1...Int64(80)))
        XCTAssertEqual(try decoded(try XCTUnwrap(store.snapshot())).revision, 80)
        XCTAssertEqual(store.writeCount, 80)
    }

    func testKeychainInitializationDoesNotInvokeAnySecurityOperation() {
        let harness = KeychainHarness()
        _ = PushInstallationKeychainStore(operations: harness.operations)
        XCTAssertTrue(harness.calls.isEmpty)
    }

    func testKeychainMissingItemUsesExactPrivateDeviceOnlyAttributes() throws {
        let harness = KeychainHarness()
        let store = PushInstallationKeychainStore(service: "fixture.private.push.v1", account: "installation-fixture",
                                                  operations: harness.operations)
        let bytes = Data("private-vault-record".utf8)
        let returned = try store.transaction { previous in
            XCTAssertNil(previous)
            return bytes
        }
        XCTAssertEqual(returned, bytes)
        XCTAssertEqual(harness.data, bytes)
        XCTAssertEqual(harness.calls.map(\.name), ["read", "add"])
        for call in harness.calls {
            assertPrivateIdentity(call.query, service: "fixture.private.push.v1", account: "installation-fixture")
            XCTAssertNil(call.query[kSecAttrAccessGroup as String])
        }
        let read = try XCTUnwrap(harness.calls.first?.query)
        XCTAssertEqual(read[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(read[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
        XCTAssertNil(read[kSecValueData as String])
        let added = try XCTUnwrap(harness.calls.last?.query)
        XCTAssertEqual(added[kSecValueData as String] as? Data, bytes)
        XCTAssertNil(added[kSecReturnData as String])
        XCTAssertNil(added[kSecMatchLimit as String])
    }

    func testKeychainExistingItemUpdatesWithoutDeleteOrRecreate() throws {
        let original = Data("old".utf8)
        let next = Data("new".utf8)
        let harness = KeychainHarness(data: original)
        let store = PushInstallationKeychainStore(operations: harness.operations)
        _ = try store.transaction { previous in
            XCTAssertEqual(previous, original)
            return next
        }
        XCTAssertEqual(harness.calls.map(\.name), ["read", "update"])
        let update = try XCTUnwrap(harness.calls.last)
        assertPrivateIdentity(update.query)
        XCTAssertEqual(update.attributes?[kSecValueData as String] as? Data, next)
        XCTAssertEqual(update.attributes?[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(harness.data, next)
    }

    func testKeychainUnchangedTransactionDoesNotWrite() throws {
        let original = Data("same".utf8)
        let harness = KeychainHarness(data: original)
        let store = PushInstallationKeychainStore(operations: harness.operations)
        XCTAssertEqual(try store.transaction { try XCTUnwrap($0) }, original)
        XCTAssertEqual(harness.calls.map(\.name), ["read"])
    }

    func testKeychainLockedOrUnavailableReadDoesNotCallUpdateClosure() throws {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed, errSecMissingEntitlement] {
            let harness = KeychainHarness(data: Data("preserved".utf8))
            harness.readStatus = status
            let store = PushInstallationKeychainStore(operations: harness.operations)
            XCTAssertThrowsError(try store.transaction { _ in
                XCTFail("A failed read must not look like a new installation")
                return Data()
            }) { XCTAssertEqual($0 as? PushInstallationVaultError, .keychainRead(status)) }
            XCTAssertEqual(harness.calls.map(\.name), ["read"])
            XCTAssertEqual(harness.data, Data("preserved".utf8))
        }
    }

    func testKeychainSuccessWithoutDataFailsClosed() throws {
        let harness = KeychainHarness(data: Data("preserved".utf8))
        harness.returnInvalidObject = true
        let store = PushInstallationKeychainStore(operations: harness.operations)
        XCTAssertThrowsError(try store.transaction { _ in XCTFail(); return Data() }) {
            XCTAssertEqual($0 as? PushInstallationVaultError, .invalidKeychainResult)
        }
        XCTAssertEqual(harness.calls.map(\.name), ["read"])
    }

    func testKeychainFailedAddAndFailedUpdateNeverDeleteOrFallback() throws {
        for existing in [nil, Data("preserved".utf8)] {
            for status in [errSecNotAvailable, errSecDuplicateItem, errSecItemNotFound] {
                let harness = KeychainHarness(data: existing)
                harness.writeStatus = status
                let store = PushInstallationKeychainStore(operations: harness.operations)
                XCTAssertThrowsError(try store.transaction { _ in Data("next".utf8) }) {
                    XCTAssertEqual($0 as? PushInstallationVaultError, .keychainWrite(status))
                }
                XCTAssertEqual(harness.data, existing)
                XCTAssertEqual(harness.calls.map(\.name), ["read", existing == nil ? "add" : "update"])
            }
        }
    }

    func testKeychainThrowingUpdateClosureLeavesPrivateBytesUntouched() throws {
        let original = Data("corrupt-but-preserved".utf8)
        let harness = KeychainHarness(data: original)
        let store = PushInstallationKeychainStore(operations: harness.operations)
        XCTAssertThrowsError(try store.transaction { _ in throw FixtureError.writeFailed }) {
            XCTAssertEqual($0 as? FixtureError, .writeFailed)
        }
        XCTAssertEqual(harness.calls.map(\.name), ["read"])
        XCTAssertEqual(harness.data, original)
    }

    func testInvalidKeychainNamespaceDoesNotReachSecurity() throws {
        let harness = KeychainHarness()
        for store in [PushInstallationKeychainStore(service: "", operations: harness.operations),
                      PushInstallationKeychainStore(account: "", operations: harness.operations)] {
            XCTAssertThrowsError(try store.transaction { _ in Data() }) {
                XCTAssertEqual($0 as? PushInstallationVaultError, .invalidKeychainNamespace)
            }
        }
        XCTAssertTrue(harness.calls.isEmpty)
    }

    func testIndependentKeychainStoresSerializeWholeReadModifyWrite() async throws {
        let harness = KeychainHarness()
        let first = PushInstallationVault(store: PushInstallationKeychainStore(operations: harness.operations),
                                          makeIdentity: { [installationId, key] in (installationId, key) })
        let second = PushInstallationVault(store: PushInstallationKeychainStore(operations: harness.operations),
                                           makeIdentity: { [installationId, key] in (installationId, key) })
        let hash = hashA
        let date = start
        let revisions = try await withThrowingTaskGroup(of: Int64.self) { group in
            for index in 0..<40 {
                let vault = index.isMultiple(of: 2) ? first : second
                group.addTask { try await vault.prepare(intentHash: hash, at: date, forceNewRevision: true).revision }
            }
            var values: [Int64] = []
            for try await revision in group { values.append(revision) }
            return values
        }
        XCTAssertEqual(revisions.sorted(), Array(1...Int64(40)))
        XCTAssertEqual(try decoded(try XCTUnwrap(harness.data)).revision, 40)
        XCTAssertEqual(harness.calls.filter { $0.name == "add" }.count, 1)
        XCTAssertEqual(harness.calls.filter { $0.name == "update" }.count, 39)
    }

    private func makeVault(_ store: any PushInstallationRecordStore) -> PushInstallationVault {
        PushInstallationVault(store: store, makeIdentity: { [installationId, key] in (installationId, key) })
    }

    private func encoded(_ record: PushInstallationRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(record)
    }

    private func decoded(_ data: Data) throws -> PushInstallationRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(PushInstallationRecord.self, from: data)
    }

    private func expect(_ expected: PushInstallationVaultError, file: StaticString = #filePath, line: UInt = #line,
                        _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? PushInstallationVaultError, expected, file: file, line: line) }
    }

    private func assertPrivateIdentity(_ query: [String: Any],
                                       service: String = "com.aproposmagazine.push-installation.v1",
                                       account: String = "installation", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String, file: file, line: line)
        XCTAssertEqual(query[kSecAttrService as String] as? String, service, file: file, line: line)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, account, file: file, line: line)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false, file: file, line: line)
        XCTAssertEqual(query[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, file: file, line: line)
    }
}

private enum FixtureError: Error, Equatable {
    case locked, writeFailed, identityMustNotBeRegenerated
}

private final class MemoryRecordStore: @unchecked Sendable, PushInstallationRecordStore {
    private let lock = NSLock()
    private var data: Data?
    var readError: Error?
    var writeError: Error?
    private(set) var readCount = 0
    private(set) var writeCount = 0

    init(data: Data? = nil) { self.data = data }

    func snapshot() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        if let readError { throw readError }
        let next = try update(data)
        if data == next { return next }
        if let writeError { throw writeError }
        data = next
        writeCount += 1
        return next
    }
}

private final class IdentityCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let id: String
    private let key: String
    private(set) var count = 0
    init(id: String, key: String) { self.id = id; self.key = key }
    func make() -> (String, String) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return (id, key)
    }
}

/// These closures implement a fake keychain, not wrappers around SecItem calls.
/// Production-store locking serializes access even across independently built stores.
private final class KeychainHarness: @unchecked Sendable {
    struct Call {
        var name: String
        var query: [String: Any]
        var attributes: [String: Any]?
    }
    var data: Data?
    var readStatus: OSStatus?
    var writeStatus: OSStatus = errSecSuccess
    var returnInvalidObject = false
    var calls: [Call] = []
    init(data: Data? = nil) { self.data = data }
    var operations: PushInstallationKeychainStore.Operations {
        .init(copyMatching: { [self] query in
            calls.append(Call(name: "read", query: query as! [String: Any]))
            if let readStatus, readStatus != errSecSuccess { return (readStatus, nil) }
            if returnInvalidObject { return (errSecSuccess, "wrong object" as CFString) }
            guard let data else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data as CFData)
        }, update: { [self] query, attributes in
            let fields = attributes as! [String: Any]
            calls.append(Call(name: "update", query: query as! [String: Any], attributes: fields))
            if writeStatus == errSecSuccess { data = fields[kSecValueData as String] as? Data }
            return writeStatus
        }, add: { [self] query in
            let fields = query as! [String: Any]
            calls.append(Call(name: "add", query: fields))
            if writeStatus == errSecSuccess { data = fields[kSecValueData as String] as? Data }
            return writeStatus
        })
    }
}
