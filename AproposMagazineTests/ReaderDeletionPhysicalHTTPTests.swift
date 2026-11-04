import Foundation
import XCTest
@testable import Apropos

/// Drive the actual delegate with a local lifecycle that deliberately withholds
/// physical completion. URLProtocol cancellation alone cannot prove this: the
/// platform can deliver didComplete immediately when its protocol is cancelled.
@MainActor
final class ReaderDeletionPhysicalHTTPTests: XCTestCase {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0, cancels = 0
        let started = XCTestExpectation(description: "Physical request resumed")
        func start() { lock.lock(); starts += 1; lock.unlock(); started.fulfill() }
        func cancel() { lock.lock(); cancels += 1; lock.unlock() }
        var counts: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (starts, cancels) }
    }
    private final class CompletionProbe {
        var didReturn = false
        let signal = XCTestExpectation(description: "Original await returned")
        func finish() { didReturn = true; signal.fulfill() }
    }
    private final class Harness {
        let state: State
        let url: URL
        let operation: PushRegistrationURLSessionExecutor.RequestOperation
        let dummy: URLSession
        let dummyTask: URLSessionDataTask
        init(physical: Bool = true) {
            let state = State(), url = URL(string: "https://reader.example.invalid/delete")!
            self.state = state; self.url = url
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
            operation = .init(request: request, awaitPhysicalCompletion: physical,
                lifecycle: .init(resume: { state.start() }, cancel: { state.cancel() }))
            let dummy = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: [DeletionProtocolStub.self]))
            self.dummy = dummy
            dummyTask = dummy.dataTask(with: request) // Never resumed. Only the delegate entry points below are exercised.
        }
        deinit { dummy.invalidateAndCancel() }
        func response(headers: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        func finish(_ error: Error? = nil) { operation.urlSession(dummy, task: dummyTask, didCompleteWithError: error) }
        func receive(_ response: URLResponse, _ callback: @escaping (URLSession.ResponseDisposition) -> Void = { _ in }) {
            operation.urlSession(dummy, dataTask: dummyTask, didReceive: response, completionHandler: callback)
        }
        func data(_ data: Data) { operation.urlSession(dummy, dataTask: dummyTask, didReceive: data) }
    }
    private func start(_ h: Harness, returned: CompletionProbe) async -> Task<(Data, HTTPURLResponse), Error> {
        let operation = h.operation
        let task = Task { defer { returned.finish() }; return try await operation.value() }
        let started = await XCTWaiter.fulfillment(of: [h.state.started], timeout: 3); XCTAssertEqual(started, .completed)
        return task
    }
    private func held(_ returned: CompletionProbe) async {
        XCTAssertFalse(returned.didReturn)
        // Leave the suspended task runnable for the same bounded observation
        // interval. Mutating an already-waited XCTest expectation is invalid.
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(returned.didReturn, "Logical denial must not finish a physically occupied operation")
    }
    private func cancelled(_ task: Task<(Data, HTTPURLResponse), Error>) async {
        do { _ = try await task.value; XCTFail("Expected original cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(type(of: error))") }
    }
    private func invalid(_ task: Task<(Data, HTTPURLResponse), Error>) async {
        do { _ = try await task.value; XCTFail("Expected policy rejection") }
        catch let error as PushRegistrationFailure { XCTAssertEqual(error, .invalidResponse) }
        catch { XCTFail("Expected policy error, got \(type(of: error))") }
    }

    func testOptInCancellationBeforeStartHasNoPhysicalReservation() async {
        let h = Harness(); h.operation.cancel()
        let task = Task { try await h.operation.value() }; await cancelled(task)
        XCTAssertEqual(h.state.counts.0, 0); XCTAssertEqual(h.state.counts.1, 0)
    }
    func testOptInCancellationRetainsAwaitUntilActualCompletionAndIgnoresLateBody() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned); task.cancel()
        XCTAssertEqual(h.state.counts.1, 1)
        h.receive(h.response()) { XCTAssertEqual($0, .cancel) }
        h.data(Data(repeating: 1, count: 65_536)); await held(returned)
        h.finish(); await cancelled(task)
        h.finish(URLError(.networkConnectionLost)); h.operation.deadlineExpired()
        XCTAssertEqual(h.state.counts.1, 1)
    }
    func testOptInDeadlineRemainsOccupiedAndFirstCauseWinsLaterCancellationAndNetworkError() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned); h.operation.deadlineExpired(); h.operation.cancel()
        XCTAssertEqual(h.state.counts.1, 1); await held(returned)
        h.finish(URLError(.cancelled))
        do { _ = try await task.value; XCTFail("Expected original deadline") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        catch { XCTFail("Unexpected error type") }
    }
    func testOptInRedirectRejectionWaitsForPhysicalCompletionAndNeverForwards() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned)
        h.operation.urlSession(h.dummy, task: h.dummyTask, willPerformHTTPRedirection: h.response(),
            newRequest: URLRequest(url: URL(string: "https://foreign.example.invalid/steal")!)) { XCTAssertNil($0) }
        XCTAssertEqual(h.state.counts.1, 1); await held(returned)
        h.finish(URLError(.cancelled)); await invalid(task)
    }
    func testOptInResponsePolicyCauseIsReservedBeforeReentrantCompletionHandler() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned)
        h.receive(h.response(headers: ["Content-Length": "16385"])) { disposition in
            XCTAssertEqual(disposition, .cancel); h.finish(URLError(.cancelled))
        }
        let completion = await XCTWaiter.fulfillment(of: [returned.signal], timeout: 3)
        XCTAssertEqual(completion, .completed)
        await invalid(task); XCTAssertEqual(h.state.counts.1, 1)
    }
    func testOptInInvalidHeadersAndBodyOverflowDoNotReleasePhysicalSlot() async {
        for header in [true, false] {
            let h = Harness(), returned = CompletionProbe()
            let task = await start(h, returned: returned)
            if header { h.receive(h.response(headers: ["Content-Length": "1, 1"])) { XCTAssertEqual($0, .cancel) } }
            else {
                h.receive(h.response()) { XCTAssertEqual($0, .allow) }
                h.data(Data(repeating: 1, count: 16_384)); h.data(Data([2]))
            }
            h.data(Data(repeating: 3, count: 65_536)); await held(returned)
            h.finish(); await invalid(task); XCTAssertEqual(h.state.counts.1, 1)
        }
    }
    func testOptInCredentialChallengeRejectionWaitsForPhysicalCompletion() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned)
        let challenge = URLAuthenticationChallenge(protectionSpace: .init(host: "reader.example.invalid", port: 443,
            protocol: "https", realm: "private", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: DeletionChallengeSender())
        h.operation.urlSession(h.dummy, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge); XCTAssertNil(credential)
        }
        await held(returned); h.finish(); await invalid(task)
    }
    func testOptInSessionInvalidationIsPhysicalAcknowledgementAndKeepsOriginalCause() async {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned); h.operation.cancel(); await held(returned)
        h.operation.urlSession(h.dummy, didBecomeInvalidWithError: URLError(.networkConnectionLost))
        await cancelled(task); h.finish(); XCTAssertEqual(h.state.counts.1, 1)
    }
    func testOptInNormalCompletionReturnsOnlyTheBoundedOriginalBody() async throws {
        let h = Harness(), returned = CompletionProbe()
        let task = await start(h, returned: returned)
        h.receive(h.response(headers: ["Content-Length": "16384"])) { XCTAssertEqual($0, .allow) }
        h.data(Data(repeating: 1, count: 8192)); h.data(Data(repeating: 2, count: 8192)); await held(returned)
        h.finish(); let result = try await task.value
        XCTAssertEqual(result.0.count, 16384); XCTAssertEqual(result.0.first, 1); XCTAssertEqual(result.0.last, 2)
        XCTAssertEqual(result.1.url, h.url); XCTAssertEqual(h.state.counts.1, 0)
    }
    func testExistingDefaultDeadlineStillCompletesBeforePhysicalCallback() async {
        let h = Harness(physical: false), returned = CompletionProbe()
        let task = await start(h, returned: returned); h.operation.deadlineExpired()
        let completion = await XCTWaiter.fulfillment(of: [returned.signal], timeout: 3)
        XCTAssertEqual(completion, .completed)
        do { _ = try await task.value; XCTFail("Expected deadline") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        catch { XCTFail("Unexpected error") }
        XCTAssertEqual(h.state.counts.1, 1); h.finish()
    }
    func testActualOptInExecutorUsesEphemeralSessionWithLocalInterceptAndOriginalHeaders() async throws {
        let url = URL(string: "https://reader.example.invalid/delete")!
        let executor = try PushRegistrationURLSessionExecutor(allowedURLs: [url], protocolClasses: [DeletionProtocolStub.self])
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue("Bearer local.id.token", forHTTPHeaderField: "Authorization")
        request.setValue("limited.use.token", forHTTPHeaderField: "X-Firebase-AppCheck")
        let result = try await executor.performAwaitingPhysicalCompletion(request)
        XCTAssertEqual(result.0, Data("local".utf8)); XCTAssertEqual(result.1.url, url)
    }
}

private final class DeletionProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.absoluteString == "https://reader.example.invalid/delete" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local.id.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "limited.use.token")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("local".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class DeletionChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
