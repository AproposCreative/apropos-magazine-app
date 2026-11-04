import XCTest
@testable import Apropos

final class IncomingLinkEntryTests: XCTestCase {
    @MainActor func testDisabledEntryNeverInitializesEitherInjectedEffect() {
        var effects = 0
        let entry = IncomingLinkEntry(disabled: true, handleGoogle: { _ in effects += 1;return true },
                                      accept: { _ in effects += 1;return true })
        XCTAssertFalse(entry.openURL(URL(string: "aproposmagazine://article/a")!))
        XCTAssertFalse(entry.continueActivity(type: NSUserActivityTypeBrowsingWeb, webpageURL: URL(string: "https://aproposmagazine.com/article/a")!))
        XCTAssertEqual(effects, 0)
    }
    @MainActor func testGoogleCallbackIsConsumedBeforeArticleIngress() {
        var accepted = 0
        let entry = IncomingLinkEntry(disabled: false, handleGoogle: { $0.scheme == "google-fixture" },
                                      accept: { _ in accepted += 1;return true })
        XCTAssertTrue(entry.openURL(URL(string: "google-fixture://callback?code=fixture")!))
        XCTAssertEqual(accepted, 0)
        XCTAssertTrue(entry.openURL(URL(string: "aproposmagazine://article/a?t=0")!))
        XCTAssertEqual(accepted, 1)
    }
    @MainActor func testUniversalActivityRequiresBrowsingWebAndValidatedHTTPS() {
        var links: [URL] = [], googleCalls = 0
        let entry = IncomingLinkEntry(disabled: false, handleGoogle: { _ in googleCalls += 1;return false },
                                      accept: { links.append($0);return true })
        let valid = URL(string: "https://aproposmagazine.com/article/a?t=125")!
        XCTAssertFalse(entry.continueActivity(type: "unrelated-activity", webpageURL: valid))
        XCTAssertFalse(entry.continueActivity(type: NSUserActivityTypeBrowsingWeb, webpageURL: nil))
        for raw in ["http://aproposmagazine.com/article/a", "https://example.com/article/a", "aproposmagazine://article/a", "https://aproposmagazine.com/article/a?t=-1"] {
            XCTAssertFalse(entry.continueActivity(type: NSUserActivityTypeBrowsingWeb, webpageURL: URL(string: raw)!))
        }
        XCTAssertTrue(entry.continueActivity(type: NSUserActivityTypeBrowsingWeb, webpageURL: valid))
        XCTAssertEqual(links, [valid])
        XCTAssertEqual(googleCalls, 0)
    }
    @MainActor func testRejectedOrUnacceptedCustomLinksReturnFalse() {
        var accepted = 0
        let entry = IncomingLinkEntry(disabled: false, handleGoogle: { _ in false }, accept: { _ in accepted += 1;return false })
        XCTAssertFalse(entry.openURL(URL(string: "aproposmagazine://unknown/a")!))
        XCTAssertEqual(accepted, 0)
        XCTAssertFalse(entry.openURL(URL(string: "aproposmagazine://article/a")!))
        XCTAssertEqual(accepted, 1)
    }
}
