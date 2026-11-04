import XCTest
@testable import Apropos

@MainActor
final class ArticlePublicationInboxSourceTests: XCTestCase {
    private let rawID = "6ae8aff199edb6a5b1f8c9f9"

    private func article(_ language: ArticleContentLanguage = .danish,
                         draft: Bool = false, archived: Bool = false,
                         published: String? = "2026-11-02T16:31:32.090Z") -> Article {
        Article(id: language == .danish ? rawID : "en_" + rawID,
                name: language == .danish ? "Ny artikel uden lyd" : "New article without audio",
                slug: "new-article", content: "", intro: "", topicID: "",
                isDraft: draft, isArchived: archived,
                createdOn: "2026-11-02T16:31:27.694Z", lastPublished: published,
                contentLanguage: language,
                sourceArticleID: language == .english ? rawID : nil,
                cmsLocaleId: language.cmsLocaleID)
    }

    private func source(_ language: ArticleContentLanguage = .danish,
                        cached: Bool = false, pending: Bool = false,
                        withdrawn: Bool = false) -> ArticleMirrorCatalog.Source {
        let value = article(language)
        var data: [String: Any] = ["id": value.id, "contentLanguage": language.rawValue,
                                  "cmsLocaleId": language.cmsLocaleID]
        if language == .english { data["sourceArticleID"] = rawID }
        if withdrawn { data["publicationState"] = "withdrawn" }
        return .init(language: language, documents: [(value.id, data)],
                     isFromCache: cached, hasPendingWrites: pending)
    }

    func testFreshPublishedArticleDoesNotRequireAudioOrDeliveredPush() {
        let value = article()
        XCTAssertEqual(ArticleMirrorCatalog.confirmedPublications(from: [value], sources: [source()]), [value])
    }

    func testCachedAndPendingSourcesCannotCreateArticleMessages() {
        for reply in [source(cached: true), source(pending: true), source(cached: true, pending: true)] {
            XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [article()], sources: [reply]).isEmpty)
        }
    }

    func testFreshEnglishCannotAuthorizeCachedDanishOrReverse() {
        let da = article(), en = article(.english)
        XCTAssertEqual(ArticleMirrorCatalog.confirmedPublications(from: [da, en],
            sources: [source(cached: true), source(.english)]), [en])
        XCTAssertEqual(ArticleMirrorCatalog.confirmedPublications(from: [da, en],
            sources: [source(), source(.english, pending: true)]), [da])
    }

    func testAbsentWithdrawnDraftArchivedAndUndatedArticlesAreNotAnnouncements() {
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [article()], sources: []).isEmpty)
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [article()], sources: [source(withdrawn: true)]).isEmpty)
        let denied = [article(draft: true), article(archived: true), article(published: nil), article(published: "invalid")]
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: denied, sources: [source()]).isEmpty)
        let other = Article(id: "aaaaaaaaaaaaaaaaaaaaaaaa", name: "Absent", slug: "absent",
                            content: "", intro: "", topicID: "", isDraft: false,
                            lastPublished: "2026-11-02T16:31:32Z", contentLanguage: .danish)
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [other], sources: [source()]).isEmpty)
    }

    func testDuplicateOrContradictoryNamespaceDoesNotClaimFreshProof() {
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [article()], sources: [source(), source()]).isEmpty)
        let contradiction = ArticleMirrorCatalog.Source(language: .english,
            documents: source().documents, isFromCache: false, hasPendingWrites: false)
        XCTAssertTrue(ArticleMirrorCatalog.confirmedPublications(from: [article(), article(.english)],
            sources: [source(), contradiction]).isEmpty)
    }

    func testFreshCompletedNamespacesFeedTheActualPersistentInboxWithoutPush() throws {
        var bytes: Data?
        var badgeCalls = 0, badgeCounts: [Int] = [], deliveryReads = 0, opened: [String] = []
        let effects = NotificationInboxModel.Effects(load: { bytes }, save: { bytes = $0 },
            delivered: { _ in deliveryReads += 1 }, removeDelivered: { _ in },
            clearBadge: { _ in badgeCalls += 1 }, open: { opened.append($0.identifier); return true },
            setBadge: { count, done in
                badgeCounts.append(count)
                MainActor.assumeIsolated { done(true) }
            }, now: { Date(timeIntervalSince1970: 0) })
        let inbox = NotificationInboxModel(effects: effects)
        // Source freshness is exercised after a genuine earlier empty inventory.
        // The first accepted inventory itself must not fabricate old deliveries.
        inbox.reconcilePublishedArticles([], verifiedLanguages: [.danish],
            stillCurrent: { true }, permitsArticle: { _ in true })
        let accepted = ArticleMirrorCatalog.confirmedPublications(from: [article()], sources: [source()])
        inbox.reconcilePublishedArticles(accepted, stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertEqual(inbox.items.count, 1)
        let first = try XCTUnwrap(inbox.items.first)
        XCTAssertEqual(first.target?.identifier, rawID)
        XCTAssertEqual(first.target?.type, "new_article")
        XCTAssertTrue(inbox.open(first.id))
        XCTAssertEqual(opened, [rawID])
        let cold = NotificationInboxModel(effects: effects)
        XCTAssertEqual(cold.items.count, 1)
        XCTAssertEqual(cold.items.first?.target?.identifier, rawID)
        XCTAssertEqual(deliveryReads, 0)
        // New publication and explicit opening update the counted projection;
        // neither may fall back to an unconditional zero or query OS deliveries.
        XCTAssertEqual(badgeCalls, 0)
        XCTAssertTrue(badgeCounts.contains(1))
        XCTAssertEqual(badgeCounts.last, 0)
    }
}
