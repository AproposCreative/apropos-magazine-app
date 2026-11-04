import CryptoKit
import Foundation

/// Pseudonymous partitioning is not encryption or server authorization.
struct FavoritesNamespace: Hashable, Sendable {
    let recordBinding: String
    var storageKey: String { "favorites_v1_" + recordBinding }
    static let guest = Self(recordBinding: "guest")
    fileprivate static func account(userID: String) -> Self? {
        guard !userID.isEmpty, userID.utf8.count <= 512,
              userID.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }),
              !userID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let digest = SHA256.hash(data: Data(("apropos/favorites/v1\u{0}" + userID).utf8))
        return Self(recordBinding: "account_" + digest.map { String(format: "%02x", $0) }.joined())
    }
    private init(recordBinding: String) { self.recordBinding = recordBinding }
}

enum FavoritesContext: Equatable, Sendable {
    case unresolved, guest, account(FavoritesNamespace)
    static func confirmed(userID: String?) -> Self {
        guard let userID else { return .guest }
        guard let namespace = FavoritesNamespace.account(userID: userID) else { return .unresolved }
        return .account(namespace)
    }
    var namespace: FavoritesNamespace? {
        switch self {
        case .unresolved: return nil
        case .guest: return .guest
        case .account(let namespace): return namespace == .guest ? nil : namespace
        }
    }
}

enum FavoritesJournalFailure: Error, Equatable, Sendable {
    case superseded, staleRevision, readFailed, writeFailed
}

enum FavoritesStorageState: Equatable, Sendable {
    case unresolved, loading, ready, pending, recovering, recoveryFailed
    case readFailed, invalidRecord, unsupportedVersion, writeFailed, cloudFailed, limitExceeded
}

struct FavoritesSnapshot: Equatable {
    let generation: UUID
    let revision: UInt64
    let articles: [Article]
    let pendingArticleIDs: Set<String>
    let serverConfirmed: Bool
    let state: FavoritesStorageState
    var recoveryReady = false
    var canRetry: Bool {
        switch state {
        case .readFailed, .invalidRecord, .unsupportedVersion, .writeFailed, .cloudFailed, .recoveryFailed: return true
        default: return false
        }
    }
    var issueMessage: String? {
        switch state {
        case .readFailed: return "Dine gemte artikler kunne ikke indlæses. Prøv igen."
        case .invalidRecord: return "Dine gemte artikler kunne ikke læses. De eksisterende data er bevaret."
        case .unsupportedVersion: return "Dine gemte artikler bruger et andet format. De eksisterende data er bevaret."
        case .writeFailed: return "Ændringerne kunne ikke gemmes på denne enhed. De kan mangle, næste gang du åbner appen. Prøv igen."
        case .cloudFailed: return "Dine gemte artikler er ikke bekræftet synkroniseret. Prøv igen."
        case .recovering: return "Dine valg afventer synkronisering."
        case .recoveryFailed: return "Synkroniseringen kunne ikke genoptages. Prøv igen."
        case .limitExceeded: return "Der er ikke plads til flere gemte artikler i denne samling. Dine eksisterende valg er bevaret."
        default: return nil
        }
    }
}

/// Only bounded scalar metadata crosses the journal's private I/O queue.
/// Runtime ownership, listener proof and raw account IDs are never persisted.
struct FavoritesRecord: Equatable, Sendable {
    let recordRevision: UUID
    let base: [Metadata]
    let pending: [Pending]
    let requiresRecovery: Bool

