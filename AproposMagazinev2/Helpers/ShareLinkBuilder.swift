import Foundation

enum ShareLinkBuilder {
    private static let host = "aproposmagazine.com"
    private static let segmentCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func articleURL(slug: String?, articleId: String) -> URL? {
        let candidates = [slug, articleId].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let identifier = candidates.first(where: DeepLink.isValidIdentifier),
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: segmentCharacters) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = "/article/" + encoded
        guard let url = components.url, DeepLink.parse(url) == .article(id: identifier) else { return nil }
        return url
    }

    static func podcastClipURL(
        slug: String?,
        articleId: String,
        timestampSeconds: Int
    ) -> URL? {
        guard let article = articleURL(slug: slug, articleId: articleId),
              case .article(let identifier) = DeepLink.parse(article),
              var components = URLComponents(url: article, resolvingAgainstBaseURL: false) else { return nil }
        let clamped = min(max(0, timestampSeconds), DeepLink.maximumStartSeconds)
        components.queryItems = [URLQueryItem(name: "t", value: "\(clamped)")]
        guard let url = components.url,
              DeepLink.parse(url) == .podcast(id: identifier, startSeconds: clamped) else { return nil }
        return url
    }

    static func timestampSeconds(_ seconds: TimeInterval) -> Int {
        // Clip links and their label share the same supported range. Bound the
        // floating-point value before Int conversion, including nonfinite input.
        let finite = seconds.isFinite ? seconds : 0
        let bounded = min(max(0, finite), TimeInterval(DeepLink.maximumStartSeconds))
        return Int(bounded.rounded())
    }

    static func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let total = timestampSeconds(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
