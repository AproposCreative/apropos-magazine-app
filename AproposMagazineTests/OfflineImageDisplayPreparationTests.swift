import Foundation
import XCTest
@testable import Apropos

@MainActor
final class OfflineImageDisplayPreparationTests: XCTestCase {
    func testRepeatedDisplayURLQueriesNeverReadMappingFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("image-display-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = String(repeating: "a", count: 64)
        let filename = String(repeating: "b", count: 64) + ".png"
        let contentDirectory = directory.appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        let remote = try XCTUnwrap(URL(string: "https://images.example.com/cover.png"))
        try Data([1, 2, 3]).write(to: contentDirectory.appendingPathComponent(filename))
        try JSONEncoder().encode([remote.absoluteString: filename]).write(to: contentDirectory.appendingPathComponent("mapping.json"))
        let reads = MappingReadCounter()
        let cache = OfflineArticleImageCache(cacheDirectory: directory, download: { _ in throw CancellationError() },
            online: { false }, contentKey: { _, _ in key }, mappingReadObserver: { reads.record() })
        for _ in 0..<100 { _ = cache.displayURL(for: remote, articleId: "article", expectedRevision: "r1") }
        XCTAssertEqual(reads.count, 0, "Repeated native display evaluation must not synchronously reload mapping.json")
    }

