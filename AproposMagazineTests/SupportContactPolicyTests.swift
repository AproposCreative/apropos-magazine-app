import Foundation
import XCTest
@testable import Apropos

final class SupportContactPolicyTests: XCTestCase {
    func testWhitespaceOnlyDraftsHaveNoMailURL() {
        for body in ["", " \t\r\n", "\u{00A0}\u{2003}\u{2028}"] {
            XCTAssertFalse(SupportContactPolicy.isMeaningfulMessage(body))
            XCTAssertNil(SupportContactPolicy.mailtoURL(body: body))
        }
    }

    func testUnicodeAndQueryCharactersRoundTripWithoutChangingFixedRecipientOrAddingHeaders() throws {
        let bodies = ["Hej! Æøå, musik 🎵 + koncert? #1 & god læsning = 100%", "  Første linje\r\nAnden linje\n  ",
                      "\r\nBcc: private@example.invalid&bcc=other@example.invalid?subject=Injected#fragment", "Null \0 + plus"]
        for body in bodies {
            let url = try XCTUnwrap(SupportContactPolicy.mailtoURL(body: body))
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.scheme, "mailto")
            XCTAssertEqual(parts.path, "support@aproposmagazine.com")
            XCTAssertNil(parts.fragment)
            XCTAssertEqual(parts.queryItems?.map(\.name), ["subject", "body"])
            XCTAssertEqual(parts.queryItems?.first?.value, SupportContactPolicy.subject)
            XCTAssertEqual(parts.queryItems?.last?.value, body)
            XCTAssertFalse(url.absoluteString.contains("+"))
            XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, SupportContactPolicy.maximumMailtoBytes)
        }
    }

    func testExactConservativeMailURLBudgetAcceptsItsBoundaryAndRejectsWithoutTruncation() throws {
        let smallest = try XCTUnwrap(SupportContactPolicy.mailtoURL(body: "a"))
        let prefixBytes = smallest.absoluteString.utf8.count - 1
        let fits = String(repeating: "a", count: SupportContactPolicy.maximumMailtoBytes - prefixBytes)
        let url = try XCTUnwrap(SupportContactPolicy.mailtoURL(body: fits))
        XCTAssertEqual(url.absoluteString.utf8.count, SupportContactPolicy.maximumMailtoBytes)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.last?.value, fits)
        XCTAssertNil(SupportContactPolicy.mailtoURL(body: fits + "a"))
        XCTAssertEqual(fits.count, SupportContactPolicy.maximumMailtoBytes - prefixBytes)
    }

    func testBudgetUsesEscapedUTF8BytesRatherThanDisplayedCharacterCount() {
        let body = String(repeating: "🎵", count: 200)
        XCTAssertLessThan(body.count, SupportContactPolicy.maximumMailtoBytes)
        XCTAssertNil(SupportContactPolicy.mailtoURL(body: body))
        XCTAssertTrue(SupportContactPolicy.canPresentComposer(body: body))
    }

    func testLargeComposerDraftsAreBoundedWithoutChangingTheirText() {
        let fits = String(repeating: "x", count: SupportContactPolicy.maximumComposerBodyBytes)
        XCTAssertTrue(SupportContactPolicy.canPresentComposer(body: fits))
        XCTAssertFalse(SupportContactPolicy.canPresentComposer(body: fits + "x"))
        XCTAssertEqual(fits.utf8.count, SupportContactPolicy.maximumComposerBodyBytes)
    }
}
