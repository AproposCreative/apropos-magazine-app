import XCTest
@testable import Apropos

final class ArticleFeedSnapshotTests: XCTestCase {
    private func article(
        _ id: String = "story", body: String = "", title: String = "Title",
        created: String = "2026-01-01T12:00:00Z", published: String = "v1",
        authorID: String = "writer"
    ) -> Article {
        Article(
            id: id, name: title, slug: id, content: body, intro: "", topicID: "topic", authorID: authorID,
            isDraft: false, createdOn: created, lastPublished: published
        )
    }

    func testFeedCommitPreservesDetailThatArrivedDuringRequest() {
        var latestDetail = article(body: "Full body completed after feed request started")
        let author = Author(id: "writer", name: "Maja", bio: nil, imageURL: nil, position: "", photoURL: "")
        latestDetail.author = author
        let incoming = article(title: "Updated feed headline")

        let result = ArticleFeedSnapshot.merging([incoming], retainingDetailsFrom: [latestDetail])
        XCTAssertEqual(result.first?.content, latestDetail.content)
        XCTAssertEqual(result.first?.author, author)
        XCTAssertEqual(result.first?.name, "Updated feed headline")
    }

    func testNewPublishedOrCreatedRevisionDoesNotReuseObsoleteBody() {
        let previous = article(body: "Obsolete body")
        for incoming in [article(published: "v2"), article(created: "2026-02-01T12:00:00Z")] {
            let result = ArticleFeedSnapshot.merging([incoming], retainingDetailsFrom: [previous])
            XCTAssertTrue(result.first?.content?.isEmpty != false)
        }
    }

    func testChangedAuthorReferenceCannotInheritOldAuthor() {
        var previous = article(body: "Body")
        previous.author = Author(id: "writer", name: "Old Author", bio: nil, imageURL: nil, position: "", photoURL: "")
        let result = ArticleFeedSnapshot.merging(
            [article(authorID: "new-writer")], retainingDetailsFrom: [previous]
        )
        XCTAssertNil(result.first?.author)
        XCTAssertEqual(result.first?.content, "Body")
    }

    func testFeedRetainsOnlyPublishedSummariesAndCurrentOrdering() {
        let old = article("old", body: "Incoming body", created: "2026-01-01T12:00:00Z")
        let new = article("new", body: "Incoming body", created: "2026-02-01T12:00:00Z")
        let draft = Article(id: "draft", name: "Draft", slug: "draft", content: "draft", intro: "", topicID: "topic", isDraft: true)
        let result = ArticleFeedSnapshot.merging([old, draft, new], retainingDetailsFrom: [])
        XCTAssertEqual(result.map(\.id), ["new", "old"])
        XCTAssertTrue(result.allSatisfy { $0.content?.isEmpty != false })
    }

    func testOlderCachedFeedKeepsEntireNewerDetailAndSortsAfterMergeWithoutResurrectingMissingIDs() {
        var current = article(
            body: "Current full body", title: "Current headline", created: "2026-03-01T12:00:00Z",
            published: "2026-10-20T10:00:00Z", authorID: "current-writer"
        )
        current.author = Author(id: "current-writer", name: "Current Author", bio: nil, imageURL: nil, position: "", photoURL: "")
        let other = article("other", created: "2026-02-01T12:00:00Z")
        let absent = article("no-longer-in-feed", body: "Saved", published: "2026-10-20T10:00:00Z")
        for older in ["2026-10-20T09:59:59Z", "2026-10-20T09:59:59.999Z"] {
            let stale = article(
                body: "Old body", title: "Old headline", created: "2026-01-01T12:00:00Z",
                published: older, authorID: "old-writer"
            )
            let result = ArticleFeedSnapshot.merging([other, stale], retainingDetailsFrom: [current, absent])
            XCTAssertEqual(result.map(\.id), ["story", "other"])
            XCTAssertEqual(result.first, current)
            XCTAssertFalse(result.contains { $0.id == absent.id })
        }
    }

