import Foundation
import Security

/// The only push registration state persisted on this installation. Transport tokens,
/// challenge nonces stay outside this private identity record. A separately validated
/// server ACK may retain the original owner/counters; it is historical evidence, not authority.
struct PushInstallationRecord: Codable, Equatable, Sendable {
    static let maximumRevision: Int64 = 9_007_199_254_740_991

    var schemaVersion: Int
    var installationId: String
    var key: String
    var revision: Int64
    var intentHash: String?
    var revisionStartedAt: Date?
    var acknowledgedBinding: PushAcknowledgedInstallationBinding?

    init(schemaVersion: Int = 1, installationId: String, key: String, revision: Int64 = 0,
         intentHash: String? = nil, revisionStartedAt: Date? = nil,
         acknowledgedBinding: PushAcknowledgedInstallationBinding? = nil) {
        self.schemaVersion = schemaVersion
        self.installationId = installationId
        self.key = key
        self.revision = revision
        self.intentHash = intentHash
        self.revisionStartedAt = revisionStartedAt
        self.acknowledgedBinding = acknowledgedBinding
    }

    func validate() throws {
        guard schemaVersion == 1,
              Self.matches(installationId, "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"),
              Self.matches(key, "^[A-Za-z0-9_-]{40,128}$"),
              revision >= 0, revision <= Self.maximumRevision else {
            throw PushInstallationVaultError.invalidRecord
        }
        if revision == 0 {
            guard intentHash == nil, revisionStartedAt == nil, acknowledgedBinding == nil else {
                throw PushInstallationVaultError.invalidRecord
            }
        } else {
            guard let intentHash, Self.isIntentHash(intentHash),
                  let revisionStartedAt, Self.isValidDate(revisionStartedAt) else {
                throw PushInstallationVaultError.invalidRecord
            }
        }
        if let acknowledgedBinding {
            do { try acknowledgedBinding.validate() }
            catch { throw PushInstallationVaultError.invalidRecord }
            guard acknowledgedBinding.installationId == installationId,
                  acknowledgedBinding.clientRevision == revision else {
                throw PushInstallationVaultError.invalidRecord
            }
        }
    }

    static func isIntentHash(_ value: String) -> Bool {
        matches(value, "^[0-9a-f]{64}$")
    }

