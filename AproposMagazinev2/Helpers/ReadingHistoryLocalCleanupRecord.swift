import CryptoKit
import Foundation

/// Bounded injected-local cleanup evidence. Article IDs and progress are never
/// retained here. This is neither an iCloud receipt nor startup authority.
struct ReadingHistoryLocalCleanupRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case pending, complete }
    enum Failure: Error, Equatable, Sendable {
        case invalidRecord, differentOriginal, changedSource, invalidLease, denied, unconfirmed, busy, unavailable, capacityExceeded
    }
    struct Envelope: Codable, Equatable, Sendable {
        var schemaVersion = 1
        var records: [ReadingHistoryLocalCleanupRecord] = []
    }
    static let maximumRecords = 64
    static let maximumBytes = 131_072
    let schemaVersion: Int
    let scope: String
    let ownerUID: String
    let membershipEpoch: Int64
    let requestID: String
    let transitionID: UUID
    let configurationDigest: String
    let owner: String
    let cleanupID: UUID
    let originalEntryCount: Int
    let sourceSHA256: String
    let sourceByteCount: Int
    let targetSHA256: String
    let targetByteCount: Int
    var phase: Phase

    init(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint, source: Data?, target: Data?,
         originalEntryCount: Int) throws {
        guard checkpoint.phase == .ledger,
              checkpoint.marker.binding.ownerUID == checkpoint.request.expectedUID,
              checkpoint.marker.binding.epoch == checkpoint.request.membershipEpoch else { throw Failure.differentOriginal }
        schemaVersion = 1; scope = "reader-local-history-cleanup-v1"
        ownerUID = checkpoint.request.expectedUID; membershipEpoch = checkpoint.request.membershipEpoch
        requestID = checkpoint.request.requestID; transitionID = checkpoint.marker.transitionID
        configurationDigest = checkpoint.configurationDigest
        guard let namespace = ReadingHistoryContext.confirmed(userID: ownerUID).namespace, namespace != .guest else { throw Failure.invalidRecord }
        owner = namespace.recordBinding
        cleanupID = UUID(); self.originalEntryCount = originalEntryCount
        sourceSHA256 = Self.digest(source); sourceByteCount = source?.count ?? 0
        targetSHA256 = Self.digest(target); targetByteCount = target?.count ?? 0; phase = .pending
        try validate()
    }
    func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        checkpoint.phase == .ledger && ownerUID == checkpoint.request.expectedUID
            && membershipEpoch == checkpoint.request.membershipEpoch && requestID == checkpoint.request.requestID
            && transitionID == checkpoint.marker.transitionID && configurationDigest == checkpoint.configurationDigest
            && checkpoint.marker.binding.ownerUID == ownerUID && checkpoint.marker.binding.epoch == membershipEpoch
    }
    func sameOriginal(as other: Self) -> Bool {
        var lhs = self, rhs = other; lhs.phase = .pending; rhs.phase = .pending
        return lhs == rhs
    }
    func matchesSource(_ data: Data?) -> Bool { Self.matches(data, count: sourceByteCount, hash: sourceSHA256) }
    func matchesTarget(_ data: Data?) -> Bool { Self.matches(data, count: targetByteCount, hash: targetSHA256) }
    private static func matches(_ data: Data?, count: Int, hash: String) -> Bool {
        (data?.count ?? 0) == count && digest(data) == hash
    }
    private static func digest(_ data: Data?) -> String {
        guard let data else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func validate() throws {
        let request = try ReaderAccountDeletionContract.Request(expectedUID: ownerUID, membershipEpoch: membershipEpoch)
        func validPair(_ count: Int, _ hash: String) -> Bool {
            count == 0 && hash.isEmpty || (1...ReadingHistoryRecordCodec.maximumRecordBytes).contains(count) && ReaderResumeIdentity.hex(hash, count: 64)
        }
        guard let namespace = ReadingHistoryContext.confirmed(userID: ownerUID).namespace, namespace != .guest else { throw Failure.invalidRecord }
        let empty = try ReadingHistoryRecordCodec.encode(.empty, namespace: namespace)
        guard schemaVersion == 1, scope == "reader-local-history-cleanup-v1", requestID == request.requestID,
              owner == namespace.recordBinding, ReaderResumeIdentity.hex(configurationDigest, count: 64),
              (0...ReadingHistoryRecordCodec.maximumEntries).contains(originalEntryCount),
              validPair(sourceByteCount, sourceSHA256), validPair(targetByteCount, targetSHA256),
              sourceByteCount == 0 ? originalEntryCount == 0 && targetByteCount == 0 && targetSHA256.isEmpty
                : targetByteCount == empty.count && targetSHA256 == Self.digest(empty) else { throw Failure.invalidRecord }
    }
    static func decode(_ data: Data?) throws -> Envelope {
        guard let data else { return .init() }
        guard !data.isEmpty, data.count <= maximumBytes,
              let value = try? JSONDecoder().decode(Envelope.self, from: data) else { throw Failure.invalidRecord }
        guard try encode(value) == data else { throw Failure.invalidRecord }
        return value
    }
    static func encode(_ value: Envelope) throws -> Data {
        guard value.schemaVersion == 1, value.records.count <= maximumRecords,
              Set(value.records.map(\.owner)).count == value.records.count else { throw Failure.invalidRecord }
        for record in value.records { try record.validate() }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw Failure.invalidRecord }
        return data
    }
}
