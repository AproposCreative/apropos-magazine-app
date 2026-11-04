import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderNewsletterHTTPTransportTests: XCTestCase {
    let endpoint = URL(string: "https://newsletter.example.invalid/signup")!

    func testActualRequestEncoderMatchesSharedServerAndResearchContract() throws {
        let request = ReaderNewsletterSignupModel.Request(requestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            expectedUserID: "reader_contract", expectedEmail: "Reader+Contract@Example.invalid")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-newsletter-wire-v1.json"))
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary)
        var expected = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        expected["reconfirmationChallenge"] = NSNull()
        XCTAssertEqual(actual, expected as NSDictionary)
        XCTAssertNil(try JSONDecoder().decode(ReaderNewsletterSignupModel.Request.self, from: fixture).reconfirmationChallenge)
    }

    func testDispatchCarriesOriginalVerifiedPayloadAndCredentialsOnlyInHeaders() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let payload = ReaderNewsletterSignupModel.Request(expectedUserID: "A", expectedEmail: "a@example.invalid")
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
            credentials: { _ in .init(idToken: "fixture-id", appCheckToken: "fixture-attestation") },
            isCurrent: canonical.isCurrent, execute: { request in
                XCTAssertEqual(request.url, self.endpoint)
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-id")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "fixture-attestation")
                XCTAssertEqual(try JSONDecoder().decode(ReaderNewsletterSignupModel.Request.self, from: XCTUnwrap(request.httpBody)), payload)
                return (try JSONEncoder().encode(ReaderNewsletterSignupModel.Response(status: .subscribed, requestID: payload.requestID)),
                    HTTPURLResponse(url: self.endpoint, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            })
        let result = try await transport.send(payload, context: canonical.contextTicket())
        XCTAssertEqual(result.status, .subscribed)
    }

    func testAccountChangeWhileFetchingTokensPreventsHTTP() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let context = canonical.contextTicket()
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint, credentials: { _ in
            canonical.adopt(nil)
            return .init(idToken: "fixture", appCheckToken: "fixture")
        }, isCurrent: canonical.isCurrent, execute: { _ in
            XCTFail("Revoked credentials must never reach HTTP")
            throw CancellationError()
        })
        do {
            _ = try await transport.send(.init(expectedUserID: "A", expectedEmail: "a@example.invalid"), context: context)
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testMissingAppAttestationCannotDispatch() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
            credentials: { _ in .init(idToken: "fixture", appCheckToken: "") },
            isCurrent: canonical.isCurrent, execute: { _ in XCTFail("No anonymous fallback"); throw CancellationError() })
        do {
            _ = try await transport.send(.init(expectedUserID: "A", expectedEmail: "a@example.invalid"), context: canonical.contextTicket())
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testRejectsMismatchedReceiptNonJSONAndHTTPFailure() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let payload = ReaderNewsletterSignupModel.Request(expectedUserID: "A", expectedEmail: "a@example.invalid")
        for scenario in 0..<3 {
            let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
                credentials: { _ in .init(idToken: "fixture", appCheckToken: "fixture") },
                isCurrent: canonical.isCurrent, execute: { _ in
                    let data = try JSONEncoder().encode(ReaderNewsletterSignupModel.Response(status: .subscribed,
                        requestID: scenario == 0 ? UUID().uuidString : payload.requestID))
                    return (data, HTTPURLResponse(url: self.endpoint, statusCode: scenario == 2 ? 503 : 200,
                        httpVersion: nil, headerFields: ["Content-Type": scenario == 1 ? "text/html" : "application/json"])!)
                })
            do {
                _ = try await transport.send(payload, context: canonical.contextTicket())
                XCTFail("Unconfirmed response must not be success")
            } catch ReaderNewsletterHTTPTransport.Failure.invalidResponse { }
        }
    }

    func testLateSuccessAfterAccountChangeIsDiscarded() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let context = canonical.contextTicket()
        let payload = ReaderNewsletterSignupModel.Request(expectedUserID: "A", expectedEmail: "a@example.invalid")
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
            credentials: { _ in .init(idToken: "fixture", appCheckToken: "fixture") },
            isCurrent: canonical.isCurrent, execute: { _ in
                canonical.adopt(.init(uid: "B", email: "b@example.invalid", isEmailVerified: true))
                return (try JSONEncoder().encode(ReaderNewsletterSignupModel.Response(status: .subscribed, requestID: payload.requestID)),
                    HTTPURLResponse(url: self.endpoint, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            })
        do { _ = try await transport.send(payload, context: context); XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testHTTPChallengeRoundTripPreservesExplicitCapabilityAndReconfirmationBinding() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let first = ReaderNewsletterSignupModel.Request(expectedUserID: "A", expectedEmail: "a@example.invalid")
        let challenge = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        var bodies: [[String: Any]] = []
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
            credentials: { _ in .init(idToken: "fixture", appCheckToken: "one-use-fixture") },
            isCurrent: canonical.isCurrent, execute: { request in
                bodies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]))
                let result = bodies.count == 1
                    ? ReaderNewsletterSignupModel.Response(status: .reconfirmationRequired, requestID: first.requestID, reconfirmationChallenge: challenge)
                    : ReaderNewsletterSignupModel.Response(status: .subscribed, requestID: first.requestID)
                return (try JSONEncoder().encode(result), HTTPURLResponse(url: self.endpoint, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            })
        let proposed = try await transport.send(first, context: canonical.contextTicket())
        XCTAssertEqual(proposed.reconfirmationChallenge, challenge); XCTAssertTrue(bodies[0]["reconfirmationChallenge"] is NSNull)
        let second = ReaderNewsletterSignupModel.Request(requestID: first.requestID, expectedUserID: "A", expectedEmail: "a@example.invalid",
            reconfirmationChallenge: proposed.reconfirmationChallenge)
        let confirmed = try await transport.send(second, context: canonical.contextTicket())
        XCTAssertEqual(confirmed.status, .subscribed)
        XCTAssertEqual(bodies[1]["requestID"] as? String, first.requestID)
        XCTAssertEqual(bodies[1]["reconfirmationChallenge"] as? String, challenge)
    }

    func testMalformedOutgoingChallengeNeverAcquiresCredentialsOrHTTP() async throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(.init(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint,
            credentials: { _ in XCTFail("Malformed challenge must stop before credentials"); throw CancellationError() },
            isCurrent: canonical.isCurrent, execute: { _ in XCTFail("Malformed challenge must stop before HTTP"); throw CancellationError() })
        do {
            _ = try await transport.send(.init(expectedUserID: "A", expectedEmail: "a@example.invalid", reconfirmationChallenge: "invalid"), context: canonical.contextTicket())
            XCTFail("Expected rejected challenge")
        } catch ReaderNewsletterHTTPTransport.Failure.invalidResponse { }
    }

    func testResponseDecoderRejectsMalformedAndSuccessAttachedChallenges() throws {
        let cases: [[String: Any]] = [
            ["status": "reconfirmationRequired", "requestID": "fixture", "reconfirmationChallenge": 42],
            ["status": "reconfirmationRequired", "requestID": "fixture", "reconfirmationChallenge": "bad"],
            ["status": "subscribed", "requestID": "fixture", "reconfirmationChallenge": "ffffffff-ffff-4fff-8fff-ffffffffffff"]
        ]
        for fields in cases {
            let data = try JSONSerialization.data(withJSONObject: fields)
            XCTAssertThrowsError(try JSONDecoder().decode(ReaderNewsletterSignupModel.Response.self, from: data))
        }
    }
}
