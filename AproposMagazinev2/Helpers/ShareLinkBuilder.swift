import Foundation

enum ShareLinkBuilder {
    private static let baseURL = "https://aproposmagazine.com"

    static func articleURL(slug: String?, articleId: String) -> URL? {
        let pathSegment = sanitizedPathSegment(slug ?? articleId)
        guard !pathSegment.isEmpty else { return nil }
        return URL(string: "\(baseURL)/article/\(pathSegment)")
    }

    static func podcastClipURL(
        slug: String?,
        articleId: String,
        timestampSeconds: Int
    ) -> URL? {
        guard var components = articleURL(slug: slug, articleId: articleId).flatMap({
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }) else {
            return nil
        }

        let clamped = max(0, timestampSeconds)
        components.queryItems = [URLQueryItem(name: "t", value: "\(clamped)")]
        return components.url
    }

    static func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func sanitizedPathSegment(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
