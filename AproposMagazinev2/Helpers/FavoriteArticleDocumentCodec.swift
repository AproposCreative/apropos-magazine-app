import Foundation

/// The shared snapshot format for both one-shot and realtime favorites reads.
/// Keep access and publication metadata with offline bodies across devices.
enum FavoriteArticleDocumentCodec {
    static func encode(_ article: Article) -> [String: Any] {
        var fields: [String: Any] = [
            "id": article.id,
            "name": article.name ?? "",
            "slug": article.slug ?? "",
            "content": article.content ?? "",
            "intro": article.intro ?? "",
            "pressAccreditation": article.pressAccreditation
        ]
        fields["trailer"] = article.trailer
        fields["stjerne"] = article.stjerne
        fields["topicID"] = article.topicID
        fields["topicsIDs"] = article.topicsIDs
        fields["sectionID"] = article.sectionID
        fields["authorID"] = article.authorID
        fields["mobileImageURL"] = article.mobileImageURL?.absoluteString
        fields["thumbURL"] = article.thumbURL?.absoluteString
        fields["coverURL"] = article.coverURL?.absoluteString
        fields["location"] = article.location
        fields["subtitle"] = article.subtitle
        fields["fotoCredit"] = article.fotoCredit
        fields["isArchived"] = article.isArchived
        fields["isDraft"] = article.isDraft
        fields["date"] = article.date
        fields["createdOn"] = article.createdOn
        fields["lastPublished"] = article.lastPublished
        fields["lastUpdated"] = article.lastUpdated
        fields["contentRevision"] = article.contentRevision
        if !article.hasValidContentIdentity || article.contentLanguage == .english || article.sourceArticleID != nil || article.cmsLocaleId != nil {
            fields["contentLanguage"] = article.contentLanguage?.rawValue ?? ""
        }
        fields["sourceArticleID"] = article.sourceArticleID
        fields["cmsLocaleId"] = article.cmsLocaleId
        fields["savedAt"] = article.favoriteSavedAt
        fields["featured"] = article.featured
        fields["isPremium"] = article.isPremium
        return fields
    }

    static func decode(_ fields: [String: Any], documentID: String) -> Article {
        let candidate = fields["id"] as? String ?? documentID
        let id = CMSMirrorDocumentPolicy.isSafeDocumentID(candidate) ? candidate : documentID
        let sourceArticleID = fields["sourceArticleID"] as? String
        let cmsLocaleId = fields["cmsLocaleId"] as? String
        let typedMetadata = ["contentLanguage", "sourceArticleID", "cmsLocaleId"].allSatisfy {
            fields[$0] == nil || fields[$0] is String
        }
        let namespaceBound = (!ArticleContentLanguage.isEnglishArticleID(id)
            && !ArticleContentLanguage.isEnglishArticleID(documentID)) || id == documentID
        let language = typedMetadata && namespaceBound ? ArticleContentLanguage.validated(articleID: id,
            languageCode: fields["contentLanguage"] as? String, sourceArticleID: sourceArticleID,
            cmsLocaleId: cmsLocaleId) : nil
        return Article(
            id: id,
            name: fields["name"] as? String ?? "",
            slug: fields["slug"] as? String ?? "",
            content: fields["content"] as? String ?? "",
            trailer: fields["trailer"] as? String,
            intro: fields["intro"] as? String ?? "",
            stjerne: fields["stjerne"] as? Int,
            topicID: fields["topicID"] as? String ?? "",
            topicsIDs: fields["topicsIDs"] as? [String],
            sectionID: fields["sectionID"] as? String,
            authorID: fields["authorID"] as? String,
            mobileImageURL: (fields["mobileImageURL"] as? String).flatMap(URL.init(string:)),
            thumbURL: (fields["thumbURL"] as? String).flatMap(URL.init(string:)),
            coverURL: (fields["coverURL"] as? String).flatMap(URL.init(string:)),
            location: fields["location"] as? String,
            subtitle: fields["subtitle"] as? String,
            fotoCredit: fields["fotoCredit"] as? String,
            isDraft: fields["isDraft"] as? Bool,
            isArchived: fields["isArchived"] as? Bool,
            date: fields["date"] as? String,
            createdOn: fields["createdOn"] as? String,
            lastPublished: fields["lastPublished"] as? String,
            lastUpdated: fields["lastUpdated"] as? String,
            contentRevision: fields["contentRevision"] as? String,
            featured: fields["featured"] as? Bool,
            isPremium: fields["isPremium"] as? Bool,
            pressAccreditation: fields["pressAccreditation"] as? Bool ?? false,
            contentLanguage: language, sourceArticleID: sourceArticleID, cmsLocaleId: cmsLocaleId
        ).withFavoriteSavedAt(FavoriteArticlesLogic.decodedSavedAt(fields["savedAt"]))
    }
}
