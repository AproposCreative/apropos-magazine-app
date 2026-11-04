import XCTest
@testable import Apropos

@MainActor
final class ArticleDisplayDateFormatterTests: XCTestCase {
    func testDateOnlyValuesKeepTheirCalendarDayAndUseDanishMonthNames() {
        let formatter = ArticleDisplayDateFormatter()
        XCTAssertEqual(formatter.string(from: "2026-10-21"), "21. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-01-01"), "1. januar 2026")
        XCTAssertEqual(formatter.string(from: "2026-03-29"), "29. marts 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-25"), "25. oktober 2026")
    }

    func testExplicitTimestampUsesDanishTimeZoneIncludingDateRollover() {
        let formatter = ArticleDisplayDateFormatter()
        XCTAssertEqual(formatter.string(from: "2026-10-21T23:30:00Z"), "22. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-21T23:30:00+02:00"), "21. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-12-31T23:30:00Z"), "1. januar 2027")
        XCTAssertEqual(formatter.string(from: "2026-06-21T22:30:00Z"), "22. juni 2026")
    }

    func testFractionalAndLegacyTimestampsUseTheSameDisplayPolicy() {
        let formatter = ArticleDisplayDateFormatter()
        XCTAssertEqual(formatter.string(from: "2026-10-21T10:30:00.123Z"), "21. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-21T23:30:00.123456Z"), "22. oktober 2026")
        XCTAssertEqual(formatter.string(from: "2026-10-21 23:30:00"), "21. oktober 2026")
    }

    func testExistingDanishNumericAndWrittenFormatsAreAccepted() {
        let formatter = ArticleDisplayDateFormatter()
        for raw in ["21.10.2026", "21/10/2026", "21. oktober 2026", "21. okt. 2026"] {
            XCTAssertEqual(formatter.string(from: raw), "21. oktober 2026", raw)
        }
        XCTAssertEqual(formatter.string(from: "1.1.2026"), "1. januar 2026")
        XCTAssertEqual(formatter.string(from: "1/1/2026"), "1. januar 2026")
    }

    func testExistingEnglishDatesBecomeDanishWithoutChangingTheDay() {
        let formatter = ArticleDisplayDateFormatter()
        for raw in ["October 21, 2026", "Oct 21, 2026", "October 21 2026", "Oct 21 2026"] {
            XCTAssertEqual(formatter.string(from: raw), "21. oktober 2026", raw)
        }
    }

    func testMissingMalformedAndImpossibleDatesDoNotInventAPublicationDate() {
        let formatter = ArticleDisplayDateFormatter()
        for raw: String? in [nil, "", " \n ", "i dag", "2026-02-30", "31. april 2026",
                            "2026-10-21T25:30:00Z", "2026-10-21 trailing text",
                            String(repeating: "2", count: 129)] {
            XCTAssertNil(formatter.string(from: raw), raw ?? "nil")
        }
    }

    func testLeapDayAndWhitespaceRemainValid() {
        let formatter = ArticleDisplayDateFormatter()
        XCTAssertEqual(formatter.string(from: " \n2024-02-29 \n"), "29. februar 2024")
        XCTAssertNil(formatter.string(from: "2025-02-29"))
    }

    func testBoundedCacheEvictionNeverChangesDateOrMissingDateResults() {
        let formatter = ArticleDisplayDateFormatter(maximumKeys: 1)
        for _ in 0..<3 {
            XCTAssertEqual(formatter.string(from: "2026-10-21"), "21. oktober 2026")
            XCTAssertNil(formatter.string(from: "invalid"))
            XCTAssertEqual(formatter.string(from: "2024-02-29"), "29. februar 2024")
        }
    }
}
