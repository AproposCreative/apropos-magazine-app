import CryptoKit
import XCTest
@testable import Apropos

final class PodcastAudioDurableStorageTests: XCTestCase {
    private func asset(_ revision: String = "r1", id: String = "episode") -> PodcastAudioAsset {
        PodcastAudioAsset(episodeID: id, canonicalArticleID: "article", kind: .human, sourceRevision: revision,
                          remoteURL: URL(string: "https://audio.example.com/shared.m4a")!)!
    }

    func testProductionDownloadsUseApplicationSupportAndPreparedFilesAreExcludedFromBackup() throws {
        XCTAssertTrue(OfflineDownloadLocations.audioDirectory.path.hasPrefix(URL.applicationSupportDirectory.path + "/"))
        XCTAssertTrue(OfflineDownloadLocations.bodyDirectory.path.hasPrefix(URL.applicationSupportDirectory.path + "/"))
        XCTAssertTrue(OfflineDownloadLocations.legacyAudioDirectory.path.hasPrefix(URL.cachesDirectory.path + "/"))
        let h = try DurableAudioHarness()
        let directory = h.root.appendingPathComponent("prepared")
        try OfflineDownloadLocations.prepareDirectory(directory)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let file = directory.appendingPathComponent("content")
        try Data([1]).write(to: file)
        try OfflineDownloadLocations.prepareFile(file)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The actual simulator returned nil for this attribute. Backup exclusion
        // is still checked above; physical file protection remains unaccepted.
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
        XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        #endif
        XCTAssertThrowsError(try OfflineDownloadLocations.prepareDirectory(file))
    }

