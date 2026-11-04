import XCTest
@testable import Apropos

final class IncomingLinkParsingTests: XCTestCase {
    private func parse(_ text: String) -> DeepLink? { URL(string: text).flatMap(DeepLink.parse) }
    func testPublishedShareAndWidgetFormsKeepCanonicalIdentifierAndExplicitZero() {
        XCTAssertEqual(parse("https://aproposmagazine.com/article/kultur?t=125"), .podcast(id: "kultur", startSeconds: 125))
        XCTAssertEqual(parse("https://aproposmagazine.com/article/kultur?t=0"), .podcast(id: "kultur", startSeconds: 0))
        XCTAssertEqual(parse("aproposmagazine://article/widget-id"), .article(id: "widget-id"))
        XCTAssertEqual(parse("aproposmagazine://home#article/legacy-id"), .article(id: "legacy-id"))
        XCTAssertEqual(parse("aproposmagazine:///article/path-id"), .article(id: "path-id"))
    }
    func testPercentEncodedUnicodeIdentifierIsDecodedExactlyOnce() {
        XCTAssertEqual(parse("https://aproposmagazine.com/article/b%C3%B8ger-og-kultur"), .article(id: "bøger-og-kultur"))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a%2Fb"))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a%252Fb"))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a%5Cb"))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a%3Fb"))
    }
    func testExactAuthorityRejectsCredentialsPortsDowngradeLookalikesAndForeignCustomHost() {
        for text in ["http://aproposmagazine.com/article/a", "https://aproposmagazine.com.evil.test/article/a",
                     "https://evilaproposmagazine.com/article/a", "https://www.aproposmagazine.com.evil.test/article/a",
                     "https://fakewww.aproposmagazine.com/article/a", "https://user@www.aproposmagazine.com/article/a",
                     "https://user@aproposmagazine.com/article/a", "https://user:password@aproposmagazine.com/article/a",
                     "https://aproposmagazine.com:443/article/a", "aproposmagazine://article:123/a",
                     "aproposmagazine://user@article/a", "aproposmagazine://evil/article/a"] {
            XCTAssertNil(parse(text), text)
        }
    }
    func testIdentifiersRejectExtraSegmentsEmptyDotsWhitespaceControlsAndOversizedInput() {
        for suffix in ["", "/a", "a/extra", "a/", "%20a", "a%20", "a%0Ab", ".", "..", "__private__", String(repeating: "x", count: 513)] {
            XCTAssertNil(parse("https://aproposmagazine.com/article/" + suffix), suffix)
        }
        XCTAssertNil(parse("https://aproposmagazine.com/article/a?utm_source=" + String(repeating: "x", count: 4096)))
    }
    func testTimestampRequiresOneBoundedUnsignedIntegerAndRejectsUnsupportedRoutes() {
        XCTAssertEqual(parse("https://aproposmagazine.com/article/a?t=604800"), .podcast(id: "a", startSeconds: 604800))
        for value in ["", "-1", "+1", "1.2", "1e2", "NaN", "Infinity", "604801", "999999999999999999999999", "%20", "%31%2E%30"] {
            XCTAssertNil(parse("https://aproposmagazine.com/article/a?t=" + value), value)
        }
        XCTAssertNil(parse("https://aproposmagazine.com/article/a?t"))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a?t=1&t=2"))
        XCTAssertNil(parse("https://aproposmagazine.com/category/musik?t=1"))
        XCTAssertNil(parse("aproposmagazine://author/author-id?t=0"))
        XCTAssertNil(parse("aproposmagazine://podcast/a?t=1"))
    }
    func testUnknownQueryDoesNotBecomeRoutingAuthorityAndFragmentsStayRestrictedToLegacyHome() {
        XCTAssertEqual(parse("https://aproposmagazine.com/article/a?utm_source=mail"), .article(id: "a"))
        XCTAssertEqual(parse("aproposmagazine://home?t=1#article/a"), .podcast(id: "a", startSeconds: 1))
        XCTAssertNil(parse("https://aproposmagazine.com/article/a#article/b"))
        XCTAssertNil(parse("aproposmagazine://article/a#article/b"))
        XCTAssertNil(parse("aproposmagazine://home#article/a/extra"))
    }
    func testTypedNotificationAudioIntentDistinguishesDefaultResumeFromExplicitZero() {
        XCTAssertNotEqual(DeepLink.podcast(id: "a", startSeconds: nil), .podcast(id: "a", startSeconds: 0))
        XCTAssertTrue(DeepLink.podcast(id: "a", startSeconds: nil).isValid)
        XCTAssertFalse(DeepLink.podcast(id: "a", startSeconds: -1).isValid)
        XCTAssertFalse(DeepLink.article(id: "a/b").isValid)
    }
    func testBothExplicitMagazineWebHostsRoundTripUnicodeAndPodcastZero() {
        for host in ["aproposmagazine.com", "www.aproposmagazine.com"] {
            var components = URLComponents()
            components.scheme = "https";components.host = host
            components.path = "/article/bøger-og-kultur"
            XCTAssertEqual(components.url.flatMap(DeepLink.parse), .article(id: "bøger-og-kultur"))
            components.queryItems = [URLQueryItem(name: "t", value: "0")]
            XCTAssertEqual(components.url.flatMap(DeepLink.parse), .podcast(id: "bøger-og-kultur", startSeconds: 0))
            components.user = "reader"
            XCTAssertNil(components.url.flatMap(DeepLink.parse))
        }
    }

}
