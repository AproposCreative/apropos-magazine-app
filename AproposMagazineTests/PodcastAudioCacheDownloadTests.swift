import XCTest
@testable import Apropos

final class PodcastAudioCacheDownloadTests: XCTestCase {
    private let a = PodcastAudioAsset(episodeID: "episode-a", canonicalArticleID: "article-a", kind: .human, sourceRevision: "r1", remoteURL: URL(string: "https://audio.example.com/a.m4a")!)!
    private let b = PodcastAudioAsset(episodeID: "episode-b", canonicalArticleID: "article-b", kind: .human, sourceRevision: "r1", remoteURL: URL(string: "https://audio.example.com/b.mp3")!)!
    private let c = PodcastAudioAsset(episodeID: "episode-c", canonicalArticleID: "article-c", kind: .human, sourceRevision: "r1", remoteURL: URL(string: "https://audio.example.com/c.m4a")!)!
    private let leaseA = UUID(), leaseB = UUID()

    func testDownloadsAreBoundedAndWaitingWorkStartsWhenASlotIsReleased() async throws {
        let h = try AudioCacheHarness()
        h.cache.scheduleBackgroundDownload(for: a)
        h.cache.scheduleBackgroundDownload(for: b)
        h.cache.scheduleBackgroundDownload(for: c)
        await h.transport.waitForStarts(2)
        XCTAssertEqual(h.cache.downloadActivity.active, 2)
        XCTAssertLessThanOrEqual(h.cache.downloadActivity.waiting, 1)
        try await h.transport.resolve(0)
        await h.transport.waitForStarts(3)
        XCTAssertEqual(h.cache.downloadActivity.active, 2)
        try await h.transport.resolve(1)
        try await h.transport.resolve(2)
        let events = await h.events.waitForCount(3)
        XCTAssertEqual(events, [.saved, .saved, .saved])
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertTrue(h.cache.isDownloaded(for: c))
    }

