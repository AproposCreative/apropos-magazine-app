import XCTest
@testable import Apropos

@MainActor
final class ArticleDisplayDateLanguageTests: XCTestCase {
    func testSameEditorialDateUsesSelectedLanguageInEitherCacheOrder() {
        let formatter = ArticleDisplayDateFormatter(maximumKeys: 4)
        XCTAssertEqual(formatter.string(from: "2026-10-31", language: .danish), "31. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-31", language: .english), "31 October 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-31", language: .danish), "31. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-31", language: .english), "31 October 2026")
    }

    func testLanguageChangesDisplayOnlyAndKeepsCopenhagenEditorialDay() {
        let formatter = ArticleDisplayDateFormatter(maximumKeys: 2)
        XCTAssertEqual(formatter.string(from: "2026-10-30T23:30:00Z", language: .english), "31 October 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-30T23:30:00Z", language: .danish), "31. oktober 2026")
        XCTAssertNil(formatter.string(from: "not-a-date", language: .english))
        XCTAssertNil(formatter.string(from: "not-a-date", language: .danish))
        XCTAssertNil(formatter.string(from: nil, language: .english))
    }
}
