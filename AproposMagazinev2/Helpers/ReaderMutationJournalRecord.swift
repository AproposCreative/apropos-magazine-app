import CryptoKit
import Foundation

/// Inactive durable data, not a dispatch queue or current server projection.
/// Original UIDs are persisted in requests; a hashed file name is not encryption.
/// Preparation/validation can hash and encode up to 2 MiB: future callers must
/// perform this work off the main actor, as the separate file journal does.
struct ReaderMutationJournalRecord: Codable, Equatable, Sendable {
    typealias Request = ReaderMutationContract.Request
    typealias Failure = ReaderMutationJournalCodec.Failure

    struct Entry: Codable, Equatable, Sendable {
        let request: Request
        let receiptData: Data?
        var requestID: String { request.requestID }
        var historicallyAcknowledged: Bool { receiptData != nil }

        init(request: Request, receiptData: Data? = nil) throws {
            if let receiptData {
                do { _ = try ReaderMutationContract.decodeReceipt(data: receiptData, for: request) }
                catch { throw Failure.invalidRecord }
            }
            self.request = request; self.receiptData = receiptData
        }

        private enum CodingKeys: String, CodingKey { case request, receiptData }
        init(from decoder: Decoder) throws {
            do {
                try ReaderMutationJournalCodec.keys(decoder, required: ["request"], allowed: ["request", "receiptData"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                // A null key is not an absent acknowledgement.
                let receipt = values.contains(.receiptData) ? try values.decode(Data.self, forKey: .receiptData) : nil
                try self.init(request: values.decode(Request.self, forKey: .request), receiptData: receipt)
            } catch { throw Failure.invalidRecord }
        }
    }

    enum LegacyKind: String, Codable, Sendable { case favoritesV1, favoritesV2 }
    struct LegacySnapshot: Codable, Equatable, Sendable {
        let kind: LegacyKind
        let rawData: Data
        let sha256: String

        /// This preserves the original bytes, including every old pending/ACK
        /// phase. Validation never converts any of them to a bound Request.
        init(kind: LegacyKind, data: Data, ownerUID: String) throws {
            guard !data.isEmpty, data.count <= FavoritesRecordCodec.maximumRecordBytes else { throw Failure.invalidRecord }
            self.kind = kind; rawData = data
            sha256 = ReaderMutationJournalCodec.digest(data)
            try ReaderMutationJournalCodec.validateLegacy(self, ownerUID: ownerUID)
        }

        private enum CodingKeys: String, CodingKey { case kind, rawData, sha256 }
        init(from decoder: Decoder) throws {
            do {
                try ReaderMutationJournalCodec.keys(decoder, required: ["kind", "rawData", "sha256"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                kind = try values.decode(LegacyKind.self, forKey: .kind)
                rawData = try values.decode(Data.self, forKey: .rawData)
                sha256 = try values.decode(String.self, forKey: .sha256)
                guard !rawData.isEmpty, rawData.count <= FavoritesRecordCodec.maximumRecordBytes,
                      sha256 == ReaderMutationJournalCodec.digest(rawData) else { throw Failure.invalidRecord }
                // The containing record validates the legacy owner namespace.
            } catch { throw Failure.invalidRecord }
        }
    }

    let ownerUID: String
    let recordRevision: UUID
    let entries: [Entry]
    let legacySnapshots: [LegacySnapshot]
    /// These values still require current membership, revision and transport
    /// admission. Neither unacknowledged nor legacy data is dispatch authority.
    var unacknowledgedEntries: [Entry] { entries.filter { !$0.historicallyAcknowledged } }

    init(ownerUID: String, recordRevision: UUID = UUID(), entries: [Entry] = [], legacySnapshots: [LegacySnapshot] = []) throws {
        self.ownerUID = ownerUID; self.recordRevision = recordRevision
        self.entries = entries; self.legacySnapshots = legacySnapshots
        try ReaderMutationJournalCodec.validate(self)
    }

    func appending(_ request: Request) throws -> Self {
        guard request.expectedUID == ownerUID else { throw Failure.wrongOwner }
        if let existing = entries.first(where: { $0.request.mutationID == request.mutationID }) {
            guard existing.request == request else { throw Failure.conflictingMutation }
            return self
        }
        return try Self(ownerUID: ownerUID, entries: entries + [Entry(request: request)], legacySnapshots: legacySnapshots)
    }

    func acknowledging(requestID: String, receiptData: Data) throws -> Self {
        guard let index = entries.firstIndex(where: { $0.requestID == requestID }) else { throw Failure.missingMutation }
        let original = entries[index]
        let receipt: ReaderMutationContract.Receipt
        do { receipt = try ReaderMutationContract.decodeReceipt(data: receiptData, for: original.request) }
        catch { throw Failure.conflictingReceipt }
        if let saved = original.receiptData {
            guard let previous = try? ReaderMutationContract.decodeReceipt(data: saved, for: original.request),
                  previous == receipt else { throw Failure.conflictingReceipt }
            // A formatting-only retry acknowledges the same history. Preserve
            // the first stored bytes and local revision instead of rewriting.
            return self
        }
        var next = entries
        next[index] = try Entry(request: original.request, receiptData: receiptData)
        return try Self(ownerUID: ownerUID, entries: next, legacySnapshots: legacySnapshots)
    }

    func preservingLegacy(kind: LegacyKind, data: Data) throws -> Self {
        let candidate = try LegacySnapshot(kind: kind, data: data, ownerUID: ownerUID)
        if let existing = legacySnapshots.first(where: { $0.kind == kind }) {
            guard existing == candidate else { throw Failure.conflictingLegacy }
            return self
        }
        return try Self(ownerUID: ownerUID, entries: entries, legacySnapshots: legacySnapshots + [candidate])
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, ownerUID, recordRevision, entries, legacySnapshots }
    init(from decoder: Decoder) throws {
        do {
            try ReaderMutationJournalCodec.keys(decoder, required: ["schemaVersion", "ownerUID", "recordRevision", "entries", "legacySnapshots"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.unsupportedVersion }
            try self.init(ownerUID: values.decode(String.self, forKey: .ownerUID),
                          recordRevision: values.decode(UUID.self, forKey: .recordRevision),
                          entries: values.decode([Entry].self, forKey: .entries),
                          legacySnapshots: values.decode([LegacySnapshot].self, forKey: .legacySnapshots))
        } catch let failure as Failure { throw failure }
        catch { throw Failure.invalidRecord }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schemaVersion)
        try values.encode(ownerUID, forKey: .ownerUID)
        try values.encode(recordRevision, forKey: .recordRevision)
        try values.encode(entries, forKey: .entries)
        try values.encode(legacySnapshots, forKey: .legacySnapshots)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = try? ReaderMutationJournalCodec.encode(lhs),
              let right = try? ReaderMutationJournalCodec.encode(rhs) else { return false }
        return left == right
    }
}

/// Bounded, SDK-free codec. Validation grants no write lease, invents no epoch
/// or resource revision and performs no reads, file writes or legacy fallback.
enum ReaderMutationJournalCodec {
    typealias Record = ReaderMutationJournalRecord
    static let maximumRecordBytes = 2_097_152
    static let maximumEntries = 256
    static let maximumLegacySnapshots = 2
    enum Failure: Error, Equatable {
        case invalidRecord, unsupportedVersion, limitExceeded, wrongOwner
        case conflictingMutation, conflictingReceipt, conflictingLegacy, missingMutation
    }

    static func validate(_ record: Record) throws { _ = try validatedBytes(record) }
    static func encode(_ record: Record) throws -> Data { try validatedBytes(record) }
    static func decode(_ data: Data, ownerUID: String) throws -> Record {
        guard !data.isEmpty else { throw Failure.invalidRecord }
        guard data.count <= maximumRecordBytes else { throw Failure.limitExceeded }
        do {
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard record.ownerUID == ownerUID else { throw Failure.wrongOwner }
            return record
        } catch let failure as Failure { throw failure }
        catch { throw Failure.invalidRecord }
    }

    /// Standalone schema validity is insufficient for replacing a durable head.
    /// This batch permits append and nil→receipt only, with no purge/compaction.
    static func validateReplacement(current: Record, next: Record) throws {
        let before = try encode(current), after = try encode(next)
        if before == after { return }
        guard current.ownerUID == next.ownerUID else { throw Failure.wrongOwner }
        guard current.recordRevision != next.recordRevision,
              next.entries.count >= current.entries.count,
              next.legacySnapshots.count >= current.legacySnapshots.count else { throw Failure.invalidRecord }
        for (index, original) in current.entries.enumerated() {
            let replacement = next.entries[index]
            guard original.request == replacement.request else { throw Failure.conflictingMutation }
            if let receipt = original.receiptData {
                guard replacement.receiptData == receipt else { throw Failure.conflictingReceipt }
            }
        }
        for (index, original) in current.legacySnapshots.enumerated() {
            guard next.legacySnapshots[index] == original else { throw Failure.conflictingLegacy }
        }
    }

    private static func validatedBytes(_ record: Record) throws -> Data {
        do { _ = try ReaderMembershipContract.Binding(ownerUID: record.ownerUID, epoch: 1) }
        catch { throw Failure.wrongOwner }
        guard record.entries.count <= maximumEntries, record.legacySnapshots.count <= maximumLegacySnapshots else {
            throw Failure.limitExceeded
        }
        // A mutation UUID stays unique across all retained epochs, preventing
        // accidental copy/rebinding from masquerading as a new intent.
        guard Set(record.entries.map { $0.request.mutationID }).count == record.entries.count else {
            throw Failure.conflictingMutation
        }
        guard Set(record.legacySnapshots.map { $0.kind.rawValue }).count == record.legacySnapshots.count else {
            throw Failure.conflictingLegacy
        }
        var minimumBytes = 0
        for entry in record.entries {
            guard entry.request.expectedUID == record.ownerUID else { throw Failure.wrongOwner }
            minimumBytes += try ReaderMutationContract.encode(entry.request).count
            if let receipt = entry.receiptData {
                do { _ = try ReaderMutationContract.decodeReceipt(data: receipt, for: entry.request) }
                catch { throw Failure.invalidRecord }
                minimumBytes += ((receipt.count + 2) / 3) * 4
            }
            guard minimumBytes <= maximumRecordBytes else { throw Failure.limitExceeded }
        }
        for legacy in record.legacySnapshots {
            try validateLegacy(legacy, ownerUID: record.ownerUID)
            minimumBytes += ((legacy.rawData.count + 2) / 3) * 4
            guard minimumBytes <= maximumRecordBytes else { throw Failure.limitExceeded }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard data.count <= maximumRecordBytes else { throw Failure.limitExceeded }
        return data
    }

    fileprivate static func validateLegacy(_ legacy: Record.LegacySnapshot, ownerUID: String) throws {
        do { _ = try ReaderMembershipContract.Binding(ownerUID: ownerUID, epoch: 1) }
        catch { throw Failure.wrongOwner }
        guard !legacy.rawData.isEmpty, legacy.rawData.count <= FavoritesRecordCodec.maximumRecordBytes,
              legacy.sha256 == digest(legacy.rawData),
              let namespace = FavoritesContext.confirmed(userID: ownerUID).namespace,
              namespace != .guest else { throw Failure.invalidRecord }
        do {
            switch legacy.kind {
            case .favoritesV1: _ = try FavoritesRecordCodec.migrateLegacyV1(legacy.rawData, namespace: namespace)
            case .favoritesV2: _ = try FavoritesRecordCodec.decode(legacy.rawData, namespace: namespace)
            }
        } catch { throw Failure.invalidRecord }
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    fileprivate static func keys(_ decoder: Decoder, required: Set<String>, allowed: Set<String>? = nil) throws {
        let values = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(values.allKeys.map(\.stringValue))
        guard actual.isSuperset(of: required), actual.isSubset(of: allowed ?? required) else { throw Failure.invalidRecord }
    }
}
