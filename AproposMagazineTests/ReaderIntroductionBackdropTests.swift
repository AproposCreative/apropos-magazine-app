import XCTest
@testable import Apropos

final class ReaderIntroductionBackdropTests: XCTestCase {
    func testInactiveBackdropDoesNotAdvance() {
        let clock = ReaderIntroductionBackdropClock()
        XCTAssertEqual(clock.elapsed(at: 100), 0)
        XCTAssertEqual(clock.elapsed(at: 1_000), 0)
    }

    func testForegroundUpdatesRetainTheCurrentPhase() {
        var clock = ReaderIntroductionBackdropClock()
        clock.setRunning(true, at: 100)
        clock.setRunning(true, at: 104) // e.g. foreground changes to another step
        XCTAssertEqual(clock.elapsed(at: 106), 6)
    }

    func testHiddenAndReducedMotionIntervalsDoNotJumpThePhaseOnResume() {
        var clock = ReaderIntroductionBackdropClock()
        clock.setRunning(true, at: 100)
        clock.setRunning(false, at: 106)
        clock.setRunning(false, at: 200)
        XCTAssertEqual(clock.elapsed(at: 300), 6)
        clock.setRunning(true, at: 300)
        XCTAssertEqual(clock.elapsed(at: 300), 6)
        XCTAssertEqual(clock.elapsed(at: 304), 10)
    }

    func testBothFieldsMoveVisiblyAndIndependentlyOverSixSeconds() {
        let first = ReaderIntroductionBackdropFrame.at(elapsed: 0)
        let later = ReaderIntroductionBackdropFrame.at(elapsed: 6)
        let blue = CGSize(width: later.blueOffset.width - first.blueOffset.width,
                          height: later.blueOffset.height - first.blueOffset.height)
        let white = CGSize(width: later.whiteOffset.width - first.whiteOffset.width,
                           height: later.whiteOffset.height - first.whiteOffset.height)
        XCTAssertGreaterThan(hypot(blue.width, blue.height), 40)
        XCTAssertGreaterThan(hypot(white.width, white.height), 40)
        // This catches the old shared whole-layer drift: the fields travel in
        // opposite horizontal directions during this part of their paths.
        XCTAssertGreaterThan(blue.width, 0)
        XCTAssertLessThan(white.width, 0)
    }

    func testBlueCycleHasNoResetAndDoesNotResetWhiteField() {
        let first = ReaderIntroductionBackdropFrame.at(elapsed: 0)
        let cycle = ReaderIntroductionBackdropFrame.at(elapsed: 28)
        XCTAssertEqual(cycle.blueOffset.width, first.blueOffset.width, accuracy: 0.000_001)
        XCTAssertEqual(cycle.blueOffset.height, first.blueOffset.height, accuracy: 0.000_001)
        XCTAssertNotEqual(cycle.whiteOffset, first.whiteOffset)

        let before = ReaderIntroductionBackdropFrame.at(elapsed: 27.99)
        let after = ReaderIntroductionBackdropFrame.at(elapsed: 28.01)
        XCTAssertLessThan(hypot(after.blueOffset.width - before.blueOffset.width,
                               after.blueOffset.height - before.blueOffset.height), 1)
    }
}
