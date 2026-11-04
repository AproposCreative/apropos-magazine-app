import Foundation
import XCTest
@testable import Apropos

final class PodcastAudioDownloadTransportTests: XCTestCase {
    private struct Fixture {
        let response: URLResponse?
        let chunks: [Data]
        var error: Error? = nil
        var hold = false
    }
    private final class Fixtures: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URL: Fixture] = [:]
        private var started: [URL: Int] = [:]
        private var stopped: [URL: Int] = [:]
        private var requests: [URL: URLRequest] = [:]
        func put(_ value: Fixture, at url: URL) { lock.withLock { values[url] = value } }
        func take(_ request: URLRequest) -> Fixture? {
            guard let url = request.url else { return nil }
            return lock.withLock { started[url, default: 0] += 1;requests[url] = request;return values[url] }
        }
        func request(_ url: URL) -> URLRequest? { lock.withLock { requests[url] } }
        func stop(_ url: URL) { lock.withLock { stopped[url, default: 0] += 1 } }
        func startCount(_ url: URL) -> Int { lock.withLock { started[url, default: 0] } }
        func stopCount(_ url: URL) -> Int { lock.withLock { stopped[url, default: 0] } }
        func remove(_ url: URL) { lock.withLock { values.removeValue(forKey: url);started.removeValue(forKey: url);stopped.removeValue(forKey: url);requests.removeValue(forKey: url) } }
    }
    private final class InterceptAllProtocol: URLProtocol {
        static let fixtures = Fixtures()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let fixture = Self.fixtures.take(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable));return
            }
            if let response = fixture.response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            for chunk in fixture.chunks { client?.urlProtocol(self, didLoad: chunk) }
            if fixture.hold { return }
            if let error = fixture.error { client?.urlProtocol(self, didFailWithError: error) }
            else { client?.urlProtocolDidFinishLoading(self) }
        }
        override func stopLoading() { if let url = request.url { Self.fixtures.stop(url) } }
    }
    private func url() -> URL { URL(string: "https://audio.example.test/\(UUID().uuidString).m4a")! }
    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("PodcastAudioTransportTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    private func response(_ url: URL, status: Int = 200, headers: [String: String] = ["Content-Type": "audio/mp4"]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
    private func operation(_ url: URL, maximum: Int64 = 8, directory: URL) -> PodcastAudioDownloadTransport.RequestOperation {
        PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: maximum,
            protocolClasses: [InterceptAllProtocol.self], temporaryDirectory: directory)
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Intercepted local operation did not settle", file: file, line: line)
    }
    private func assertInvalid(_ url: URL, fixture: Fixture, maximum: Int64 = 8,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let root = try directory();defer { try? FileManager.default.removeItem(at: root);InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(fixture, at: url)
        do { _ = try await operation(url, maximum: maximum, directory: root).value();XCTFail("Invalid transport succeeded", file: file, line: line) }
        catch { XCTAssertEqual(error as? PodcastAudioDownloadTransport.Failure, .invalidResponse, file: file, line: line) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], file: file, line: line)
    }

    func testInitializationStartsNoSessionOrTemporaryFileAndUnknownRequestsAreIntercepted() async throws {
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root) }
        let value = operation(url, directory: root)
        XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        do { _ = try await value.value();XCTFail("Unknown local fixture should fail") } catch {}
        XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        InterceptAllProtocol.fixtures.remove(url)
    }
    func testChunkedUnknownLengthStreamsExactlyWithinCapAndReturnsCallerOwnedFile() async throws {
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root);InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url), chunks: [Data([1, 2]), Data([3, 4, 5]), Data([6, 7, 8])]), at: url)
        let output = try await operation(url, directory: root).value()
        XCTAssertEqual(output.response.url, url)
        XCTAssertEqual(try Data(contentsOf: output.temporaryURL), Data([1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertTrue(output.temporaryURL.path.hasPrefix(root.path + "/"))
    }
    func testDeclaredExactLengthSucceeds() async throws {
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root);InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url, headers: ["Content-Type": "audio/mpeg", "Content-Length": "4"]), chunks: [Data([1]), Data([2, 3, 4])]), at: url)
        let value = operation(url, directory: root)
        let output = try await value.value()
        value.cancel()
        do { _ = try await value.value();XCTFail("One operation must not be reused") }
        catch { XCTAssertEqual(error as? PodcastAudioDownloadTransport.Failure, .invalidResponse) }
        XCTAssertEqual(try Data(contentsOf: output.temporaryURL), Data([1, 2, 3, 4]))
        let request = try XCTUnwrap(InterceptAllProtocol.fixtures.request(url))
        XCTAssertEqual(request.httpMethod, "GET");XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"));XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies);XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testDeclaredOversizeRejectsBeforeBodyAndRemovesFile() async throws {
        for length in ["9", "-1", "bad", "9223372036854775808"] {
            let url = url()
            try await assertInvalid(url, fixture: .init(response: response(url, headers: ["Content-Type": "audio/mp4", "Content-Length": length]), chunks: []))
        }
    }
    func testUnknownLengthOverflowAndSingleOversizedChunkCannotCommit() async throws {
        for chunks in [[Data(repeating: 1, count: 5), Data(repeating: 2, count: 4)], [Data(repeating: 1, count: 9)]] {
            let url = url();try await assertInvalid(url, fixture: .init(response: response(url), chunks: chunks))
        }
    }
    func testShortDeclaredLengthAndExtraBytesReject() async throws {
        for body in [Data([1, 2]), Data([1, 2, 3, 4, 5])] {
            let url = url();try await assertInvalid(url, fixture: .init(response: response(url, headers: ["Content-Type": "audio/mp4", "Content-Length": "4"]), chunks: [body]))
        }
    }
    func testPartialNonSuccessAndUnexpectedMimeOrEncodingNeverProduceAudioFile() async throws {
        for (status, headers) in [(206, ["Content-Type": "audio/mp4"]), (503, ["Content-Type": "audio/mp4"]),
            (200, ["Content-Type": "text/html"]), (200, ["Content-Type": "audio/mp4", "Content-Encoding": "gzip"]),
            (200, ["Content-Type": "audio/mp4", "Content-Range": "bytes 0-1/100"])] {
            let url = url();try await assertInvalid(url, fixture: .init(response: response(url, status: status, headers: headers), chunks: [Data([1, 2])]))
        }
    }
    func testEmptyNonHTTPAndResponseURLMismatchFailClosed() async throws {
        let empty = url();try await assertInvalid(empty, fixture: .init(response: response(empty), chunks: []))
        let nonHTTP = url();try await assertInvalid(nonHTTP, fixture: .init(response: URLResponse(url: nonHTTP, mimeType: "audio/mp4", expectedContentLength: 2, textEncodingName: nil), chunks: [Data([1, 2])]))
        let mismatch = url();try await assertInvalid(mismatch, fixture: .init(response: response(url()), chunks: [Data([1, 2])]))
    }
    func testCancellationAfterPartialBodyRemovesAllTemporaryBytes() async throws {
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root);InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url), chunks: [Data([1, 2])], hold: true), at: url)
        let value = operation(url, directory: root)
        let task = Task { try await value.value() }
        await wait { InterceptAllProtocol.fixtures.startCount(url) == 1 }
        task.cancel()
        do { _ = try await task.value;XCTFail("Canceled operation succeeded") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await wait { InterceptAllProtocol.fixtures.stopCount(url) == 1 }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testCancelBeforeStartAndInvalidConfigurationOpenNoRequestOrFile() async throws {
        let root = try directory();defer { try? FileManager.default.removeItem(at: root) }
        let canceledURL = url(), canceled = operation(canceledURL, directory: root)
        canceled.cancel()
        do { _ = try await canceled.value();XCTFail("Pre-canceled operation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(canceledURL), 0)
        for maximum in [Int64(0), -1, PodcastAudioDownloadTransport.hardMaximumBytes + 1] {
            let url = url()
            do { _ = try await operation(url, maximum: maximum, directory: root).value();XCTFail("Invalid cap succeeded") }
            catch { XCTAssertEqual(error as? PodcastAudioDownloadTransport.Failure, .invalidResponse) }
            XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 0)
        }
        for raw in ["http://audio.example.test/a.m4a", "https://user:password@audio.example.test/a.m4a", "https://audio.example.test/a.m3u8"] {
            let url = URL(string: raw)!
            do { _ = try await operation(url, directory: root).value();XCTFail("Invalid source succeeded") }
            catch { XCTAssertEqual(error as? PodcastAudioDownloadTransport.Failure, .invalidResponse) }
            XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 0)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testDeadlineRetiresActualSessionAndRemovesPartialFile() async throws {
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root);InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url), chunks: [Data([1, 2])], hold: true), at: url)
        let samples = ProgressSamples()
        let value = PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: 8,
            protocolClasses: [InterceptAllProtocol.self], temporaryDirectory: root,
            onProgress: { received, total in samples.record(received, total) })
        let task = Task { try await value.value() }
        // Expire a partial transfer, rather than racing URLProtocol.startLoading.
        await wait { samples.snapshot.last?.received == 2 }
        XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 1)
        XCTAssertEqual(samples.snapshot.last?.received, 2)
        let partialFile = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.first
        let partialBytes = partialFile.flatMap { try? Data(contentsOf: $0) }
        XCTAssertEqual(partialBytes, Data([1, 2]))
        value.deadlineExpired()
        do { _ = try await task.value;XCTFail("Expired operation succeeded") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(InterceptAllProtocol.fixtures.stopCount(url), 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testEphemeralConfigurationAndForeignRedirectReplyCannotStartOrTransferAnything() async throws {
        let configuration = PodcastAudioDownloadTransport.configuration(protocolClasses: [InterceptAllProtocol.self])
        XCTAssertNil(configuration.urlCache);XCTAssertNil(configuration.urlCredentialStorage);XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies);XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 180)
        let url = url(), root = try directory();defer { try? FileManager.default.removeItem(at: root) }
        let value = operation(url, directory: root)
        let foreign = URLSession(configuration: configuration);defer { foreign.invalidateAndCancel() }
        let foreignTask = foreign.dataTask(with: url)
        let done = expectation(description: "Foreign redirect denied exactly once")
        let replies = ReplyCounter()
        value.urlSession(foreign, task: foreignTask, willPerformHTTPRedirection: response(url, status: 302),
            newRequest: URLRequest(url: URL(string: "http://audio.example.test/downgrade.m4a")!)) { request in
                replies.received(request);done.fulfill()
            }
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(replies.count, 1);XCTAssertNil(replies.request)
        XCTAssertEqual(InterceptAllProtocol.fixtures.startCount(url), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    private final class ReplyCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URLRequest?] = []
        func received(_ request: URLRequest?) { lock.withLock { values.append(request) } }
        var count: Int { lock.withLock { values.count } }
        var request: URLRequest? { lock.withLock { values.first ?? nil } }
    }

    private final class ProgressSamples: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(received: Int64, total: Int64?, persisted: Int64?)] = []
        func record(_ received: Int64, _ total: Int64?, persisted: Int64? = nil) { lock.withLock { values.append((received, total, persisted)) } }
        var snapshot: [(received: Int64, total: Int64?, persisted: Int64?)] { lock.withLock { values } }
    }
    func testKnownLengthReportsOnlyActualWrittenBytesAndRetainsItsDeclaredTotal() async throws {
        let url = url(), root = try directory(), samples = ProgressSamples()
        defer { try? FileManager.default.removeItem(at: root); InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url, headers: ["Content-Type": "audio/mp4", "Content-Length": "4"]),
            chunks: [Data([1]), Data([2]), Data([3, 4])]), at: url)
        let request = PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: 8, protocolClasses: [InterceptAllProtocol.self],
            temporaryDirectory: root, onProgress: { received, total in
                let file = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.first
                let attributes = file.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
                samples.record(received, total, persisted: (attributes?[.size] as? NSNumber)?.int64Value)
            })
        let output = try await request.value(), values = samples.snapshot
        XCTAssertEqual(values.first?.received, 0); XCTAssertEqual(values.last?.received, 4)
        XCTAssertTrue(values.allSatisfy { $0.total == 4 && (0...4).contains($0.received) })
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { pair in pair.0.received <= pair.1.received })
        XCTAssertTrue(values.allSatisfy { $0.persisted == $0.received }, "Callbacks follow the actual successful staging-file write")
        XCTAssertEqual(try Data(contentsOf: output.temporaryURL).count, Int(values.last!.received))
    }
    func testUnknownLengthReportsBytesWithNoInventedTotal() async throws {
        let url = url(), root = try directory(), samples = ProgressSamples()
        defer { try? FileManager.default.removeItem(at: root); InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url), chunks: [Data([1, 2]), Data([3, 4])]), at: url)
        let request = PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: 8, protocolClasses: [InterceptAllProtocol.self],
            temporaryDirectory: root, onProgress: { received, total in samples.record(received, total) })
        _ = try await request.value()
        XCTAssertEqual(samples.snapshot.last?.received, 4); XCTAssertTrue(samples.snapshot.allSatisfy { $0.total == nil })
    }
    func testPartialCanceledTransferNeverManufacturesCompletionProgress() async throws {
        let url = url(), root = try directory(), samples = ProgressSamples()
        defer { try? FileManager.default.removeItem(at: root); InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url, headers: ["Content-Type": "audio/mp4", "Content-Length": "8"]),
            chunks: [Data([1, 2])], hold: true), at: url)
        let request = PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: 8, protocolClasses: [InterceptAllProtocol.self],
            temporaryDirectory: root, onProgress: { received, total in samples.record(received, total) })
        let task = Task { try await request.value() }
        await wait { samples.snapshot.last?.received == 2 };task.cancel()
        do { _ = try await task.value;XCTFail("Cancellation succeeded") } catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(samples.snapshot.last?.received, 2);XCTAssertTrue(samples.snapshot.allSatisfy { $0.total == 8 })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testRejectedResponseCannotPublishDownloadProgress() async throws {
        let url = url(), root = try directory(), samples = ProgressSamples()
        defer { try? FileManager.default.removeItem(at: root); InterceptAllProtocol.fixtures.remove(url) }
        InterceptAllProtocol.fixtures.put(.init(response: response(url, status: 503), chunks: [Data([1, 2])]), at: url)
        let request = PodcastAudioDownloadTransport.RequestOperation(url: url, maximumBytes: 8, protocolClasses: [InterceptAllProtocol.self],
            temporaryDirectory: root, onProgress: { received, total in samples.record(received, total) })
        do { _ = try await request.value();XCTFail("Rejected response succeeded") } catch { }
        XCTAssertTrue(samples.snapshot.isEmpty)
    }

}
