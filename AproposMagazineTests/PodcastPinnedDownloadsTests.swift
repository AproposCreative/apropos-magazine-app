import XCTest
@testable import Apropos

final class PodcastPinnedDownloadsTests: XCTestCase {
    private enum ProgressFailure: Error { case stalled }

    private func waitForSavedProgress(_ receipts: [XCTestExpectation],
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        for (index, receipt) in receipts.enumerated() {
            let result = await XCTWaiter.fulfillment(of: [receipt], timeout: 10)
            XCTAssertEqual(result, .completed, "Saved receipt \(index + 1)/\(receipts.count) must make progress",
                           file: file, line: line)
            guard result == .completed else { throw ProgressFailure.stalled }
        }
    }

    private func asset(_ index: Int) -> PodcastAudioAsset {
        PodcastAudioAsset(episodeID: "pinned-episode-\(index)", canonicalArticleID: "pinned-article-\(index)",
            kind: .human, sourceRevision: "r1", remoteURL: URL(string: "https://audio.example.com/pinned-\(index).m4a")!)!
    }

    func testAllCurrentPinsBeyondQueueCapacityDownloadOnceAsPhysicalSlotsDrain() async throws {
        let saved = (0..<80).map { expectation(description: "Verified receipt \($0 + 1)/80") }
        let events = PinnedCacheEvents(saved)
        let h = try PinnedCacheHarness(limit: 2, onEvent: { if $0 == .saved { events.record($0) } })
        let assets = (0..<80).map(asset)
        for (index, asset) in assets.enumerated() {
            h.cache.pinAndDownload(pinKey: "favorites-v1:reader-\(index)", leaseID: UUID(), asset: asset)
        }
        await h.transport.waitForStarts(2)
        XCTAssertEqual(h.cache.downloadActivity.active, 2)
        XCTAssertLessThanOrEqual(h.cache.downloadActivity.waiting, 64)
        await h.transport.releaseAll()
        // Every receipt must progress; this is not a bulk disk-throughput benchmark.
        try await waitForSavedProgress(saved)
        let calls = await h.transport.started
        XCTAssertEqual(calls.count, assets.count)
        XCTAssertEqual(Set(calls), Set(assets.map(\.remoteURL)))
        for asset in assets {
            XCTAssertTrue(h.cache.isDownloaded(for: asset), "Each admitted saved article must have its exact receipt")
            XCTAssertEqual(h.cache.resolvePlaybackURL(for: asset).cacheResult, .hit)
        }
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        XCTAssertEqual(events.values, Array(repeating: .saved, count: assets.count))
    }

