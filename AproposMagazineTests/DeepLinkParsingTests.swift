import XCTest
@testable import Apropos_Magazine

/// Regression coverage for `DeepLink.parse`. The article/widget/notification
/// deep-link flow has repeatedly broken (wrong route, double-open), so these
/// tests pin down exactly which URLs map to which action.
final class DeepLinkParsingTests: XCTestCase {

    private func parse(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else {
            XCTFail("Invalid test URL: \(string)")
            return nil
        }
        return DeepLink.parse(url)
    }

    // MARK: - Article links

    func testArticleHostStyleLink() {
        // Widget / notification format: aproposmagazine://article/{id}
        XCTAssertEqual(parse("aproposmagazine://article/abc123"), .article(id: "abc123"))
    }

    func testArticleHostStyleLinkWithSlug() {
        XCTAssertEqual(
            parse("aproposmagazine://article/heartland-festival-2026"),
            .article(id: "heartland-festival-2026")
        )
    }

    func testArticlePathStyleLink() {
        // Universal-link style path: /article/{id}
        XCTAssertEqual(
            parse("https://aproposmagazine.com/article/xyz789"),
            .article(id: "xyz789")
        )
    }

    func testArticleFragmentStyleLink() {
        XCTAssertEqual(parse("aproposmagazine://home#article/frag42"), .article(id: "frag42"))
    }

    func testArticleHostWithoutIdIsNotAnArticle() {
        // No id after the host -> must not resolve to an empty article id.
        XCTAssertNil(parse("aproposmagazine://article/"))
        XCTAssertNil(parse("aproposmagazine://article"))
    }

    // MARK: - Category & author links

    func testCategoryLink() {
        XCTAssertEqual(parse("aproposmagazine://category/musik"), .category(name: "musik"))
    }

    func testAuthorLink() {
        XCTAssertEqual(parse("aproposmagazine://author/42"), .author(id: "42"))
    }

    // MARK: - Rejected links

    func testUnknownSchemeReturnsNil() {
        XCTAssertNil(parse("https://example.com/article/123"))
        XCTAssertNil(parse("spotify://track/123"))
    }

    func testUnknownTypeReturnsNil() {
        XCTAssertNil(parse("aproposmagazine://podcast/123"))
    }

    func testHomeLinkReturnsNil() {
        // "home" has no second path component and no article fragment.
        XCTAssertNil(parse("aproposmagazine://home"))
    }
}
