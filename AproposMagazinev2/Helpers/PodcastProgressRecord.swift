import CryptoKit
import Foundation

/// A local partition, never a stored Firebase identifier. Hashing separates
/// readers' progress; it is not encryption or an account authorization boundary.
struct PodcastProgressNamespace: Hashable, Sendable {
    let recordBinding: String
    var storageKey: String { "podcast_progress_v1_" + recordBinding }
    static let guest = Self(recordBinding: "guest")

    fileprivate static func account(userID: String) -> Self? {
        guard !userID.isEmpty, userID.utf8.count <= 512,
              userID.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              !userID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let input = Data(("apropos/podcast-progress/v1\u{0}" + userID).utf8)
        let hash = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return Self(recordBinding: "account_" + hash)
    }

    private init(recordBinding: String) { self.recordBinding = recordBinding }
}

enum PodcastProgressContext: Equatable, Sendable {
    case unresolved
    case guest
    case account(PodcastProgressNamespace)

    /// Only the canonical authentication callback may confirm nil as guest.
    /// Invalid non-nil identifiers remain unresolved, never a guest fallback.
    static func confirmed(userID: String?) -> Self {
        guard let userID else { return .guest }
        guard let namespace = PodcastProgressNamespace.account(userID: userID) else { return .unresolved }
        return .account(namespace)
    }

    var namespace: PodcastProgressNamespace? {
        switch self {
        case .unresolved: return nil
        case .guest: return .guest
        case .account(let namespace): return namespace == .guest ? nil : namespace
        }
    }
}

enum PodcastProgressStorageState: Equatable, Sendable {
    case unresolved, loading, ready, readFailed, invalidRecord, unsupportedVersion, writeFailed, recoveryLimited
}

struct PodcastProgressSnapshot: Equatable, Sendable {
    let generation: UUID
    let state: PodcastProgressStorageState
    fileprivate let record: PodcastProgressRecord

    var lastPlayedEpisodeID: String? { record.lastEpisodeID }
    var lastPlayedArticleID: String? {
        record.entries.first { $0.episodeID == record.lastEpisodeID }?.articleID
    }
    var canRetry: Bool {
        switch state {
        case .readFailed, .invalidRecord, .unsupportedVersion, .writeFailed: return true
        case .unresolved, .loading, .ready, .recoveryLimited: return false
        }
    }
    var issueMessage: String? {
        switch state {
        case .readFailed: return "Lyttepositioner kunne ikke indlæses. Du kan lytte fra starten. Prøv igen."
        case .invalidRecord: return "De gemte lyttepositioner kunne ikke læses. Du kan lytte fra starten."
        case .unsupportedVersion: return "De gemte lyttepositioner bruger et andet format. Du kan lytte fra starten."
        case .writeFailed: return "Lyttepositionen kunne ikke gemmes. Den kan mangle næste gang du åbner appen."
        case .recoveryLimited: return "Lyttepositioner er utilgængelige resten af denne session. Din afspilning fortsætter."
        case .unresolved, .loading, .ready: return nil
        }
    }

    func position(for episodeID: String) -> TimeInterval? {
        record.entries.first { $0.episodeID == episodeID }?.positionSeconds
    }
    func hasResumableProgress(for episodeID: String) -> Bool { position(for: episodeID) != nil }
    func playButtonTitle(for episodeID: String) -> String { hasResumableProgress(for: episodeID) ? "Fortsæt" : "Lyt" }
    func articlePlayButtonTitle(for episodeID: String) -> String {
        hasResumableProgress(for: episodeID) ? "Fortsæt lytning" : "Lyt til artiklen"
    }

    init(generation: UUID, state: PodcastProgressStorageState, record: PodcastProgressRecord = .empty) {
        self.generation = generation
        self.state = state
        self.record = record
    }
}

