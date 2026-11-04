import XCTest
@testable import Apropos

final class CMSDocumentIdentifierTests: XCTestCase {
    func testDocumentPathsReservedNamesAndControlCharactersAreRejected() {
        for id in ["", " ", ".", "..", "/article", "article/", "article/other", "__reserved__", "a\nb", "a\u{0}b"] {
            XCTAssertFalse(CMSMirrorDocumentPolicy.isSafeDocumentID(id), id.debugDescription)
        }
        XCTAssertThrowsError(try CMSArticleDocumentCodec.decodeArticle(from: ["id": "nested/document", "fieldData": [:]]))
        XCTAssertThrowsError(try CMSArticleDocumentCodec.decodeArticle(from: ["id": "first-story", "fieldData": [:]], expectedID: "other-story"))
    }

    func testLegacySlugsAndUnicodeRespectByteLimitRatherThanCharacterCount() {
        for id in ["67dbf17ba540975b5b21c2a6", "legacy-article-slug", "ældre-artikel", String(repeating: "a", count: 1500),
                   String(repeating: "ø", count: 750)] {
            XCTAssertTrue(CMSMirrorDocumentPolicy.isSafeDocumentID(id))
        }
        XCTAssertFalse(CMSMirrorDocumentPolicy.isSafeDocumentID(String(repeating: "a", count: 1501)))
        XCTAssertFalse(CMSMirrorDocumentPolicy.isSafeDocumentID(String(repeating: "ø", count: 751)))
    }

    func testMalformedFavoritePayloadFallsBackToItsSafeDocumentID() {
        let favorite = FavoriteArticleDocumentCodec.decode(["id": "nested/path", "name": "Story"], documentID: "valid-story")
        XCTAssertEqual(favorite.id, "valid-story")
    }
}
