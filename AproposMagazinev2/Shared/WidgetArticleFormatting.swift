import Foundation

enum WidgetArticleFormatting {
    static func topicLine(for article: WidgetArticle) -> String {
        let topic = article.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return "" }

        if let dateLabel = relativeDateLabel(for: article.date) {
            return "\(topic) · \(dateLabel)"
        }
        return topic
    }

    static func ctaText(for article: WidgetArticle) -> String {
        article.stjerne != nil ? "Læs anmeldelsen →" : "Læs artikelen →"
    }

    static func starRatingText(for rating: Int) -> String {
        let filled = min(max(rating, 0), 5)
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
    }

    static func relativeDateLabel(for dateString: String) -> String? {
        guard let date = parseDate(dateString) else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let articleDay = calendar.startOfDay(for: date)

        if calendar.isDate(articleDay, inSameDayAs: today) {
            return "I dag"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(articleDay, inSameDayAs: yesterday) {
            return "I går"
        }

        let daysBetween = calendar.dateComponents([.day], from: articleDay, to: today).day ?? Int.max
        if daysBetween >= 2, daysBetween <= 7 {
            return shortDanishDate(from: date)
        }

        return nil
    }

    private static func shortDanishDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "d. MMM"

        var label = formatter.string(from: date)
        if label.hasSuffix(".") {
            label.removeLast()
        }
        return label
    }

    private static func parseDate(_ rawDate: String) -> Date? {
        let value = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "dd.MM.yyyy",
            "d.M.yyyy",
            "dd/MM/yyyy",
            "d/M/yyyy",
            "d. MMMM yyyy",
            "dd. MMMM yyyy",
            "d. MMM yyyy",
            "dd. MMM yyyy"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "da_DK")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
