import XCTest
@testable import Apropos

final class ShareLinkRoundTripTests: XCTestCase {
    func testValidTrimmedSlugWinsAndExistingShareURLsStayStable() throws {
        let url = try XCTUnwrap(ShareLinkBuilder.articleURL(slug: " \n cape-fear \t", articleId: "id-1"))
        XCTAssertEqual(url.absoluteString, "https://aproposmagazine.com/article/cape-fear")
        XCTAssertEqual(DeepLink.parse(url), .article(id: "cape-fear"))
        let clip = try XCTUnwrap(ShareLinkBuilder.podcastClipURL(slug: "bond", articleId: "id-2", timestampSeconds: 125))
        XCTAssertEqual(clip.absoluteString, "https://aproposmagazine.com/article/bond?t=125")
        XCTAssertEqual(DeepLink.parse(clip), .podcast(id: "bond", startSeconds: 125))
    }
    func testMissingEmptyOrInvalidSlugFallsBackToValidCanonicalIdentifier() throws {
        for slug in [nil, "", " \n ", ".", "..", "__private__", "a/b", "a\\b", "a?next=evil", "a#fragment", "a%2Fb", "a%252Fb", "bad\u{0}slug", String(repeating: "x", count: 513)] as [String?] {
            let url = try XCTUnwrap(ShareLinkBuilder.articleURL(slug: slug, articleId: "canonical-id"))
            XCTAssertEqual(DeepLink.parse(url), .article(id: "canonical-id"), "Invalid slug must never become a path or routing parameter")
            XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
            XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment)
        }
    }
    func testInvalidFallbackDoesNotEraseAValidSlugAndTwoInvalidCandidatesReturnNil() {
        XCTAssertEqual(ShareLinkBuilder.articleURL(slug: "valid", articleId: "invalid/id").flatMap(DeepLink.parse), .article(id: "valid"))
        for id in ["", " ", ".", "..", "a/b", "a\\b", "a?query", "a#fragment", "a%2Fb", "a%252Fb", "a\nb", String(repeating: "x", count: 513)] {
            XCTAssertNil(ShareLinkBuilder.articleURL(slug: nil, articleId: id), id)
            XCTAssertNil(ShareLinkBuilder.podcastClipURL(slug: "bad/slug", articleId: id, timestampSeconds: 0), id)
        }
    }
    func testUnicodeAndReservedPunctuationAreOneEncodedIdentifierWithoutQueryInjection() throws {
        let id = "bøger & kultur + @kolon: 'citat' \"tekst\""
        let url = try XCTUnwrap(ShareLinkBuilder.articleURL(slug: id, articleId: "fallback"))
        XCTAssertEqual(DeepLink.parse(url), .article(id: id))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "aproposmagazine.com")
        XCTAssertEqual(components.path, "/article/" + id)
        XCTAssertTrue(components.percentEncodedPath.contains("%C3%B8"))
        XCTAssertTrue(components.percentEncodedPath.contains("%26"))
        XCTAssertTrue(components.percentEncodedPath.contains("%2B"))
        XCTAssertNil(components.query);XCTAssertNil(components.fragment)
        let clip = try XCTUnwrap(ShareLinkBuilder.podcastClipURL(slug: id, articleId: "fallback", timestampSeconds: 0))
        XCTAssertEqual(DeepLink.parse(clip), .podcast(id: id, startSeconds: 0))
        XCTAssertEqual(URLComponents(url: clip, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name), ["t"])
    }
    func testPreencodedSeparatorsAreRejectedRatherThanDoubleDecodedIntoAnotherRoute() {
        for encoded in ["%2f", "%2F", "%252F", "%5c", "%3f", "%23", "%00", "%2e%2e", "%252e%252e"] {
            XCTAssertNil(ShareLinkBuilder.articleURL(slug: encoded, articleId: encoded))
        }
    }
    func testIdentifierByteBoundaryRoundTripsEvenWhenPercentEncodingExpandsIt() throws {
        let id = String(repeating: "ø", count: DeepLink.maximumIdentifierBytes / 2)
        let url = try XCTUnwrap(ShareLinkBuilder.articleURL(slug: id, articleId: "fallback"))
        XCTAssertEqual(DeepLink.parse(url), .article(id: id))
        XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, DeepLink.maximumURLBytes)
        XCTAssertEqual(ShareLinkBuilder.articleURL(slug: id + "x", articleId: "fallback").flatMap(DeepLink.parse), .article(id: "fallback"))
        XCTAssertNil(ShareLinkBuilder.articleURL(slug: nil, articleId: id + "x"))
    }
    func testClipTimestampsClampBothIntegerExtremesAndPreserveExplicitZero() throws {
        for (input, expected) in [(Int.min, 0), (-1, 0), (0, 0), (125, 125), (604800, 604800), (604801, 604800), (Int.max, 604800)] {
            let url = try XCTUnwrap(ShareLinkBuilder.podcastClipURL(slug: nil, articleId: "id", timestampSeconds: input))
            XCTAssertEqual(DeepLink.parse(url), .podcast(id: "id", startSeconds: expected))
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                           [URLQueryItem(name: "t", value: String(expected))])
        }
    }
    func testFormattedTimestampPreservesExistingOutputAndRoundsWithinSafeRange() {
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(65), "1:05")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(3665), "1:01:05")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(64.6), "1:05")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(-1), "0:00")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(604800), "168:00:00")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(604800.9), "168:00:00")
    }
    func testFormattedTimestampDoesNotTrapOnNonfiniteOrIntegerOverflowInputs() {
        for value in [Double.nan, Double.infinity, -Double.infinity, -Double.greatestFiniteMagnitude] {
            XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(value), "0:00")
        }
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(Double.greatestFiniteMagnitude), "168:00:00")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(Double(Int.max)), "168:00:00")
        XCTAssertEqual(ShareLinkBuilder.formattedTimestamp(Double(Int.min)), "0:00")
    }
}
