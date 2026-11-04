import CryptoKit
import Foundation

/// Device-local evidence only. Retained tombstones do not authorize a reader
/// session or prove cloud deletion. No article contents or credentials are kept.
struct ReaderResumeLocalCleanupRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case pending, complete }
    enum Failure: Error, Equatable, Sendable {
        case invalidRecord, differentOriginal, changedSource, invalidLease, denied, unconfirmed, ownerClosed
    }
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
    let originalEntriesSHA256: String
    var phase: Phase

    init(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
         entries: [ReaderResumeRecord.Entry]) throws {
        guard checkpoint.phase == .ledger,
              checkpoint.marker.binding.ownerUID == checkpoint.request.expectedUID,
              checkpoint.marker.binding.epoch == checkpoint.request.membershipEpoch,
              let namespace = ReadingHistoryContext.confirmed(userID: checkpoint.request.expectedUID).namespace,
              namespace != .guest else { throw Failure.differentOriginal }
        schemaVersion = 1; scope = "reader-local-resume-cleanup-v1"
        ownerUID = checkpoint.request.expectedUID; membershipEpoch = checkpoint.request.membershipEpoch
        requestID = checkpoint.request.requestID; transitionID = checkpoint.marker.transitionID
        configurationDigest = checkpoint.configurationDigest; owner = namespace.recordBinding
        cleanupID = UUID(); phase = .pending
        let original = entries.filter { $0.owner == namespace.recordBinding }
        originalEntryCount = original.count
        originalEntriesSHA256 = try Self.digest(original)
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

    func validate() throws {
        let request = try ReaderAccountDeletionContract.Request(expectedUID: ownerUID, membershipEpoch: membershipEpoch)
        guard schemaVersion == 1, scope == "reader-local-resume-cleanup-v1", requestID == request.requestID,
              ReadingHistoryContext.confirmed(userID: ownerUID).namespace?.recordBinding == owner,
              owner != "guest", ReaderResumeIdentity.hex(configurationDigest, count: 64),
              (0...ReaderResumeRecord.maximumEntries).contains(originalEntryCount),
              ReaderResumeIdentity.hex(originalEntriesSHA256, count: 64) else { throw Failure.invalidRecord }
    }

    func validateRemaining(_ entries: [ReaderResumeRecord.Entry]) throws {
        let current = entries.filter { $0.owner == owner }
        switch phase {
        case .pending:
            guard current.count == originalEntryCount, try Self.digest(current) == originalEntriesSHA256 else {
                throw Failure.changedSource
            }
        case .complete:
            guard current.isEmpty else { throw Failure.changedSource }
        }
    }

    private static func digest(_ entries: [ReaderResumeRecord.Entry]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(entries)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
