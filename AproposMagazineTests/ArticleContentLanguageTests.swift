import XCTest
@testable import Apropos

/// The actual CMS/cache/favorite codecs and body policies, without SDK or disk effects.
final class ArticleContentLanguageTests: XCTestCase {
    private let source = "6ae1f9da0e01d3d2ff34859f"
    private var englishID: String { "en_" + source }

    private func fields(english: Bool = true) -> [String: Any] {
        var value: [String: Any] = [
            "id": english ? englishID : source,
            "fieldData": ["name": english ? "An English article" : "En dansk artikel",
                "slug": english ? "english-story" : "dansk-artikel", "content": english ? "<p>English body</p>" : "<p>Dansk tekst</p>",
                "intro": "", "topic": ""],
            "isDraft": false, "isArchived": false, "lastPublished": "2026-10-30T12:00:00Z",
            "createdOn": "2026-10-28T10:00:00Z", "contentRevision": "shared-revision-for-isolation-test"
        ]
        if english {
            value["contentLanguage"] = "en"
            value["sourceArticleID"] = source
            value["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
        }
        return value
    }

    private func decode(_ value: [String: Any]) throws -> Article {
        try CMSArticleDocumentCodec.decodeArticle(from: value, expectedID: value["id"] as? String)
    }

    func testLegacyDanishAndExplicitPrimaryLocaleKeepTheirIDsAndCacheShape() throws {
        let legacy = try decode(fields(english: false))
        XCTAssertEqual(legacy.id, source)
        XCTAssertEqual(legacy.contentLanguage, .danish)
        XCTAssertTrue(legacy.hasValidContentIdentity)
        var primaryFields = fields(english: false)
        primaryFields["cmsLocaleId"] = ArticleContentLanguage.danishCMSLocaleID
        let primary = try decode(primaryFields)
        XCTAssertEqual(primary.id, legacy.id)
        XCTAssertEqual(primary.contentLanguage, .danish)
        let encoded = try JSONEncoder().encode(legacy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["contentLanguage"])
        XCTAssertNil(object["sourceArticleID"])
        XCTAssertNil(object["cmsLocaleId"])
        for id in ["legacy-story", "fixture-a", "en_legacy-story", source] {
            let article = Article(id: id, name: "Dansk", slug: id, content: "", intro: "", topicID: "")
            XCTAssertEqual(try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(article)).id, id)
            XCTAssertTrue(article.hasValidContentIdentity)
        }
        XCTAssertEqual(ArticleContentLanguage(preference: .danish), .danish)
        XCTAssertEqual(ArticleContentLanguage(preference: .english), .english)
        XCTAssertNil(ArticleContentLanguage(preference: .swedish))
        XCTAssertNil(ArticleContentLanguage(preference: .norwegian))
    }