/// Array order is oldest to newest. Positions and the last-played association
/// are committed together, with no cross-key intermediate state.
struct PodcastProgressRecord: Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let episodeID: String
        let articleID: String?
        let positionSeconds: TimeInterval
        let durationSeconds: TimeInterval
    }
    var entries: [Entry]
    var lastEpisodeID: String?
    var cleanup: PodcastProgressLocalCleanupRecord? = nil
    static let empty = Self(entries: [], lastEpisodeID: nil)
}

enum PodcastProgressRecordCodec {
    enum Failure: Error, Equatable { case invalidRecord, unsupportedVersion }
    static let maximumRecordBytes = 131_072
    static let maximumEntries = 100
    static let maximumIDBytes = 512
    static let minimumSavedPosition: TimeInterval = 5
    static let completionThreshold: TimeInterval = 15
    // Far beyond an editorial episode, while safely representable by CMTime.
    static let maximumDurationSeconds: TimeInterval = 7 * 24 * 60 * 60

    private struct Envelope: Codable {
        let schemaVersion: Int
        let namespace: String
        let entries: [PodcastProgressRecord.Entry]
        let lastEpisodeID: String?
        let cleanup: PodcastProgressLocalCleanupRecord?
    }

    static func isValidID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumIDBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func completionPosition(duration: TimeInterval) -> TimeInterval {
        duration > completionThreshold ? duration - completionThreshold : duration
    }

    static func decode(_ data: Data, namespace: PodcastProgressNamespace) throws -> PodcastProgressRecord {
        guard !data.isEmpty, data.count <= maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schemaVersion", "namespace", "entries", "lastEpisodeID", "cleanup"]),
              let rows = object["entries"] as? [[String: Any]], rows.count <= maximumEntries,
              rows.allSatisfy({ Set($0.keys).isSubset(of: ["episodeID", "articleID", "positionSeconds", "durationSeconds"]) }),
              let value = try? JSONDecoder().decode(Envelope.self, from: data) else { throw Failure.invalidRecord }
        guard value.schemaVersion == 1 else { throw Failure.unsupportedVersion }
        guard value.namespace == namespace.recordBinding else { throw Failure.invalidRecord }
        let record = PodcastProgressRecord(entries: value.entries, lastEpisodeID: value.lastEpisodeID, cleanup: value.cleanup)
        guard valid(record) else { throw Failure.invalidRecord }
        if object.keys.contains("cleanup") {
            guard let cleanup = record.cleanup else { throw Failure.invalidRecord }
            try cleanup.validate(namespace: namespace)
            try cleanup.validateRemaining(record, namespace: namespace)
            guard try encode(record, namespace: namespace) == data else { throw Failure.invalidRecord }
        }
        return record
    }

    static func encode(_ record: PodcastProgressRecord, namespace: PodcastProgressNamespace) throws -> Data {
        guard valid(record) else { throw Failure.invalidRecord }
        if let cleanup = record.cleanup {
            try cleanup.validate(namespace: namespace)
            try cleanup.validateRemaining(record, namespace: namespace)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let value = Envelope(schemaVersion: 1, namespace: namespace.recordBinding,
                             entries: record.entries, lastEpisodeID: record.lastEpisodeID, cleanup: record.cleanup)
        let data = try encoder.encode(value)
        guard data.count <= maximumRecordBytes else { throw Failure.invalidRecord }
        return data
    }

    private static func valid(_ record: PodcastProgressRecord) -> Bool {
        guard record.entries.count <= maximumEntries,
              Set(record.entries.map(\.episodeID)).count == record.entries.count,
              record.entries.allSatisfy({ entry in
                  isValidID(entry.episodeID) && (entry.articleID.map(isValidID) ?? true)
                      && entry.positionSeconds.isFinite && entry.durationSeconds.isFinite
                      && entry.durationSeconds > 0 && entry.durationSeconds <= maximumDurationSeconds
                      && entry.positionSeconds >= minimumSavedPosition
                      && entry.positionSeconds < completionPosition(duration: entry.durationSeconds)
              }) else { return false }
        return record.lastEpisodeID.map { last in record.entries.contains { $0.episodeID == last } } ?? true
    }
}