    static func isValidDate(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite && seconds > 0 && (seconds * 1_000).isFinite
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

enum PushInstallationVaultError: Error, Equatable {
    case invalidRecord
    case invalidIntentHash
    case invalidClock
    case revisionExhausted
    case identityGenerationFailed
    case invalidKeychainNamespace
    case invalidKeychainResult
    case acknowledgedBindingConflict
    case bindingLeaseExpired
    case readbackMismatch
    case keychainRead(OSStatus)
    case keychainWrite(OSStatus)
}

/// Implementations must serialize the entire read, update and durable write across
/// every instance sharing a record. Only confirmed absence may be passed as nil.
/// A thrown read/update must leave the previous record intact. A physical write
/// may have completed before a later readback fails; callers must not publish it.
protocol PushInstallationRecordStore: Sendable {
    func transaction(_ update: (Data?) throws -> Data) throws -> Data
    func readExistingData() throws -> Data?
    func transactionAndReadback(_ update: (Data?) throws -> Data) throws -> Data
}

private struct PushInstallationReadCapture: Error { let data: Data? }

extension PushInstallationRecordStore {
    /// Existing conformers retain their own physical serialization, and aborting
    /// the update avoids manufacturing a record or invoking any write operation.
    func readExistingData() throws -> Data? {
        do {
            _ = try transaction { throw PushInstallationReadCapture(data: $0) }
            throw PushInstallationVaultError.invalidRecord
        } catch let capture as PushInstallationReadCapture { return capture.data }
    }

    /// Compatibility for injected stores. Each operation uses its own physical
    /// boundary; an intervening replacement must fail exact byte comparison.
    /// The real Keychain adapter overrides this with one lock across both phases.
    func transactionAndReadback(_ update: (Data?) throws -> Data) throws -> Data {
        let expected = try transaction(update)
        guard let observed = try readExistingData(), observed == expected else {
            throw PushInstallationVaultError.readbackMismatch
        }
        return observed
    }
}

actor PushInstallationVault {
    private let store: any PushInstallationRecordStore
    private let makeIdentity: @Sendable () throws -> (String, String)

    init(store: any PushInstallationRecordStore,
         makeIdentity: @escaping @Sendable () throws -> (String, String) = { try PushInstallationVault.makeIdentity() }) {
        self.store = store
        self.makeIdentity = makeIdentity
    }

    /// Persists a monotonic revision before returning anything that can be sent.
    /// Repeating an unchanged intent preserves the original challenge lifetime.
    func prepare(intentHash: String, at date: Date, forceNewRevision: Bool = false) async throws -> PushInstallationRecord {
        guard PushInstallationRecord.isIntentHash(intentHash) else {
            throw PushInstallationVaultError.invalidIntentHash
        }
        guard PushInstallationRecord.isValidDate(date) else {
            throw PushInstallationVaultError.invalidClock
        }
        let createIdentity = makeIdentity
        let stored = try store.transaction { data in
            var record: PushInstallationRecord
            if let data {
                record = try Self.decode(data)
            } else {
                let identity = try createIdentity()
                record = PushInstallationRecord(installationId: identity.0, key: identity.1)
                try record.validate()
            }
            if let data, record.revision > 0, record.intentHash == intentHash, !forceNewRevision {
                return data
            }
            guard record.revision < PushInstallationRecord.maximumRevision else {
                throw PushInstallationVaultError.revisionExhausted
            }
            if let started = record.revisionStartedAt, date < started {
                throw PushInstallationVaultError.invalidClock
            }
            record.revision += 1
            record.intentHash = intentHash
            record.revisionStartedAt = date
            record.acknowledgedBinding = nil
            try record.validate()
            return try Self.encode(record)
        }
        return try Self.decode(stored)
    }

    /// Historical persisted evidence only. Absence never generates identity,
    /// advances a revision, or grants current account/server authority.
    func readExisting() async throws -> PushInstallationRecord? {
        try Task.checkCancellation()
        let data = try store.readExistingData()
        let record = try data.map(Self.decode)
        try Task.checkCancellation()
        return record
    }

    func acknowledge(_ binding: PushAcknowledgedInstallationBinding, original: PushInstallationRecord,
                     lease: PushRegistrationBindingLease) async throws -> PushInstallationRecord {
        try Self.checkBindingAccess(lease)
        try original.validate()
        try binding.validate()
        guard original.revision > 0, binding.installationId == original.installationId,
              binding.clientRevision == original.revision else {
            throw PushInstallationVaultError.acknowledgedBindingConflict
        }
        var expectedBytes: Data?
        let stored = try store.transactionAndReadback { data in
            try Self.checkBindingAccess(lease)
            guard let data else { throw PushInstallationVaultError.acknowledgedBindingConflict }
            var record = try Self.decode(data)
            guard record.installationId == original.installationId, record.key == original.key,
                  record.revision == original.revision, record.intentHash == original.intentHash,
                  record.revisionStartedAt == original.revisionStartedAt else {
                throw PushInstallationVaultError.acknowledgedBindingConflict
            }
            if let previous = record.acknowledgedBinding {
                guard previous.schemaVersion == binding.schemaVersion,
                      previous.installationId == binding.installationId,
                      previous.appId == binding.appId, previous.ownerUID == binding.ownerUID,
                      previous.ownerEpoch == binding.ownerEpoch, previous.revision == binding.revision,
                      previous.clientRevision == binding.clientRevision,
                      previous.status == binding.status || (previous.status == .pending && binding.status == .active) else {
                    throw PushInstallationVaultError.acknowledgedBindingConflict
                }
            }
            if record.acknowledgedBinding == binding {
                try Self.checkBindingAccess(lease)
                expectedBytes = data
                return data
            }
            record.acknowledgedBinding = binding
            try record.validate()
            let next = try Self.encode(record)
            try Self.checkBindingAccess(lease)
            expectedBytes = next
            return next
        }
        guard expectedBytes == stored else { throw PushInstallationVaultError.readbackMismatch }
        let result = try Self.decode(stored)
        guard result.acknowledgedBinding == binding else {
            throw PushInstallationVaultError.readbackMismatch
        }
        try Self.checkBindingAccess(lease)
        return result
    }

    private static func checkBindingAccess(_ lease: PushRegistrationBindingLease) throws {
        try Task.checkCancellation()
        guard lease.isValid else { throw PushInstallationVaultError.bindingLeaseExpired }
    }

    private static func decode(_ data: Data) throws -> PushInstallationRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            guard data.count <= 4_096,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys).isSubset(of: ["schemaVersion", "installationId", "key", "revision", "intentHash", "revisionStartedAt", "acknowledgedBinding"]) else {
                throw PushInstallationVaultError.invalidRecord
            }
            if let binding = object["acknowledgedBinding"], !(binding is NSNull) {
                guard let fields = binding as? [String: Any],
                      Set(fields.keys).isSubset(of: ["schemaVersion", "installationId", "appId", "ownerUID",
                                                    "ownerEpoch", "revision", "clientRevision", "status"]) else {
                    throw PushInstallationVaultError.invalidRecord
                }
            }
            let record = try decoder.decode(PushInstallationRecord.self, from: data)
            try record.validate()
            return record
        } catch {
            throw PushInstallationVaultError.invalidRecord
        }
    }

    private static func encode(_ record: PushInstallationRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(record)
    }

    private static func makeIdentity() throws -> (String, String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PushInstallationVaultError.identityGenerationFailed
        }
        return (UUID().uuidString.lowercased(), bytes.map { String(format: "%02x", $0) }.joined())
    }
}

