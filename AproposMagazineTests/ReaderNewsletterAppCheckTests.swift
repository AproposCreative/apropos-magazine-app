import FirebaseAppCheck
import FirebaseCore
import XCTest
@testable import Apropos

final class ReaderNewsletterAppCheckTests: XCTestCase {
    private final class Provider: NSObject, AppCheckProvider {
        var standardCalls = 0
        var limitedCalls = 0
        var failure: Error?
        let token = AppCheckToken(token: "local-fixture-only", expirationDate: Date(timeIntervalSince1970: 2_000_000_000))

        func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
            standardCalls += 1
            completion(token, nil)
        }
        func getLimitedUseToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
            limitedCalls += 1
            completion(failure == nil ? token : nil, failure)
        }
    }

    private final class StandardOnlyProvider: NSObject, AppCheckProvider {
        var calls = 0
        func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
            calls += 1
            completion(nil, NSError(domain: "fixture", code: 42))
        }
    }

    func testOrdinaryTokenAndRefreshRequestsNeverConstructAttestation() {
        XCTAssertNil(FirebaseApp.allApps)
        var builds = 0
        let provider = ReaderNewsletterAppCheckProvider { builds += 1; return Provider() }
        var callbacks = 0
        for _ in 0..<3 {
            provider.getToken { token, error in
                XCTAssertNil(token); XCTAssertNotNil(error); callbacks += 1
            }
        }
        XCTAssertEqual(builds, 0); XCTAssertEqual(callbacks, 3)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testLimitedUseIsExplicitAndFreshEachTimeWhileProviderIsReused() {
        let underlying = Provider()
        var builds = 0
        let provider = ReaderNewsletterAppCheckProvider { builds += 1; return underlying }
        for _ in 0..<3 {
            provider.getLimitedUseToken { token, error in
                XCTAssertTrue(token === underlying.token); XCTAssertNil(error)
            }
        }
        provider.getToken { token, error in XCTAssertNil(token); XCTAssertNotNil(error) }
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(underlying.limitedCalls, 3); XCTAssertEqual(underlying.standardCalls, 0)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testDisabledOrUnsupportedProviderFailsLocallyWithoutFallback() {
        let provider = ReaderNewsletterAppCheckProvider { nil }
        var calls = 0
        provider.getLimitedUseToken { token, error in
            XCTAssertNil(token); XCTAssertNotNil(error); calls += 1
        }
        XCTAssertEqual(calls, 1); XCTAssertNil(FirebaseApp.allApps)
    }

    func testProviderWithoutLimitedUseCannotFallBackToStandardToken() {
        let underlying = StandardOnlyProvider()
        let provider = ReaderNewsletterAppCheckProvider { underlying }
        provider.getLimitedUseToken { token, error in XCTAssertNil(token); XCTAssertNotNil(error) }
        XCTAssertEqual(underlying.calls, 0)
    }

    func testAttestationFailureIsForwardedWithoutStandardRetry() {
        let underlying = Provider()
        underlying.failure = NSError(domain: "fixture-error", code: 17)
        let provider = ReaderNewsletterAppCheckProvider { underlying }
        provider.getLimitedUseToken { token, error in
            XCTAssertNil(token); XCTAssertEqual((error as NSError?)?.domain, "fixture-error")
        }
        XCTAssertEqual(underlying.limitedCalls, 1); XCTAssertEqual(underlying.standardCalls, 0)
    }

    func testReviewedResearchProductionConfigurationIsTypedExactAndInert() throws {
        XCTAssertNil(FirebaseApp.allApps)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("AproposMagazinev2/AproposMagazinev2/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let address = "https://ai.aproposmagazine.com/api/reader-newsletter/signup"
        XCTAssertEqual(info["ReaderNewsletterEnabled"] as? Bool, true)
        XCTAssertEqual(info["ReaderNewsletterEndpoint"] as? String, address)
        XCTAssertEqual(ReaderNewsletterConfiguration.endpoint(in: info)?.absoluteString, address)
        var untyped = info
        untyped["ReaderNewsletterEnabled"] = "true"
        XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: untyped))
        XCTAssertNil(FirebaseApp.allApps, "Configuration validation must not initialize Firebase or attestation")
    }

    func testConfigurationNeedsExplicitEnableAndValidExactHTTPSDestination() {
        let address = "https://newsletter.example.invalid/signup"
        XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: [:]))
        XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: ["ReaderNewsletterEndpoint": address]))
        XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: ["ReaderNewsletterEnabled": true]))
        XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: ["ReaderNewsletterEnabled": false, "ReaderNewsletterEndpoint": address]))
        for invalid in ["http://newsletter.example.invalid/signup", "https://user:pass@example.invalid/signup",
                        "https://example.invalid/signup?token=fixture", "https://example.invalid/signup#fragment",
                        "https://example.invalid/"] {
            XCTAssertNil(ReaderNewsletterConfiguration.endpoint(in: ["ReaderNewsletterEnabled": true, "ReaderNewsletterEndpoint": invalid]))
        }
        XCTAssertEqual(ReaderNewsletterConfiguration.endpoint(in: ["ReaderNewsletterEnabled": true, "ReaderNewsletterEndpoint": address]), URL(string: address))
        XCTAssertNil(FirebaseApp.allApps)
    }
}
