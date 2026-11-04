import CryptoKit
import Foundation

/// A paragraph location is valid only for these exact source bytes. It is never
/// reconstructed from legacy reading percentages or from transformed HTML.
struct ReaderResumeIdentity: Codable, Equatable, Sendable {
    let articleID: String
    let sourceRevision: String?
    let sourceDigest: String

    init?(articleID: String, sourceRevision: String?, html: String) {
        guard Self.validID(articleID), sourceRevision.map(Self.validID) ?? true,
              !html.isEmpty, html.utf8.count <= 4_194_304 else { return nil }
        self.articleID = articleID
        self.sourceRevision = sourceRevision
        sourceDigest = SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var isValid: Bool {
        Self.validID(articleID) && (sourceRevision.map(Self.validID) ?? true)
            && Self.hex(sourceDigest, count: 64)
    }
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct ReaderResumeAnchor: Codable, Equatable, Sendable {
    let index: Int
    let fingerprint: String
    var isValid: Bool { (0..<1_200).contains(index) && ReaderResumeIdentity.hex(fingerprint, count: 8) }
}

enum ReaderResumeRecord {
    static let maximumEntries = 120
    static let maximumBytes = 262_144
    static let maximumCleanups = 64
    struct Entry: Codable, Equatable, Sendable {
        let owner: String
        let source: ReaderResumeIdentity
        let anchor: ReaderResumeAnchor
    }
    struct Envelope: Codable, Equatable, Sendable {
        var schemaVersion = 1
        var entries: [Entry] = []
        var cleanups: [ReaderResumeLocalCleanupRecord] = []

        init(schemaVersion: Int = 1, entries: [Entry] = [], cleanups: [ReaderResumeLocalCleanupRecord] = []) {
            self.schemaVersion = schemaVersion; self.entries = entries; self.cleanups = cleanups
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, entries, cleanups }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            entries = try container.decode([Entry].self, forKey: .entries)
            // Old records have no metadata. A present null/malformed value is
            // rejected rather than silently reopening a previously closed owner.
            cleanups = container.contains(.cleanups)
                ? try container.decode([ReaderResumeLocalCleanupRecord].self, forKey: .cleanups) : []
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(entries, forKey: .entries)
            // Preserve the exact original legacy encoding until explicit cleanup.
            if !cleanups.isEmpty { try container.encode(cleanups, forKey: .cleanups) }
        }
    }
    enum Failure: Error { case invalid, unavailable, unconfirmed }
    static func validOwner(_ value: String) -> Bool {
        value == "guest" || (value.hasPrefix("account_") && ReaderResumeIdentity.hex(String(value.dropFirst(8)), count: 64))
    }
    static func decode(_ data: Data?) throws -> Envelope {
        guard let data else { return Envelope() }
        guard !data.isEmpty, data.count <= maximumBytes,
              let result = try? JSONDecoder().decode(Envelope.self, from: data),
              result.schemaVersion == 1, result.entries.count <= maximumEntries,
              result.cleanups.count <= maximumCleanups else { throw Failure.invalid }
        var keys = Set<String>()
        for entry in result.entries {
            guard validOwner(entry.owner), entry.source.isValid, entry.anchor.isValid,
                  keys.insert(entry.owner + "\u{0}" + entry.source.articleID).inserted else { throw Failure.invalid }
        }
        var owners = Set<String>()
        for cleanup in result.cleanups {
            try cleanup.validate()
            guard owners.insert(cleanup.owner).inserted else { throw Failure.invalid }
            try cleanup.validateRemaining(result.entries)
        }
        if !result.cleanups.isEmpty {
            // Unknown/repeated fields cannot be discarded by a later other-owner
            // save. Cleanup records are always emitted in this canonical format.
            guard try canonicalBytes(result) == data else { throw Failure.invalid }
        }
        return result
    }
    private static func canonicalBytes(_ envelope: Envelope) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(envelope)
    }
    static func encode(_ envelope: Envelope) throws -> Data {
        let data = try canonicalBytes(envelope)
        _ = try decode(data)
        return data
    }
}

/// Coordinates are native points relative to the current prose viewport. Font
/// changes are handled by freshly measuring the paragraph, never by a ratio.
enum ReaderResumeGeometry {
    static func offset(paragraphTop: Double, viewportTop: Double, currentOffset: Double,
                       contentHeight: Double, viewportHeight: Double,
                       topInset: Double, bottomInset: Double) -> Double? {
        let values = [paragraphTop, viewportTop, currentOffset, contentHeight, viewportHeight, topInset, bottomInset]
        guard values.allSatisfy(\.isFinite), paragraphTop >= 0, contentHeight > 0,
              viewportHeight > 0, topInset >= 0, bottomInset >= 0 else { return nil }
        let proposed = currentOffset + paragraphTop - viewportTop
        let maximum = max(-topInset, contentHeight - viewportHeight + bottomInset)
        guard proposed.isFinite, maximum.isFinite else { return nil }
        return min(max(-topInset, proposed), maximum)
    }
}