    func testSameAudioIsNotDownloadedTwiceWhileActiveOrQueued() async throws {
        let h = try AudioCacheHarness(limit: 1)
        for _ in 0..<3 { h.cache.scheduleBackgroundDownload(for: a) }
        for _ in 0..<3 { h.cache.scheduleBackgroundDownload(for: b) }
        await h.transport.waitForStarts(1)
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        await h.transport.waitForStarts(2)
        try await h.transport.resolve(1)
        _ = await h.events.waitForCount(2)
        let calls = await h.transport.startedURLs
        XCTAssertEqual(calls, [a.remoteURL, b.remoteURL])
        h.cache.scheduleBackgroundDownload(for: a)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.resolvePlaybackURL(for: a).cacheResult, .hit)
    }

    func testClearCancelsActiveWorkDropsWaitingWorkAndRejectsLateFiles() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseA, asset: a)
        h.cache.scheduleBackgroundDownload(for: b)
        h.cache.scheduleBackgroundDownload(for: c)
        await h.transport.waitForStarts(2)
        h.cache.removeAllCachedFiles()
        XCTAssertEqual(h.cache.downloadActivity.active, 2, "Cancellation-ignoring transports still occupy their actual slots")
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        // The fixture deliberately ignores cancellation until manually resumed.
        try await h.transport.resolve(0)
        try await h.transport.resolve(1)
        let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.discarded, .discarded])
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        XCTAssertFalse(h.cache.isPinned(articleId: "favorites-v1:A"))
        XCTAssertEqual(h.cache.totalCacheSizeBytes(), 0)
        XCTAssertNil(h.defaults.object(forKey: "podcast_audio_cache_access_v1"))
        let cancelled = await h.transport.cancelled
        XCTAssertEqual(Set(cancelled), [0, 1])
        let calls = await h.transport.startedURLs
        XCTAssertEqual(calls.count, 2)
    }

    func testOldCompletionCannotDeleteOrReplaceNewWorkForTheSameURL() async throws {
        let h = try AudioCacheHarness(limit: 1)
        h.cache.scheduleBackgroundDownload(for: a)
        await h.transport.waitForStarts(1)
        h.cache.removeAllCachedFiles()
        h.cache.scheduleBackgroundDownload(for: a)
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        _ = await h.events.waitForCount(1)
        await h.transport.waitForStarts(2)
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        try await h.transport.resolve(1)
        let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.discarded, .saved])
        XCTAssertTrue(h.cache.isDownloaded(for: a))
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        let temporaryFiles = await h.transport.temporaryFiles
        XCTAssertTrue(temporaryFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testUnpinningOneArticlePreservesAudioNeededByAnotherArticle() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseA, asset: a)
        h.cache.pinAndDownload(pinKey: "favorites-v1:B", leaseID: leaseB, asset: a)
        await h.transport.waitForStarts(1)
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:A", leaseID: leaseA, onlyIfAsset: a)
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        XCTAssertTrue(h.cache.isPinned(articleId: "favorites-v1:B"))
        try await h.transport.resolve(0)
        _ = await h.events.waitForCount(1)
        XCTAssertFalse(h.cache.isDownloaded(forArticleId: "favorites-v1:A"))
        XCTAssertTrue(h.cache.isDownloaded(forArticleId: "favorites-v1:B"))
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:B", leaseID: leaseB, onlyIfAsset: a)
        XCTAssertTrue(h.cache.isDownloaded(for: a))
        XCTAssertEqual(h.cache.totalCacheSizeBytes(), 8)
    }

    func testUnpinCancelsWorkAndLateDownloadDoesNotRestoreRemovedAudio() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseA, asset: a)
        await h.transport.waitForStarts(1)
        h.cache.invalidate([a])
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        let events = await h.events.waitForCount(1)
        XCTAssertEqual(events, [.discarded])
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        XCTAssertFalse(h.cache.isPinned(articleId: "favorites-v1:A"))
        let cancelled = await h.transport.cancelled
        XCTAssertEqual(cancelled, [0])
    }

    func testHTTPErrorEmptyFileHTMLAndInsecureRedirectAreNotSaved() async throws {
        let h = try AudioCacheHarness()
        let cases: [(Int, Int, String, URL?)] = [
            (500, 8, "audio/mp4", nil), (200, 0, "audio/mp4", nil),
            (200, 8, "text/html", nil), (200, 8, "audio/mp4", URL(string: "http://audio.example.com/a.m4a"))
        ]
        for (index, sample) in cases.enumerated() {
            h.cache.scheduleBackgroundDownload(for: a)
            await h.transport.waitForStarts(index + 1)
            try await h.transport.resolve(index, status: sample.0, bytes: sample.1, mime: sample.2, responseURL: sample.3)
            let events = await h.events.waitForCount(index + 1)
            XCTAssertEqual(events.last, .failed)
            XCTAssertFalse(h.cache.isDownloaded(for: a))
        }
        let files = await h.transport.temporaryFiles
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testTransportFailureReleasesSlotForNextRequest() async throws {
        let h = try AudioCacheHarness(limit: 1)
        h.cache.scheduleBackgroundDownload(for: a)
        h.cache.scheduleBackgroundDownload(for: b)
        await h.transport.waitForStarts(1)
        await h.transport.fail(0)
        await h.transport.waitForStarts(2)
        try await h.transport.resolve(1)
        let events = await h.events.waitForCount(2)
        XCTAssertEqual(events.filter { $0 == .failed }.count, 1)
        XCTAssertEqual(events.filter { $0 == .saved }.count, 1)
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        XCTAssertTrue(h.cache.isDownloaded(for: b))
    }

    func testLegacyURLOnlyCallsNeverEnterQueueOrAdoptBytes() throws {
        let h = try AudioCacheHarness()
        for raw in ["https://audio.example.com/a.m4a", "https://audio.example.com/playlist.m3u8", "http://audio.example.com/audio.mp3", "https://accounts.google.com/audio.mp3"] {
            let url = try XCTUnwrap(URL(string: raw))
            h.cache.pinAndDownload(articleId: raw, remoteURL: url)
            h.cache.scheduleBackgroundDownload(from: url)
            XCTAssertFalse(h.cache.isPinned(articleId: raw))
            XCTAssertFalse(h.cache.isDownloaded(for: url))
            XCTAssertEqual(h.cache.resolvePlaybackURL(for: url).cacheResult, .miss)
        }
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
    }
}