    func testEnglishIdentitySurvivesBodyCopiesAndActualColdCatalogBytes() throws {
        let original = try decode(fields())
        XCTAssertEqual(original.id, englishID)
        XCTAssertNotEqual(original.id, source)
        XCTAssertEqual(original.sourceArticleID, source)
        XCTAssertEqual(original.contentLanguage, .english)
        XCTAssertEqual(original.cmsLocaleId, ArticleContentLanguage.englishCMSLocaleID)
        XCTAssertEqual(ArticleContentLanguage.english.articleID(sourceID: source), englishID)
        XCTAssertTrue(original.hasValidContentIdentity)
        for article in [original, original.strippingBodyContent(), original.replacingBodyContent("<p>Updated English</p>")] {
            let cold = try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(article))
            XCTAssertEqual(cold, article)
            XCTAssertEqual(cold.contentLanguage, .english)
            XCTAssertTrue(cold.hasValidContentIdentity)
        }
        let danish = try decode(fields(english: false))
        let bytes = try JSONEncoder().encode(CacheData(articles: [danish, original], timestamp: Date(timeIntervalSince1970: 100), version: "1.3"))
        let cold = try JSONDecoder().decode(CacheData.self, from: bytes)
        XCTAssertEqual(cold.articles.map(\.id), [source, englishID])
        XCTAssertEqual(cold.articles.map(\.contentLanguage), [.danish, .english])
        XCTAssertEqual(cold.articles.map(\.content), [danish.content, original.content])
    }

    func testIncompleteUnknownAndContradictoryNamespaceContractsAreRejected() throws {
        var cases: [[String: Any]] = []
        for missing in ["contentLanguage", "sourceArticleID", "cmsLocaleId"] {
            var value = fields(); value.removeValue(forKey: missing); cases.append(value)
        }
        for (key, invalid) in [("contentLanguage", "sv"), ("contentLanguage", "EN"),
            ("sourceArticleID", String(repeating: "f", count: 24)),
            ("sourceArticleID", source.uppercased()), ("cmsLocaleId", ArticleContentLanguage.danishCMSLocaleID),
            ("id", source), ("id", "en_../outside")] {
            var value = fields(); value[key] = invalid; cases.append(value)
        }
        var falselyPrimary = fields(english: false)
        falselyPrimary["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID; cases.append(falselyPrimary)
        var unknownPrimary = fields(english: false)
        unknownPrimary["contentLanguage"] = "unknown"; cases.append(unknownPrimary)
        var nullDeclaration = fields(); nullDeclaration["contentLanguage"] = NSNull(); cases.append(nullDeclaration)
        for value in cases {
            XCTAssertThrowsError(try decode(value))
            XCTAssertThrowsError(try JSONDecoder().decode(Article.self, from: JSONSerialization.data(withJSONObject: value)))
        }
        XCTAssertThrowsError(try CMSArticleDocumentCodec.decodeArticle(from: fields(), expectedID: source))
        let invalid = Article(id: englishID, name: "Not admitted", slug: "x", content: "body", intro: "", topicID: "",
            lastPublished: "2026-10-30T12:00:00Z", contentLanguage: .english)
        XCTAssertFalse(invalid.hasValidContentIdentity)
        XCTAssertFalse(invalid.isPubliclyPublished)
        XCTAssertThrowsError(try JSONEncoder().encode(invalid))
    }

    func testSameSourceAndRevisionCannotBorrowTheOtherLanguagesBody() throws {
        let danish = try decode(fields(english: false))
        let english = try decode(fields())
        let result = ArticleFeedSnapshot.merging([danish.strippingBodyContent(), english.strippingBodyContent()],
            retainingDetailsFrom: [danish])
        XCTAssertEqual(result.first(where: { $0.id == source })?.content, danish.content)
        XCTAssertEqual(result.first(where: { $0.id == englishID })?.content, "")
        let cached = ArticleDetailContentPolicy.cachedArticle(id: englishID, feed: english.strippingBodyContent(),
            full: danish, initial: danish)
        XCTAssertEqual(cached?.id, englishID)
        XCTAssertEqual(cached?.content, "")
        XCTAssertNotEqual(ArticleDetailRequestIdentity(danish), ArticleDetailRequestIdentity(english))
    }

    func testBothLanguagesRetainTheirMetadataAcrossFavoriteCloudAndJournalReload() throws {
        let danish = try decode(fields(english: false)), english = try decode(fields())
        for article in [danish, english] {
            let cloud = FavoriteArticleDocumentCodec.decode(FavoriteArticleDocumentCodec.encode(article), documentID: article.id)
            XCTAssertEqual(cloud, article)
            XCTAssertTrue(cloud.hasValidContentIdentity)
        }
        let record = FavoritesRecord(articles: [danish, english])
        let bytes = try FavoritesRecordCodec.encode(record, namespace: .guest)
        let cold = try FavoritesRecordCodec.decode(bytes, namespace: .guest)
        XCTAssertEqual(Set(cold.articles.map(\.id)), [source, englishID])
        let restored = try XCTUnwrap(cold.articles.first { $0.id == englishID })
        XCTAssertEqual(restored.contentLanguage, .english)
        XCTAssertEqual(restored.sourceArticleID, source)
        XCTAssertEqual(restored.cmsLocaleId, ArticleContentLanguage.englishCMSLocaleID)
        XCTAssertTrue(restored.hasValidContentIdentity)
        XCTAssertEqual(restored.content, "")
        XCTAssertEqual(cold.articles.first(where: { $0.id == source })?.contentLanguage, .danish)
    }

    func testMalformedFavoriteIdentityCannotBecomeDanishOrSurviveAStoredRoundTrip() throws {
        let article = try decode(fields())
        let validCloud = FavoriteArticleDocumentCodec.encode(article)
        for (key, value) in [("contentLanguage", "unknown"), ("sourceArticleID", "other"), ("cmsLocaleId", "unknown")] {
            var cloud = validCloud; cloud[key] = value
            let invalid = FavoriteArticleDocumentCodec.decode(cloud, documentID: englishID)
            XCTAssertNil(invalid.contentLanguage)
            XCTAssertFalse(invalid.hasValidContentIdentity)
            XCTAssertFalse(invalid.isPubliclyPublished)
            XCTAssertThrowsError(try FavoritesRecordCodec.lightweight(invalid))
            XCTAssertThrowsError(try FavoritesRecordCodec.encode(FavoritesRecord(articles: [invalid]), namespace: .guest))
        }
        let aliased = FavoriteArticleDocumentCodec.decode(validCloud, documentID: source)
        XCTAssertFalse(aliased.hasValidContentIdentity)
        let bytes = try FavoritesRecordCodec.encode(.init(articles: [article]), namespace: .guest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var rows = try XCTUnwrap(object["base"] as? [[String: Any]])
        rows[0].removeValue(forKey: "sourceArticleID"); object["base"] = rows
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(JSONSerialization.data(withJSONObject: object), namespace: .guest))
    }
}
