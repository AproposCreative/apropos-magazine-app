import Foundation

extension Article {
    /// Preferred thumbnail URL for list rows (mobile image first).
    var listThumbnailURL: URL? {
        if let mobileImageURL {
            return mobileImageURL
        }
        if let thumbURL {
            return thumbURL
        }
        if let coverURL {
            return coverURL
        }

        var mutable = self
        let fallback = mutable.thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return nil }
        return URL(string: fallback)
    }
}
