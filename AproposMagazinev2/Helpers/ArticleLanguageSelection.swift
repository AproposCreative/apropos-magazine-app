import Foundation

/// Locale selection never guesses a translation from its title or slug. The
/// published mirror contract owns identity; legacy unlabelled articles are DA.
enum ArticleLanguageSelection {
    static func mirrorLanguage(forReaderID id: String) -> ArticleContentLanguage {
        ArticleContentLanguage.isEnglishArticleID(id) ? .english : .danish
    }
    static func visible(_ articles: [Article], language: ArticleContentLanguage) -> [Article] {
        articles.filter { $0.hasValidContentIdentity && $0.contentLanguage == language }
    }

    static func identifier(_ identifier: String, language: ArticleContentLanguage) -> String {
        let raw = identifier.hasPrefix("en_") ? String(identifier.dropFirst(3)) : identifier
        guard WebflowLiveCatalogLoader.isCMSIdentifier(raw), raw == raw.lowercased() else { return identifier }
        return language == .english ? "en_" + raw : raw
    }

    /// The caller reads at most three slug rows. Three means the bounded query
    /// may be truncated; reject it instead of arbitrarily selecting one locale.
    static func uniqueSlugDocument(_ documents: [(id: String, data: [String: Any])],
                                   language: ArticleContentLanguage) throws -> (id: String, data: [String: Any])? {
        guard documents.count < 3 else { throw FirestoreArticleError.decodeFailed("Ambiguous identity") }
        let matches = try documents.filter {
            guard $0.data["id"] as? String == $0.id else {
                throw FirestoreArticleError.decodeFailed("Mirror article identity mismatch")
            }
            for key in ["contentLanguage", "sourceArticleID", "cmsLocaleId"] {
                if let value = $0.data[key], !(value is String),
                   !(key != "contentLanguage" && value is NSNull) {
                    throw FirestoreArticleError.decodeFailed("Invalid article locale")
                }
            }
            guard let declared = ArticleContentLanguage.validated(articleID: $0.id,
                languageCode: $0.data["contentLanguage"] as? String,
                sourceArticleID: $0.data["sourceArticleID"] as? String,
                cmsLocaleId: $0.data["cmsLocaleId"] as? String) else {
                throw FirestoreArticleError.decodeFailed("Invalid article locale")
            }
            return declared == language
        }
        guard matches.count <= 1 else { throw FirestoreArticleError.decodeFailed("Ambiguous identity") }
        return matches.first
    }
}