    func testColdPrepareCopiesOnlyRequestedValidatedV2AssetAndSurvivesWithoutLegacyCache() async throws {
        let h = try DurableAudioHarness(), accepted = asset(), unrelated = asset(id: "unrelated")
        let bytes = Data([1, 2, 3])
        let original = try h.seed(accepted, bytes: bytes, legacy: true)
        let unrelatedOriginal = try h.seed(unrelated, bytes: Data([9]), legacy: true)
        let cache = h.open()
        XCTAssertFalse(cache.isDownloaded(for: accepted))
        let prepared = await cache.prepare(accepted)
        XCTAssertTrue(prepared)
        let selected = cache.resolvePlaybackURL(for: accepted)
        XCTAssertEqual(selected.cacheResult, .hit)
        XCTAssertTrue(selected.url.path.hasPrefix(h.durable.path + "/assets-v2/"))
        XCTAssertEqual(try Data(contentsOf: selected.url), bytes)
        try assertStoragePolicy(selected.url)
        try assertStoragePolicy(h.receiptURL(accepted, legacy: false))
        XCTAssertEqual(try Data(contentsOf: original.file), bytes)
        XCTAssertEqual(try Data(contentsOf: original.receipt), original.receiptBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedOriginal.file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(unrelated, legacy: false).path))
        XCTAssertEqual(h.downloads.count, 0)
        try FileManager.default.removeItem(at: h.legacy)
        let cold = h.open()
        XCTAssertFalse(cold.isDownloaded(for: accepted))
        let reopened = await cold.prepare(accepted)
        XCTAssertTrue(reopened)
        XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: accepted).url), bytes)
    }

    func testLegacyWrongDescriptorHashSizeAndUnsupportedReceiptNeverMigrate() async throws {
        for corruption in 0..<4 {
            let h = try DurableAudioHarness(), accepted = asset()
            let source = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
            switch corruption {
            case 0:
                let wrong = try PodcastAudioReceipt(asset: asset("r2"), byteCount: 3, sha256: Self.digest(Data([1, 2, 3])))
                try wrong.encoded().write(to: source.receipt)
            case 1: try Data([4, 5, 6]).write(to: source.file) // Same length, different bytes.
            case 2: try Data([1, 2]).write(to: source.file)
            default:
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: source.receiptBytes) as? [String: Any])
                object["schemaVersion"] = 1
                try JSONSerialization.data(withJSONObject: object).write(to: source.receipt)
            }
            let receiptBefore = try Data(contentsOf: source.receipt), fileBefore = try Data(contentsOf: source.file)
            let cache = h.open(), prepared = await cache.prepare(accepted)
            XCTAssertFalse(prepared, "Corruption case \(corruption)")
            XCTAssertFalse(cache.isDownloaded(for: accepted))
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: false).path))
            XCTAssertEqual(try Data(contentsOf: source.receipt), receiptBefore)
            XCTAssertEqual(try Data(contentsOf: source.file), fileBefore)
            XCTAssertEqual(h.downloads.count, 0)
        }
    }

    func testNewerValidDestinationWinsAndInvalidExistingDestinationIsNeverOverwritten() async throws {
        for validDestination in [true, false] {
            let h = try DurableAudioHarness(), accepted = asset()
            let old = try h.seed(accepted, bytes: Data([1]), legacy: true)
            let current = try h.seed(accepted, bytes: Data([7, 8]), legacy: false)
            if !validDestination { try Data([5, 6]).write(to: current.file) }
            let receiptBefore = try Data(contentsOf: current.receipt), fileBefore = try Data(contentsOf: current.file)
            let cache = h.open(), prepared = await cache.prepare(accepted)
            XCTAssertEqual(prepared, validDestination)
            XCTAssertEqual(try Data(contentsOf: current.receipt), receiptBefore)
            XCTAssertEqual(try Data(contentsOf: current.file), fileBefore)
            XCTAssertEqual(try Data(contentsOf: old.file), Data([1]))
            if validDestination { XCTAssertEqual(cache.resolvePlaybackURL(for: accepted).url, current.file) }
            XCTAssertEqual(h.downloads.count, 0)
        }
    }

    func testDestinationArrivingDuringMigrationIsPreservedInsteadOfOverwritten() async throws {
        let h = try DurableAudioHarness(), accepted = asset()
        _ = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
        let hook = DurableMigrationHook(bytes: 64)
        hook.onCall(2) { _ = try? h.seed(accepted, bytes: Data([7, 8]), legacy: false) }
        let cache = h.open(budget: { hook.read() })
        let prepared = await cache.prepare(accepted)
        XCTAssertFalse(prepared)
        await hook.waitForActionCompletion()
        let currentReceipt = try Data(contentsOf: h.receiptURL(accepted, legacy: false))
        let cold = h.open(), next = await cold.prepare(accepted)
        XCTAssertTrue(next)
        XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: accepted).url), Data([7, 8]))
        XCTAssertEqual(try Data(contentsOf: h.receiptURL(accepted, legacy: false)), currentReceipt)
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testRevocationDuringLegacyValidationRejectsMigrationAndDeletesOnlyRevokedLegacyAsset() async throws {
        let h = try DurableAudioHarness(), accepted = asset(), other = asset(id: "other")
        let original = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
        let unrelated = try h.seed(other, bytes: Data([9]), legacy: true)
        let hook = DurableMigrationHook(bytes: 64)
        let cache = h.open(budget: { hook.read() })
        hook.onCall(1) { cache.invalidate([accepted]) }
        let prepared = await cache.prepare(accepted)
        XCTAssertFalse(prepared)
        XCTAssertFalse(cache.isDownloaded(for: accepted))
        await hook.waitForActionCompletion()
        await waitForRemovalIO(cache)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: false).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.receipt.path))
        XCTAssertEqual(try Data(contentsOf: unrelated.file), Data([9]))
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testRevocationInMigrationBudgetCallbackCannotEvictUnrelatedDurableBytes() async throws {
        let h = try DurableAudioHarness(), accepted = asset(), other = asset(id: "other")
        _ = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
        let unrelated = try h.seed(other, bytes: Data([9, 9, 9, 9]), legacy: false)
        let hook = DurableMigrationHook(bytes: 4)
        let cache = h.open(budget: { hook.read() })
        // First budget call validates the legacy receipt; the second runs only
        // after the bounded copy, inside makeRoom before its eviction lock.
        hook.onCall(2) { cache.invalidate([accepted]) }
        let prepared = await cache.prepare(accepted)
        XCTAssertFalse(prepared)
        await hook.waitForActionCompletion()
        await waitForRemovalIO(cache)
        XCTAssertEqual(try Data(contentsOf: unrelated.file), Data([9, 9, 9, 9]))
        XCTAssertEqual(try Data(contentsOf: unrelated.receipt), unrelated.receiptBytes)
        let cold = h.open(budget: { 4 }), otherPrepared = await cold.prepare(other)
        XCTAssertTrue(otherPrepared)
        XCTAssertFalse(cache.isDownloaded(for: accepted))
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testExplicitClearRemovesBothV2CopiesBeforeColdPrepareButPreservesV1AndOtherFolders() async throws {
        let h = try DurableAudioHarness(), accepted = asset()
        _ = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
        let v1 = h.legacy.appendingPathComponent("old-v1-audio.m4a")
        try Data([8]).write(to: v1)
        let outside = h.durable.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: h.durable, withIntermediateDirectories: true)
        try Data([7]).write(to: outside)
        let cache = h.open(), first = await cache.prepare(accepted)
        XCTAssertTrue(first)
        cache.removeAllCachedFiles()
        await waitForRemovalIO(cache)
        let cold = h.open(), afterClear = await cold.prepare(accepted)
        XCTAssertFalse(afterClear)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: true).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: false).path))
        XCTAssertEqual(try Data(contentsOf: v1), Data([8]))
        XCTAssertEqual(try Data(contentsOf: outside), Data([7]))
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testExplicitPerAssetRemovalAndInvalidationCannotResurrectFromLegacyOnColdPrepare() async throws {
        for revoke in [false, true] {
            let h = try DurableAudioHarness(), accepted = asset()
            let legacy = try h.seed(accepted, bytes: Data([1, 2]), legacy: true)
            let cache = h.open(), first = await cache.prepare(accepted)
            XCTAssertTrue(first)
            let local = cache.resolvePlaybackURL(for: accepted).url
            if revoke { cache.invalidate([accepted]) }
            else { cache.removeUnpinnedAudio(for: [accepted]) }
            await waitForRemovalIO(cache)
            let cold = h.open(), afterRemoval = await cold.prepare(accepted)
            XCTAssertFalse(afterRemoval)
            XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.file.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.receipt.path))
            XCTAssertEqual(h.downloads.count, 0)
        }
    }

    func testPerAssetCleanupPreservesPinnedCopiesThenDeletesOnlyAfterUnpin() async throws {
        let h = try DurableAudioHarness(), accepted = asset()
        let legacy = try h.seed(accepted, bytes: Data([1, 2]), legacy: true)
        let cache = h.open(), first = await cache.prepare(accepted)
        XCTAssertTrue(first)
        let lease = UUID()
        cache.pinAndDownload(pinKey: "favorites-v1:owner", leaseID: lease, asset: accepted)
        cache.removeUnpinnedAudio(for: [accepted])
        await waitForRemovalIO(cache)
        let cold = h.open(), retained = await cold.prepare(accepted)
        XCTAssertTrue(retained)
        XCTAssertEqual(try Data(contentsOf: legacy.file), Data([1, 2]))
        cache.releasePinKeepingBytes(pinKey: "favorites-v1:owner", leaseID: lease, onlyIfAsset: accepted)
        cache.removeUnpinnedAudio(for: [accepted])
        await waitForRemovalIO(cache)
        let final = h.open(), removed = await final.prepare(accepted)
        XCTAssertFalse(removed)
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testPerAssetCleanupDoesNotDeleteForeignReceiptOwnedFilesOrUnknownLegacyFiles() async throws {
        let h = try DurableAudioHarness(), accepted = asset(), foreign = asset("r2")
        let other = try h.seed(foreign, bytes: Data([9]), legacy: true)
        let foreignAtRequestedKey = h.receiptURL(accepted, legacy: true)
        try other.receiptBytes.write(to: foreignAtRequestedKey)
        let unknown = foreignAtRequestedKey.deletingLastPathComponent().appendingPathComponent("unknown.dat")
        try Data([8]).write(to: unknown)
        let cache = h.open()
        cache.removeUnpinnedAudio(for: [accepted])
        await waitForRemovalIO(cache)
        XCTAssertEqual(try Data(contentsOf: foreignAtRequestedKey), other.receiptBytes)
        XCTAssertEqual(try Data(contentsOf: other.file), Data([9]))
        XCTAssertEqual(try Data(contentsOf: other.receipt), other.receiptBytes)
        XCTAssertEqual(try Data(contentsOf: unknown), Data([8]))
        let cold = h.open(), prepared = await cold.prepare(accepted)
        XCTAssertFalse(prepared)
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testMigrationCannotEvictPinnedDurableAssetOrExceedAggregateBudget() async throws {
        let h = try DurableAudioHarness(), accepted = asset(), protected = asset(id: "protected")
        _ = try h.seed(accepted, bytes: Data([1, 2, 3]), legacy: true)
        let existing = try h.seed(protected, bytes: Data([8, 8, 8, 8]), legacy: false)
        let cache = h.open(budget: { 4 })
        let first = await cache.prepare(protected)
        XCTAssertTrue(first)
        cache.pinAndDownload(pinKey: "favorites-v1:protected", leaseID: UUID(), asset: protected)
        let prepared = await cache.prepare(accepted)
        XCTAssertFalse(prepared)
        XCTAssertTrue(cache.isDownloaded(for: protected))
        XCTAssertEqual(cache.totalCacheSizeBytes(), 4)
        XCTAssertEqual(try Data(contentsOf: existing.file), Data([8, 8, 8, 8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: false).path))
        XCTAssertEqual(h.downloads.count, 0)
    }

    func testLegacyV1URLFilesAreNeverAdoptedOrRemoved() async throws {
        let h = try DurableAudioHarness(), accepted = asset()
        try FileManager.default.createDirectory(at: h.legacy, withIntermediateDirectories: true)
        let old = h.legacy.appendingPathComponent(Self.digest(Data(accepted.remoteURL.absoluteString.utf8)) + ".m4a")
        try Data([9, 8]).write(to: old)
        let cache = h.open(), prepared = await cache.prepare(accepted)
        XCTAssertFalse(prepared)
        XCTAssertEqual(try Data(contentsOf: old), Data([9, 8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.receiptURL(accepted, legacy: false).path))
        XCTAssertEqual(h.downloads.count, 0)
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Existing deletion is asynchronous on this cache's serial I/O queue. This
    /// unrelated local probe runs after it, without claiming a global clear/CAS.
    private func waitForRemovalIO(_ cache: PodcastAudioCache) async {
        let barrier = asset(id: "removal-io-barrier")
        let present = await cache.prepare(barrier)
        XCTAssertFalse(present)
    }

    private func assertStoragePolicy(_ url: URL) throws {
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The actual simulator returned nil for protection metadata. Retain the
        // strict device assertion without claiming simulator/device equivalence.
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
        XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        #endif
    }
}

private final class DurableAudioHarness: @unchecked Sendable {
    struct Seed { let file: URL; let receipt: URL; let receiptBytes: Data }
    let root: URL
    let durable: URL
    let legacy: URL
    let downloads = DurableDownloadCounter()
    private let defaults: UserDefaults
    private let suite = "DurableAudio-" + UUID().uuidString
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        durable = root.appendingPathComponent("application-support", isDirectory: true)
        legacy = root.appendingPathComponent("old-cache", isDirectory: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    func open(budget: @escaping @Sendable () -> Int64 = { 64 }) -> PodcastAudioCache {
        let downloads = downloads
        return PodcastAudioCache(cacheDirectory: durable, defaults: defaults, legacyCacheDirectory: legacy, maxBytes: budget,
                                 download: { _ in downloads.record();throw URLError(.notConnectedToInternet) })
    }
    func receiptURL(_ asset: PodcastAudioAsset, legacy: Bool) -> URL {
        (legacy ? self.legacy : durable).appendingPathComponent("assets-v2", isDirectory: true).appendingPathComponent(asset.key + ".json")
    }
    func seed(_ asset: PodcastAudioAsset, bytes: Data, legacy: Bool) throws -> Seed {
        let directory = (legacy ? self.legacy : durable).appendingPathComponent("assets-v2", isDirectory: true)
        try OfflineDownloadLocations.prepareDirectory(directory)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let receipt = try PodcastAudioReceipt(asset: asset, byteCount: Int64(bytes.count), sha256: digest)
        let file = directory.appendingPathComponent(receipt.fileName)
        try bytes.write(to: file)
        let encoded = try receipt.encoded(), path = receiptURL(asset, legacy: legacy)
        try encoded.write(to: path)
        return Seed(file: file, receipt: path, receiptBytes: encoded)
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class DurableDownloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock();defer { lock.unlock() };return value }
    func record() { lock.lock();value += 1;lock.unlock() }
}
private final class DurableMigrationHook: @unchecked Sendable {
    private let lock = NSLock()
    private let bytes: Int64
    private var remaining: Int?
    private var action: (@Sendable () -> Void)?
    private var actionCompleted = false
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    init(bytes: Int64) { self.bytes = bytes }
    func onCall(_ count: Int, perform: @escaping @Sendable () -> Void) {
        lock.lock();remaining = count;action = perform;actionCompleted = false;lock.unlock()
    }
    func waitForActionCompletion() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            let completed = actionCompleted
            if !completed { completionWaiters.append(continuation) }
            lock.unlock()
            if completed { continuation.resume() }
        }
    }
    func read() -> Int64 {
        lock.lock()
        var perform: (@Sendable () -> Void)?
        if let count = remaining {
            if count == 1 { perform = action;action = nil;remaining = nil }
            else { remaining = count - 1 }
        }
        lock.unlock()
        if let perform {
            perform()
            // Invalidation may resume the prepare waiter before it enqueues
            // disk cleanup. Signal only after that complete action returns.
            lock.lock();actionCompleted = true
            let waiters = completionWaiters;completionWaiters = []
            lock.unlock();waiters.forEach { $0.resume() }
        }
        return bytes
    }
}
