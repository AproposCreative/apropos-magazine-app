import Foundation

/// Create and keep each instance on one worker. There is no shared formatter,
/// default storage or SDK. This deliberately has no Sendable conformance.
final class ArticlePresentationDateParser {
    struct Keys: Equatable {
        let created: Date?
        let feed: Date
    }
    private struct RawKey: Hashable { let created: String?; let editorial: String? }
    private let fractional: ISO8601DateFormatter
    private let iso: ISO8601DateFormatter
    private let editorialISO: ISO8601DateFormatter
    private let alternatives: [DateFormatter]
    private let danish: [DateFormatter]
    private let english: [DateFormatter]
    private var cache: [RawKey: Keys] = [:]
    private let maximumKeys: Int
    private(set) var dateParses = 0
    private(set) var sortOperations = 0

    init(maximumKeys: Int = 10_000) {
        self.maximumKeys = max(1, maximumKeys)
        fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        editorialISO = ISO8601DateFormatter()
        alternatives = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss"].map {
            let value = DateFormatter(); value.dateFormat = $0; return value
        }
        danish = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "dd.MM.yyyy", "d.M.yyyy", "dd/MM/yyyy", "d/M/yyyy",
                  "d. MMMM yyyy", "dd. MMMM yyyy", "d. MMM yyyy", "dd. MMM yyyy"].map {
            let value = DateFormatter(); value.locale = Locale(identifier: "da_DK")
            value.calendar = Calendar(identifier: .gregorian); value.dateFormat = $0; return value
        }
        english = ["MMMM d, yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMM d yyyy"].map {
            let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
            value.calendar = Calendar(identifier: .gregorian); value.dateFormat = $0; return value
        }
    }
    func dates(for article: Article) -> Keys {
        let key = RawKey(created: article.createdOn, editorial: article.date)
        if let value = cache[key] { return value }
        let created = timestamp(article.createdOn), editorial = editorialDate(article.date)
        let value = Keys(created: created, feed: [created, editorial].compactMap { $0 }.max() ?? .distantPast)
        if cache.count >= maximumKeys { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
        return value
    }
    func sortedByCreatedNewestFirst(_ articles: [Article]) -> [Article] {
        sortOperations += 1
        let prepared = articles.map { (article: $0, dates: dates(for: $0)) }
        return prepared.sorted { lhs, rhs in
            let left = lhs.article.createdOn ?? "", right = rhs.article.createdOn ?? ""
            if !left.isEmpty, !right.isEmpty, left != right { return left > right }
            if lhs.dates.feed != rhs.dates.feed { return lhs.dates.feed > rhs.dates.feed }
            return lhs.article.id > rhs.article.id
        }.map(\.article)
    }
    private func timestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        dateParses += 1
        if let parsed = fractional.date(from: value) ?? iso.date(from: value) { return parsed }
        for formatter in alternatives { if let parsed = formatter.date(from: value) { return parsed } }
        return nil
    }
    private func editorialDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        dateParses += 1
        if let parsed = editorialISO.date(from: value) { return parsed }
        for formatter in danish + english { if let parsed = formatter.date(from: value) { return parsed } }
        return nil
    }
}