/// No keychain work occurs during initialization. Every Security operation is
/// injectable so hermetic tests never touch the user's keychain.
struct PushInstallationKeychainStore: @unchecked Sendable, PushInstallationRecordStore {
    struct Operations: @unchecked Sendable {
        var copyMatching: (CFDictionary) -> (OSStatus, CFTypeRef?)
        var update: (CFDictionary, CFDictionary) -> OSStatus
        var add: (CFDictionary) -> OSStatus

        static var system: Operations {
            Operations(copyMatching: { query in
                var value: CFTypeRef?
                let status = SecItemCopyMatching(query, &value)
                return (status, value)
            }, update: { SecItemUpdate($0, $1) }, add: { SecItemAdd($0, nil) })
        }
    }

    // Access to the injected operations and complete transaction is serialized,
    // including independently constructed vault/store instances in this process.
    private static let transactionLock = NSLock()
    private let service: String
    private let account: String
    private let operations: Operations

    init(service: String = "com.aproposmagazine.push-installation.v1", account: String = "installation",
         operations: Operations = .system) {
        self.service = service
        self.account = account
        self.operations = operations
    }

    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        try performTransaction(update, requiresReadback: false)
    }

    func transactionAndReadback(_ update: (Data?) throws -> Data) throws -> Data {
        try performTransaction(update, requiresReadback: true)
    }

    private func performTransaction(_ update: (Data?) throws -> Data, requiresReadback: Bool) throws -> Data {
        Self.transactionLock.lock()
        defer { Self.transactionLock.unlock() }
        guard !service.isEmpty, service.utf8.count <= 256,
              !account.isEmpty, account.utf8.count <= 256 else {
            throw PushInstallationVaultError.invalidKeychainNamespace
        }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (readStatus, object) = operations.copyMatching(query as CFDictionary)
        let previous: Data?
        switch readStatus {
        case errSecSuccess:
            guard let data = object as? Data else {
                throw PushInstallationVaultError.invalidKeychainResult
            }
            previous = data
        case errSecItemNotFound:
            previous = nil
        default:
            throw PushInstallationVaultError.keychainRead(readStatus)
        }
        let next = try update(previous)
        if let previous, next == previous {
            // The same locked initial read is already exact evidence for an
            // idempotent ACK; no physical write or artificial revision occurs.
            return previous
        }
        let writeStatus: OSStatus
        if previous != nil {
            let attributes: [String: Any] = [
                kSecValueData as String: next,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            writeStatus = operations.update(identity as CFDictionary, attributes as CFDictionary)
        } else {
            var attributes = identity
            attributes[kSecValueData as String] = next
            writeStatus = operations.add(attributes as CFDictionary)
        }
        guard writeStatus == errSecSuccess else {
            throw PushInstallationVaultError.keychainWrite(writeStatus)
        }
        if requiresReadback {
            let (status, value) = operations.copyMatching(query as CFDictionary)
            guard status == errSecSuccess else { throw PushInstallationVaultError.keychainRead(status) }
            guard let observed = value as? Data else { throw PushInstallationVaultError.invalidKeychainResult }
            guard observed == next else { throw PushInstallationVaultError.readbackMismatch }
            return observed
        }
        return next
    }
}
