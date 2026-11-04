import CryptoKit
import Foundation

/// Retained per-owner local evidence, not a server deletion receipt or playback
/// authority. No episode contents, credentials or other owner's keys are kept.
struct PodcastProgressLocalCleanupRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case pending, complete }
    enum Failure: Error, Equatable, Sendable {
        case invalidRecord, differentOriginal, changedSource, invalidLease, denied, unconfirmed, busy, capacityExceeded
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
    let originalByteCount: Int
    let originalSHA256: String
    var phase: Phase

    init(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
         namespace: PodcastProgressNamespace, raw: Data?, record: PodcastProgressRecord) throws {
        guard checkpoint.phase == .ledger,
              checkpoint.marker.binding.ownerUID == checkpoint.request.expectedUID,
              checkpoint.marker.binding.epoch == checkpoint.request.membershipEpoch,
              PodcastProgressContext.confirmed(userID: checkpoint.request.expectedUID).namespace == namespace,
              namespace != .guest else { throw Failure.differentOriginal }
        schemaVersion = 1; scope = "reader-local-podcast-progress-cleanup-v1"
        ownerUID = checkpoint.request.expectedUID; membershipEpoch = checkpoint.request.membershipEpoch
        requestID = checkpoint.request.requestID; transitionID = checkpoint.marker.transitionID
        configurationDigest = checkpoint.configurationDigest; owner = namespace.recordBinding
        cleanupID = UUID(); originalEntryCount = record.entries.count
        originalByteCount = raw?.count ?? 0; originalSHA256 = Self.digest(raw); phase = .pending
        try validate(namespace: namespace)
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
    func validate(namespace: PodcastProgressNamespace) throws {
        let request = try ReaderAccountDeletionContract.Request(expectedUID: ownerUID, membershipEpoch: membershipEpoch)
        guard schemaVersion == 1, scope == "reader-local-podcast-progress-cleanup-v1", requestID == request.requestID,
              namespace != .guest, namespace.recordBinding == owner,
              PodcastProgressContext.confirmed(userID: ownerUID).namespace == namespace,
              ReaderResumeIdentity.hex(configurationDigest, count: 64),
              (0...PodcastProgressRecordCodec.maximumEntries).contains(originalEntryCount),
              originalByteCount == 0 && originalSHA256.isEmpty && originalEntryCount == 0
                || (1...PodcastProgressRecordCodec.maximumRecordBytes).contains(originalByteCount)
                    && ReaderResumeIdentity.hex(originalSHA256, count: 64) else { throw Failure.invalidRecord }
    }
    func validateRemaining(_ record: PodcastProgressRecord, namespace: PodcastProgressNamespace) throws {
        switch phase {
        case .pending:
            var source = record; source.cleanup = nil
            if originalByteCount == 0 {
                guard source == .empty else { throw Failure.changedSource }
            } else {
                let raw = try PodcastProgressRecordCodec.encode(source, namespace: namespace)
                guard source.entries.count == originalEntryCount, raw.count == originalByteCount,
                      Self.digest(raw) == originalSHA256 else { throw Failure.changedSource }
            }
        case .complete:
            guard record.entries.isEmpty, record.lastEpisodeID == nil else { throw Failure.changedSource }
        }
    }
    private static func digest(_ data: Data?) -> String {
        guard let data else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
