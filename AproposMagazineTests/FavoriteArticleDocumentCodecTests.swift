import XCTest
@testable import Apropos

final class FavoriteArticleDocumentCodecTests: XCTestCase {
    func testFavoriteRoundTripPreservesAccessAndOfflineMetadata() {
        let article = Article(
            id: "premium-1", name: "Premium", slug: "premium",
            content: "<p>Full article</p>", trailer: "https://example.invalid/trailer",
            intro: "Intro", stjerne: 5, topicID: "music", topicsIDs: ["music"],
            sectionID: "reviews", authorID: "author-1",
            mobileImageURL: URL(string: "https://example.invalid/image.jpg"),
            subtitle: "Subtitle", fotoCredit: "Photographer", isDraft: false,
            date: "2026-10-15", createdOn: "2026-10-15T10:00:00Z",
            lastPublished: "2026-10-15T11:00:00Z", featured: true,
            isPremium: true, pressAccreditation: true
        )
        let restored = FavoriteArticleDocumentCodec.decode(
            FavoriteArticleDocumentCodec.encode(article), documentID: article.id
        )
        XCTAssertEqual(restored, article)
        XCTAssertEqual(restored.isPremium, true)
        XCTAssertEqual(restored.content, article.content)
        XCTAssertEqual(restored.fotoCredit, "Photographer")
        XCTAssertTrue(restored.pressAccreditation)
        XCTAssertTrue(restored.isPubliclyPublished)
    }

    func testExplicitFreeStatusAndLegacyMissingStatusRemainDistinct() {
        let legacy = FavoriteArticleDocumentCodec.decode(["name": "Old favorite"], documentID: "legacy-1")
        let free = FavoriteArticleDocumentCodec.decode(["isPremium": false], documentID: "free-1")
        XCTAssertNil(legacy.isPremium)
        XCTAssertEqual(legacy.id, "legacy-1")
        XCTAssertEqual(free.isPremium, false)
    }
}
