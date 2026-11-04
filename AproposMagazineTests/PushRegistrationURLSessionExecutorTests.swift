import Foundation
import XCTest
@testable import Apropos

/// Every URLSession created by this fixture has an intercept-all URLProtocol.
/// Unknown requests fail locally; none can fall through to a socket.
final class PushRegistrationURLSessionExecutorTests: XCTestCase {
    private func endpoint() -> URL { URL(string: "https://push.example.test/\(UUID().uuidString)")! }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer inert.test", forHTTPHeaderField: "Authorization")
        request.setValue("inert.app.check", forHTTPHeaderField: "X-Firebase-AppCheck")
        return request
    }
    private func executor(_ urls: Set<URL>) throws -> PushRegistrationURLSessionExecutor {
        try .init(allowedURLs: urls, protocolClasses: [RegistrationProtocolStub.self])
    }
    private func operation(_ url: URL) -> PushRegistrationURLSessionExecutor.RequestOperation {
        .init(request: request(url), protocolClasses: [RegistrationProtocolStub.self])
    }
    private func response(_ url: URL, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
    private func assertInvalid(_ operation: () async throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected policy rejection", file: file, line: line) }
        catch let error as PushRegistrationFailure { XCTAssertEqual(error, .invalidResponse, file: file, line: line) }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }
    private func assertCancelled(_ operation: () async throws -> Void,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected cancellation", file: file, line: line) }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error type", file: file, line: line) }
    }
    override func tearDown() {
        RegistrationProtocolStub.clear()
        super.tearDown()
    }

    func testConstructionRequiresExplicitSafeAllowlistAndCreatesNoRequests() throws {
        XCTAssertThrowsError(try executor([]))
        XCTAssertThrowsError(try executor([endpoint(), endpoint(), endpoint()]))
        for string in ["http://push.example.test/register", "https://push.example.test/",
                       "https://user:pass@push.example.test/register", "https://push.example.test/register?secret=1",
                       "https://push.example.test/register#fragment"] {
            XCTAssertThrowsError(try executor([URL(string: string)!]))
        }
        let url = endpoint()
        RegistrationProtocolStub.register(url) { _ in XCTFail("Construction cannot start a request") }
        _ = try executor([url])
    }

    func testEphemeralConfigurationHasNoPersistentStateAndBoundedDeadlines() {
        let configuration = PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self])
        XCTAssertNil(configuration.identifier)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 60)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 1)
        XCTAssertEqual(configuration.protocolClasses?.count, 1)
    }

    func testRealSessionCollectsChunksAndPreservesExplicitCredentials() async throws {
        let url = endpoint()
        RegistrationProtocolStub.register(url) { stub in
            XCTAssertEqual(stub.request.url, url)
            XCTAssertEqual(stub.request.httpMethod, "POST")
            XCTAssertEqual(stub.request.value(forHTTPHeaderField: "Authorization"), "Bearer inert.test")
            XCTAssertEqual(stub.request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "inert.app.check")
            XCTAssertEqual(stub.request.timeoutInterval, 60)
            XCTAssertFalse(stub.request.httpShouldHandleCookies)
            XCTAssertEqual(stub.request.cachePolicy, .reloadIgnoringLocalCacheData)
            stub.respond(self.response(url))
            stub.chunk(Data("first".utf8)); stub.chunk(Data("second".utf8)); stub.complete()
        }
        var input = request(url)
        input.timeoutInterval = 600
        input.httpShouldHandleCookies = true
        input.cachePolicy = .returnCacheDataElseLoad
        let (data, result) = try await executor([url]).perform(input)
        XCTAssertEqual(data, Data("firstsecond".utf8))
        XCTAssertEqual(result.url, url)
    }

    func testUnsafeDirectRequestsNeverReachProtocol() async throws {
        let url = endpoint(), executor = try executor([url])
        RegistrationProtocolStub.register(url) { _ in XCTFail("Rejected request cannot dispatch") }
        var rows: [URLRequest] = []
        var input = request(url); input.httpMethod = "GET"; rows.append(input)
        input = request(url); input.httpBody = nil; rows.append(input)
        input = request(url); input.httpBody = Data(repeating: 1, count: 16_385); rows.append(input)
        input = request(url); input.httpBodyStream = InputStream(data: Data("{}".utf8)); rows.append(input)
        rows.append(request(endpoint()))
        for input in rows { await assertInvalid { _ = try await executor.perform(input) } }
    }

    func testExactlyMaximumRequestAndResponseBytesAreAccepted() async throws {
        let url = endpoint()
        RegistrationProtocolStub.register(url) { stub in
            stub.respond(self.response(url, headers: ["Content-Length": "16384"]))
            stub.chunk(Data(repeating: 0x61, count: 8192))
            stub.chunk(Data(repeating: 0x62, count: 8192))
            stub.complete()
        }
        var input = request(url)
        input.httpBody = Data(repeating: 0x63, count: 16_384)
        let (data, _) = try await executor([url]).perform(input)
        XCTAssertEqual(data.count, 16_384)
        XCTAssertEqual(data.first, 0x61)
        XCTAssertEqual(data.last, 0x62)
    }

    func testUnknownLengthStreamIsRejectedAtFirstChunkBeyondLimit() async throws {
        let url = endpoint()
        RegistrationProtocolStub.register(url) { stub in
            stub.respond(self.response(url))
            stub.chunk(Data(repeating: 0x61, count: 16_384))
            stub.chunk(Data([0x62]))
            stub.complete()
        }
        let executor = try executor([url])
        await assertInvalid { _ = try await executor.perform(self.request(url)) }
    }

    func testSingleOversizeChunkIsRejectedWithoutReturningPartialBody() async throws {
        let url = endpoint()
        RegistrationProtocolStub.register(url) { stub in
            stub.respond(self.response(url))
            stub.chunk(Data(repeating: 1, count: 65_536)); stub.complete()
        }
        let executor = try executor([url])
        await assertInvalid { _ = try await executor.perform(self.request(url)) }
    }

    func testShortDeclaredLengthAndErrorStatusCannotBypassStreamingCap() async throws {
        for status in [200, 503] {
            let url = endpoint()
            RegistrationProtocolStub.register(url) { stub in
                stub.respond(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Length": "1"])!)
                stub.chunk(Data(repeating: 1, count: 16_385)); stub.complete()
            }
            let executor = try executor([url])
            await assertInvalid { _ = try await executor.perform(self.request(url)) }
        }
    }

    func testDeclaredOversizeAndInvalidContentLengthAreRejectedBeforeBody() async throws {
        for length in ["16385", "-1", "no-length", "18446744073709551616", "12, 12"] {
            let url = endpoint()
            RegistrationProtocolStub.register(url) { stub in
                stub.respond(self.response(url, headers: ["Content-Length": length])); stub.complete()
            }
            let executor = try executor([url])
            await assertInvalid { _ = try await executor.perform(self.request(url)) }
        }
    }

    func testForeignAndNonHTTPResponsesAreRejected() async throws {
        let original = endpoint()
        let candidates: [URLResponse] = [response(endpoint()),
            URLResponse(url: original, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)]
        for candidate in candidates {
            RegistrationProtocolStub.register(original) { stub in stub.respond(candidate); stub.chunk(Data("{}".utf8)); stub.complete() }
            let executor = try executor([original])
            await assertInvalid { _ = try await executor.perform(self.request(original)) }
        }
    }

    func testNetworkFailureIsReturnedWithoutPrivateDiagnosticMapping() async throws {
        let url = endpoint()
        RegistrationProtocolStub.register(url) { $0.fail(URLError(.notConnectedToInternet)) }
        do { _ = try await executor([url]).perform(request(url)); XCTFail("Expected network error") }
        catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
    }

    func testCancellationBeforeContinuationCreatesNoSessionOrRequest() async {
        let url = endpoint()
        let operation = operation(url)
        RegistrationProtocolStub.register(url) { _ in XCTFail("Cancelled operation cannot dispatch") }
        operation.cancel()
        await assertCancelled { _ = try await operation.value() }
        operation.cancel()
        operation.deadlineExpired()
    }

    func testAlreadyCancelledCallerNeverDispatches() async throws {
        let url = endpoint(), executor = try executor([url])
        RegistrationProtocolStub.register(url) { _ in XCTFail("Cancelled caller cannot dispatch") }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await executor.perform(self.request(url))
        }
        await assertCancelled { _ = try await task.value }
    }

    func testActiveCancellationStopsOwnedProtocolAndReturnsOnce() async {
        let ownedURL = endpoint(), ownedOperation = self.operation(ownedURL)
        let started = expectation(description: "Protocol started"), stopped = expectation(description: "Protocol stopped")
        RegistrationProtocolStub.register(ownedURL, stopped: { stopped.fulfill() }) { _ in started.fulfill() }
        let task = Task { try await ownedOperation.value() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await assertCancelled { _ = try await task.value }
        await fulfillment(of: [stopped], timeout: 2)
        ownedOperation.cancel()
        ownedOperation.deadlineExpired()
    }

    func testIndependentSessionsDoNotShareCancellation() async throws {
        let firstURL = endpoint(), secondURL = endpoint(), executor = try executor([firstURL, secondURL])
        let started = expectation(description: "First started")
        RegistrationProtocolStub.register(firstURL) { _ in started.fulfill() }
        let first = Task { try await executor.perform(self.request(firstURL)) }
        await fulfillment(of: [started], timeout: 2)
        first.cancel()
        await assertCancelled { _ = try await first.value }
        RegistrationProtocolStub.register(secondURL) { stub in
            stub.respond(self.response(secondURL))
            stub.chunk(Data("ok".utf8)); stub.complete()
        }
        let (data, _) = try await executor.perform(request(secondURL))
        XCTAssertEqual(data, Data("ok".utf8))
    }

    func testCompletedSessionCannotPersistCookiesIntoNextSession() async throws {
        let url = endpoint(), executor = try executor([url])
        RegistrationProtocolStub.register(url) { stub in
            XCTAssertNil(stub.request.value(forHTTPHeaderField: "Cookie"))
            stub.respond(self.response(url, headers: ["Set-Cookie": "private=ignored; Secure; Path=/"]))
            stub.chunk(Data("first".utf8)); stub.complete()
        }
        _ = try await executor.perform(request(url))
        RegistrationProtocolStub.register(url) { stub in
            XCTAssertNil(stub.request.value(forHTTPHeaderField: "Cookie"))
            stub.respond(self.response(url)); stub.chunk(Data("second".utf8)); stub.complete()
        }
        let (data, _) = try await executor.perform(request(url))
        XCTAssertEqual(data, Data("second".utf8))
    }

    func testExplicitDeadlineCancelsHangingProtocolWithoutWaitingSixtySeconds() async {
        let url = endpoint(), started = expectation(description: "Started"), stopped = expectation(description: "Stopped")
        RegistrationProtocolStub.register(url, stopped: { stopped.fulfill() }) { _ in started.fulfill() }
        let operation = operation(url), task = Task { try await operation.value() }
        await fulfillment(of: [started], timeout: 2)
        operation.deadlineExpired()
        do { _ = try await task.value; XCTFail("Expected timeout") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        catch { XCTFail("Unexpected error type") }
        await fulfillment(of: [stopped], timeout: 2)
        operation.cancel()
    }

    func testRedirectDelegateRejectsSameEndpointSameOriginAndForeignDestinations() async {
        // URLProtocol redirect emulation is not supported consistently by
        // Foundation. Exercise the actual delegate entry point; no redirect
        // request is ever resumed or sent to a target in this fixture.
        let url = endpoint()
        for destination in [url.absoluteString, "https://push.example.test/confirm",
                            "https://foreign.example.test/stolen", "http://push.example.test/register"] {
            let started = expectation(description: "Started")
            RegistrationProtocolStub.register(url) { _ in started.fulfill() }
            let operation = operation(url), task = Task { try await operation.value() }
            await fulfillment(of: [started], timeout: 2)
            let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
            let dummyTask = dummy.dataTask(with: request(url))
            var redirected = true, callbacks = 0
            operation.urlSession(dummy, task: dummyTask, willPerformHTTPRedirection: response(url),
                                 newRequest: request(URL(string: destination)!)) { callbacks += 1; redirected = $0 != nil }
            XCTAssertFalse(redirected)
            XCTAssertEqual(callbacks, 1)
            await assertInvalid { _ = try await task.value }
            dummy.invalidateAndCancel()
        }
    }

    func testNonTrustChallengeRejectsAmbientCredentialsAndFinishes() async {
        let operation = operation(endpoint())
        let challenge = URLAuthenticationChallenge(protectionSpace: .init(host: "push.example.test", port: 443,
            protocol: "https", realm: "private", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            proposedCredential: URLCredential(user: "ambient", password: "inert", persistence: .permanent),
            previousFailureCount: 0, failureResponse: nil, error: nil, sender: InertChallengeSender())
        let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
        var disposition: URLSession.AuthChallengeDisposition?, credential: URLCredential?
        operation.urlSession(dummy, didReceive: challenge) { disposition = $0; credential = $1 }
        XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
        XCTAssertNil(credential)
        await assertInvalid { _ = try await operation.value() }
        dummy.invalidateAndCancel()
    }

    func testServerTrustChallengeKeepsSystemValidation() {
        let operation = operation(endpoint())
        let challenge = URLAuthenticationChallenge(protectionSpace: .init(host: "push.example.test", port: 443,
            protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: InertChallengeSender())
        let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
        operation.urlSession(dummy, task: dummy.dataTask(with: request(endpoint())), didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
        }
        operation.cancel()
        dummy.invalidateAndCancel()
    }

    func testLateResponseDataAndRepeatedCompletionCannotRestoreCancelledOperation() async {
        let url = endpoint(), operation = operation(endpoint())
        operation.cancel()
        let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
        let dummyTask = dummy.dataTask(with: request(url))
        operation.urlSession(dummy, dataTask: dummyTask, didReceive: response(url)) { XCTAssertEqual($0, .cancel) }
        operation.urlSession(dummy, dataTask: dummyTask, didReceive: Data("late private body".utf8))
        operation.urlSession(dummy, task: dummyTask, didCompleteWithError: nil)
        operation.urlSession(dummy, task: dummyTask, didCompleteWithError: URLError(.networkConnectionLost))
        await assertCancelled { _ = try await operation.value() }
        dummy.invalidateAndCancel()
    }

    func testCompletionWithoutResponseAndDataBeforeResponseCannotSucceed() async {
        for earlyData in [false, true] {
            let url = endpoint(), operation = operation(endpoint())
            let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
            let dummyTask = dummy.dataTask(with: request(url))
            if earlyData { operation.urlSession(dummy, dataTask: dummyTask, didReceive: Data("{}".utf8)) }
            operation.urlSession(dummy, task: dummyTask, didCompleteWithError: nil)
            await assertInvalid { _ = try await operation.value() }
            dummy.invalidateAndCancel()
        }
    }

    func testSecondResponseCannotReplaceTheOriginalReceipt() async {
        let ownedURL = endpoint(), ownedOperation = self.operation(ownedURL)
        let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [RegistrationProtocolStub.self]))
        let dummyTask = dummy.dataTask(with: request(ownedURL))
        ownedOperation.urlSession(dummy, dataTask: dummyTask, didReceive: response(ownedURL)) { XCTAssertEqual($0, .allow) }
        ownedOperation.urlSession(dummy, dataTask: dummyTask, didReceive: response(ownedURL)) { XCTAssertEqual($0, .cancel) }
        ownedOperation.urlSession(dummy, task: dummyTask, didCompleteWithError: nil)
        await assertInvalid { _ = try await ownedOperation.value() }
        dummy.invalidateAndCancel()
    }

    func testRealExecutorFeedsTransportReceiptAndKeepsPolicyFailureNonRetryable() async throws {
        let registerURL = endpoint(), confirmURL = endpoint(), executor = try executor([registerURL, confirmURL])
        let installation = "a1234567-1234-4123-8123-123456789abc"
        let call = PushRegistrationCall.register(.init(installationId: installation, key: String(repeating: "k", count: 48),
            clientRevision: 3, permission: false, preferences: .init(articles: .off, categoryIds: [], podcasts: false), token: nil))
        let ticket = PushRegistrationTicket(generation: UUID(), context: .guest(epoch: UUID()), installationId: installation, clientRevision: 3)
        let body = try JSONSerialization.data(withJSONObject: ["status": "disabled", "installationId": installation,
                                                               "clientRevision": 3, "revision": 5])
        RegistrationProtocolStub.register(registerURL) { stub in
            stub.respond(self.response(registerURL, headers: ["Content-Type": "application/json"]))
            stub.chunk(body); stub.complete()
        }
        let transport = try await PushRegistrationHTTPTransport(registerURL: registerURL, confirmURL: confirmURL,
            credentials: { _ in .init(appCheckToken: "inert.app.check", idToken: nil, ownerUID: nil) },
            isCurrent: { _ in true }, perform: executor.perform)
        let receipt = try await transport.send(call, ticket: ticket)
        XCTAssertEqual(receipt.status, .disabled)
        RegistrationProtocolStub.register(registerURL) { stub in
            stub.respond(self.response(registerURL)); stub.chunk(Data(repeating: 1, count: 16_385)); stub.complete()
        }
        await assertInvalid { _ = try await transport.send(call, ticket: ticket) }
    }
}

private final class RegistrationProtocolStub: URLProtocol {
    private struct Handler { let start: (RegistrationProtocolStub) -> Void; let stop: (() -> Void)? }
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    private var stopped: (() -> Void)?

    static func register(_ url: URL, stopped: (() -> Void)? = nil, start: @escaping (RegistrationProtocolStub) -> Void) {
        lock.lock(); defer { lock.unlock() }
        handlers[url.absoluteString] = .init(start: start, stop: stopped)
    }
    static func clear() { lock.lock(); handlers.removeAll(); lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = request.url.flatMap { Self.handlers[$0.absoluteString] }
        stopped = handler?.stop
        Self.lock.unlock()
        guard let handler else { fail(URLError(.unsupportedURL)); return }
        handler.start(self)
    }
    override func stopLoading() {
        Self.lock.lock()
        let stopped = self.stopped
        self.stopped = nil
        Self.lock.unlock()
        stopped?()
    }
    func respond(_ response: URLResponse) { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
    func chunk(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func complete() { client?.urlProtocolDidFinishLoading(self) }
    func fail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}

private final class InertChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) { }
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) { }
    func cancel(_ challenge: URLAuthenticationChallenge) { }
}
