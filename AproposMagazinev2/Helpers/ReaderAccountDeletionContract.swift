import CryptoKit
import Foundation

/// Wire boundary for the staged reader-only worker. This type performs no I/O
/// and cannot authorize deletion or attest that deployed writers are fenced.
enum ReaderAccountDeletionContract {
    static let scope = "reader-cloud-slice-v1"
    static let unresolved = [
        "shared_profile_fields", "legacy_or_nested_data",
        "device_and_icloud_data", "push_membership_and_pending_delivery"
    ]
    static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    enum Failure: Error, Equatable { case invalidRequest, invalidReceipt }

    struct Request: Codable, Equatable, Sendable {
        let expectedUID: String
        let membershipEpoch: Int64

        init(expectedUID: String, membershipEpoch: Int64) throws {
            let bytes = Array(expectedUID.utf8)
            guard (1...128).contains(bytes.count), bytes.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0)
                    || (48...57).contains($0) || $0 == 95 || $0 == 45
            }), (1...maximumSafeInteger).contains(membershipEpoch) else { throw Failure.invalidRequest }
            self.expectedUID = expectedUID
            self.membershipEpoch = membershipEpoch
        }

        private enum CodingKeys: String, CodingKey { case expectedUID, membershipEpoch }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(expectedUID: values.decode(String.self, forKey: .expectedUID),
                          membershipEpoch: values.decode(Int64.self, forKey: .membershipEpoch))
        }

        /// Matches JSON.stringify([SCOPE, uid, epoch]) in the actual JS worker.
        /// Validated ASCII UIDs contain no characters requiring JSON escaping.
        var requestID: String {
            let canonical = "[\"\(scope)\",\"\(expectedUID)\",\(membershipEpoch)]"
            return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    enum Status: String, Decodable, Sendable {
        case pending, paused, scopedCloudDataRemoved
    }

    struct Receipt: Decodable, Equatable, Sendable {
        let requestID: String
        let scope: String
        let status: Status
        let accountDeletionComplete: Bool
        let unresolved: [String]
        let removedFavoriteDocuments: Int64?
        let code: String?
    }

    private static let pausedCodes: Set<String> = [
        "transport_unavailable", "reader_membership_mismatch", "reader_boundary_changed",
        "reader_boundary_unverified", "reader_boundary_unavailable", "invalid_cleanup_path",
        "invalid_cleanup_page", "invalid_deletion_record", "invalid_clock", "invalid_request"
    ]

    /// A scoped cloud receipt is deliberately never a completed-account result.
    /// Reject changed schemas so a future server cannot silently broaden this claim.
    static func decodeReceipt(data: Data, for request: Request) throws -> Receipt {
        guard !data.isEmpty, data.count <= 16_384 else { throw Failure.invalidReceipt }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys).isSubset(of: ["requestID", "scope", "status", "accountDeletionComplete",
                                                "unresolved", "removedFavoriteDocuments", "code"]) else {
                throw Failure.invalidReceipt
            }
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            guard receipt.requestID == request.requestID, receipt.scope == scope,
                  receipt.accountDeletionComplete == false, receipt.unresolved == unresolved else {
                throw Failure.invalidReceipt
            }
            if let count = receipt.removedFavoriteDocuments {
                guard (0...maximumSafeInteger).contains(count) else { throw Failure.invalidReceipt }
            }
            switch receipt.status {
            case .scopedCloudDataRemoved:
                guard receipt.removedFavoriteDocuments != nil, receipt.code == nil else { throw Failure.invalidReceipt }
            case .pending:
                guard receipt.code == nil else { throw Failure.invalidReceipt }
            case .paused:
                guard let code = receipt.code, pausedCodes.contains(code),
                      receipt.removedFavoriteDocuments == nil else { throw Failure.invalidReceipt }
            }
            return receipt
        } catch { throw Failure.invalidReceipt }
    }

    // Explicit additional server scope. A v1 parent receipt does not itself
    // request this phase or authorize any local/identity cleanup.
    static let ledgerScope = "reader-mutation-ledger-cleanup-v1"
    static let ledgerUnresolved = unresolved + [
        "local_mutation_journal", "membership_and_deletion_job_retention"
    ]

    struct LedgerRequest: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let scope: String
        let expectedUID: String
        let membershipEpoch: Int64
        let parentRequestID: String

        init(expectedUID: String, membershipEpoch: Int64, parentRequestID: String) throws {
            let parent = try Request(expectedUID: expectedUID, membershipEpoch: membershipEpoch)
            guard parentRequestID == parent.requestID else { throw Failure.invalidRequest }
            self.schemaVersion = 1
            self.scope = ReaderAccountDeletionContract.ledgerScope
            self.expectedUID = expectedUID
            self.membershipEpoch = membershipEpoch
            self.parentRequestID = parentRequestID
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, scope, expectedUID, membershipEpoch, parentRequestID
        }

        init(from decoder: Decoder) throws {
            do {
                let all = try decoder.container(keyedBy: LedgerCodingKey.self)
                guard Set(all.allKeys.map(\.stringValue)) == [
                    "schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID"
                ] else { throw Failure.invalidRequest }
                let values = try decoder.container(keyedBy: CodingKeys.self)
                guard try values.decode(Int.self, forKey: .schemaVersion) == 1,
                      try values.decode(String.self, forKey: .scope) == ReaderAccountDeletionContract.ledgerScope else {
                    throw Failure.invalidRequest
                }
                try self.init(expectedUID: values.decode(String.self, forKey: .expectedUID),
                              membershipEpoch: values.decode(Int64.self, forKey: .membershipEpoch),
                              parentRequestID: values.decode(String.self, forKey: .parentRequestID))
            } catch { throw Failure.invalidRequest }
        }

        /// Matches the actual worker's [scope, parentRequestID, UID, epoch] hash.
        var requestID: String {
            let canonical = "[\"\(scope)\",\"\(parentRequestID)\",\"\(expectedUID)\",\(membershipEpoch)]"
            return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct LedgerCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    enum LedgerStatus: String, Decodable, Sendable {
        case pending, paused, ledgerDataRemoved
    }

    struct LedgerReceipt: Decodable, Equatable, Sendable {
        let requestID: String
        let parentRequestID: String?
        let scope: String
        let status: LedgerStatus
        let accountDeletionComplete: Bool
        let unresolved: [String]
        let removedReceiptDocuments: Int64?
        let removedRevisionDocuments: Int64?
        let code: String?
    }

    private static let ledgerPausedCodes = pausedCodes.union([
        "parent_cleanup_required", "invalid_ledger_record"
    ])

    /// Accept only actual full store receipts or bounded worker responses. A
    /// bounded pending/paused result is bound by its deterministic child ID;
    /// missing parent/counters are never filled in as server-provided evidence.
    static func decodeLedgerReceipt(data: Data, for request: LedgerRequest) throws -> LedgerReceipt {
        guard !data.isEmpty, data.count <= 16_384 else { throw Failure.invalidReceipt }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.invalidReceipt
            }
            let receipt = try JSONDecoder().decode(LedgerReceipt.self, from: data)
            guard receipt.requestID == request.requestID, receipt.scope == ledgerScope,
                  receipt.accountDeletionComplete == false, receipt.unresolved == ledgerUnresolved else {
                throw Failure.invalidReceipt
            }
            let base: Set<String> = ["requestID", "scope", "status", "accountDeletionComplete", "unresolved"]
            let full = base.union(["parentRequestID", "removedReceiptDocuments", "removedRevisionDocuments"])
            let fields = Set(object.keys)
            switch receipt.status {
            case .pending:
                guard fields == base || fields == full else { throw Failure.invalidReceipt }
            case .paused:
                guard fields == base.union(["code"]), let code = receipt.code,
                      ledgerPausedCodes.contains(code) else { throw Failure.invalidReceipt }
            case .ledgerDataRemoved:
                guard fields == full else { throw Failure.invalidReceipt }
            }
            if fields == full {
                guard receipt.parentRequestID == request.parentRequestID,
                      let receiptCount = receipt.removedReceiptDocuments,
                      let revisionCount = receipt.removedRevisionDocuments,
                      (0...maximumSafeInteger).contains(receiptCount),
                      (0...maximumSafeInteger).contains(revisionCount) else { throw Failure.invalidReceipt }
            }
            return receipt
        } catch { throw Failure.invalidReceipt }
    }

    // One explicitly inventoried installation only. Preparation is a historical
    // observation; retirement needs a separate action and fresh credentials.
    static let pushPreparationScope = "reader-push-installation-prepare-v1"
    static let pushScope = "reader-push-installation-retirement-v1"
    static let pushUnresolved = ledgerUnresolved + [
        "push_installation_inventory", "historical_push_material",
        "admitted_or_inflight_deliveries", "push_retirement_job_retention"
    ]

    struct PushCounters: Codable, Equatable, Sendable {
        let ownerEpoch: Int64
        let revision: Int64
        let clientRevision: Int64
        init(ownerEpoch: Int64, revision: Int64, clientRevision: Int64) throws {
            guard [ownerEpoch, revision, clientRevision].allSatisfy({ $0 > 0 && $0 < maximumSafeInteger }) else {
                throw Failure.invalidRequest
            }
            self.ownerEpoch = ownerEpoch; self.revision = revision; self.clientRevision = clientRevision
        }
        private enum CodingKeys: String, CodingKey { case ownerEpoch, revision, clientRevision }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["ownerEpoch", "revision", "clientRevision"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(ownerEpoch: c.decode(Int64.self, forKey: .ownerEpoch), revision: c.decode(Int64.self, forKey: .revision),
                          clientRevision: c.decode(Int64.self, forKey: .clientRevision))
        }
    }

    struct PushSnapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let requestId: String
        let installationId: String
        let appId: String
        let ownerUID: String
        let ownerEpoch: Int64
        let revision: Int64
        let clientRevision: Int64
        let stateDigest: String
        init(requestId: String, installationId: String, appId: String, ownerUID: String,
             ownerEpoch: Int64, revision: Int64, clientRevision: Int64, stateDigest: String) throws {
            _ = try PushCounters(ownerEpoch: ownerEpoch, revision: revision, clientRevision: clientRevision)
            _ = try Request(expectedUID: ownerUID, membershipEpoch: 1)
            guard PushRegistrationValidation.validID(installationId), validPushRequestID(requestId),
                  !appId.isEmpty, appId.utf8.count <= 256, appId.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  PushRegistrationValidation.validHash(stateDigest) else { throw Failure.invalidRequest }
            self.schemaVersion = 1; self.requestId = requestId; self.installationId = installationId; self.appId = appId
            self.ownerUID = ownerUID; self.ownerEpoch = ownerEpoch; self.revision = revision
            self.clientRevision = clientRevision; self.stateDigest = stateDigest
        }
        private enum CodingKeys: String, CodingKey {
            case schemaVersion, requestId, installationId, appId, ownerUID, ownerEpoch, revision, clientRevision, stateDigest
        }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["schemaVersion", "requestId", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "stateDigest"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidRequest }
            try self.init(requestId: c.decode(String.self, forKey: .requestId), installationId: c.decode(String.self, forKey: .installationId),
                appId: c.decode(String.self, forKey: .appId), ownerUID: c.decode(String.self, forKey: .ownerUID),
                ownerEpoch: c.decode(Int64.self, forKey: .ownerEpoch), revision: c.decode(Int64.self, forKey: .revision),
                clientRevision: c.decode(Int64.self, forKey: .clientRevision), stateDigest: c.decode(String.self, forKey: .stateDigest))
        }
    }

    struct PushInstallation: Codable, Equatable, Sendable {
        let installationId: String
        let key: String
        let requestId: String
        let expected: PushCounters
        let snapshot: PushSnapshot?
        init(installationId: String, key: String, requestId: String, expected: PushCounters, snapshot: PushSnapshot? = nil) throws {
            guard PushRegistrationValidation.validID(installationId), PushRegistrationValidation.validPrivateValue(key),
                  validPushRequestID(requestId) else { throw Failure.invalidRequest }
            if let snapshot {
                guard snapshot.installationId == installationId, snapshot.requestId == requestId,
                      snapshot.ownerEpoch == expected.ownerEpoch, snapshot.revision == expected.revision,
                      snapshot.clientRevision == expected.clientRevision else { throw Failure.invalidRequest }
            }
            self.installationId = installationId; self.key = key; self.requestId = requestId; self.expected = expected; self.snapshot = snapshot
        }
        private enum CodingKeys: String, CodingKey { case installationId, key, requestId, expected, snapshot }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let hasSnapshot = c.contains(.snapshot)
            try exactKeys(decoder, Set(["installationId", "key", "requestId", "expected"] + (hasSnapshot ? ["snapshot"] : [])))
            try self.init(installationId: c.decode(String.self, forKey: .installationId), key: c.decode(String.self, forKey: .key),
                requestId: c.decode(String.self, forKey: .requestId), expected: c.decode(PushCounters.self, forKey: .expected),
                snapshot: hasSnapshot ? c.decode(PushSnapshot.self, forKey: .snapshot) : nil)
        }
    }

    struct PushRequest: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let scope: String
        let expectedUID: String
        let membershipEpoch: Int64
        let parentRequestID: String
        let ledgerRequestID: String
        let installation: PushInstallation
        init(expectedUID: String, membershipEpoch: Int64, parentRequestID: String, ledgerRequestID: String,
             installation: PushInstallation, scope: String = "reader-push-installation-prepare-v1") throws {
            let ledger = try LedgerRequest(expectedUID: expectedUID, membershipEpoch: membershipEpoch, parentRequestID: parentRequestID)
            guard ledgerRequestID == ledger.requestID,
                  (scope == pushPreparationScope && installation.snapshot == nil) ||
                    (scope == pushScope && installation.snapshot?.ownerUID == expectedUID) else { throw Failure.invalidRequest }
            self.schemaVersion = 1; self.scope = scope; self.expectedUID = expectedUID; self.membershipEpoch = membershipEpoch
            self.parentRequestID = parentRequestID; self.ledgerRequestID = ledgerRequestID; self.installation = installation
        }
        private enum CodingKeys: String, CodingKey {
            case schemaVersion, scope, expectedUID, membershipEpoch, parentRequestID, ledgerRequestID, installation
        }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID", "ledgerRequestID", "installation"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidRequest }
            try self.init(expectedUID: c.decode(String.self, forKey: .expectedUID), membershipEpoch: c.decode(Int64.self, forKey: .membershipEpoch),
                parentRequestID: c.decode(String.self, forKey: .parentRequestID), ledgerRequestID: c.decode(String.self, forKey: .ledgerRequestID),
                installation: c.decode(PushInstallation.self, forKey: .installation), scope: c.decode(String.self, forKey: .scope))
        }
        /// The caller supplies the accepted original snapshot explicitly. This
        /// never fetches or replaces a snapshot after an uncertain retirement.
        func committing(_ snapshot: PushSnapshot) throws -> Self {
            guard scope == pushPreparationScope else { throw Failure.invalidRequest }
            return try .init(expectedUID: expectedUID, membershipEpoch: membershipEpoch, parentRequestID: parentRequestID,
                ledgerRequestID: ledgerRequestID, installation: .init(installationId: installation.installationId,
                    key: installation.key, requestId: installation.requestId, expected: installation.expected, snapshot: snapshot), scope: pushScope)
        }
        var requestID: String {
            let canonical = "[\"\(pushScope)\",\"\(parentRequestID)\",\"\(ledgerRequestID)\",\"\(expectedUID)\",\(membershipEpoch),\"\(installation.installationId)\"]"
            return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct PushPreparationReceipt: Decodable, Equatable, Sendable {
        let schemaVersion: Int
        let scope: String
        let expectedUID: String
        let membershipEpoch: Int64
        let parentRequestID: String
        let ledgerRequestID: String
        let installationId: String
        let status: String
        let preparedOnly: Bool
        let retirementComplete: Bool
        let accountDeletionComplete: Bool
        let historicalMaterialComplete: Bool
        let deliveriesRecalled: Bool
        let unresolved: [String]
        let snapshot: PushSnapshot
    }
    struct PushRetirementReceipt: Decodable, Equatable, Sendable {
        let schemaVersion: Int
        let status: String
        let requestId: String
        let installationId: String
        let ownerUID: String
        let appId: String
        let ownerEpoch: Int64
        let revision: Int64
        let clientRevision: Int64
        let retiredAtMs: Int64
        let retiredChallenges: Int64
        let removedTokenOwners: Int64
        let preservedForeignChallenges: Int64
        let preservedForeignTokenOwners: Int64
        let preservedUnprovenTokenOwners: Int64
        let historicalMaterialComplete: Bool
        let accountDeletionComplete: Bool
        let deliveriesRecalled: Bool
    }
    struct PushReceipt: Decodable, Equatable, Sendable {
        let requestID: String
        let scope: String
        let parentRequestID: String
        let ledgerRequestID: String
        let installationId: String
        let status: String
        let accountDeletionComplete: Bool
        let historicalMaterialComplete: Bool
        let deliveriesRecalled: Bool
        let unresolved: [String]
        let retirementReceipt: PushRetirementReceipt
    }

    static func decodePushPreparationReceipt(data: Data, for request: PushRequest, appID: String) throws -> PushPreparationReceipt {
        do {
            let object = try strictPushObject(data)
            guard Set(object.keys) == ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID", "ledgerRequestID", "installationId",
                "status", "preparedOnly", "retirementComplete", "accountDeletionComplete", "historicalMaterialComplete", "deliveriesRecalled", "unresolved", "snapshot"],
                request.scope == pushPreparationScope else { throw Failure.invalidReceipt }
            let r = try JSONDecoder().decode(PushPreparationReceipt.self, from: data), s = r.snapshot, original = request.installation
            guard r.schemaVersion == 1, r.scope == pushPreparationScope, r.expectedUID == request.expectedUID,
                  r.membershipEpoch == request.membershipEpoch, r.parentRequestID == request.parentRequestID,
                  r.ledgerRequestID == request.ledgerRequestID, r.installationId == original.installationId,
                  r.status == "prepared", r.preparedOnly, !r.retirementComplete, !r.accountDeletionComplete,
                  !r.historicalMaterialComplete, !r.deliveriesRecalled, r.unresolved == pushUnresolved,
                  s.appId == appID, s.ownerUID == request.expectedUID, s.installationId == original.installationId,
                  s.requestId == original.requestId, s.ownerEpoch == original.expected.ownerEpoch,
                  s.revision == original.expected.revision, s.clientRevision == original.expected.clientRevision else { throw Failure.invalidReceipt }
            return r
        } catch { throw Failure.invalidReceipt }
    }
    static func decodePushReceipt(data: Data, for request: PushRequest, appID: String) throws -> PushReceipt {
        do {
            let object = try strictPushObject(data)
            guard Set(object.keys) == ["requestID", "scope", "parentRequestID", "ledgerRequestID", "installationId", "status",
                "accountDeletionComplete", "historicalMaterialComplete", "deliveriesRecalled", "unresolved", "retirementReceipt"],
                  let child = object["retirementReceipt"] as? [String: Any], Set(child.keys) == ["schemaVersion", "status", "requestId", "installationId",
                    "ownerUID", "appId", "ownerEpoch", "revision", "clientRevision", "retiredAtMs", "retiredChallenges", "removedTokenOwners",
                    "preservedForeignChallenges", "preservedForeignTokenOwners", "preservedUnprovenTokenOwners", "historicalMaterialComplete",
                    "accountDeletionComplete", "deliveriesRecalled"], request.scope == pushScope,
                  request.installation.snapshot?.appId == appID else { throw Failure.invalidReceipt }
            let r = try JSONDecoder().decode(PushReceipt.self, from: data), c = r.retirementReceipt, original = request.installation
            guard r.requestID == request.requestID, r.scope == pushScope, r.parentRequestID == request.parentRequestID,
                  r.ledgerRequestID == request.ledgerRequestID, r.installationId == original.installationId,
                  r.status == "installationRetired", !r.accountDeletionComplete, !r.historicalMaterialComplete,
                  !r.deliveriesRecalled, r.unresolved == pushUnresolved, c.schemaVersion == 1, c.status == "retired",
                  c.requestId == original.requestId, c.installationId == original.installationId, c.ownerUID == request.expectedUID,
                  c.appId == appID, c.ownerEpoch == original.expected.ownerEpoch, c.revision == original.expected.revision + 1,
                  c.clientRevision == original.expected.clientRevision, (0...maximumSafeInteger).contains(c.retiredAtMs),
                  [c.retiredChallenges, c.removedTokenOwners, c.preservedForeignChallenges, c.preservedForeignTokenOwners,
                    c.preservedUnprovenTokenOwners].allSatisfy({ (0...2).contains($0) }),
                  c.retiredChallenges + c.preservedForeignChallenges <= 2,
                  c.removedTokenOwners + c.preservedForeignTokenOwners + c.preservedUnprovenTokenOwners <= 2,
                  !c.historicalMaterialComplete, !c.accountDeletionComplete, !c.deliveriesRecalled else { throw Failure.invalidReceipt }
            return r
        } catch { throw Failure.invalidReceipt }
    }
    private static func validPushRequestID(_ value: String) -> Bool {
        PushRegistrationValidation.matches(value, "^[a-zA-Z0-9_-]{16,128}$")
    }
    private static func exactKeys(_ decoder: Decoder, _ expected: Set<String>) throws {
        let all = try decoder.container(keyedBy: LedgerCodingKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == expected else { throw Failure.invalidRequest }
    }
    private static func strictPushObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 16_384, String(data: data, encoding: .utf8) != nil else { throw Failure.invalidReceipt }
        var scanner = PushJSONKeys(bytes: Array(data))
        try scanner.scan()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidReceipt }
        return object
    }
    /// JSONDecoder/Foundation collapse duplicate keys. Check decoded keys before
    /// decoding, including escaped aliases, so neither nested receipts nor their
    /// claimed completion flags can be ambiguously interpreted.
    private struct PushJSONKeys {
        let bytes: [UInt8]
        var index = 0
        var nodes = 0
        mutating func scan() throws {
            try value(depth: 0); whitespace()
            guard index == bytes.count else { throw Failure.invalidReceipt }
        }
        mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ byte: UInt8) throws {
            whitespace(); guard index < bytes.count && bytes[index] == byte else { throw Failure.invalidReceipt }; index += 1
        }
        mutating func string() throws -> String {
            whitespace(); let start = index; try take(34)
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                if byte == 92 { guard index < bytes.count else { throw Failure.invalidReceipt }; index += 1 }
            }
            throw Failure.invalidReceipt
        }
        mutating func value(depth: Int) throws {
            nodes += 1; whitespace()
            guard depth <= 16, nodes <= 2_048, index < bytes.count else { throw Failure.invalidReceipt }
            switch bytes[index] {
            case 123:
                index += 1; whitespace(); var keys = Set<String>()
                if index < bytes.count && bytes[index] == 125 { index += 1; return }
                while true {
                    let key = try string(); guard keys.insert(key).inserted else { throw Failure.invalidReceipt }
                    try take(58); try value(depth: depth + 1); whitespace()
                    if index < bytes.count && bytes[index] == 125 { index += 1; return }
                    try take(44)
                }
            case 91:
                index += 1; whitespace()
                if index < bytes.count && bytes[index] == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); whitespace()
                    if index < bytes.count && bytes[index] == 93 { index += 1; return }
                    try take(44)
                }
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw Failure.invalidReceipt }
            }
        }
    }
}