    func testFailedPinStopsAtOneAttemptUntilEachExplicitRecoveryEvent() async throws {
        let first = expectation(description: "Initial failure")
        let second = expectation(description: "One recovery failure")
        let third = expectation(description: "Next explicit recovery succeeds")
        let events = PinnedCacheEvents([first, second, third])
        let h = try PinnedCacheHarness(onEvent: { events.record($0) })
        let asset = asset(1), lease = UUID()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: asset)
        await h.transport.waitForStarts(1)
        XCTAssertEqual(h.cache.downloadState(for: asset), .downloading)
        await h.transport.fail(0)
        await fulfillment(of: [first], timeout: 3)
        XCTAssertEqual(h.cache.downloadState(for: asset), .failed)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        XCTAssertEqual(h.cache.validationActivity.active, 0)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: asset)
        XCTAssertEqual(h.cache.downloadState(for: asset), .failed, "Status reconciliation is not a retry event")
        h.cache.retryPinnedDownloads()
        h.cache.retryPinnedDownloads() // An active/coalesced recovery cannot duplicate transport.
        await h.transport.waitForStarts(2)
        await h.transport.fail(1)
        await fulfillment(of: [second], timeout: 3)
        XCTAssertEqual(h.cache.downloadState(for: asset), .failed)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        h.cache.retryPinnedDownloads()
        await h.transport.waitForStarts(3)
        try await h.transport.resolve(2)
        await fulfillment(of: [third], timeout: 3)
        XCTAssertEqual(events.values, [.failed, .failed, .saved])
        XCTAssertEqual(h.cache.downloadState(for: asset), .available)
        let calls = await h.transport.started
        XCTAssertEqual(calls, [asset.remoteURL, asset.remoteURL, asset.remoteURL])
    }

    func testCurrentWaitingPinsAreRemovedWithoutOldLeaseReleasingReplacement() async throws {
        let completed = (0..<79).map { expectation(description: "Current wanted receipt \($0 + 1)/79") }
        let events = PinnedCacheEvents(completed)
        let h = try PinnedCacheHarness(limit: 1, onEvent: { if $0 == .saved { events.record($0) } })
        let first = asset(0)
        h.cache.pinAndDownload(pinKey: "favorites-v1:first", leaseID: UUID(), asset: first)
        await h.transport.waitForStarts(1)
        let assets = (1..<80).map(asset)
        let leases = assets.map { _ in UUID() }
        for (index, asset) in assets.enumerated() {
            h.cache.pinAndDownload(pinKey: "favorites-v1:member-\(index)", leaseID: leases[index], asset: asset)
        }
        // The last asset is outside physical/queued admission while the first
        // transport is held. Releasing its original pin must remove the wish.
        let last = try XCTUnwrap(assets.last), index = assets.count - 1
        let key = "favorites-v1:member-\(index)"
        let oldLease = leases[index], newLease = UUID()
        XCTAssertEqual(h.cache.downloadState(for: last), .waiting)
        h.cache.releasePinKeepingBytes(pinKey: key, leaseID: oldLease, onlyIfAsset: last)
        XCTAssertFalse(h.cache.isPinned(articleId: key))
        h.cache.pinAndDownload(pinKey: key, leaseID: newLease, asset: last)
        h.cache.releasePinKeepingBytes(pinKey: key, leaseID: oldLease, onlyIfAsset: last)
        XCTAssertTrue(h.cache.isPinned(articleId: key), "Late A cleanup cannot remove B's current lease for identical public bytes")
        h.cache.releasePinKeepingBytes(pinKey: key, leaseID: newLease, onlyIfAsset: last)
        XCTAssertEqual(h.cache.downloadState(for: last), .notDownloaded)
        await h.transport.releaseAll()
        try await waitForSavedProgress(completed)
        let calls = await h.transport.started
        XCTAssertEqual(calls.count, 79)
        XCTAssertFalse(calls.contains(last.remoteURL))
        XCTAssertFalse(h.cache.isDownloaded(for: last))
        XCTAssertEqual(events.values, Array(repeating: .saved, count: 79))
    }

    func testStorageLimitIsNotReadyAndDoesNotSacrificeAnotherSavedReceipt() async throws {
        let first = expectation(description: "First saved receipt")
        let second = expectation(description: "Storage rejection")
        let events = PinnedCacheEvents([first, second])
        let h = try PinnedCacheHarness(maxBytes: 4, onEvent: { events.record($0) })
        let a = asset(1), b = asset(2)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: a)
        await h.transport.waitForStarts(1)
        try await h.transport.resolve(0)
        await fulfillment(of: [first], timeout: 3)
        h.cache.pinAndDownload(pinKey: "favorites-v1:B", leaseID: UUID(), asset: b)
        await h.transport.waitForStarts(2)
        try await h.transport.resolve(1)
        await fulfillment(of: [second], timeout: 3)
        XCTAssertEqual(events.values, [.saved, .failed])
        XCTAssertEqual(h.cache.downloadState(for: a), .available)
        XCTAssertEqual(h.cache.downloadState(for: b), .storageLimit)
        XCTAssertFalse(h.cache.isDownloaded(for: b))
        XCTAssertEqual(h.cache.resolvePlaybackURL(for: b).cacheResult, .miss)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        XCTAssertEqual(try Data(contentsOf: h.cache.resolvePlaybackURL(for: a).url), Data([1, 2, 3, 4]))
    }

    func testColdPinValidatesActualReceiptWithoutStartingAnotherDownload() async throws {
        let saved = expectation(description: "Initial receipt")
        let h = try PinnedCacheHarness(onEvent: { if $0 == .saved { saved.fulfill() } })
        let asset = asset(1)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: asset)
        await h.transport.waitForStarts(1)
        try await h.transport.resolve(0)
        await fulfillment(of: [saved], timeout: 3)
        let cold = h.reopen()
        XCTAssertEqual(cold.downloadState(for: asset), .notDownloaded, "No warm proof is synthesized at construction")
        cold.pinAndDownload(pinKey: "favorites-v1:cold-A", leaseID: UUID(), asset: asset)
        let prepared = await cold.prepare(asset)
        XCTAssertTrue(prepared)
        XCTAssertEqual(cold.downloadState(for: asset), .available)
        XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: asset).url), Data([1, 2, 3, 4]))
        let calls = await h.transport.started
        XCTAssertEqual(calls.count, 1)
    }

    func testClearAndRevocationKeepCancelledPhysicalBarrierAndCannotRefillOldPins() async throws {
        let discarded = expectation(description: "Old physical transport retires")
        let current = expectation(description: "Replacement physical transport saves")
        let events = PinnedCacheEvents([discarded, current])
        let h = try PinnedCacheHarness(limit: 1, onEvent: { events.record($0) })
        let asset = asset(1), oldLease = UUID(), newLease = UUID()
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: oldLease, asset: asset)
        await h.transport.waitForStarts(1)
        h.cache.removeAllCachedFiles()
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: newLease, asset: asset)
        h.cache.releasePinKeepingBytes(pinKey: "favorites-v1:A", leaseID: oldLease, onlyIfAsset: asset)
        XCTAssertTrue(h.cache.isPinned(articleId: "favorites-v1:A"))
        XCTAssertEqual(h.cache.downloadActivity.active, 1)
        try await h.transport.resolve(0)
        await fulfillment(of: [discarded], timeout: 3)
        await h.transport.waitForStarts(2)
        try await h.transport.resolve(1)
        await fulfillment(of: [current], timeout: 3)
        XCTAssertEqual(events.values, [.discarded, .saved])
        XCTAssertEqual(h.cache.downloadState(for: asset), .available)
        h.cache.invalidate([asset])
        h.cache.retryPinnedDownloads()
        XCTAssertFalse(h.cache.isPinned(articleId: "favorites-v1:A"))
        XCTAssertEqual(h.cache.downloadState(for: asset), .notDownloaded)
        XCTAssertFalse(h.cache.isDownloaded(for: asset))
    }

    func testStateAndCapacityNotificationsPermitMemoryQueryAndIdenticalPinReentry() async throws {
        let saved = expectation(description: "Receipt despite notification reentry")
        let hook = PinnedCacheReentry()
        let h = try PinnedCacheHarness(onEvent: { if $0 == .saved { saved.fulfill() } },
            onIndexChange: { hook.call() })
        let asset = asset(1), lease = UUID()
        hook.action = { [cache = h.cache] in
            _ = cache.downloadState(for: asset)
            cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: asset)
        }
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: lease, asset: asset)
        await h.transport.waitForStarts(1)
        try await h.transport.resolve(0)
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertGreaterThan(hook.calls, 1)
        XCTAssertEqual(h.cache.downloadState(for: asset), .available)
        hook.action = nil
    }

    func testDisabledCacheCannotQueueOrAdvertisePinnedAudio() throws {
        let h = try PinnedCacheHarness(enabled: false)
        let asset = asset(1)
        h.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: asset)
        h.cache.retryPinnedDownloads()
        XCTAssertEqual(h.cache.downloadState(for: asset), .disabled)
        XCTAssertEqual(h.cache.downloadActivity.active, 0)
        XCTAssertEqual(h.cache.downloadActivity.waiting, 0)
        XCTAssertFalse(h.cache.isDownloaded(for: asset))
    }
}

