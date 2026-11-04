import CryptoKit
import XCTest
@testable import Apropos

final class PodcastAudioAssetCacheTests: XCTestCase {
    private func asset(_ revision: String = "r1", id: String = "episode") -> PodcastAudioAsset {
        PodcastAudioAsset(episodeID: id, canonicalArticleID: "article", kind: .human, sourceRevision: revision,
                          remoteURL: URL(string: "https://audio.example.com/shared.m4a")!)!
    }
    func testColdRestartOnlyExactBoundAssetValidatesAndSameURLNewSourceIsMiss() async throws {
        let h = try ProvenanceHarness();let old = asset(), new = asset("r2")
        h.cache.scheduleBackgroundDownload(for: old);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data([1, 2, 3]));_ = await h.events.waitForCount(1)
        let cold = h.reopen()
        XCTAssertFalse(cold.isDownloaded(for: old));XCTAssertEqual(cold.resolvePlaybackURL(for: old).cacheResult, .miss)
        let wrong = await cold.prepare(new);XCTAssertFalse(wrong);XCTAssertFalse(cold.isDownloaded(for: new))
        let exact = await cold.prepare(old);XCTAssertTrue(exact);XCTAssertEqual(cold.resolvePlaybackURL(for: old).cacheResult, .hit)
        XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: old).url), Data([1, 2, 3]))
    }
    func testOpenRevalidationRejectsSameSizeTamperingAndClearsOnlyVerifiedMemoryHit() async throws {
        let h = try ProvenanceHarness();let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data([1, 2, 3]));_ = await h.events.waitForCount(1)
        let file = h.cache.resolvePlaybackURL(for: accepted).url
        try Data([4, 5, 6]).write(to: file)
        XCTAssertTrue(h.cache.isDownloaded(for: accepted), "Status is the bounded in-memory observation, not a repeated disk hash")
        let prepared = await h.cache.prepare(accepted)
        XCTAssertFalse(prepared);XCTAssertFalse(h.cache.isDownloaded(for: accepted))
        XCTAssertEqual(h.cache.resolvePlaybackURL(for: accepted).cacheResult, .miss)
    }
    func testMissingCorruptOversizedForeignAndUnsupportedReceiptsAreMisses() async throws {
        let h = try ProvenanceHarness();let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data([1, 2, 3]));_ = await h.events.waitForCount(1)
        let receiptURL = h.receiptURL(accepted);let original = try Data(contentsOf: receiptURL)
        try FileManager.default.removeItem(at: receiptURL)
        var prepared = await h.cache.prepare(accepted);XCTAssertFalse(prepared)
        for bytes in [Data("broken".utf8), Data(repeating: 0x20, count: PodcastAudioReceipt.maximumBytes + 1)] {
            try bytes.write(to: receiptURL);prepared = await h.cache.prepare(accepted);XCTAssertFalse(prepared)
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["schemaVersion"] = 99;try JSONSerialization.data(withJSONObject: object).write(to: receiptURL)
        prepared = await h.cache.prepare(accepted);XCTAssertFalse(prepared)
        var foreign = try XCTUnwrap(object["asset"] as? [String: Any]);foreign["sourceRevision"] = "r2";object["asset"] = foreign;object["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: receiptURL)
        prepared = await h.cache.prepare(accepted);XCTAssertFalse(prepared)
        try original.write(to: receiptURL);prepared = await h.cache.prepare(accepted);XCTAssertTrue(prepared)
    }
    func testLegacyURLFilesAndPersistedPinsNeverAdoptIntoAssetOrMutateTheirStorage() async throws {
        let h = try ProvenanceHarness();let accepted = asset()
        let legacyKey = SHA256.hash(data: Data(accepted.remoteURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let legacy = h.directory.appendingPathComponent(legacyKey + ".m4a")
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true);try Data([9, 8, 7]).write(to: legacy)
        h.defaults.set(["unassigned-A": accepted.remoteURL.absoluteString], forKey: "podcast_audio_pinned_by_article_v1")
        let prepared = await h.cache.prepare(accepted)
        XCTAssertFalse(prepared);XCTAssertFalse(h.cache.isDownloaded(for: accepted));XCTAssertFalse(h.cache.isPinned(articleId: "unassigned-A"))
        XCTAssertEqual(h.defaults.dictionary(forKey: "podcast_audio_pinned_by_article_v1") as? [String: String], ["unassigned-A": accepted.remoteURL.absoluteString])
        h.cache.removeAllCachedFiles()
        let afterClear = await h.cache.prepare(accepted);XCTAssertFalse(afterClear)
        XCTAssertEqual(try Data(contentsOf: legacy), Data([9, 8, 7]))
        XCTAssertNotNil(h.defaults.object(forKey: "podcast_audio_pinned_by_article_v1"))
    }
    func testPartialCommitWithAudioOnlyCannotProduceVerifiedHit() async throws {
        let h = try ProvenanceHarness();let accepted = asset()
        let directory = h.directory.appendingPathComponent("assets-v2")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent(accepted.key + "-" + UUID().uuidString.lowercased() + ".m4a"))
        let prepared = await h.cache.prepare(accepted);XCTAssertFalse(prepared)
        XCTAssertEqual(h.cache.resolvePlaybackURL(for: accepted).cacheResult, .miss)
    }
    func testByteAdmissionPreservesProtectedExistingAssetInsteadOfExceedingBudget() async throws {
        let h = try ProvenanceHarness(maxBytes: 8);let first = asset(id: "first"), second = asset(id: "second")
        h.cache.pinAndDownload(pinKey: "favorites-v1:owner-A", leaseID: UUID(), asset: first)
        await h.transport.waitForStarts(1);try await h.transport.resolve(0, bytes: Data(repeating: 1, count: 8));_ = await h.events.waitForCount(1)
        h.cache.scheduleBackgroundDownload(for: second);await h.transport.waitForStarts(2)
        try await h.transport.resolve(1, bytes: Data(repeating: 2, count: 8));let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.saved, .failed]);XCTAssertTrue(h.cache.isDownloaded(for: first));XCTAssertFalse(h.cache.isDownloaded(for: second))
        XCTAssertEqual(h.cache.totalCacheSizeBytes(), 8)
    }
    func testOversizedArtifactFailsBeforeCommitAndReleasesActualTransportSlot() async throws {
        let h = try ProvenanceHarness(maxBytes: 4);let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data(repeating: 1, count: 8));let events = await h.events.waitForCount(1)
        XCTAssertEqual(events, [.failed]);XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertFalse(h.cache.isDownloaded(for: accepted));XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted).path))
    }
    func testClearKeepsActualCancelledTransportBarrierAndNewestSameAssetStartsAfterReturn() async throws {
        let h = try ProvenanceHarness(limit: 1);let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        h.cache.removeAllCachedFiles();h.cache.scheduleBackgroundDownload(for: accepted)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        let before = await h.transport.started;XCTAssertEqual(before.count, 1)
        try await h.transport.resolve(0, bytes: Data([1]));_ = await h.events.waitForCount(1)
        await h.transport.waitForStarts(2);XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(1, bytes: Data([2, 3]));let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.discarded, .saved]);XCTAssertEqual(try Data(contentsOf: h.cache.resolvePlaybackURL(for: accepted).url), Data([2, 3]))
    }
    func testManyRequestsRemainBoundedAndInvalidationDoesNotRecycleCancelledCapacity() async throws {
        let h = try ProvenanceHarness(limit: 2)
        let assets = (0..<200).map { asset(id: "episode-\($0)") }
        assets.forEach { h.cache.scheduleBackgroundDownload(for: $0) }
        await h.transport.waitForStarts(2)
        XCTAssertEqual(h.cache.downloadActivity.active, 2)
        XCTAssertLessThanOrEqual(h.cache.downloadActivity.waiting, 64)
        XCTAssertLessThanOrEqual(h.cache.validationActivity.active, 2)
        XCTAssertLessThanOrEqual(h.cache.validationActivity.waiting, 64)
        h.cache.invalidate(Set(assets));XCTAssertEqual(h.cache.downloadActivity.active, 2)
        try await h.transport.resolve(0, bytes: Data([1]));try await h.transport.resolve(1, bytes: Data([2]))
        let events = await h.events.waitForCount(2);XCTAssertEqual(events, [.discarded, .discarded])
        let starts = await h.transport.started;XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(h.cache.downloadActivity.active, 0);XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
    }
    func testPinAcquiredInsideBudgetCallbackProtectsVictimBeforeAdmissionReservation() async throws {
        let hooks = CacheRaceHooks(bytes: 8)
        let h = try ProvenanceHarness(budget: { hooks.readBudget() });let first = asset(id: "first"), second = asset(id: "second")
        h.cache.scheduleBackgroundDownload(for: first);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data(repeating: 1, count: 8));_ = await h.events.waitForCount(1)
        let original = h.cache.resolvePlaybackURL(for: first).url
        h.cache.scheduleBackgroundDownload(for: second);await h.transport.waitForStarts(2)
        let cache = h.cache
        hooks.onBudgetCall(2) { cache.pinAndDownload(pinKey: "favorites-v1:new-owner", leaseID: UUID(), asset: first) }
        try await h.transport.resolve(1, bytes: Data(repeating: 2, count: 8));let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.saved, .failed]);XCTAssertTrue(cache.isPinned(articleId: "favorites-v1:new-owner"))
        XCTAssertTrue(cache.isDownloaded(for: first));XCTAssertEqual(try Data(contentsOf: original), Data(repeating: 1, count: 8))
        XCTAssertFalse(cache.isDownloaded(for: second));XCTAssertEqual(cache.totalCacheSizeBytes(), 8)
    }
    func testPinDuringReservedRemovalCannotOpenDeletedBytesAndWaitsForFreshDownload() async throws {
        let hooks = CacheRaceHooks(bytes: 16)
        let h = try ProvenanceHarness(onIndexChange: { hooks.indexChanged() });let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data([1, 2]));_ = await h.events.waitForCount(1)
        await hooks.waitForIndexChanges(1)
        let original = h.cache.resolvePlaybackURL(for: accepted).url;let cache = h.cache
        hooks.onNextIndexChange {
            cache.pinAndDownload(pinKey: "favorites-v1:new-owner", leaseID: UUID(), asset: accepted)
            hooks.observe(downloaded: cache.isDownloaded(for: accepted), result: cache.resolvePlaybackURL(for: accepted).cacheResult,
                          validators: cache.validationActivity.active, downloads: cache.downloadActivity.active)
        }
        cache.removeUnpinnedAudio(for: [accepted])
        await h.transport.waitForStarts(2)
        XCTAssertEqual(hooks.observation?.downloaded, false);XCTAssertEqual(hooks.observation?.result, .miss)
        XCTAssertEqual(hooks.observation?.validators, 0);XCTAssertEqual(hooks.observation?.downloads, 0)
        XCTAssertTrue(cache.isPinned(articleId: "favorites-v1:new-owner"));XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(cache.isDownloaded(for: accepted))
        try await h.transport.resolve(1, bytes: Data([3, 4]));_ = await h.events.waitForCount(2)
        XCTAssertTrue(cache.isDownloaded(for: accepted));XCTAssertEqual(try Data(contentsOf: cache.resolvePlaybackURL(for: accepted).url), Data([3, 4]))
    }
    func testPinDuringPostCommitBudgetCheckProtectsFirstAssetDuringLimitEnforcement() async throws {
        let hooks = CacheRaceHooks(bytes: 16)
        let h = try ProvenanceHarness(budget: { hooks.readBudget() });let first = asset(id: "first"), second = asset(id: "second")
        h.cache.scheduleBackgroundDownload(for: first);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data(repeating: 1, count: 8));_ = await h.events.waitForCount(1)
        let original = h.cache.resolvePlaybackURL(for: first).url;let cache = h.cache
        cache.scheduleBackgroundDownload(for: second);await h.transport.waitForStarts(2)
        hooks.onBudgetCall(3, thenBytes: 8) { cache.pinAndDownload(pinKey: "favorites-v1:new-owner", leaseID: UUID(), asset: first) }
        try await h.transport.resolve(1, bytes: Data(repeating: 2, count: 8));_ = await h.events.waitForCount(2)
        XCTAssertTrue(cache.isDownloaded(for: first));XCTAssertEqual(try Data(contentsOf: original), Data(repeating: 1, count: 8))
        XCTAssertFalse(cache.isDownloaded(for: second));XCTAssertEqual(cache.totalCacheSizeBytes(), 8)
    }
    func testRevocationOverflowClosesAdmissionAgainstHeldUnrelatedDownloadAndWarmStatus() async throws {
        let h = try ProvenanceHarness();let warm = asset(id: "warm"), held = asset(id: "held")
        h.cache.pinAndDownload(pinKey: "favorites-v1:warm", leaseID: UUID(), asset: warm)
        await h.transport.waitForStarts(1);try await h.transport.resolve(0, bytes: Data([1]));_ = await h.events.waitForCount(1)
        h.cache.scheduleBackgroundDownload(for: held);await h.transport.waitForStarts(2)
        h.cache.invalidate(Set((0..<513).map { asset(id: "revoked-\($0)") }))
        XCTAssertFalse(h.cache.isDownloaded(for: warm));XCTAssertFalse(h.cache.isDownloaded(forArticleId: "favorites-v1:warm"))
        XCTAssertEqual(h.cache.resolvePlaybackURL(for: warm).cacheResult, .miss)
        try await h.transport.resolve(1, bytes: Data([2]));let events = await h.events.waitForCount(2)
        XCTAssertEqual(events, [.saved, .discarded]);XCTAssertFalse(h.cache.isDownloaded(for: held))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(held).path))
        let prepared = await h.cache.prepare(warm);XCTAssertFalse(prepared)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
    }
    func testInjectedPartialResponsesNeverCommitEvenWhenTransportReturnsSuccess() async throws {
        for (status, headers) in [(206, ["Content-Type": "audio/mp4"]), (200, ["Content-Type": "audio/mp4", "Content-Range": "bytes 0-1/8"])] {
            let h = try ProvenanceHarness();let accepted = asset()
            h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
            try await h.transport.resolve(0, bytes: Data([1, 2]), status: status, headers: headers)
            let events = await h.events.waitForCount(1)
            XCTAssertEqual(events, [.failed]);XCTAssertFalse(h.cache.isDownloaded(for: accepted))
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted).path))
        }
    }

    func testInjectedDeclaredLengthMustMatchActualFileBeforeReceiptCommit() async throws {
        for length in ["0", "1", "3", "268435457"] {
            try await assertRejectedArtifact(headers: ["Content-Type": "audio/mp4", "Content-Length": length])
        }
    }
    func testMalformedExplicitLengthCannotMasqueradeAsUnknownLength() async throws {
        for length in ["", "-1", "two", "2,2", "9223372036854775808"] {
            try await assertRejectedArtifact(headers: ["Content-Type": "audio/mp4", "Content-Length": length])
        }
    }
    func testInjectedCompressedArtifactCannotBecomeAnOfflineReceipt() async throws {
        for encoding in ["", "gzip", "deflate", "br", "identity,gzip"] {
            try await assertRejectedArtifact(headers: ["Content-Type": "audio/mp4", "Content-Encoding": encoding, "Content-Length": "2"])
        }
    }
    func testUnknownOrExactLengthAndIdentityEncodingPreserveCompleteArtifactBytes() async throws {
        for headers in [["Content-Type": "audio/mp4"],
                        ["Content-Type": "audio/mp4", "Content-Length": "2"],
                        ["Content-Type": "audio/mp4", "Content-Length": "2", "Content-Encoding": "IDENTITY"]] {
            let h = try ProvenanceHarness();let accepted = asset()
            h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
            try await h.transport.resolve(0, bytes: Data([1, 2]), headers: headers)
            let events = await h.events.waitForCount(1);XCTAssertEqual(events, [.saved])
            let cold = h.reopen();let prepared = await cold.prepare(accepted);XCTAssertTrue(prepared)
            XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: accepted).url), Data([1, 2]))
        }
    }
    private func assertRejectedArtifact(headers: [String: String], file: StaticString = #filePath, line: UInt = #line) async throws {
        let h = try ProvenanceHarness();let accepted = asset()
        h.cache.scheduleBackgroundDownload(for: accepted);await h.transport.waitForStarts(1)
        try await h.transport.resolve(0, bytes: Data([1, 2]), headers: headers)
        let events = await h.events.waitForCount(1)
        XCTAssertEqual(events, [.failed], "Headers: \(headers)", file: file, line: line)
        XCTAssertFalse(h.cache.isDownloaded(for: accepted), file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted).path), file: file, line: line)
        XCTAssertEqual(h.cache.downloadActivity.active, 0, file: file, line: line)
    }

}

