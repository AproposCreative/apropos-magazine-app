import Foundation

/// Presentation of the CMS editorial date only. It never substitutes a creation,
/// republish or sorting date. A timestamp is shown in the magazine's Danish time
/// zone; a date without a time retains its calendar day.
@MainActor
final class ArticleDisplayDateFormatter {
    static let shared = ArticleDisplayDateFormatter()

    private struct CachedLabel { let text: String? }
    private let parsers: [DateFormatter]
    private let outputs: [ArticleContentLanguage: DateFormatter]
    private let maximumKeys: Int
    private var cache: [String: CachedLabel] = [:]

    init(maximumKeys: Int = 512) {
        self.maximumKeys = max(1, maximumKeys)
        let formats: [(String, String)] = [
            ("en_US_POSIX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"),
            ("en_US_POSIX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"),
            ("en_US_POSIX", "yyyy-MM-dd HH:mm:ss"),
            ("en_US_POSIX", "yyyy-MM-dd"),
            ("da_DK", "d.M.yyyy"),
            ("da_DK", "d/M/yyyy"),
            ("da_DK", "d. MMMM yyyy"),
            ("da_DK", "d. MMM yyyy"),
            ("en_US_POSIX", "MMMM d, yyyy"),
            ("en_US_POSIX", "MMM d, yyyy"),
            ("en_US_POSIX", "MMMM d yyyy"),
            ("en_US_POSIX", "MMM d yyyy")
        ]
        parsers = formats.map { locale, format in
            Self.formatter(locale: locale, format: format)
        }
        outputs = [
            .danish: Self.formatter(locale: "da_DK", format: "d. MMMM yyyy"),
            .english: Self.formatter(locale: "en_GB", format: "d MMMM yyyy")
        ]
    }

    func string(from raw: String?, language: ArticleContentLanguage = .danish) -> String? {
        guard let raw, raw.utf8.count <= 128 else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let cacheKey = language.rawValue + "|" + key
        if let cached = cache[cacheKey] { return cached.text }

        let date = parsers.lazy.compactMap { $0.date(from: key) }.first
        let label = date.flatMap { outputs[language]?.string(from: $0) }
        if cache.count >= maximumKeys { cache.removeAll(keepingCapacity: true) }
        // Invalid values are cached too. Repeated card initialization must not
        // keep parsing malformed CMS data, and raw machine strings stay hidden.
        cache[cacheKey] = CachedLabel(text: label)
        return label
    }

    private static func formatter(locale: String, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }
}