private final class PinnedCacheHarness {
    let root: URL
    let directory: URL
    let defaults: UserDefaults
    let cache: PodcastAudioCache
    let transport: PinnedCacheTransport
    private let suite: String
    private let maximumBytes: Int64
    private let limit: Int

    init(limit: Int = 1, maxBytes: Int64 = 120 * 1024 * 1024, enabled: Bool = true,
         onEvent: @escaping @Sendable (PodcastAudioCache.DownloadEvent) -> Void = { _ in },
         onIndexChange: @escaping @Sendable () -> Void = {}) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directory = root.appendingPathComponent("cache", isDirectory: true)
        suite = "PinnedAudio-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        transport = PinnedCacheTransport(root: root)
        maximumBytes = maxBytes; self.limit = limit
        let transport = transport
        cache = PodcastAudioCache(cacheDirectory: directory, defaults: defaults, enabled: { enabled }, maxBytes: { maxBytes },
            maximumConcurrentDownloads: limit, download: { try await transport.download($0) },
            onEvent: onEvent, onIndexChange: onIndexChange)
    }

    func reopen() -> PodcastAudioCache {
        let transport = transport, maxBytes = maximumBytes
        return PodcastAudioCache(cacheDirectory: directory, defaults: defaults, maxBytes: { maxBytes },
            maximumConcurrentDownloads: limit, download: { try await transport.download($0) })
    }

    deinit {
        cache.removeAllCachedFiles()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor PinnedCacheTransport {
    let root: URL
    private(set) var started: [URL] = []
    private var released = false
    private var continuations: [Int: CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>] = [:]
    private var startsWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(root: URL) { self.root = root }

    func download(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        let index = started.count
        started.append(url)
        let ready = startsWaiters.filter { $0.0 <= started.count }
        startsWaiters.removeAll { $0.0 <= started.count }
        ready.forEach { $0.1.resume() }
        if released { return try artifact(for: index) }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func waitForStarts(_ count: Int) async {
        if started.count >= count { return }
        await withCheckedContinuation { startsWaiters.append((count, $0)) }
    }

    func releaseAll() {
        released = true
        let held = continuations
        continuations = [:]
        for (index, continuation) in held { continuation.resume(with: Result { try artifact(for: index) }) }
    }

    func resolve(_ index: Int) throws {
        continuations.removeValue(forKey: index)?.resume(returning: try artifact(for: index))
    }

    func fail(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume(throwing: URLError(.notConnectedToInternet))
    }

    private func artifact(for index: Int) throws -> PodcastAudioCache.DownloadArtifact {
        let file = root.appendingPathComponent(UUID().uuidString + ".download")
        try Data([1, 2, 3, 4]).write(to: file)
        let response = HTTPURLResponse(url: started[index], statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "audio/mp4", "Content-Length": "4"])!
        return .init(temporaryURL: file, response: response)
    }
}

private final class PinnedCacheEvents: @unchecked Sendable {
    private let lock = NSLock()
    private let expectations: [XCTestExpectation]
    private var recorded: [PodcastAudioCache.DownloadEvent] = []
    init(_ expectations: [XCTestExpectation]) { self.expectations = expectations }
    func record(_ event: PodcastAudioCache.DownloadEvent) {
        lock.lock()
        let index = recorded.count
        recorded.append(event)
        let expectation = index < expectations.count ? expectations[index] : nil
        lock.unlock()
        expectation?.fulfill()
    }
    var values: [PodcastAudioCache.DownloadEvent] { lock.lock();defer { lock.unlock() };return recorded }
}

private final class PinnedCacheReentry: @unchecked Sendable {
    private let lock = NSLock()
    private var actionValue: (@Sendable () -> Void)?
    private var count = 0
    var action: (@Sendable () -> Void)? {
        get { lock.lock();defer { lock.unlock() };return actionValue }
        set { lock.lock();actionValue = newValue;lock.unlock() }
    }
    var calls: Int { lock.lock();defer { lock.unlock() };return count }
    func call() {
        lock.lock();count += 1;let action = actionValue;lock.unlock()
        action?()
    }
}