    init(recordRevision: UUID = UUID(), base: [Metadata], pending: [Pending] = [], requiresRecovery: Bool = false) {
        self.recordRevision = recordRevision; self.base = base; self.pending = pending; self.requiresRecovery = requiresRecovery
    }
    init(articles: [Article]) { self.init(base: articles.map(Metadata.init)) }
    static var empty: Self { Self(base: []) }
    var articles: [Article] {
        let ids = Set(pending.map { $0.payload.id })
        return (base.filter { !ids.contains($0.id) }.map(\.article)
            + pending.filter(\.enabled).map { $0.article.article }).sorted { $0.id < $1.id }
    }
    enum Phase: String, Codable, Equatable, Sendable { case queued, started, acknowledged, failed, blocked }
    struct Pending: Codable, Equatable, Sendable {
        let intentID: UUID
        let payload: Metadata
        let article: Metadata
        let enabled: Bool
        let phase: Phase
        let attemptID: UUID?
        var articleID: String { payload.id }
        init(intentID: UUID, payload: Metadata, article: Metadata? = nil, enabled: Bool, phase: Phase = .queued, attemptID: UUID? = nil) {
            self.intentID = intentID; self.payload = payload; self.article = article ?? payload
            self.enabled = enabled; self.phase = phase; self.attemptID = attemptID
        }
    }
    struct Metadata: Codable, Equatable, Sendable {
        let id: String
        let name: String?
        let slug: String?
        let stjerne: Int?
        let topicID: String?
        let topicsIDs: [String]?
        let sectionID: String?
        let authorID: String?
        let mobileImageURL: String?
        let thumbURL: String?
        let coverURL: String?
        let location: String?
        let subtitle: String?
        let fotoCredit: String?
        let isDraft: Bool?
        let isArchived: Bool?
        let date: String?
        let createdOn: String?
        let lastPublished: String?
        let lastUpdated: String?
        let contentRevision: String?
        let contentLanguage: String?
        let sourceArticleID: String?
        let cmsLocaleId: String?
        let featured: Bool?
        let isPremium: Bool?
        let pressAccreditation: Bool
        let favoriteSavedAt: TimeInterval?

        init(_ article: Article) {
            favoriteSavedAt = article.favoriteSavedAt
            id = article.id; name = article.name; slug = article.slug; stjerne = article.stjerne
            topicID = article.topicID; topicsIDs = article.topicsIDs; sectionID = article.sectionID; authorID = article.authorID
            mobileImageURL = article.mobileImageURL?.absoluteString; thumbURL = article.thumbURL?.absoluteString; coverURL = article.coverURL?.absoluteString
            location = article.location; subtitle = article.subtitle; fotoCredit = article.fotoCredit
            isDraft = article.isDraft; isArchived = article.isArchived; date = article.date; createdOn = article.createdOn
            lastPublished = article.lastPublished; lastUpdated = article.lastUpdated; contentRevision = article.contentRevision
            contentLanguage = article.contentLanguage == .danish && article.sourceArticleID == nil && article.cmsLocaleId == nil
                ? nil : (article.contentLanguage?.rawValue ?? "")
            sourceArticleID = article.sourceArticleID; cmsLocaleId = article.cmsLocaleId
            featured = article.featured; isPremium = article.isPremium; pressAccreditation = article.pressAccreditation
        }
        var article: Article {
            Article(id: id, name: name ?? "", slug: slug ?? id, content: "", intro: "", stjerne: stjerne,
                    topicID: topicID ?? "", topicsIDs: topicsIDs, sectionID: sectionID, authorID: authorID,
                    mobileImageURL: mobileImageURL.flatMap(URL.init(string:)), thumbURL: thumbURL.flatMap(URL.init(string:)),
                    coverURL: coverURL.flatMap(URL.init(string:)), location: location, subtitle: subtitle, fotoCredit: fotoCredit,
                    isDraft: isDraft, isArchived: isArchived, date: date, createdOn: createdOn, lastPublished: lastPublished,
                    lastUpdated: lastUpdated, contentRevision: contentRevision, featured: featured, isPremium: isPremium,
                    pressAccreditation: pressAccreditation,
                    contentLanguage: ArticleContentLanguage.validated(articleID: id, languageCode: contentLanguage,
                        sourceArticleID: sourceArticleID, cmsLocaleId: cmsLocaleId),
                    sourceArticleID: sourceArticleID, cmsLocaleId: cmsLocaleId).withFavoriteSavedAt(favoriteSavedAt)
        }
        var boundedUTF8Bytes: Int {
            let strings = [id, name, slug, topicID, sectionID, authorID, mobileImageURL, thumbURL, coverURL,
                           location, subtitle, fotoCredit, date, createdOn, lastPublished, lastUpdated, contentRevision,
                           contentLanguage, sourceArticleID, cmsLocaleId]
            return 256 + strings.compactMap { $0 }.reduce(0) { $0 + $1.utf8.count }
                + (topicsIDs ?? []).reduce(0) { $0 + $1.utf8.count }
        }
        var valid: Bool {
            guard favoriteSavedAt.map(FavoriteArticlesLogic.validSavedAt) ?? true else { return false }
            guard FavoritesRecordCodec.isValidID(id), (stjerne.map { (0...10).contains($0) } ?? true) else { return false }
            guard ArticleContentLanguage.validated(articleID: id, languageCode: contentLanguage,
                sourceArticleID: sourceArticleID, cmsLocaleId: cmsLocaleId) != nil else { return false }
            let fields: [(String?, Int)] = [(name, 2048), (slug, 1024), (topicID, 512), (sectionID, 512), (authorID, 512),
                (mobileImageURL, 4096), (thumbURL, 4096), (coverURL, 4096), (location, 1024), (subtitle, 4096),
                (fotoCredit, 2048), (date, 128), (createdOn, 128), (lastPublished, 128), (lastUpdated, 128), (contentRevision, 1024)]
            guard fields.allSatisfy({ value, limit in value.map { $0.utf8.count <= limit && !$0.contains("\u{0}") } ?? true }),
                  topicsIDs.map({ $0.count <= 32 && $0.allSatisfy(FavoritesRecordCodec.isValidID) }) ?? true else { return false }
            return [mobileImageURL, thumbURL, coverURL].allSatisfy { raw in
                guard let raw else { return true }
                guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                      url.host != nil, url.user == nil, url.password == nil else { return false }
                return true
            }
        }
        static let keys: Set<String> = ["id", "name", "slug", "stjerne", "topicID", "topicsIDs", "sectionID", "authorID", "mobileImageURL", "thumbURL", "coverURL", "location", "subtitle", "fotoCredit", "isDraft", "isArchived", "date", "createdOn", "lastPublished", "lastUpdated", "contentRevision", "contentLanguage", "sourceArticleID", "cmsLocaleId", "featured", "isPremium", "pressAccreditation", "favoriteSavedAt"]
    }

}

