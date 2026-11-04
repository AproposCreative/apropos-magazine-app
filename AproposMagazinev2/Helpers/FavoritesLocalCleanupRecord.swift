import CryptoKit
import Foundation

/// Retained local evidence, never membership or server authority. No article
/// payload, provider credential or deletion receipt is stored in this record.
struct FavoritesLocalCleanupRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case v2, v1, complete }
    enum Failure: Error, Equatable, Sendable {
        case invalidRecord, differentOriginal, changedSource, missingBegin, invalidLease, denied, unconfirmed, legacyDeleteUnavailable
    }
    nonisolated static let maximumBytes = 4_096
    let schemaVersion: Int
    let scope: String
    let ownerUID: String
    let membershipEpoch: Int64
    let requestID: String
    let transitionID: UUID
    let configurationDigest: String
    let namespace: String
    let cleanupID: UUID
    let v1SHA256: String
    let v1ByteCount: Int
    let v2SHA256: String
    let v2ByteCount: Int
    let v2Revision: String
    var phase: Phase

    nonisolated init(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint, v1: Data?, v2: Data?, revision: UUID?) throws {
        guard checkpoint.phase == .ledger,
              checkpoint.marker.binding.ownerUID == checkpoint.request.expectedUID,
              checkpoint.marker.binding.epoch == checkpoint.request.membershipEpoch,
              let owner = FavoritesContext.confirmed(userID: checkpoint.request.expectedUID).namespace, owner != .guest else {
            throw Failure.differentOriginal
        }
        schemaVersion = 1; scope = "reader-local-favorites-cleanup-v1"
        ownerUID = checkpoint.request.expectedUID; membershipEpoch = checkpoint.request.membershipEpoch
        requestID = checkpoint.request.requestID; transitionID = checkpoint.marker.transitionID
        configurationDigest = checkpoint.configurationDigest; namespace = owner.recordBinding
        cleanupID = UUID(); v1SHA256 = Self.digest(v1); v1ByteCount = v1?.count ?? 0
        v2SHA256 = Self.digest(v2); v2ByteCount = v2?.count ?? 0; v2Revision = revision?.uuidString ?? ""
        phase = .v2
        try validate()
    }

    nonisolated func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        checkpoint.phase == .ledger && ownerUID == checkpoint.request.expectedUID
            && membershipEpoch == checkpoint.request.membershipEpoch && requestID == checkpoint.request.requestID
            && transitionID == checkpoint.marker.transitionID && configurationDigest == checkpoint.configurationDigest
            && checkpoint.marker.binding.ownerUID == ownerUID && checkpoint.marker.binding.epoch == membershipEpoch
    }
    nonisolated func sameOriginal(as other: Self) -> Bool {
        var lhs = self, rhs = other; lhs.phase = .v2; rhs.phase = .v2
        return lhs == rhs
    }
    nonisolated func matchesV1(_ data: Data?) -> Bool { Self.matches(data, digest: v1SHA256, count: v1ByteCount) }
    nonisolated func matchesV2(_ data: Data?) -> Bool { Self.matches(data, digest: v2SHA256, count: v2ByteCount) }
    nonisolated static func digest(_ data: Data?) -> String {
        guard let data else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated private static func matches(_ data: Data?, digest: String, count: Int) -> Bool {
        guard let data else { return digest.isEmpty && count == 0 }
        return data.count == count && Self.digest(data) == digest
    }
    nonisolated private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    nonisolated private func validate() throws {
        let request = try ReaderAccountDeletionContract.Request(expectedUID: ownerUID, membershipEpoch: membershipEpoch)
        guard schemaVersion == 1, scope == "reader-local-favorites-cleanup-v1", requestID == request.requestID,
              FavoritesContext.confirmed(userID: ownerUID).namespace?.recordBinding == namespace,
              Self.validDigest(configurationDigest),
              (v1SHA256.isEmpty && v1ByteCount == 0 || Self.validDigest(v1SHA256) && (1...FavoritesRecordCodec.maximumRecordBytes).contains(v1ByteCount)),
              (v2SHA256.isEmpty && v2ByteCount == 0 && v2Revision.isEmpty
                || Self.validDigest(v2SHA256) && (1...FavoritesRecordCodec.maximumRecordBytes).contains(v2ByteCount)
                    && UUID(uuidString: v2Revision)?.uuidString == v2Revision) else { throw Failure.invalidRecord }
    }
    nonisolated static func encode(_ record: Self) throws -> Data {
        try record.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard data.count <= maximumBytes else { throw Failure.invalidRecord }
        return data
    }
    nonisolated static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.invalidRecord }
        let record = try JSONDecoder().decode(Self.self, from: data)
        // Our records have one canonical encoding. This also rejects unknown or
        // repeated keys and non-integral/ambiguous field representations.
        guard try encode(record) == data else { throw Failure.invalidRecord }
        return record
    }
}