private final class AudioCacheHarness {
    let root: URL
    let defaults: UserDefaults
    let cache: PodcastAudioCache
    let transport: AudioDownloadFixture
    let events: AudioDownloadEvents
    private let suite: String
    init(limit: Int = 2) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let suite = "AudioCacheTests-" + UUID().uuidString
        self.suite = suite
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        self.defaults = defaults
        let transport = AudioDownloadFixture(root: root), events = AudioDownloadEvents()
        self.transport = transport
        self.events = events
        cache = PodcastAudioCache(cacheDirectory: root.appendingPathComponent("cache"), defaults: defaults,
                                  maximumConcurrentDownloads: limit,
                                  download: { try await transport.download($0) },
                                  onEvent: { event in Task { await events.record(event) } })
    }
    deinit {
        cache.removeAllCachedFiles()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor AudioDownloadFixture {
    let root: URL
    private(set) var startedURLs: [URL] = []
    private(set) var cancelled: [Int] = []
    private(set) var temporaryFiles: [URL] = []
    private var continuations: [Int: CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(root: URL) { self.root = root }
    func download(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        let index = startedURLs.count
        startedURLs.append(url)
        defer { if Task.isCancelled { cancelled.append(index) } }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            let ready = waiters.filter { $0.0 <= startedURLs.count }
            waiters.removeAll { $0.0 <= startedURLs.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForStarts(_ count: Int) async {
        if startedURLs.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func resolve(_ index: Int, status: Int = 200, bytes: Int = 8, mime: String = "audio/mp4", responseURL: URL? = nil) throws {
        let file = root.appendingPathComponent(UUID().uuidString + ".download")
        try Data(repeating: 1, count: bytes).write(to: file)
        temporaryFiles.append(file)
        let response = try XCTUnwrap(HTTPURLResponse(url: responseURL ?? startedURLs[index], statusCode: status,
                                                   httpVersion: nil, headerFields: ["Content-Type": mime]))
        continuations.removeValue(forKey: index)?.resume(returning: PodcastAudioCache.DownloadArtifact(temporaryURL: file, response: response))
    }
    func fail(_ index: Int) { continuations.removeValue(forKey: index)?.resume(throwing: URLError(.notConnectedToInternet)) }
}

private actor AudioDownloadEvents {
    private var events: [PodcastAudioCache.DownloadEvent] = []
    private var waiters: [(Int, CheckedContinuation<[PodcastAudioCache.DownloadEvent], Never>)] = []
    func record(_ event: PodcastAudioCache.DownloadEvent) {
        events.append(event)
        let ready = waiters.filter { $0.0 <= events.count }
        waiters.removeAll { $0.0 <= events.count }
        ready.forEach { $0.1.resume(returning: events) }
    }
    func waitForCount(_ count: Int) async -> [PodcastAudioCache.DownloadEvent] {
        if events.count >= count { return events }
        return await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

extension PodcastAudioCacheDownloadTests {
    func testRevokedUnpinnedPrefetchDropsWaitingRequestAndRejectsLateCompletion() async throws {
        let h = try AudioCacheHarness(limit: 1)
        h.cache.scheduleBackgroundDownload(for: a)
        h.cache.scheduleBackgroundDownload(for: b)
        await h.transport.waitForStarts(1)
        h.cache.removeUnpinnedAudio(for: [a, b])
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        try await h.transport.resolve(0)
        let events = await h.events.waitForCount(1)
        XCTAssertEqual(events, [.discarded])
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        let calls = await h.transport.startedURLs
        XCTAssertEqual(calls, [a.remoteURL])
    }

    func testRevokedPrefetchCleanupPreservesAnotherArticlesPinThenDeletesAfterUnpin() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:unrelated-owner", leaseID: leaseA, asset: a)
        await h.transport.waitForStarts(1)
        h.cache.removeUnpinnedAudio(for: [a])
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        _ = await h.events.waitForCount(1)
        XCTAssertTrue(h.cache.isDownloaded(for: a))
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:unrelated-owner", leaseID: leaseA, onlyIfAsset: a)
        h.cache.removeUnpinnedAudio(for: [a])
        XCTAssertFalse(h.cache.isDownloaded(for: a))
    }
}

extension PodcastAudioCacheDownloadTests {
    func testWithdrawalUnpinCanRetainAudioUsedByAnAllowedUnpinnedEpisode() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:withdrawn", leaseID: leaseA, asset: a)
        await h.transport.waitForStarts(1)
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:withdrawn", leaseID: leaseA, onlyIfAsset: a)
        XCTAssertFalse(h.cache.isPinned(articleId: "favorites-v1:withdrawn"))
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        _ = await h.events.waitForCount(1)
        XCTAssertTrue(h.cache.isDownloaded(for: a))
        h.cache.removeUnpinnedAudio(for: [a])
        XCTAssertFalse(h.cache.isDownloaded(for: a))
    }
}

extension PodcastAudioCacheDownloadTests {
    func testObsoleteRevisionCleanupCannotUnpinTheNewerAudioAlreadySavedForSameArticle() async throws {
        let h = try AudioCacheHarness()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseA, asset: a)
        await h.transport.waitForStarts(1)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: leaseB, asset: b)
        await h.transport.waitForStarts(2)
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:A", leaseID: leaseA, onlyIfAsset: a)
        XCTAssertTrue(h.cache.isPinned(articleId: "favorites-v1:A"))
        h.cache.removeUnpinnedAudio(for: [a])
        try await h.transport.resolve(0)
        let first = await h.events.waitForCount(1)
        XCTAssertEqual(first, [.discarded])
        try await h.transport.resolve(1)
        _ = await h.events.waitForCount(2)
        XCTAssertFalse(h.cache.isDownloaded(for: a))
        XCTAssertTrue(h.cache.isDownloaded(for: b))
        XCTAssertTrue(h.cache.isDownloaded(forArticleId: "favorites-v1:A"))
    }
}