private final class ProvenanceHarness {
    let root: URL
    let directory: URL
    let defaults: UserDefaults
    let transport: ProvenanceTransport
    let events = ProvenanceEvents()
    let cache: PodcastAudioCache
    private let suite: String
    private let limit: Int
    private let maximumBytes: Int64
    init(limit: Int = 2, maxBytes: Int64 = 120 * 1024 * 1024, budget: (@Sendable () -> Int64)? = nil,
         onIndexChange: @escaping @Sendable () -> Void = {}) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = root.appendingPathComponent("cache");try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "AudioProvenance-" + UUID().uuidString;defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        transport = ProvenanceTransport(root: root);self.limit = limit;maximumBytes = maxBytes
        let transport = transport, events = events
        cache = PodcastAudioCache(cacheDirectory: directory, defaults: defaults, maxBytes: budget ?? { maxBytes }, maximumConcurrentDownloads: limit,
                                  download: { try await transport.download($0) }, onEvent: { event in Task { await events.record(event) } }, onIndexChange: onIndexChange)
    }
    func reopen() -> PodcastAudioCache {
        let transport = transport, events = events, bytes = maximumBytes
        return PodcastAudioCache(cacheDirectory: directory, defaults: defaults, maxBytes: { bytes }, maximumConcurrentDownloads: limit,
                                 download: { try await transport.download($0) }, onEvent: { event in Task { await events.record(event) } })
    }
    func receiptURL(_ asset: PodcastAudioAsset) -> URL { directory.appendingPathComponent("assets-v2").appendingPathComponent(asset.key + ".json") }
    deinit { cache.removeAllCachedFiles();defaults.removePersistentDomain(forName: suite);try? FileManager.default.removeItem(at: root) }
}
private actor ProvenanceTransport {
    let root: URL
    private(set) var started: [URL] = []
    private var continuations: [Int: CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>] = [:]
    private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []
    init(root: URL) { self.root = root }
    func download(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        let index = started.count;started.append(url)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            let ready = waiting.filter { $0.0 <= started.count };waiting.removeAll { $0.0 <= started.count };ready.forEach { $0.1.resume() }
        }
    }
    func waitForStarts(_ count: Int) async {
        if started.count >= count { return }
        await withCheckedContinuation { waiting.append((count, $0)) }
    }
    func resolve(_ index: Int, bytes: Data, status: Int = 200, headers: [String: String] = ["Content-Type": "audio/mp4"]) throws {
        let file = root.appendingPathComponent(UUID().uuidString + ".download");try bytes.write(to: file)
        let response = HTTPURLResponse(url: started[index], statusCode: status, httpVersion: nil, headerFields: headers)!
        continuations.removeValue(forKey: index)?.resume(returning: .init(temporaryURL: file, response: response))
    }
}
private actor ProvenanceEvents {
    private var events: [PodcastAudioCache.DownloadEvent] = []
    private var waiting: [(Int, CheckedContinuation<[PodcastAudioCache.DownloadEvent], Never>)] = []
    func record(_ event: PodcastAudioCache.DownloadEvent) {
        events.append(event);let ready = waiting.filter { $0.0 <= events.count };waiting.removeAll { $0.0 <= events.count };ready.forEach { $0.1.resume(returning: events) }
    }
    func waitForCount(_ count: Int) async -> [PodcastAudioCache.DownloadEvent] {
        if events.count >= count { return events }
        return await withCheckedContinuation { waiting.append((count, $0)) }
    }
}