    func testNewerFeedRevisionStillReplacesMetadataAndDiscardsPreviousBody() {
        let previous = article(body: "Old body", published: "2026-10-20T10:00:00Z")
        let incoming = article(title: "New headline", published: "2026-10-20T10:00:00.001Z", authorID: "new-writer")
        let result = ArticleFeedSnapshot.merging([incoming], retainingDetailsFrom: [previous])
        XCTAssertEqual(result.first?.name, "New headline")
        XCTAssertEqual(result.first?.lastPublished, incoming.lastPublished)
        XCTAssertEqual(result.first?.authorID, "new-writer")
        XCTAssertTrue(result.first?.content?.isEmpty != false)
    }

    func testUnparseablePublicationDatesDoNotInventARevisionOrder() {
        for (previousDate, incomingDate) in [
            ("2026-10-20T10:00:00Z", "invalid-incoming"),
            ("invalid-previous", "2026-10-20T09:00:00Z"),
            ("invalid-previous", "invalid-incoming")
        ] {
            let previous = article(body: "Previous body", published: previousDate)
            let incoming = article(title: "Incoming headline", published: incomingDate)
            let result = ArticleFeedSnapshot.merging([incoming], retainingDetailsFrom: [previous])
            XCTAssertEqual(result.first?.name, "Incoming headline")
            XCTAssertEqual(result.first?.lastPublished, incomingDate)
            XCTAssertTrue(result.first?.content?.isEmpty != false)
        }
    }
}

/// Exercises the actual codecs and cache policies; no SDK, disk singleton or network.
extension ArticleFeedSnapshotTests {
    private func revised(_ revision: String?, body: String = "", updated: String? = nil) -> Article {
        Article(id: "corrected", name: "Story", slug: "story", content: body, intro: "", topicID: "topic",
                createdOn: "2026-01-01T12:00:00Z", lastPublished: "2026-10-20T10:00:00Z",
                lastUpdated: updated, contentRevision: revision)
    }

    func testSamePublicationDateCorrectionDoesNotInheritPreviousFeedBody() {
        let old = revised("cms-sha256-v1:old", body: "Incorrect old text")
        let new = revised("cms-sha256-v1:corrected")
        let result = ArticleFeedSnapshot.merging([new], retainingDetailsFrom: [old])
        XCTAssertEqual(result.first?.contentRevision, new.contentRevision)
        XCTAssertTrue(result.first?.content?.isEmpty != false)
        XCTAssertFalse(ArticleDetailContentPolicy.sameRevision(old, new))
        XCTAssertNotEqual(ArticleDetailRequestIdentity(old), ArticleDetailRequestIdentity(new))
    }

    func testSameExplicitRevisionPreservesBodyAcrossFeedRefresh() {
        let old = revised("cms-sha256-v1:same", body: "Saved current text")
        let result = ArticleFeedSnapshot.merging([revised(old.contentRevision)], retainingDetailsFrom: [old])
        XCTAssertEqual(result.first?.content, old.content)
    }

    func testOfflineSummaryCannotAttachOldBodyToCorrectedRevision() {
        let old = revised("cms-sha256-v1:old", body: "Incorrect text")
        let new = revised("cms-sha256-v1:corrected")
        let result = OfflineLibrarySnapshot.merging([new], into: [old])
        XCTAssertEqual(result.changedArticles.count, 1)
        XCTAssertEqual(result.articles.first?.contentRevision, new.contentRevision)
        XCTAssertTrue(result.articles.first?.content?.isEmpty != false)
    }

