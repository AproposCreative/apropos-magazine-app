import Foundation
import XCTest
@testable import Apropos

@MainActor
final class PushRegistrationHTTPTransportTests: XCTestCase {
    private let registerURL = URL(string: "https://push.example.test/register")!
    private let confirmURL = URL(string: "https://push.example.test/confirm")!
    private let installation = "a1234567-1234-4123-8123-123456789abc"
    private let key = String(repeating: "k", count: 48)
    private let challenge = String(repeating: "a", count: 64)

    private func ticket(_ context: PushAccountContext? = nil, revision: Int64 = 3) -> PushRegistrationTicket {
        .init(generation: UUID(), context: context ?? .guest(epoch: UUID()), installationId: installation, clientRevision: revision)
    }
    private func call(enabled: Bool = true, revision: Int64 = 3) -> PushRegistrationCall {
        .register(.init(installationId: installation, key: key, clientRevision: revision, permission: enabled,
                       preferences: .init(articles: enabled ? .all : .off, categoryIds: [], podcasts: false),
                       token: enabled ? String(repeating: "t", count: 80) : nil))
    }
    private func body(status: String = "pending", revision: Any? = nil) throws -> Data {
        var result: [String: Any] = ["status": status, "installationId": installation, "clientRevision": 3]
        if let revision { result["revision"] = revision }
        if status == "pending" { result["challengeId"] = challenge }
        return try JSONSerialization.data(withJSONObject: result)
    }
    private func response(_ status: Int = 200, url: URL? = nil, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url ?? registerURL, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"].merging(headers, uniquingKeysWith: { _, new in new }))!
    }
    private func transport(
        credentials: @escaping (PushAccountContext) async throws -> PushRegistrationCredentials = { context in
            .init(appCheckToken: "app.check", idToken: context.ownerUID == nil ? nil : "user.token", ownerUID: context.ownerUID)
        },
        isCurrent: @escaping (PushRegistrationTicket) -> Bool = { _ in true },
        perform: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) throws -> PushRegistrationHTTPTransport {
        try .init(registerURL: registerURL, confirmURL: confirmURL, credentials: credentials, isCurrent: isCurrent, perform: perform)
    }
    private func assertFailure(_ expected: PushRegistrationFailure, operation: () async throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected a safe transport failure", file: file, line: line) }
        catch let failure as PushRegistrationFailure { XCTAssertEqual(failure, expected, file: file, line: line) }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }

    func testEveryRetryRefreshesCredentialsAndKeepsTheSameIdempotentRequest() async throws {
        let expectedBody = try call().body(), receiptBody = try body()
        var credentialCalls = 0
        var requests: [URLRequest] = []
        let transport = try transport(credentials: { context in
            credentialCalls += 1
            return .init(appCheckToken: "app.\(credentialCalls)", idToken: nil, ownerUID: context.ownerUID)
        }, perform: { request in
            requests.append(request)
            return (receiptBody, self.response())
        })
        let current = ticket()
        let first = try await transport.send(call(), ticket: current)
        let second = try await transport.send(call(), ticket: current)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.status, .pending)
        XCTAssertEqual(credentialCalls, 2)
        XCTAssertEqual(requests.map(\.httpBody), [expectedBody, expectedBody])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "X-Firebase-AppCheck") }, ["app.1", "app.2"])
    }

    func testAuthenticatedHeadersStayOutOfURLAndBody() async throws {
        let reply = try body(status: "active", revision: 4)
        var sent: URLRequest?
        let transport = try transport(perform: { request in sent = request; return (reply, self.response()) })
        let result = try await transport.send(call(), ticket: ticket(.authenticated(uid: "reader_1", epoch: UUID())))
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, registerURL)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let contents = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(contents.contains("user.token"))
        XCTAssertFalse(contents.contains("app.check"))
        XCTAssertNil(request.url?.query)
    }

    func testAuthenticatedCredentialFailureNeverFallsBackToGuest() async throws {
        var sends = 0
        let transport = try transport(credentials: { _ in throw URLError(.userAuthenticationRequired) }, perform: { _ in
            sends += 1; return (Data(), self.response())
        })
        await assertFailure(.authentication) {
            _ = try await transport.send(self.call(), ticket: self.ticket(.authenticated(uid: "reader", epoch: UUID())))
        }
        XCTAssertEqual(sends, 0)
    }

    func testAccountChangeDuringCredentialFetchCancelsWithoutSending() async throws {
        var current = true, sends = 0
        let transport = try transport(credentials: { context in
            await Task.yield()
            current = false
            return .init(appCheckToken: "app.check", idToken: nil, ownerUID: context.ownerUID)
        }, isCurrent: { _ in current }, perform: { _ in sends += 1; return (Data(), self.response()) })
        await assertFailure(.cancelled) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        XCTAssertEqual(sends, 0)
    }

    func testStaleTicketIsRejectedBeforeCredentialFetch() async throws {
        var fetches = 0
        let transport = try transport(credentials: { _ in
            fetches += 1; return .init(appCheckToken: "app.check", idToken: nil, ownerUID: nil)
        }, isCurrent: { _ in false }, perform: { _ in XCTFail("Must not send"); return (Data(), self.response()) })
        await assertFailure(.cancelled) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        XCTAssertEqual(fetches, 0)
    }

    func testAccountChangeDuringHTTPAwaitDiscardsReceipt() async throws {
        var current = true
        let reply = try body()
        let transport = try transport(isCurrent: { _ in current }, perform: { _ in
            await Task.yield(); current = false; return (reply, self.response())
        })
        await assertFailure(.cancelled) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
    }

    func testGuestCredentialsCannotContainAnAccountTokenOrAnotherOwner() async throws {
        for identity in [PushRegistrationCredentials(appCheckToken: "app.check", idToken: "user.token", ownerUID: nil),
                         .init(appCheckToken: "app.check", idToken: nil, ownerUID: "other")] {
            let transport = try transport(credentials: { _ in identity }, perform: { _ in
                XCTFail("Mismatched identity must not send"); return (Data(), self.response())
            })
            await assertFailure(.authentication) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        }
    }

    func testAuthenticatedCredentialsRequireSameOwnerAndPresentValidIDToken() async throws {
        for identity in [PushRegistrationCredentials(appCheckToken: "app.check", idToken: nil, ownerUID: "reader"),
                         .init(appCheckToken: "app.check", idToken: "user.token", ownerUID: "other"),
                         .init(appCheckToken: "app.check", idToken: "bad\r\nheader", ownerUID: "reader")] {
            let transport = try transport(credentials: { _ in identity }, perform: { _ in
                XCTFail("Invalid credentials must not send"); return (Data(), self.response())
            })
            await assertFailure(.authentication) {
                _ = try await transport.send(self.call(), ticket: self.ticket(.authenticated(uid: "reader", epoch: UUID())))
            }
        }
    }

    func testUnresolvedAccountAndInvalidTicketNeverFetchCredentials() async throws {
        var fetches = 0
        let transport = try transport(credentials: { _ in fetches += 1; return .init(appCheckToken: "app.check", idToken: nil, ownerUID: nil) },
                                      perform: { _ in XCTFail("Must not send"); return (Data(), self.response()) })
        await assertFailure(.authentication) { _ = try await transport.send(self.call(), ticket: self.ticket(.unresolved)) }
        await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket(revision: 0)) }
        await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket(revision: 4)) }
        XCTAssertEqual(fetches, 0)
    }

    func testConstructionRejectsInsecureCredentialBearingAndDifferentOriginEndpoints() {
        let invalid = ["http://push.example.test/register", "https://user:pass@push.example.test/register",
                       "https://push.example.test/register?key=secret", "https://push.example.test/register#fragment",
                       "https://push.example.test/", "https://other.example.test/register"]
        for candidate in invalid {
            XCTAssertThrowsError(try PushRegistrationHTTPTransport(registerURL: URL(string: candidate)!, confirmURL: confirmURL,
                credentials: { _ in .init(appCheckToken: "test", idToken: nil, ownerUID: nil) }, isCurrent: { _ in true },
                perform: { _ in XCTFail("Construction must not send"); return (Data(), self.response()) }))
        }
    }

    func testConfirmUsesOnlyTheConfiguredConfirmEndpointAndRequiresActiveReceipt() async throws {
        let reply = try body(status: "active", revision: 5)
        let transport = try transport(perform: { request in
            XCTAssertEqual(request.url, self.confirmURL)
            return (reply, self.response(url: self.confirmURL))
        })
        let confirmation = PushRegistrationCall.confirm(.init(installationId: installation, key: key, challengeId: challenge,
                                                              nonce: String(repeating: "n", count: 48)))
        let receipt = try await transport.send(confirmation, ticket: ticket())
        XCTAssertEqual(receipt.status, .active)
        let wrongStatus = try self.transport(perform: { _ in (try self.body(), self.response(url: self.confirmURL)) })
        await assertFailure(.invalidResponse) { _ = try await wrongStatus.send(confirmation, ticket: self.ticket()) }
    }

    func testForeignOrRedirectedResponseIsRejectedEvenWithValidReceipt() async throws {
        let reply = try body()
        for url in [URL(string: "https://elsewhere.example.test/register")!, URL(string: "https://push.example.test/elsewhere")!,
                    URL(string: "https://push.example.test/register?redirected=true")!] {
            let transport = try transport(perform: { _ in (reply, self.response(url: url)) })
            await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        }
    }

    func testMalformedOversizeAndNonJSONSuccessAreRejected() async throws {
        let cases: [(Data, HTTPURLResponse)] = [
            (Data("[]".utf8), response()), (Data("not json".utf8), response()),
            (Data(repeating: 0x20, count: 16_385), response()),
            (try body(), response(headers: ["Content-Type": "text/html"]))
        ]
        for value in cases {
            let transport = try transport(perform: { _ in value })
            await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        }
    }

    func testStrictReceiptRejectsUnknownFieldsWrongRevisionAndWrongInstallation() async throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: body()) as? [String: Any])
        var rows: [[String: Any]] = []
        for (key, value) in [("nonce", "private" as Any), ("clientRevision", 4), ("clientRevision", true),
                             ("clientRevision", 9_007_199_254_740_992 as Int64), ("clientRevision", 3.5),
                             ("installationId", "b1234567-1234-4123-8123-123456789abc"), ("challengeId", "bad"),
                             ("revision", false), ("revision", 0)] {
            var row = original; row[key] = value; rows.append(row)
        }
        for row in rows {
            let data = try JSONSerialization.data(withJSONObject: row)
            let transport = try transport(perform: { _ in (data, self.response()) })
            await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        }
    }

    func testDisabledReceiptMustMatchDisabledRequestAndHaveServerRevision() async throws {
        let disabled = try body(status: "disabled", revision: 5)
        let transport = try transport(perform: { _ in (disabled, self.response()) })
        let receipt = try await transport.send(call(enabled: false), ticket: ticket())
        XCTAssertEqual(receipt.status, .disabled)
        await assertFailure(.invalidResponse) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        let missing = try self.transport(perform: { _ in (try self.body(status: "disabled"), self.response()) })
        await assertFailure(.invalidResponse) { _ = try await missing.send(self.call(enabled: false), ticket: self.ticket()) }
    }

    func testHTTPStatusErrorsAreSafeAndDoNotExposeServerDetails() async throws {
        for (status, expected) in [(401, PushRegistrationFailure.authentication), (403, .forbidden), (409, .conflict),
                                   (400, .invalidResponse), (302, .invalidResponse), (503, .transient(retryAfter: nil)),
                                   (500, .transient(retryAfter: nil))] {
            let transport = try transport(perform: { _ in (Data("private proxy diagnostic".utf8), self.response(status)) })
            await assertFailure(expected) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        }
    }

    func testRateLimitHonorsNumericAndHTTPDateRetryAfter() async throws {
        let secondsTransport = try transport(perform: { _ in (Data(), self.response(429, headers: ["Retry-After": "120"])) })
        await assertFailure(.transient(retryAfter: 120)) { _ = try await secondsTransport.send(self.call(), ticket: self.ticket()) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let future = formatter.string(from: Date().addingTimeInterval(180))
        let dateTransport = try transport(perform: { _ in (Data(), self.response(429, headers: ["Retry-After": future])) })
        do { _ = try await dateTransport.send(call(), ticket: ticket()); XCTFail("Expected retry") }
        catch let error as PushRegistrationFailure {
            guard case .transient(let delay) = error else { return XCTFail("Expected bounded retry") }
            XCTAssertGreaterThan(try XCTUnwrap(delay), 170)
            XCTAssertLessThanOrEqual(try XCTUnwrap(delay), 180)
        }
    }

    func testNetworkErrorBecomesTransientAndCancellationStaysCancelled() async throws {
        let transport = try transport(perform: { _ in throw URLError(.notConnectedToInternet) })
        await assertFailure(.transient(retryAfter: nil)) { _ = try await transport.send(self.call(), ticket: self.ticket()) }
        let cancelled = try self.transport(perform: { _ in throw URLError(.cancelled) })
        await assertFailure(.cancelled) { _ = try await cancelled.send(self.call(), ticket: self.ticket()) }
    }

    func testExecutorPolicyFailureBlocksWithoutPropagatingArbitraryInjectedAuthentication() async throws {
        let rejected = try transport(perform: { _ in throw PushRegistrationFailure.invalidResponse })
        await assertFailure(.invalidResponse) { _ = try await rejected.send(self.call(), ticket: self.ticket()) }
        let untrusted = try transport(perform: { _ in throw PushRegistrationFailure.authentication })
        await assertFailure(.transient(retryAfter: nil)) { _ = try await untrusted.send(self.call(), ticket: self.ticket()) }
        var current = true
        let stale = try transport(isCurrent: { _ in current }, perform: { _ in
            current = false
            throw PushRegistrationFailure.invalidResponse
        })
        await assertFailure(.cancelled) { _ = try await stale.send(self.call(), ticket: self.ticket()) }
    }
}
