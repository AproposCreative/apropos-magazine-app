import Foundation

/// The exact mirror decoder used by FirestoreArticleService, independent of the
/// Firestore SDK transport. Empty public results from explicit withdrawal rows
/// are authoritative; malformed public documents must not look like emptiness.
enum CMSArticleDocumentCodec {
    struct FeedResult {
        let articles: [Article]
        let failures: [String]
    }

    static func decodeFeed(_ documents: [(id: String, data: [String: Any])]) throws -> FeedResult {
        var articles = [Article]()
        var failures = [String]()
        for document in documents {
            if CMSMirrorDocumentPolicy.isWithdrawn(document.data) { continue }
            do {
                let article = try decodeArticle(from: document.data, stripBodyContent: true, expectedID: document.id)
                if article.isPubliclyPublished { articles.append(article) }
            } catch {
                failures.append("\(document.id): \(error.localizedDescription)")
            }
        }
        if articles.isEmpty, !failures.isEmpty {
            throw FirestoreArticleError.decodeFailed(failures.joined(separator: "; "))
        }
        return FeedResult(articles: articles, failures: failures)
    }

    static func decodeArticle(from data: [String: Any], stripBodyContent: Bool = false, expectedID: String? = nil) throws -> Article {
        guard !CMSMirrorDocumentPolicy.isWithdrawn(data) else { throw FirestoreArticleError.withdrawn }
        var payload: [String: Any] = [:]

        if let id = data["id"] as? String, CMSMirrorDocumentPolicy.isSafeDocumentID(id) {
            if let expectedID, id != expectedID { throw FirestoreArticleError.decodeFailed("Mirror article identity mismatch") }
            payload["id"] = id
        } else {
            throw FirestoreArticleError.decodeFailed("Missing article id")
        }

        if var fieldData = data["fieldData"] as? [String: Any] {
            if stripBodyContent {
                fieldData.removeValue(forKey: "content")
            }
            payload["fieldData"] = fieldData
        } else {
            payload["fieldData"] = [:]
        }

        if let isArchived = data["isArchived"] {
            payload["isArchived"] = isArchived
        }
        if let isDraft = data["isDraft"] {
            payload["isDraft"] = isDraft
        }
        if let createdOn = data["createdOn"] {
            payload["createdOn"] = createdOn
        }
        if let lastPublished = data["lastPublished"] {
            payload["lastPublished"] = lastPublished
        }

        for key in ["lastUpdated", "contentRevision", "contentLanguage", "sourceArticleID", "cmsLocaleId"] {
            if let value = data[key] { payload[key] = value }
        }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Article.self, from: jsonData)
    }
}