    func testMirrorFavoriteAndDiskSnapshotRoundTripContentRevision() throws {
        let fields: [String: Any] = ["id": "corrected", "lastPublished": "2026-10-20T10:00:00Z",
            "lastUpdated": "2026-10-20T11:00:00Z", "contentRevision": "cms-sha256-v1:corrected",
            "fieldData": ["name": "Corrected title", "slug": "story", "content": "Corrected body"]]
        let mirror = try CMSArticleDocumentCodec.decodeArticle(from: fields, expectedID: "corrected")
        let favorite = FavoriteArticleDocumentCodec.decode(FavoriteArticleDocumentCodec.encode(mirror), documentID: mirror.id)
        let disk = try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(favorite))
        for copy in [mirror, favorite, disk, disk.strippingBodyContent(), disk.replacingBodyContent("Replacement")] {
            XCTAssertEqual(copy.bodyRevision, "cms-sha256-v1:corrected")
            XCTAssertEqual(copy.lastUpdated, "2026-10-20T11:00:00Z")
        }
        let summary = try CMSArticleDocumentCodec.decodeArticle(from: fields, stripBodyContent: true)
        XCTAssertEqual(summary.bodyRevision, mirror.bodyRevision)
        XCTAssertTrue(summary.content?.isEmpty != false)
    }

    func testLegacyBodyIsNotReusedForNewExplicitRevision() throws {
        let legacy = revised(nil, body: "Legacy body")
        let decoded = try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.bodyRevision, decoded.lastPublished)
        XCTAssertNil(decoded.contentRevision)
        let new = revised("cms-sha256-v1:corrected")
        XCTAssertFalse(ArticleDetailContentPolicy.sameRevision(decoded, new))
        XCTAssertEqual(ArticleDetailContentPolicy.cachedArticle(id: new.id, feed: new, full: decoded, initial: decoded)?.content, "")
    }

    func testUpdateTimestampFallbackDistinguishesDirectCMSCorrections() {
        let old = revised(nil, body: "Old", updated: "2026-10-20T10:00:00Z")
        let new = revised(nil, updated: "2026-10-20T11:00:00Z")
        XCTAssertNotEqual(old.bodyRevision, new.bodyRevision)
        XCTAssertFalse(ArticleDetailContentPolicy.sameRevision(old, new))
        XCTAssertEqual(revised("opaque", updated: "2026-10-20T11:00:00Z").bodyRevision, "opaque")
        XCTAssertEqual(revised(" ", updated: "invalid").bodyRevision, old.lastPublished)
    }

    func testOlderCorrectedFeedAndBodyCannotDowngradeNewerUpdate() {
        let old = revised("cms-sha256-v1:old", body: "Old", updated: "2026-10-20T10:00:00Z")
        let new = revised("cms-sha256-v1:new", body: "Corrected", updated: "2026-10-20T11:00:00Z")
        XCTAssertEqual(ArticleFeedSnapshot.merging([old], retainingDetailsFrom: [new]).first?.contentRevision, new.contentRevision)
        XCTAssertFalse(ArticleDetailContentPolicy.canApplyFetchedBody(old, requestedFrom: old, current: new))
    }

    @MainActor
    func testAvailabilityCorrectionRejectsOldBodyAfterRestartWithoutChangingPublicationDate() throws {
        var callback: ((Result<ArticleAvailabilityModel.Update, Error>) -> Void)?
        var saved = ArticleAvailabilityModel.Snapshot()
        let model = ArticleAvailabilityModel(save: { saved = $0 }, schedule: { _ in {} })
        let old = revised("cms-sha256-v1:old", body: "Old")
        let new = revised("cms-sha256-v1:new", body: "Corrected")
        model.observe(id: old.id) { _, receive in callback = receive; return {} }
        callback?(.success(.init(withdrawn: false, isFromCache: false, revision: old.bodyRevision)))
        XCTAssertTrue(model.permitsBody(old))
        callback?(.success(.init(withdrawn: false, isFromCache: false, revision: new.bodyRevision)))
        XCTAssertFalse(model.permitsBody(old))
        XCTAssertTrue(model.permitsBody(new))
        XCTAssertEqual(model.sanitized(old)?.content, "")
        XCTAssertEqual(model.sanitized(old)?.contentRevision, old.contentRevision)
        callback?(.success(.init(withdrawn: false, isFromCache: true, revision: old.bodyRevision)))
        XCTAssertFalse(model.permitsBody(old))
        let data = try JSONEncoder().encode(saved)
        let restored = ArticleAvailabilityModel(snapshot: try JSONDecoder().decode(ArticleAvailabilityModel.Snapshot.self, from: data), schedule: { _ in {} })
        XCTAssertFalse(restored.permitsBody(old))
        XCTAssertTrue(restored.permitsBody(new))
    }
}
