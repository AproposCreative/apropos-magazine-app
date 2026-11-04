import CryptoKit
import Foundation

/// The partition is pseudonymous, not encrypted or an authorization boundary.
/// No Firebase identifier is retained in this value or its storage key.
struct ReadingHistoryNamespace: Hashable, Sendable {
    let recordBinding: String
    var storageKey: String { "reading_history_v1_" + recordBinding }
    static let guest = Self(recordBinding: "guest")

    fileprivate static func account(userID: String) -> Self? {
        guard !userID.isEmpty, userID.utf8.count <= 512,
              userID.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              !userID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let data = Data(("apropos/reading-history/v1\u{0}" + userID).utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Self(recordBinding: "account_" + hash)
    }
    private init(recordBinding: String) { self.recordBinding = recordBinding }
}

enum ReadingHistoryContext: Equatable, Sendable {
    case unresolved
    case guest
    case account(ReadingHistoryNamespace)

    static func confirmed(userID: String?) -> Self {
        guard let userID else { return .guest }
        guard let namespace = ReadingHistoryNamespace.account(userID: userID) else { return .unresolved }
        return .account(namespace)
    }
    var namespace: ReadingHistoryNamespace? {
        switch self {
        case .unresolved: return nil
        case .guest: return .guest
        case .account(let value): return value == .guest ? nil : value
        }
    }
}

enum ReadingHistoryStorageState: Equatable, Sendable {
    case unresolved, loading, ready, pending, readFailed, invalidRecord, unsupportedVersion, writeFailed
}

struct ReadingHistorySnapshot: Equatable, Sendable {
    let generation: UUID
    let revision: UInt64
    let readArticleIDs: [String]
    let progress: [String: Double]
    let state: ReadingHistoryStorageState

    var canRetry: Bool {
        switch state {
        case .readFailed, .invalidRecord, .unsupportedVersion, .writeFailed: return true
        case .unresolved, .loading, .ready, .pending: return false
        }
    }
    var issueMessage: String? {
        switch state {
        case .readFailed: return "Læsehistorikken kunne ikke indlæses. Du kan fortsat læse. Prøv igen."
        case .invalidRecord: return "Den gemte læsehistorik kunne ikke læses. Du kan fortsat læse."
        case .unsupportedVersion: return "Den gemte læsehistorik bruger et andet format. Du kan fortsat læse."
        case .writeFailed: return "Læsehistorikken kunne ikke gemmes. Dine seneste ændringer kan mangle, næste gang du åbner appen."
        case .unresolved, .loading, .ready, .pending: return nil
        }
    }

    init(generation: UUID, revision: UInt64, state: ReadingHistoryStorageState, record: ReadingHistoryRecord = .empty) {
        self.generation = generation
        self.revision = revision
        self.state = state
        readArticleIDs = record.entries.filter(\.read).map(\.articleID)
        progress = Dictionary(uniqueKeysWithValues: record.entries.compactMap { entry in
            entry.progress.map { (entry.articleID, $0) }
        })
    }
}

/// Read means the existing app's article-open history, not verified completion.
/// Order is oldest to most recently edited. Both fields share one bounded write.
struct ReadingHistoryRecord: Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let articleID: String
        let read: Bool
        let progress: Double?
    }
    var entries: [Entry]
    static let empty = Self(entries: [])
}

enum ReadingHistoryRecordCodec {
    enum Failure: Error, Equatable { case invalidRecord, unsupportedVersion }
    static let maximumEntries = 200
    static let maximumRecordBytes = 131_072
    static let maximumIDBytes = 512

    private struct Envelope: Codable {
        let schemaVersion: Int
        let namespace: String
        let entries: [ReadingHistoryRecord.Entry]
    }

    static func isValidID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumIDBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func decode(_ data: Data, namespace: ReadingHistoryNamespace) throws -> ReadingHistoryRecord {
        guard !data.isEmpty, data.count <= maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "namespace", "entries"],
              let rows = object["entries"] as? [[String: Any]], rows.count <= maximumEntries,
              rows.allSatisfy({ Set($0.keys).isSubset(of: ["articleID", "read", "progress"]) }),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw Failure.invalidRecord }
        guard envelope.schemaVersion == 1 else { throw Failure.unsupportedVersion }
        guard envelope.namespace == namespace.recordBinding else { throw Failure.invalidRecord }
        let record = ReadingHistoryRecord(entries: envelope.entries)
        guard valid(record) else { throw Failure.invalidRecord }
        return record
    }

    static func encode(_ record: ReadingHistoryRecord, namespace: ReadingHistoryNamespace) throws -> Data {
        guard valid(record) else { throw Failure.invalidRecord }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Envelope(schemaVersion: 1, namespace: namespace.recordBinding, entries: record.entries))
        guard data.count <= maximumRecordBytes else { throw Failure.invalidRecord }
        return data
    }

    private static func valid(_ record: ReadingHistoryRecord) -> Bool {
        record.entries.count <= maximumEntries
            && Set(record.entries.map(\.articleID)).count == record.entries.count
            && record.entries.allSatisfy { entry in
                isValidID(entry.articleID) && (entry.read || entry.progress != nil)
                    && (entry.progress.map { $0.isFinite && (0...1).contains($0) } ?? true)
            }
    }
}
