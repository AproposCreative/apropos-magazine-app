import XCTest
@testable import Apropos

final class ArticleReadingGeometryTests: XCTestCase {
    func testProgressStaysAtZeroWhileViewportIsBeforeTheBody() {
        XCTAssertEqual(ArticleReadingGeometry(top: -900, bottom: -300, bodyHeight: 2_400).fraction, 0)
        XCTAssertEqual(ArticleReadingGeometry(top: -600, bottom: 0, bodyHeight: 2_400).fraction, 0)
    }

    func testBodyAtViewportTopStartsAtZero() {
        XCTAssertEqual(ArticleReadingGeometry(top: 0, bottom: 600, bodyHeight: 2_400).fraction, 0)
    }

    func testMidpointMeasuresDistanceUntilLastScreenRatherThanWholeBodyHeight() throws {
        let progress = try XCTUnwrap(ArticleReadingGeometry(top: 900, bottom: 1_500, bodyHeight: 2_400).fraction)
        XCTAssertEqual(progress, 0.5, accuracy: 0.000_001)
    }

    func testLastBodyScreenCompletesReadingBeforeRelatedContent() {
        XCTAssertEqual(ArticleReadingGeometry(top: 1_800, bottom: 2_400, bodyHeight: 2_400).fraction, 1)
    }

    func testOverscrollClampsBothEnds() {
        XCTAssertEqual(ArticleReadingGeometry(top: -250, bottom: 350, bodyHeight: 2_400).fraction, 0)
        XCTAssertEqual(ArticleReadingGeometry(top: 2_000, bottom: 2_600, bodyHeight: 2_400).fraction, 1)
        XCTAssertEqual(ArticleReadingGeometry(top: 3_000, bottom: 3_600, bodyHeight: 2_400).fraction, 1)
    }

    func testShortBodyCompletesWhenItsEndIsVisible() {
        XCTAssertEqual(ArticleReadingGeometry(top: -100, bottom: 500, bodyHeight: 400).fraction, 1)
        XCTAssertEqual(ArticleReadingGeometry(top: 0, bottom: 600, bodyHeight: 400).fraction, 1)
        XCTAssertEqual(ArticleReadingGeometry(top: 200, bottom: 800, bodyHeight: 400).fraction, 1)
    }

    func testShortBodyBelowViewportOrPartiallyEnteredDoesNotComplete() {
        XCTAssertEqual(ArticleReadingGeometry(top: -700, bottom: -100, bodyHeight: 400).fraction, 0)
        XCTAssertEqual(ArticleReadingGeometry(top: -600, bottom: 0, bodyHeight: 400).fraction, 0)
        XCTAssertEqual(ArticleReadingGeometry(top: -400, bottom: 200, bodyHeight: 400).fraction, 0)
    }

    func testExactlyOneScreenCompletesOnlyWhenBodyEndIsVisible() {
        XCTAssertEqual(ArticleReadingGeometry(top: -1, bottom: 399, bodyHeight: 400).fraction, 0)
        XCTAssertEqual(ArticleReadingGeometry(top: 0, bottom: 400, bodyHeight: 400).fraction, 1)
    }

    func testViewportResizeRecalculatesRemainingReadingDistance() throws {
        let portrait = try XCTUnwrap(ArticleReadingGeometry(top: 900, bottom: 1_500, bodyHeight: 2_400).fraction)
        let landscape = try XCTUnwrap(ArticleReadingGeometry(top: 900, bottom: 1_200, bodyHeight: 2_400).fraction)
        XCTAssertEqual(portrait, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(landscape, 900.0 / 2_100.0, accuracy: 0.000_001)
        XCTAssertLessThan(landscape, portrait)
    }

    func testLargerTextBodyRecalculatesProgressWithoutKeepingOldExtent() throws {
        var geometry = ArticleReadingGeometry(top: 900, bottom: 1_500, bodyHeight: 2_400)
        XCTAssertEqual(try XCTUnwrap(geometry.fraction), 0.5, accuracy: 0.000_001)
        geometry.bodyHeight = 4_800
        XCTAssertEqual(try XCTUnwrap(geometry.fraction), 900.0 / 4_200.0, accuracy: 0.000_001)
        geometry.top = 4_200
        geometry.bottom = 4_800
        XCTAssertEqual(geometry.fraction, 1)
    }

    func testInvalidOrUnmeasuredDimensionsDoNotProduceProgress() {
        let invalid: [ArticleReadingGeometry] = [
            .init(top: 0, bottom: 0, bodyHeight: 2_400),
            .init(top: 600, bottom: 0, bodyHeight: 2_400),
            .init(top: 0, bottom: 600, bodyHeight: 0),
            .init(top: 0, bottom: 600, bodyHeight: -1)
        ]
        for geometry in invalid {
            XCTAssertNil(geometry.fraction, "Invalid geometry: \(geometry)")
        }
    }

    func testNonfiniteCoordinatesOrBodyExtentDoNotProduceProgress() {
        for nonfinite in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(ArticleReadingGeometry(top: nonfinite, bottom: 600, bodyHeight: 2_400).fraction)
            XCTAssertNil(ArticleReadingGeometry(top: 0, bottom: nonfinite, bodyHeight: 2_400).fraction)
            XCTAssertNil(ArticleReadingGeometry(top: 0, bottom: 600, bodyHeight: nonfinite).fraction)
        }
    }

    func testOverflowingViewportExtentDoesNotProduceFalseCompletion() {
        let geometry = ArticleReadingGeometry(top: -Double.greatestFiniteMagnitude,
                                              bottom: Double.greatestFiniteMagnitude,
                                              bodyHeight: 2_400)
        XCTAssertNil(geometry.fraction)
    }
}