/// Per-test callbacks run outside this lock, so the budget/index seams exercise
/// actual reentrant pin decisions without sleeping or touching a shared suite.
private final class CacheRaceHooks: @unchecked Sendable {
    struct Observation { let downloaded: Bool;let result: PodcastAudioCacheResult;let validators: Int;let downloads: Int }
    private let lock = NSLock()
    private var bytes: Int64
    private var budgetCountdown: Int?
    private var budgetAction: (@Sendable () -> Void)?
    private var replacementBytes: Int64?
    private var indexAction: (@Sendable () -> Void)?
    private var observed: Observation?
    private var indexCount = 0
    private var indexWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(bytes: Int64) { self.bytes = bytes }
    func onBudgetCall(_ count: Int, thenBytes: Int64? = nil, perform: @escaping @Sendable () -> Void) {
        lock.lock();budgetCountdown = count;replacementBytes = thenBytes;budgetAction = perform;lock.unlock()
    }
    func readBudget() -> Int64 {
        lock.lock()
        var action: (@Sendable () -> Void)?
        if let count = budgetCountdown {
            if count == 1 { action = budgetAction;budgetAction = nil;budgetCountdown = nil;if let replacementBytes { bytes = replacementBytes } }
            else { budgetCountdown = count - 1 }
        }
        let result = bytes;lock.unlock();action?();return result
    }
    func onNextIndexChange(_ perform: @escaping @Sendable () -> Void) { lock.lock();indexAction = perform;lock.unlock() }
    func indexChanged() {
        lock.lock();indexCount += 1;let action = indexAction;indexAction = nil
        let ready = indexWaiters.filter { $0.0 <= indexCount };indexWaiters.removeAll { $0.0 <= indexCount }
        lock.unlock();action?();ready.forEach { $0.1.resume() }
    }
    func waitForIndexChanges(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock();let ready = indexCount >= count
            if !ready { indexWaiters.append((count, continuation)) };lock.unlock()
            if ready { continuation.resume() }
        }
    }
    func observe(downloaded: Bool, result: PodcastAudioCacheResult, validators: Int, downloads: Int) {
        lock.lock();observed = Observation(downloaded: downloaded, result: result, validators: validators, downloads: downloads);lock.unlock()
    }
    var observation: Observation? { lock.lock();defer { lock.unlock() };return observed }
}
