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

    /// Returns a locally cached file URL when the article is saved offline; otherwise the remote URL.
    func offlineDisplayImageURL(for remote: URL?) -> URL? {
        OfflineArticleImageCache.shared.displayURL(for: remote, articleId: id)
    }

    var offlineListThumbnailURL: URL? {
        offlineDisplayImageURL(for: listThumbnailURL)
    }
}
