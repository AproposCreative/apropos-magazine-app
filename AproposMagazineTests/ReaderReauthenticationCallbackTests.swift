import XCTest
@testable import Apropos

final class ReaderReauthenticationCallbackTests: XCTestCase {
    private enum ProviderFailure: Error, Equatable { case userMismatch }

    func testProviderErrorRejectsEvenAPresentResult() {
        let result = ReaderReauthenticationCallback.result("another-account", error: ProviderFailure.userMismatch)
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ProviderFailure, .userMismatch)
        }
    }

    func testMissingResultCannotBeSuccessOrLeaveContinuationUnresolved() {
        let result = ReaderReauthenticationCallback.result(String?.none, error: nil)
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is ReaderReauthenticationCallback.MissingResult)
        }
    }

    func testConfirmedResultPreservesOriginalValue() throws {
        XCTAssertEqual(try ReaderReauthenticationCallback.result("original-account", error: nil).get(), "original-account")
    }
}