    func testPreparedLookupReadsMappingOffMainOnceAndRenderQueriesUseMemory() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: true)
        let value = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(value, h.originalFile); XCTAssertEqual(h.probe.count, 1); XCTAssertFalse(h.probe.readOnMain)
        for _ in 0..<100 { XCTAssertEqual(h.cache.displayURL(for: h.remote, articleId: "a", expectedRevision: "r1"), h.originalFile) }
        XCTAssertEqual(h.probe.count, 1)
        let same = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(same, h.originalFile); XCTAssertEqual(h.probe.count, 1)
    }
    func testOriginalThenOptimizedFallbackResolveInsideOneOffMainMappingRead() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: false, optimized: true)
        let value = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(value, h.optimizedFile); XCTAssertEqual(h.probe.count, 1); XCTAssertFalse(h.probe.readOnMain)
    }
    func testForcedLifecycleRevalidationAfterExternalEvictionSelectsOptimizedFallback() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: true, optimized: true)
        let initial = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(initial, h.originalFile)
        try FileManager.default.removeItem(at: h.originalFile)
        let generation = h.cache.displayGeneration
        let refreshed = await h.cache.prepareDisplayURL(for: h.remote, access: h.access(), force: true)
        XCTAssertEqual(refreshed, h.optimizedFile); XCTAssertEqual(h.probe.count, 2)
        XCTAssertEqual(h.cache.displayGeneration, generation, "Lookup completion must not trigger a lifecycle refresh loop")
        XCTAssertFalse(h.probe.readOnMain)
    }
    func testOnlineRemoteMissingAndRevokedAccessNeverReadMapping() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: true)
        h.online = true
        let online = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(online, h.remote)
        h.online = false
        let remote = await h.cache.prepareDisplayURL(for: h.remote, access: .remote)
        XCTAssertEqual(remote, h.remote)
        let access = h.access(); h.allowed = false
        let rejected = await h.cache.prepareDisplayURL(for: h.remote, access: access)
        XCTAssertNil(rejected); XCTAssertEqual(h.probe.count, 0)
    }
    func testLookupMissRetainsRemoteFallbackAndNoDownloadIsStarted() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }
        let value = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(value, h.remote); XCTAssertEqual(h.probe.count, 1); XCTAssertEqual(h.cache.downloadActivity, 0)
    }
    func testConcurrentForcedAppearancesShareOnePhysicalLookup() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }; try h.store(original: true)
        let access = h.access()
        let first = Task { await h.cache.prepareDisplayURL(for: h.remote, access: access, force: true) }
        await h.waitForFirstRead()
        let second = Task { await h.cache.prepareDisplayURL(for: h.remote, access: access, force: true) }
        await settle()
        XCTAssertEqual(h.cache.displayActivity.active, 1); XCTAssertEqual(h.cache.displayActivity.pending, 0)
        h.probe.release()
        let a = await first.value, b = await second.value
        XCTAssertEqual(a, h.originalFile); XCTAssertEqual(b, h.originalFile); XCTAssertEqual(h.probe.count, 1)
    }
    func testCancellationRetiresWaiterButDoesNotFreeEnqueuedPhysicalLookup() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }; try h.store(original: true)
        let task = Task { await h.cache.prepareDisplayURL(for: h.remote, access: h.access()) }
        await h.waitForFirstRead(); task.cancel()
        let result = await task.value
        XCTAssertNil(result); XCTAssertEqual(h.cache.displayActivity.active, 1)
        h.probe.release(); await waitUntil { h.cache.displayActivity.active == 0 }
        XCTAssertEqual(h.cache.displayURL(for: h.remote, articleId: "a", expectedRevision: "r1"), h.remote)
    }
    func testAccountReturnAndRevisionLeaseChangeRejectOriginalCallback() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }; try h.store(original: true)
        let access = h.access()
        let task = Task { await h.cache.prepareDisplayURL(for: h.remote, access: access) }
        await h.waitForFirstRead()
        h.allowed = false; h.lease = UUID(); h.allowed = true
        h.probe.release(); let result = await task.value
        XCTAssertNil(result); XCTAssertEqual(h.cache.displayURL(for: h.remote, articleId: "a", expectedRevision: "r1"), h.remote)
        let fresh = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertEqual(fresh, h.originalFile); XCTAssertEqual(h.probe.count, 2)
    }
    func testModeChangeDuringPhysicalLookupCannotPublishLocalURL() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }; try h.store(original: true)
        let task = Task { await h.cache.prepareDisplayURL(for: h.remote, access: h.access()) }
        await h.waitForFirstRead(); h.online = true; h.probe.release()
        let result = await task.value; XCTAssertNil(result)
        XCTAssertEqual(h.cache.displayURL(for: h.remote, articleId: "a", expectedRevision: "r1"), h.remote)
    }
    func testFourPhysicalSlotsStayOccupiedAfterCancellationAndBoundPendingWork() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }
        var tasks: [Task<URL?, Never>] = []
        for index in 0..<4 {
            tasks.append(Task { await h.cache.prepareDisplayURL(for: URL(string: "https://example.com/\(index).jpg"), access: h.access()) })
        }
        await h.waitForFirstRead(); await waitUntil { h.cache.displayActivity.active == 4 }
        tasks.forEach { $0.cancel() }; for task in tasks { let result = await task.value; XCTAssertNil(result) }
        XCTAssertEqual(h.cache.displayActivity.active, 4)
        let latest = Task { await h.cache.prepareDisplayURL(for: h.remote, access: h.access()) }
        await waitUntil { h.cache.displayActivity.pending == 1 }
        XCTAssertEqual(h.cache.displayActivity.active, 4)
        h.probe.release(); let value = await latest.value
        XCTAssertEqual(value, h.remote); await waitUntil { h.cache.displayActivity.active == 0 }
    }
    func testQueuePressureSettlesEveryDisplacedRequestAndDoesNotHangVisibleRows() async throws {
        let h = try ImageDisplayHarness(blockFirst: true); defer { h.close() }
        var entered = 0
        let tasks = (0..<40).map { index in
            Task { @MainActor in
                entered += 1
                return await h.cache.prepareDisplayURL(for: URL(string: "https://example.com/row-\(index).jpg"), access: h.access())
            }
        }
        await h.waitForFirstRead(); await waitUntil { entered == 40 }
        XCTAssertEqual(h.cache.displayActivity.active, 4); XCTAssertEqual(h.cache.displayActivity.pending, 32)
        h.probe.release()
        var nilResults = 0
        for task in tasks { if await task.value == nil { nilResults += 1 } }
        XCTAssertEqual(nilResults, 4); XCTAssertEqual(h.cache.displayActivity.active, 0); XCTAssertEqual(h.cache.displayActivity.pending, 0)
    }
    func testExplicitEvictionInvalidatesWarmMemoryWithoutAnyRenderRead() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: true)
        let first = await h.cache.prepareDisplayURL(for: h.remote, access: h.access()); XCTAssertEqual(first, h.originalFile)
        let generation = h.cache.displayGeneration, count = h.probe.count
        h.cache.removeContent(h.key)
        XCTAssertNotEqual(h.cache.displayGeneration, generation)
        XCTAssertEqual(h.cache.displayURL(for: h.remote, articleId: "a", expectedRevision: "r1"), h.remote)
        XCTAssertEqual(h.probe.count, count)
        let refreshed = await h.cache.prepareDisplayURL(for: h.remote, access: h.access(), force: true)
        XCTAssertEqual(refreshed, h.remote)
    }
    func testPreparedResultMemoryIsBoundedAndOldestLookupCanBePreparedAgain() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }
        for index in 0..<129 {
            let remote = URL(string: "https://example.com/item-\(index).jpg")!
            let result = await h.cache.prepareDisplayURL(for: remote, access: h.access())
            XCTAssertEqual(result, remote)
        }
        XCTAssertEqual(h.probe.count, 129)
        let first = URL(string: "https://example.com/item-0.jpg")!
        let preparedAgain = await h.cache.prepareDisplayURL(for: first, access: h.access())
        XCTAssertEqual(preparedAgain, first); XCTAssertEqual(h.probe.count, 130)
    }
    func testAccessGetterReentryRevocationCannotGrantCachedLocalFile() async throws {
        let h = try ImageDisplayHarness(); defer { h.close() }; try h.store(original: true)
        let first = await h.cache.prepareDisplayURL(for: h.remote, access: h.access()); XCTAssertEqual(first, h.originalFile)
        let generation = h.lease
        var calls = 0
        let access = OfflineArticleImageCache.PreparationAccess(contentKey: h.key, generation: generation, isCurrent: {
            calls += 1
            if calls == 3 { h.lease = UUID() }
            return h.lease == generation
        })
        let rejected = await h.cache.prepareDisplayURL(for: h.remote, access: access)
        XCTAssertNil(rejected); XCTAssertEqual(h.probe.count, 1)
    }
    func testAcceptedImageWriteAdvancesGenerationAndInvalidatesCachedMiss() async throws {
        let h = try ImageDisplayHarness(download: { remote in
            let response = HTTPURLResponse(url: remote, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
            return .init(data: Data([1, 2, 3]), response: response)
        }); defer { h.close() }
        let miss = await h.cache.prepareDisplayURL(for: h.remote, access: h.access()); XCTAssertEqual(miss, h.remote)
        let generation = h.cache.displayGeneration
        let article = Article(id: "a", name: "Artikel", slug: "a", content: "", intro: "", topicID: "topic", mobileImageURL: h.remote, contentRevision: "r1")
        h.cache.scheduleCacheImages(for: article, contentKey: h.key)
        await waitUntil { h.cache.downloadActivity == 0 }
        XCTAssertNotEqual(h.cache.displayGeneration, generation)
        let loaded = await h.cache.prepareDisplayURL(for: h.remote, access: h.access())
        XCTAssertTrue(try XCTUnwrap(loaded).isFileURL)
    }

    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<3_000 { if condition() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Local image work did not settle", file: file, line: line)
    }
}

