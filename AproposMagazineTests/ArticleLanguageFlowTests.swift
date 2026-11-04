import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class ArticleLanguageFlowTests: XCTestCase {
    private let sourceID = "0123456789abcdef01234567"
    private func article(_ language: ArticleContentLanguage) -> Article {
        Article(id: language == .danish ? sourceID : "en_" + sourceID,
            name: language.displayName, slug: "same-slug", content: language.rawValue,
            intro: language.displayName, topicID: "topic", isDraft: false,
            lastPublished: "2026-10-30T00:00:00Z", contentRevision: language.rawValue + "-v1", contentLanguage: language,
            sourceArticleID: sourceID, cmsLocaleId: language.cmsLocaleID)
    }

    func testBundledConfigurationLoadsEnglishThroughMirrorDecoderAndLanguageSelection() async throws {
        let suite = "language-bundled-mirror-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(userDefaults: defaults)
        let vm = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init(), languagePreferences: preferences)
        var requested: [ArticleContentLanguage] = []
        let enabled = ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:])
        let sources = try await ArticleMirrorCatalog.load(englishEnabled: enabled, stillCurrent: { true }) { language in
            requested.append(language)
            let readerID = language == .english ? "en_" + self.sourceID : self.sourceID
            var data: [String: Any] = ["id": readerID, "isDraft": false, "isArchived": false,
                "lastPublished": "2026-11-03T10:00:00Z", "contentRevision": language.rawValue + "-current",
                "fieldData": ["name": language.displayName, "slug": "same-slug", "intro": "Intro", "topic": "topic",
                    "content": language == .english ? "<p>Exact English body</p>" : "<p>Dansk tekst</p>"]]
            if language == .english {
                data["contentLanguage"] = "en"; data["sourceArticleID"] = self.sourceID
                data["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
            }
            return .init(language: language, documents: [(readerID, data)], isFromCache: false, hasPendingWrites: false)
        }
        let decoded = try CMSArticleDocumentCodec.decodeFeed(sources.flatMap(\.documents))
        XCTAssertTrue(decoded.failures.isEmpty)
        vm.articles = decoded.articles
        XCTAssertEqual(vm.visibleArticles.map(\.id), [sourceID])
        preferences.updateArticleLanguage(.english)
        XCTAssertEqual(requested, [.danish, .english], "The packaged configuration must actually admit the English source")
        XCTAssertEqual(vm.visibleArticles.map(\.id), ["en_" + sourceID])
        let englishDocument = try XCTUnwrap(sources.first { $0.language == .english }?.documents.first)
        let detail = try CMSArticleDocumentCodec.decodeArticle(from: englishDocument.data, expectedID: "en_" + sourceID)
        XCTAssertEqual(detail.content, "<p>Exact English body</p>")
        XCTAssertEqual(detail.sourceArticleID, sourceID)
        XCTAssertEqual(detail.contentLanguage, .english)
        XCTAssertEqual(detail.cmsLocaleId, ArticleContentLanguage.englishCMSLocaleID)
        vm.articles = ArticleFeedSnapshot.merging(decoded.articles, retainingDetailsFrom: [detail])
        let bytes = try JSONEncoder().encode(CacheData(articles: vm.articles, timestamp: Date(timeIntervalSince1970: 100), version: "1.3"))
        vm.articles = try JSONDecoder().decode(CacheData.self, from: bytes).articles
        XCTAssertEqual(vm.visibleArticles.first?.content, "<p>Exact English body</p>")
        preferences.updateArticleLanguage(.danish)
        XCTAssertEqual(vm.visibleArticles.map(\.id), [sourceID])
        XCTAssertNil(FirebaseApp.app())
    }

    func testSettingsProjectionPersistsWithoutMutatingCanonicalCatalogOrBorrowingBody() throws {
        let suite = "language-flow-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(userDefaults: defaults)
        let vm = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init(), languagePreferences: preferences)
        let original = [article(.danish), article(.english)]
        vm.articles = original
        var displayed: [[String]] = []
        let observation = vm.visibleArticleChanges.sink { displayed.append($0.map(\.id)) }
        XCTAssertEqual(vm.visibleArticles.map(\.content), ["da"])
        preferences.updateArticleLanguage(.english)
        XCTAssertEqual(vm.visibleArticles.map(\.content), ["en"])
        XCTAssertEqual(displayed.last, ["en_" + sourceID])
        XCTAssertEqual(vm.articles, original)
        let coldPreferences = PreferencesManager(userDefaults: defaults)
        XCTAssertEqual(coldPreferences.articleLanguage, .english)
        vm.articles = [original[0]]
        XCTAssertTrue(vm.visibleArticles.isEmpty, "English emptiness never borrows Danish")
        preferences.updateArticleLanguage(.danish)
        XCTAssertEqual(vm.visibleArticles.map(\.id), [sourceID])
        XCTAssertEqual(vm.articles, [original[0]])
        XCTAssertNil(FirebaseApp.app())
        withExtendedLifetime(observation) {}
    }

    func testTwoLocalesWithSameSlugResolveBySelectedLanguageAndDuplicatesStayAmbiguous() throws {
        func document(_ value: Article) throws -> (id: String, data: [String: Any]) {
            let bytes = try JSONEncoder().encode(value)
            return (value.id, try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]))
        }
        let da = try document(article(.danish)), en = try document(article(.english))
        XCTAssertEqual(try ArticleLanguageSelection.uniqueSlugDocument([da, en], language: .danish)?.id, da.id)
        XCTAssertEqual(try ArticleLanguageSelection.uniqueSlugDocument([da, en], language: .english)?.id, en.id)
        XCTAssertNil(try ArticleLanguageSelection.uniqueSlugDocument([da], language: .english))
        var nullLegacy = da.data
        nullLegacy.removeValue(forKey: "contentLanguage")
        nullLegacy["cmsLocaleId"] = NSNull(); nullLegacy["sourceArticleID"] = NSNull()
        XCTAssertEqual(try ArticleLanguageSelection.uniqueSlugDocument([(da.id, nullLegacy)], language: .danish)?.id, da.id)
        nullLegacy["contentLanguage"] = NSNull()
        XCTAssertThrowsError(try ArticleLanguageSelection.uniqueSlugDocument([(da.id, nullLegacy)], language: .danish))
        XCTAssertThrowsError(try ArticleLanguageSelection.uniqueSlugDocument([en, en], language: .english))
        XCTAssertThrowsError(try ArticleLanguageSelection.uniqueSlugDocument([da, en, da], language: .english))
        var withdrawn = en.data; withdrawn["publicationState"] = "withdrawn"
        XCTAssertEqual(try ArticleLanguageSelection.uniqueSlugDocument([da, (en.id, withdrawn)], language: .english)?.id, en.id)
        var malformed = en.data; malformed["cmsLocaleId"] = ArticleContentLanguage.danishCMSLocaleID
        XCTAssertThrowsError(try ArticleLanguageSelection.uniqueSlugDocument([(en.id, malformed)], language: .english))
    }

    func testDirectIdentifierTranslationNeverAliasesStoredBodies() {
        XCTAssertEqual(ArticleLanguageSelection.identifier(sourceID, language: .english), "en_" + sourceID)
        XCTAssertEqual(ArticleLanguageSelection.identifier("en_" + sourceID, language: .danish), sourceID)
        XCTAssertEqual(ArticleLanguageSelection.identifier("same-slug", language: .english), "same-slug")
        XCTAssertEqual(ArticleLanguageSelection.visible([article(.english)], language: .danish), [])
    }

    func testUnverifiedRevisionKeepsEnglishBookmarkIdentityWithoutOldBody() throws {
        let old = article(.english)
        let newer = Article(id: old.id, name: "Updated English", slug: "same-slug", content: "New body",
            intro: "Updated", topicID: "topic", isDraft: false, lastPublished: old.lastPublished,
            contentRevision: "en-v2", contentLanguage: .english, sourceArticleID: sourceID,
            cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        let model = ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} })
        // Give the mirror a different approved revision without touching cache,
        // favorites membership, an SDK, or any live availability listener.
        model.trackPublicationIDs([old.id])
        let ticket = model.beginRead()
        model.recordPublications([newer], ticket: ticket)
        let sanitized = try XCTUnwrap(model.sanitized(old))
        XCTAssertEqual(sanitized.id, old.id)
        XCTAssertEqual(sanitized.contentLanguage, .english)
        XCTAssertEqual(sanitized.sourceArticleID, sourceID)
        XCTAssertTrue(sanitized.hasValidContentIdentity)
        XCTAssertTrue(sanitized.content?.isEmpty != false)
    }

    func testLanguageSwitchRejectsAnInFlightIncomingArticleWithoutFallback() async throws {
        let suite = "language-flight-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(userDefaults: defaults)
        let identity = CanonicalSessionState(); _ = identity.adopt(nil)
        let entered = expectation(description: "Original language lookup entered")
        var reply: CheckedContinuation<Result<Article, Error>, Never>?
        var lookups: [String] = []
        var effects = ArticleViewModel.ReadEffects()
        effects.incoming = { identifier, permission in
            XCTAssertTrue(permission()); lookups.append(identifier)
            return await withCheckedContinuation { reply = $0; entered.fulfill() }
        }
        let vm = ArticleViewModel(startup: ReaderSDKStartupState.application,
            identity: identity, actualUserID: { nil }, readEffects: effects, languagePreferences: preferences)
        let task = Task { await vm.fetchIncomingArticle(sourceID, fallback: "same-slug") }
        await fulfillment(of: [entered], timeout: 2)
        preferences.updateArticleLanguage(.english)
        try XCTUnwrap(reply).resume(returning: .success(article(.danish)))
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(lookups, [sourceID], "A superseded read cannot acquire a fallback in the new language")
        XCTAssertTrue(vm.articles.isEmpty)
        XCTAssertNil(FirebaseApp.app())
    }
}