enum FavoritesRecordCodec {
    enum Failure: Error, Equatable, Sendable { case invalidRecord, unsupportedVersion, limitExceeded }
    static let maximumEntries = 200
    static let maximumPending = 256
    static let maximumRecordBytes = 524_288
    static let maximumIDBytes = 512
    private struct Envelope: Codable {
        let schemaVersion: Int
        let namespace: String
        let recordRevision: UUID
        let base: [FavoritesRecord.Metadata]
        let pending: [FavoritesRecord.Pending]
        let requiresRecovery: Bool
    }
    private struct LegacyEnvelope: Codable {
        let schemaVersion: Int
        let namespace: String
        let entries: [FavoritesRecord.Metadata]
    }
    static func isValidID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumIDBytes && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func lightweight(_ article: Article) throws -> Article {
        guard article.hasValidContentIdentity else { throw Failure.invalidRecord }
        let metadata = FavoritesRecord.Metadata(article)
        guard metadata.valid else { throw Failure.invalidRecord }
        return metadata.article
    }
    /// Structural/field validation is bounded and does not encode JSON on MainActor.
    static func validate(_ record: FavoritesRecord, namespace: FavoritesNamespace) throws {
        try validateStructure(record)
        guard namespace != .guest || (record.pending.isEmpty && !record.requiresRecovery) else { throw Failure.invalidRecord }
    }
    static func validateStructure(_ record: FavoritesRecord) throws {
        guard record.base.count <= maximumEntries, record.pending.count <= maximumPending else { throw Failure.limitExceeded }
        guard Set(record.base.map(\.id)).count == record.base.count,
              Set(record.pending.map(\.articleID)).count == record.pending.count,
              Set(record.pending.map(\.intentID)).count == record.pending.count,
              record.base.allSatisfy(\.valid) else { throw Failure.invalidRecord }
        for intent in record.pending {
            guard intent.payload.valid, intent.article.valid, intent.payload.id == intent.article.id else { throw Failure.invalidRecord }
            switch intent.phase {
            case .queued: guard intent.attemptID == nil else { throw Failure.invalidRecord }
            case .started, .acknowledged, .failed: guard intent.attemptID != nil else { throw Failure.invalidRecord }
            case .blocked: break
            }
            guard intent.attemptID == nil || record.requiresRecovery else { throw Failure.invalidRecord }
            if intent.phase != .blocked {
                guard intent.payload.article.bodyRevision == intent.article.article.bodyRevision else { throw Failure.invalidRecord }
            }
        }
        // Bound queued scalar memory before encoding; JSON escaping is checked
        // again by the I/O worker's final encoded-byte limit.
        let metadata = record.base + record.pending.flatMap { [$0.payload, $0.article] }
        var bytes = 128 + record.pending.count * 128
        for row in metadata {
            bytes += row.boundedUTF8Bytes
            guard bytes <= maximumRecordBytes else { throw Failure.limitExceeded }
        }
        let pendingIDs = Set(record.pending.map(\.articleID))
        let visible = record.base.filter { !pendingIDs.contains($0.id) }.count + record.pending.filter(\.enabled).count
        guard visible <= maximumEntries else { throw Failure.limitExceeded }
    }
    static func decode(_ data: Data, namespace: FavoritesNamespace) throws -> FavoritesRecord {
        let object = try root(data)
        guard object["schemaVersion"] as? Int == 2 else { throw Failure.unsupportedVersion }
        guard Set(object.keys) == ["schemaVersion", "namespace", "recordRevision", "base", "pending", "requiresRecovery"],
              let base = object["base"] as? [[String: Any]], base.count <= maximumEntries,
              let pending = object["pending"] as? [[String: Any]], pending.count <= maximumPending,
              base.allSatisfy(metadataFields), pending.allSatisfy({ row in
                  guard Set(row.keys).isSubset(of: ["intentID", "payload", "article", "enabled", "phase", "attemptID"]),
                        let payload = row["payload"] as? [String: Any], let article = row["article"] as? [String: Any] else { return false }
                  return metadataFields(payload) && metadataFields(article)
              }), let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.namespace == namespace.recordBinding else { throw Failure.invalidRecord }
        let record = FavoritesRecord(recordRevision: envelope.recordRevision, base: envelope.base, pending: envelope.pending,
                                     requiresRecovery: envelope.requiresRecovery)
        try validate(record, namespace: namespace)
        return record
    }
    static func encode(_ record: FavoritesRecord, namespace: FavoritesNamespace) throws -> Data {
        try validate(record, namespace: namespace)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Envelope(schemaVersion: 2, namespace: namespace.recordBinding,
                                              recordRevision: record.recordRevision, base: record.base,
                                              pending: record.pending, requiresRecovery: record.requiresRecovery))
        guard data.count <= maximumRecordBytes else { throw Failure.limitExceeded }
        return data
    }
    /// Explicit known-owner migration only. It cannot reconstruct old intentions or ACKs.
    static func migrateLegacyV1(_ data: Data, namespace: FavoritesNamespace) throws -> FavoritesRecord {
        let object = try root(data)
        guard object["schemaVersion"] as? Int == 1 else { throw Failure.unsupportedVersion }
        guard Set(object.keys) == ["schemaVersion", "namespace", "entries"],
              let entries = object["entries"] as? [[String: Any]], entries.count <= maximumEntries,
              entries.allSatisfy(metadataFields), let envelope = try? JSONDecoder().decode(LegacyEnvelope.self, from: data),
              envelope.namespace == namespace.recordBinding else { throw Failure.invalidRecord }
        let record = FavoritesRecord(base: envelope.entries, requiresRecovery: namespace != .guest)
        try validate(record, namespace: namespace)
        return record
    }
    private static func root(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidRecord }
        return object
    }
    private static func metadataFields(_ row: [String: Any]) -> Bool {
        Set(row.keys).isSubset(of: FavoritesRecord.Metadata.keys)
            && (row["favoriteSavedAt"] == nil || FavoriteArticlesLogic.decodedSavedAt(row["favoriteSavedAt"]) != nil)
            && ["contentLanguage", "sourceArticleID", "cmsLocaleId"].allSatisfy {
                row[$0] == nil || row[$0] is String
            }
    }
}