@MainActor private final class ImageDisplayHarness {
    let root: URL
    let key = String(repeating: "a", count: 64)
    let remote = URL(string: "https://uploads-ssl.webflow.com/assets/cover.jpg")!
    var lease = UUID()
    var allowed = true
    var online = false
    let probe: ImageMappingProbe
    let download: OfflineArticleImageCache.Download
    var originalFile: URL { root.appendingPathComponent(key).appendingPathComponent(String(repeating: "b", count: 64) + ".jpg") }
    var optimizedFile: URL { root.appendingPathComponent(key).appendingPathComponent(String(repeating: "c", count: 64) + ".jpg") }
    lazy var cache = OfflineArticleImageCache(cacheDirectory: root, download: download,
        online: { [weak self] in self?.online ?? true },
        preparationAccess: { [weak self] id, revision in
            guard let self, id == "a", revision == "r1" else { return .remote }; return self.access()
        }, mappingReadObserver: { [probe] in probe.record() })
    init(blockFirst: Bool = false, download: OfflineArticleImageCache.Download? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("prepared-image-\(UUID().uuidString)", isDirectory: true)
        probe = ImageMappingProbe(blockFirst: blockFirst)
        self.download = download ?? { _ in throw CancellationError() }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(key), withIntermediateDirectories: true)
    }
    func access() -> OfflineArticleImageCache.PreparationAccess {
        let original = lease
        return .init(contentKey: key, generation: original, isCurrent: { [weak self] in
            self?.allowed == true && self?.lease == original
        })
    }
    func store(original: Bool, optimized: Bool = false) throws {
        var mapping: [String: String] = [:]
        if original { try Data([1, 2, 3]).write(to: originalFile); mapping[remote.absoluteString] = originalFile.lastPathComponent }
        if optimized {
            try Data([4, 5, 6]).write(to: optimizedFile)
            mapping[ArticleHTMLProcessor.optimizedImageURL(from: remote.absoluteString)] = optimizedFile.lastPathComponent
        }
        try JSONEncoder().encode(mapping).write(to: root.appendingPathComponent(key).appendingPathComponent("mapping.json"))
    }
    func waitForFirstRead() async {
        let result = await XCTWaiter.fulfillment(of: [probe.started], timeout: 3)
        XCTAssertEqual(result, .completed)
    }
    func close() { probe.release(); try? FileManager.default.removeItem(at: root) }
}

private final class ImageMappingProbe: @unchecked Sendable {
    let started = XCTestExpectation(description: "Actual mapping read began on background queue")
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let blockFirst: Bool
    private var reads = 0
    private var onMain = false
    private var released = false
    init(blockFirst: Bool) { self.blockFirst = blockFirst }
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var readOnMain: Bool { lock.lock(); defer { lock.unlock() }; return onMain }
    func record() {
        lock.lock(); reads += 1; onMain = onMain || Thread.isMainThread; let first = reads == 1; lock.unlock()
        if first { started.fulfill(); if blockFirst { semaphore.wait() } }
    }
    func release() {
        lock.lock(); let signal = !released; released = true; lock.unlock()
        if signal { semaphore.signal() }
    }
}

private final class MappingReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}
