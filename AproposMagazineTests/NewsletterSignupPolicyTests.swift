import XCTest
@testable import Apropos

final class NewsletterSignupPolicyTests: XCTestCase {
    func testEmailPrefillOnlyAllowsThePublicFormDocument() throws {
        XCTAssertTrue(NewsletterSignupPolicy.canPrefill(NewsletterSignupPolicy.formURL))
        for raw in [
            "http://www.aproposmagazine.com/", "https://aproposmagazine.com/",
            "https://www.aproposmagazine.com.evil.example/", "https://ai.aproposmagazine.com/ai",
            "https://www.aproposmagazine.com/other/legal", "https://www.aproposmagazine.com:444/",
            "https://name@www.aproposmagazine.com/"
        ] { XCTAssertFalse(NewsletterSignupPolicy.canPrefill(URL(string: raw)), raw) }
        XCTAssertFalse(NewsletterSignupPolicy.canPrefill(nil))
        let url = try XCTUnwrap(NewsletterSignupPolicy.formURL)
        XCTAssertEqual(url.fragment, "Subscribe-Footer")
        XCTAssertNil(url.query) // Never leak account email through URL/referrer.
    }

    func testUntrustedEmailIsEncodedAsDataRatherThanJavaScript() throws {
        let email = "reader\"; window.bad = true; //\n@example.com"
        let script = try XCTUnwrap(NewsletterSignupPolicy.prefillScript(email: email))
        let encoded = try XCTUnwrap(script.components(separatedBy: "input.value = ").last?.components(separatedBy: "[0];").first)
        let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String]
        XCTAssertEqual(decoded, [email])
        XCTAssertFalse(script.contains(".submit("))
        XCTAssertFalse(script.contains(".click("))
        XCTAssertFalse(script.contains(".checked ="))
    }

    func testOversizedEmailCannotBeInjectedIntoPage() {
        XCTAssertNil(NewsletterSignupPolicy.prefillScript(email: String(repeating: "a", count: 255)))
    }
}
