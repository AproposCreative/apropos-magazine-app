import Foundation
import XCTest
@testable import Apropos

final class PodcastAudioCacheProgressTests: XCTestCase {
    private final class Transport: @unchecked Sendable {
        struct Job {
            let url: URL
            let progress: PodcastAudioDownloadTransport.Progress
            let completion: CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>
        }
        private let lock = NSLock()
        private var jobs: [Job] = []
        var count: Int { lock.withLock { jobs.count } }
        func download(_ url: URL, progress: @escaping PodcastAudioDownloadTransport.Progress) async throws -> PodcastAudioCache.DownloadArtifact {
            try await withCheckedThrowingContinuation { completion in lock.withLock { jobs.append(Job(url: url, progress: progress, completion: completion)) } }
        }
        func report(_ index: Int, _ received: Int64, _ total: Int64?) { lock.withLock { jobs[index].progress }(received, total) }
        func resolve(_ index: Int) throws {
            let job = lock.withLock { jobs[index] }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let bytes = Data([1, 2, 3, 4, 5, 6, 7, 8]);try bytes.write(to: file)
            let response = HTTPURLResponse(url: job.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "audio/mp4", "Content-Length": "8"])!
            job.completion.resume(returning: .init(temporaryURL: file, response: response))
        }
        func fail(_ index: Int) { lock.withLock { jobs[index].completion }.resume(throwing: URLError(.networkConnectionLost)) }
    }
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock();private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }
    private struct Fixture {
        let directory: URL
        let transport: Transport
        let changes: Counter
        let cache: PodcastAudioCache
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let transport = Transport(), changes = Counter();self.transport = transport;self.changes = changes
            cache = PodcastAudioCache(cacheDirectory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!, maximumConcurrentDownloads: 1,
                download: { _ in throw URLError(.unsupportedURL) }, progressDownload: { url, progress in try await transport.download(url, progress: progress) },
                onIndexChange: { changes.increment() })
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    private func asset(_ revision: String = "r1", name: String = "a") -> PodcastAudioAsset {
        PodcastAudioAsset(episodeID: "episode-\(name)", canonicalArticleID: "article-\(name)", kind: .human,
            sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/\(name).m4a")!)!
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Controlled audio work did not settle", file: file, line: line)
        throw URLError(.timedOut)
    }
    func testKnownLengthProgressUsesActualBytesAndCannotBecomeReadyBeforeValidatedCommit() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset(), lease = UUID()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: a)
        try await wait { f.transport.count == 1 }
        XCTAssertNil(f.cache.downloadProgress(for: a))
        f.transport.report(0, 2, 8);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.25)
        f.transport.report(0, 6, 8);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.75)
        f.transport.report(0, 8, 8)
        XCTAssertLessThan(try XCTUnwrap(f.cache.downloadProgress(for: a)), 1)
        XCTAssertFalse(f.cache.isDownloaded(for: a));XCTAssertEqual(f.cache.downloadState(for: a), .downloading)
        try f.transport.resolve(0);try await wait { f.cache.isDownloaded(for: a) }
        XCTAssertEqual(f.cache.downloadProgress(for: a), 1);XCTAssertEqual(f.cache.downloadState(for: a), .available)
    }
    func testUnknownInvalidRegressingOrChangedTotalCannotInventProgress() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: a);try await wait { f.transport.count == 1 }
        for total in [nil, Int64(0), -1, PodcastAudioReceipt.maximumAudioBytes + 1] { f.transport.report(0, 2, total);XCTAssertNil(f.cache.downloadProgress(for: a)) }
        f.transport.report(0, 4, 8);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.5)
        let invalid: [(Int64, Int64?)] = [(3, 8), (6, 16), (-1, 8), (9, 8), (7, nil)]
        for sample in invalid {
            f.transport.report(0, sample.0, sample.1);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.5)
        }
        f.transport.fail(0);try await wait { f.cache.downloadActivity.active == 0 }
        XCTAssertNil(f.cache.downloadProgress(for: a));XCTAssertEqual(f.cache.downloadState(for: a), .failed)
    }
    func testNotificationsOnlyAdvanceWithIntegerPercentAndQueriesHaveNoEffects() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: a);try await wait { f.transport.count == 1 }
        try await wait { f.changes.count >= 2 }
        let before = f.changes.count
        f.transport.report(0, 100, 1000);XCTAssertEqual(f.changes.count, before + 1)
        for byte in 101...109 { f.transport.report(0, Int64(byte), 1000) }
        for _ in 0..<100 { XCTAssertNotNil(f.cache.downloadProgress(for: a)) }
        XCTAssertEqual(f.changes.count, before + 1)
        f.transport.report(0, 110, 1000);XCTAssertEqual(f.changes.count, before + 2)
        f.transport.fail(0);try await wait { f.cache.downloadActivity.active == 0 }
    }
    func testUnpinHidesProgressButKeepsAnotherOwnersSamePhysicalDownload() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset(), leaseA = UUID(), leaseB = UUID()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseA, asset: a);f.cache.pinAndDownload(pinKey: "favorites-v1:B", leaseID: leaseB, asset: a)
        try await wait { f.transport.count == 1 };f.transport.report(0, 4, 8)
        f.cache.releasePinKeepingBytes(pinKey: "favorites-v1:A", leaseID: leaseA, onlyIfAsset: a);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.5)
        f.cache.releasePinKeepingBytes(pinKey: "favorites-v1:B", leaseID: leaseB, onlyIfAsset: a);XCTAssertNil(f.cache.downloadProgress(for: a))
        f.transport.report(0, 7, 8);XCTAssertNil(f.cache.downloadProgress(for: a));XCTAssertEqual(f.transport.count, 1)
        try f.transport.resolve(0);try await wait { f.cache.isDownloaded(for: a) };XCTAssertNil(f.cache.downloadProgress(for: a))
    }
    func testClearAndOldWorkCannotPublishIntoNewGenerationForSameAsset() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: a);try await wait { f.transport.count == 1 };f.transport.report(0, 4, 8)
        f.cache.removeAllCachedFiles();XCTAssertNil(f.cache.downloadProgress(for: a))
        f.cache.pinAndDownload(pinKey: "favorites-v1:B", leaseID: UUID(), asset: a);f.transport.report(0, 7, 8);XCTAssertNil(f.cache.downloadProgress(for: a))
        try f.transport.resolve(0);try await wait { f.transport.count == 2 }
        f.transport.report(1, 2, 8);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.25)
        f.transport.report(0, 8, 8);XCTAssertEqual(f.cache.downloadProgress(for: a), 0.25)
        try f.transport.resolve(1);try await wait { f.cache.isDownloaded(for: a) };XCTAssertEqual(f.cache.downloadProgress(for: a), 1)
    }
    func testRevisionReplacementAndInvalidationNeverExposeOldAssetProgress() async throws {
        let f = try Fixture();defer { f.cleanup() };let old = asset(), current = asset("r2"), lease = UUID()
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: old);try await wait { f.transport.count == 1 };f.transport.report(0, 4, 8)
        f.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: current);XCTAssertNil(f.cache.downloadProgress(for: old));XCTAssertNil(f.cache.downloadProgress(for: current))
        try f.transport.resolve(0);try await wait { f.transport.count == 2 };f.transport.report(1, 4, 8);XCTAssertEqual(f.cache.downloadProgress(for: current), 0.5)
        f.cache.invalidate([current]);XCTAssertNil(f.cache.downloadProgress(for: current));f.transport.report(1, 7, 8);XCTAssertNil(f.cache.downloadProgress(for: current))
        try f.transport.resolve(1);try await wait { f.cache.downloadActivity.active == 0 };XCTAssertFalse(f.cache.isDownloaded(for: current))
    }
    func testOrdinaryBackgroundWarmingWithoutPinNeverClaimsSavedDownloadProgress() async throws {
        let f = try Fixture();defer { f.cleanup() };let a = asset()
        f.cache.scheduleBackgroundDownload(for: a);try await wait { f.transport.count == 1 };f.transport.report(0, 4, 8)
        XCTAssertNil(f.cache.downloadProgress(for: a));try f.transport.resolve(0);try await wait { f.cache.isDownloaded(for: a) };XCTAssertNil(f.cache.downloadProgress(for: a))
    }
}
