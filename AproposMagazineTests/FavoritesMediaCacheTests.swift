import XCTest
@testable import Apropos

final class FavoritesMediaCacheTests: XCTestCase {
    private let audioURL = URL(string: "https://audio.example.com/a.m4a")!
    private let imageURL = URL(string: "https://images.example.com/photo.jpg")!
    private func asset(_ url: URL, revision: String = "r1") -> PodcastAudioAsset {
        PodcastAudioAsset(episodeID: "episode-a", canonicalArticleID: "a", kind: .human, sourceRevision: revision, remoteURL: url)!
    }
    private let key = String(repeating: "a", count: 64)
    private func article(revision: String = "r1") -> Article {
        Article(id: "a", name: "Artikel", slug: "a", content: "<p>Indhold</p>", intro: "", topicID: "topic", mobileImageURL: imageURL, contentRevision: revision)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<2000 { if condition() { return }; try await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Local fixture did not settle")
    }
    private func audioStarts(_ transport: MediaTransport, atLeast count: Int) async throws -> Int {
        for _ in 0..<2000 {
            let observed = await transport.urls.count
            if observed >= count { return observed }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return await transport.urls.count
    }
    func testOldLeaseCannotReleaseReplacementOrOtherOwnersPinAndBytesRemain() async throws {
        let h = try MediaHarness(); let a = "favorites-v1:owner-a", b = "favorites-v1:owner-b"
        let old = UUID(), new = UUID(), other = UUID()
        h.audio.pinAndDownload(pinKey: a, leaseID: old, asset: asset(audioURL))
        h.audio.pinAndDownload(pinKey: a, leaseID: new, asset: asset(audioURL))
        h.audio.pinAndDownload(pinKey: b, leaseID: other, asset: asset(audioURL))
        h.audio.releasePinKeepingBytes(pinKey: a, leaseID: old, onlyIfAsset: asset(audioURL))
        XCTAssertTrue(h.audio.isPinned(articleId: a)); XCTAssertTrue(h.audio.isPinned(articleId: b))
        await h.transport.waitForStarts(1); try await h.transport.resolveAudio(0)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        h.audio.releasePinKeepingBytes(pinKey: a, leaseID: new, onlyIfAsset: asset(audioURL))
        XCTAssertFalse(h.audio.isPinned(articleId: a)); XCTAssertTrue(h.audio.isPinned(articleId: b))
        h.audio.releasePinKeepingBytes(pinKey: b, leaseID: other, onlyIfAsset: asset(audioURL))
        XCTAssertFalse(h.audio.isPinned(articleId: b)); XCTAssertTrue(h.audio.isDownloaded(for: asset(audioURL)))
    }
    func testLateReleaseWithOldURLCannotDropNewRevisionPin() async throws {
        let h = try MediaHarness(), key = "favorites-v1:owner-a"
        let old = UUID(), new = UUID(), newURL = URL(string: "https://audio.example.com/b.m4a")!
        h.audio.pinAndDownload(pinKey: key, leaseID: old, asset: asset(audioURL))
        h.audio.pinAndDownload(pinKey: key, leaseID: new, asset: asset(newURL))
        h.audio.releasePinKeepingBytes(pinKey: key, leaseID: old, onlyIfAsset: asset(audioURL))
        h.audio.releasePinKeepingBytes(pinKey: key, leaseID: new, onlyIfAsset: asset(audioURL))
        XCTAssertTrue(h.audio.isPinned(articleId: key)); await h.transport.waitForStarts(2)
        try await h.transport.resolveAudio(0); try await h.transport.resolveAudio(1)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(h.audio.isDownloaded(forArticleId: key)); XCTAssertTrue(h.audio.isDownloaded(for: asset(audioURL)))
    }
    func testOwnerReleaseDoesNotCancelSharedPublicDownloadOrRecreatePin() async throws {
        let h = try MediaHarness(), lease = UUID(), pin = "favorites-v1:owner-a"
        h.audio.pinAndDownload(pinKey: pin, leaseID: lease, asset: asset(audioURL))
        await h.transport.waitForStarts(1)
        h.audio.releasePinKeepingBytes(pinKey: pin, leaseID: lease, onlyIfAsset: asset(audioURL))
        XCTAssertFalse(h.audio.isPinned(articleId: pin)); XCTAssertEqual(h.audio.downloadActivity.active, 1)
        try await h.transport.resolveAudio(0); try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(h.audio.isDownloaded(for: asset(audioURL))); XCTAssertFalse(h.audio.isPinned(articleId: pin))
    }
    func testImageClearRejectsTransportThatCompletesAfterInvalidation() async throws {
        let h = try MediaHarness(); let cache = h.image()
        cache.scheduleCacheImages(for: article(), contentKey: key); await h.transport.waitForStarts(1)
        cache.removeAllCachedImages(); try await h.transport.resolveImage(0, bytes: [1])
        try await waitUntil { cache.downloadActivity == 0 }
        // A completion may still be unwinding; it has no live commit ticket.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(cache.localFileURL(forRemote: imageURL.absoluteString, contentKey: key))
        XCTAssertEqual(cache.totalCacheSizeBytes(), 0)
    }
    func testOldImageCompletionCannotCommitOverNewGenerationOrRemoveItsWork() async throws {
        let h = try MediaHarness(); let cache = h.image()
        cache.scheduleCacheImages(for: article(), contentKey: key); await h.transport.waitForStarts(1)
        cache.removeContent(key); cache.scheduleCacheImages(for: article(), contentKey: key)
        await h.transport.waitForStarts(2); try await h.transport.resolveImage(0, bytes: [1])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(cache.downloadActivity, 1)
        XCTAssertNil(cache.localFileURL(forRemote: imageURL.absoluteString, contentKey: key))
        try await h.transport.resolveImage(1, bytes: [2, 3]); try await waitUntil { cache.downloadActivity == 0 }
        let file = try XCTUnwrap(cache.localFileURL(forRemote: imageURL.absoluteString, contentKey: key))
        XCTAssertEqual(try Data(contentsOf: file), Data([2, 3]))
    }
    func testImageCacheRejectsUnsafeContentKeyAndInvalidMime() async throws {
        let h = try MediaHarness(); let cache = h.image()
        cache.scheduleCacheImages(for: article(), contentKey: "../../other-owner")
        XCTAssertEqual(cache.downloadActivity, 0)
        cache.scheduleCacheImages(for: article(), contentKey: key); await h.transport.waitForStarts(1)
        try await h.transport.resolveImage(0, bytes: [1], mime: "text/html")
        try await waitUntil { cache.downloadActivity == 0 }
        XCTAssertNil(cache.localFileURL(forRemote: imageURL.absoluteString, contentKey: key))
    }
    @MainActor
    func testInlineImageReplacementBoundsRepeatedSourceExpansion() async throws {
        let h = try MediaHarness()
        let acceptedKey = key
        let cache = h.image(online: { false }, contentKey: { _, revision in revision == "r1" ? acceptedKey : nil })
        cache.scheduleCacheImages(for: article(), contentKey: key); await h.transport.waitForStarts(1)
        try await h.transport.resolveImage(0, bytes: [UInt8](repeating: 1, count: 1024 * 1024))
        try await waitUntil { cache.downloadActivity == 0 }
        let one = "<img src='\(imageURL.absoluteString)'>"
        XCTAssertTrue(cache.prepareHTMLForOfflineDisplay(one, articleId: "a", expectedRevision: "r1").html.contains("data:image/jpeg;base64,"))
        let repeated = String(repeating: one, count: 20)
        let prepared = cache.prepareHTMLForOfflineDisplay(repeated, articleId: "a", expectedRevision: "r1").html
        XCTAssertEqual(prepared, repeated)
        XCTAssertFalse(prepared.contains("data:image"))
    }
    @MainActor
    func testInlineImageAggregateBudgetLeavesRemainingImagesAsRemoteFallback() async throws {
        let h = try MediaHarness(), acceptedKey = key
        let cache = h.image(online: { false }, contentKey: { _, revision in revision == "r1" ? acceptedKey : nil })
        let urls = ["a", "b", "c"].map { URL(string: "https://images.example.com/\($0).jpg")! }
        let value = Article(id: "a", name: "Artikel", slug: "a", content: "", intro: "", topicID: "topic", mobileImageURL: urls[0], thumbURL: urls[1], coverURL: urls[2], contentRevision: "r1")
        cache.scheduleCacheImages(for: value, contentKey: key)
        for id in 0..<3 {
            await h.transport.waitForStarts(id + 1)
            try await h.transport.resolveImage(id, bytes: [UInt8](repeating: 1, count: 1536 * 1024))
        }
        try await waitUntil { cache.downloadActivity == 0 }
        let html = urls.map { "<img src='\($0.absoluteString)'>" }.joined()
        let prepared = cache.prepareHTMLForOfflineDisplay(html, articleId: "a", expectedRevision: "r1").html
        XCTAssertEqual(prepared.components(separatedBy: "data:image/jpeg;base64,").count - 1, 2)
        XCTAssertTrue(prepared.contains("https://images.example.com/")); XCTAssertLessThan(prepared.utf8.count, 8 * 1024 * 1024)
    }
    @MainActor
    func testActualImageAdapterRequiresOriginalCurrentMemberRevisionEvenWhenBytesExist() async throws {
        let h = try MediaHarness(); var records: [FavoritesNamespace: FavoritesRecord] = [:]
        let model = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(records[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard records[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict));return }
                records[namespace] = record;completion(.success(()))
            }))
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article(), enabled: true)
        let bridge = FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }), permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil }, audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        let cache = h.image(online: { false }, contentKey: { id, revision in
            guard let revision, let ticket = bridge.captureAccess(articleID: id), ticket.contentRevision == revision else { return nil }; return ticket.contentKey
        }, preparationAccess: { id, revision in
            OfflineArticleImageCache.preparationAccess(bridge: bridge, articleID: id, revision: revision)
        })
        cache.scheduleCacheImages(for: article(), contentKey: original.contentKey); await h.transport.waitForStarts(1)
        try await h.transport.resolveImage(0, bytes: [4, 5]); try await waitUntil { cache.downloadActivity == 0 }
        let prepared = await cache.prepareDisplayURL(for: imageURL, access: cache.capturePreparationAccess(articleID: "a", revision: "r1"))
        XCTAssertTrue(try XCTUnwrap(prepared).isFileURL)
        XCTAssertTrue(try XCTUnwrap(cache.displayURL(for: imageURL, articleId: "a", expectedRevision: "r1")).isFileURL)
        XCTAssertEqual(cache.displayURL(for: imageURL, articleId: "a", expectedRevision: "old"), imageURL)
        XCTAssertEqual(cache.displayURL(for: imageURL, articleId: "a"), imageURL)
        model.changeContext(to: .guest); bridge.synchronizeCurrentMembership()
        XCTAssertEqual(cache.displayURL(for: imageURL, articleId: "a", expectedRevision: "r1"), imageURL)
        XCTAssertNotNil(cache.localFileURL(forRemote: imageURL.absoluteString, contentKey: original.contentKey))
    }
    @MainActor private func audioBridge(model: FavoritesModel, cache: PodcastAudioCache,
        accepted: @escaping @MainActor (Article) -> PodcastAudioAsset?,
        onPin: @escaping @MainActor () -> Void = {}) -> FavoritesOfflineCoordinator {
        FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }),
            permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: accepted,
                audioIsCached: { cache.isDownloaded(for: $0) }, pinAudio: { key, lease, asset in
                    cache.pinAndDownload(pinKey: key, leaseID: lease, asset: asset)
                    onPin()
                }, releaseAudio: { key, lease, asset in
                    cache.releasePinKeepingBytes(pinKey: key, leaseID: lease, onlyIfAsset: asset)
                }, scheduleRetry: { _, _ in {} }))
    }
    @MainActor func testActualModelToCacheRetriesFailedAudioForSameOriginalTicket() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL)
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        let model = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(records[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard records[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict)); return }
                records[namespace] = record; completion(.success(()))
            }))
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertTrue(bridge.cacheAudio(original, asset: accepted))
        let first = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(first, 1); guard first == 1 else { return }
        let failed = await h.transport.failAudio(0); XCTAssertTrue(failed)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertFalse(bridge.audioDownloaded(articleID: "a", expectedAsset: accepted))
        XCTAssertTrue(bridge.cacheAudio(original, asset: accepted))
        // Reconciliation/redraw alone must not spin a failed transport forever.
        XCTAssertEqual(h.audio.downloadState(for: accepted), .failed)
        let beforeRecovery = await h.transport.urls.count
        XCTAssertEqual(beforeRecovery, 1)
        // The foreground/online/user recovery path explicitly retries current pins.
        h.audio.retryPinnedDownloads()
        let retried = try await audioStarts(h.transport, atLeast: 2)
        XCTAssertEqual(retried, 2)
        guard retried == 2 else { return } // Bounded before-proof must not wait forever for an absent retry.
        try await h.transport.resolveAudio(1)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedAsset: accepted))
    }
    @MainActor private func favoriteModel() -> FavoritesModel {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        return FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(records[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard records[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict)); return }
                records[namespace] = record; completion(.success(()))
            }))
    }
    @MainActor func testActualModelToCacheRepeatedPendingAndCachedRequestsDoNotDuplicateDownload() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL), model = favoriteModel()
        model.changeContext(to: .guest); _ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        for _ in 0..<20 { XCTAssertTrue(bridge.cacheAudio(original, asset: accepted)) }
        let first = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(first, 1); guard first == 1 else { return }
        for _ in 0..<20 { XCTAssertTrue(bridge.cacheAudio(original, asset: accepted)) }
        let pendingStarts = await h.transport.urls.count
        XCTAssertEqual(pendingStarts, 1); XCTAssertEqual(h.audio.downloadActivity.active, 1)
        XCTAssertEqual(h.audio.downloadActivity.waiting, 0)
        try await h.transport.resolveAudio(0)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedAsset: accepted))
        for _ in 0..<20 { XCTAssertTrue(bridge.cacheAudio(original, asset: accepted)) }
        let cachedStarts = await h.transport.urls.count
        XCTAssertEqual(cachedStarts, 1); XCTAssertEqual(h.audio.downloadActivity.active, 0)
        XCTAssertEqual(h.audio.downloadActivity.waiting, 0)
        XCTAssertEqual(h.audio.validationActivity.active, 0); XCTAssertEqual(h.audio.validationActivity.waiting, 0)
    }
    @MainActor func testActualModelToCacheFailedRemovedTicketCannotRetryReaddedFavorite() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL), model = favoriteModel()
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertTrue(bridge.cacheAudio(original, asset: accepted))
        let first = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(first, 1); guard first == 1 else { return }
        let failed = await h.transport.failAudio(0); XCTAssertTrue(failed)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        _ = model.setFavorite(article(), enabled: false); bridge.synchronizeCurrentMembership()
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
        XCTAssertFalse(h.audio.isPinned(articleId: original.pinKey))
        _ = model.setFavorite(article(), enabled: true)
        let current = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertNotEqual(current.leaseID, original.leaseID)
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
        let beforeCurrent = await h.transport.urls.count; XCTAssertEqual(beforeCurrent, 1)
        XCTAssertTrue(bridge.cacheAudio(current, asset: accepted))
        let retried = try await audioStarts(h.transport, atLeast: 2)
        XCTAssertEqual(retried, 2); guard retried == 2 else { return }
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
        h.audio.releasePinKeepingBytes(pinKey: original.pinKey, leaseID: original.leaseID, onlyIfAsset: accepted)
        XCTAssertTrue(h.audio.isPinned(articleId: current.pinKey))
        try await h.transport.resolveAudio(1); try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedAsset: accepted))
    }
    @MainActor func testActualModelToCacheFailedTicketCannotRetryAfterAccountABA() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL), model = favoriteModel()
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertTrue(bridge.cacheAudio(original, asset: accepted))
        let first = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(first, 1); guard first == 1 else { return }
        let failed = await h.transport.failAudio(0); XCTAssertTrue(failed)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        model.changeContext(to: .confirmed(userID: "B")); bridge.synchronizeCurrentMembership()
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
        XCTAssertNil(bridge.captureAccess(articleID: "a"))
        model.changeContext(to: .confirmed(userID: "A"))
        let current = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertNotEqual(current.leaseID, original.leaseID)
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
        let beforeCurrent = await h.transport.urls.count; XCTAssertEqual(beforeCurrent, 1)
        XCTAssertTrue(bridge.cacheAudio(current, asset: accepted))
        let retried = try await audioStarts(h.transport, atLeast: 2)
        XCTAssertEqual(retried, 2); guard retried == 2 else { return }
        try await h.transport.resolveAudio(1); try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedAsset: accepted))
        XCTAssertFalse(bridge.cacheAudio(original, asset: accepted))
    }
    @MainActor func testActualModelToCacheFailedRevisionCannotRetryReplacementDescriptor() async throws {
        let h = try MediaHarness(), old = asset(audioURL), model = favoriteModel()
        let replacement = asset(URL(string: "https://audio.example.com/revised.m4a")!, revision: "r2")
        var accepted = old
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertTrue(bridge.cacheAudio(original, asset: old))
        let first = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(first, 1); guard first == 1 else { return }
        let failed = await h.transport.failAudio(0); XCTAssertTrue(failed)
        try await waitUntil { h.audio.downloadActivity.active == 0 }
        _ = model.setFavorite(article(), enabled: false)
        accepted = replacement; _ = model.setFavorite(article(revision: "r2"), enabled: true)
        // Direct capture avoids prefetch: only the explicit current descriptor may start the second transport.
        let current = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertFalse(bridge.cacheAudio(original, asset: old)); XCTAssertFalse(bridge.cacheAudio(current, asset: old))
        let beforeCurrent = await h.transport.urls.count; XCTAssertEqual(beforeCurrent, 1)
        XCTAssertFalse(h.audio.isPinned(articleId: original.pinKey))
        XCTAssertTrue(bridge.cacheAudio(current, asset: replacement))
        let retried = try await audioStarts(h.transport, atLeast: 2)
        XCTAssertEqual(retried, 2); guard retried == 2 else { return }
        let requestedURLs = await h.transport.urls
        XCTAssertEqual(requestedURLs, [old.remoteURL, replacement.remoteURL])
        try await h.transport.resolveAudio(1); try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedRevision: "r2", expectedAsset: replacement))
        XCTAssertFalse(h.audio.isDownloaded(for: old)); XCTAssertFalse(bridge.audioDownloaded(articleID: "a", expectedAsset: old))
    }
    @MainActor func testActualModelToCacheSamePinEffectReentryDoesNotRecurseOrDuplicateTransport() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL), model = favoriteModel()
        model.changeContext(to: .guest); _ = model.setFavorite(article(), enabled: true)
        var bridge: FavoritesOfflineCoordinator?, original: FavoritesOfflineCoordinator.AccessTicket?, pinEffects = 0
        bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted }, onPin: {
            pinEffects += 1
            if pinEffects < 4, let original { _ = bridge?.cacheAudio(original, asset: accepted) }
        })
        defer { bridge = nil }
        let coordinator = try XCTUnwrap(bridge)
        original = try XCTUnwrap(coordinator.captureAccess(articleID: "a"))
        XCTAssertTrue(coordinator.cacheAudio(try XCTUnwrap(original), asset: accepted))
        XCTAssertEqual(pinEffects, 1)
        let starts = try await audioStarts(h.transport, atLeast: 1)
        XCTAssertEqual(starts, 1); guard starts == 1 else { return }
        try await h.transport.resolveAudio(0); try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(coordinator.audioDownloaded(articleID: "a", expectedAsset: accepted))
    }
    @MainActor func testActualModelToCacheSharedAssetKeepsBPinAfterAReleaseAndLateReceipt() async throws {
        let h = try MediaHarness(), accepted = asset(audioURL)
        var recordsA: [FavoritesNamespace: FavoritesRecord] = [:], recordsB: [FavoritesNamespace: FavoritesRecord] = [:]
        let modelA = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(recordsA[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard recordsA[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict));return }
                recordsA[namespace] = record;completion(.success(()))
            }))
        let modelB = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(recordsB[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard recordsB[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict));return }
                recordsB[namespace] = record;completion(.success(()))
            }))
        modelA.changeContext(to: .confirmed(userID: "A"));modelB.changeContext(to: .confirmed(userID: "B"))
        _ = modelA.setFavorite(article(), enabled: true);_ = modelB.setFavorite(article(), enabled: true)
        let a = audioBridge(model: modelA, cache: h.audio, accepted: { _ in accepted })
        let b = audioBridge(model: modelB, cache: h.audio, accepted: { _ in accepted })
        let originalA = try XCTUnwrap(a.captureAccess(articleID: "a")), originalB = try XCTUnwrap(b.captureAccess(articleID: "a"))
        XCTAssertNotEqual(originalA.pinKey, originalB.pinKey)
        XCTAssertTrue(a.cacheAudio(originalA, asset: accepted));XCTAssertTrue(b.cacheAudio(originalB, asset: accepted))
        await h.transport.waitForStarts(1)
        modelA.changeContext(to: .guest);a.synchronizeCurrentMembership()
        XCTAssertFalse(h.audio.isPinned(articleId: originalA.pinKey));XCTAssertTrue(h.audio.isPinned(articleId: originalB.pinKey))
        try await h.transport.resolveAudio(0);try await waitUntil { h.audio.downloadActivity.active == 0 }
        XCTAssertTrue(b.audioDownloaded(articleID: "a", expectedAsset: accepted))
        XCTAssertFalse(a.audioDownloaded(articleID: "a", expectedAsset: accepted))
        XCTAssertFalse(a.cacheAudio(originalA, asset: accepted))
        h.audio.releasePinKeepingBytes(pinKey: originalA.pinKey, leaseID: originalA.leaseID, onlyIfAsset: accepted)
        XCTAssertTrue(h.audio.isPinned(articleId: originalB.pinKey));XCTAssertTrue(h.audio.isDownloaded(for: accepted))
    }
    @MainActor func testActualModelToCacheLateR1CannotAcknowledgeOrReleaseSameURLR2() async throws {
        let h = try MediaHarness(), old = asset(audioURL), replacement = asset(audioURL, revision: "r2")
        var records: [FavoritesNamespace: FavoritesRecord] = [:], accepted = old
        let model = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(records[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard records[namespace]?.recordRevision == expectedRevision else { completion(.failure(MediaStorageFailure.conflict));return }
                records[namespace] = record;completion(.success(()))
            }))
        model.changeContext(to: .guest);_ = model.setFavorite(article(), enabled: true)
        let bridge = audioBridge(model: model, cache: h.audio, accepted: { _ in accepted })
        let original = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        XCTAssertTrue(bridge.cacheAudio(original, asset: old));await h.transport.waitForStarts(1)
        _ = model.setFavorite(article(), enabled: false)
        let corrected = article(revision: "r2")
        _ = model.setFavorite(corrected, enabled: true);accepted = replacement
        bridge.synchronizeCurrentMembership()
        let current = try XCTUnwrap(bridge.captureAccess(articleID: "a"))
        await h.transport.waitForStarts(2)
        h.audio.invalidate([old])
        XCTAssertFalse(bridge.cacheAudio(original, asset: old));XCTAssertFalse(bridge.cacheAudio(current, asset: old))
        try await h.transport.resolveAudio(1);try await waitUntil { h.audio.isDownloaded(for: replacement) }
        XCTAssertTrue(bridge.audioDownloaded(articleID: "a", expectedRevision: "r2", expectedAsset: replacement))
        try await h.transport.resolveAudio(0);try await waitUntil { h.audio.downloadActivity.active == 0 }
        h.audio.releasePinKeepingBytes(pinKey: original.pinKey, leaseID: original.leaseID, onlyIfAsset: old)
        XCTAssertTrue(h.audio.isPinned(articleId: current.pinKey));XCTAssertTrue(h.audio.isDownloaded(for: replacement))
        XCTAssertFalse(h.audio.isDownloaded(for: old));XCTAssertFalse(bridge.audioDownloaded(articleID: "a", expectedAsset: old))
    }

}

private final class MediaHarness {
    let root: URL
    let transport: MediaTransport
    let audio: PodcastAudioCache
    private let defaults: UserDefaults
    private let suite: String
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        transport = MediaTransport(root: root)
        suite = "FavoritesMediaCacheTests-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let transport = transport
        audio = PodcastAudioCache(cacheDirectory: root.appendingPathComponent("audio"), defaults: defaults, download: { try await transport.audio($0) })
    }
    func image(online: (@MainActor () -> Bool)? = nil, contentKey: (@MainActor (String, String?) -> String?)? = nil,
               preparationAccess: (@MainActor (String, String?) -> OfflineArticleImageCache.PreparationAccess)? = nil) -> OfflineArticleImageCache {
        let transport = transport
        return OfflineArticleImageCache(cacheDirectory: root.appendingPathComponent("images"), download: { try await transport.image($0) }, online: online, contentKey: contentKey, preparationAccess: preparationAccess)
    }
    deinit { audio.removeAllCachedFiles(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}
private actor MediaTransport {
    let root: URL
    var urls: [URL] = []
    var audioContinuations: [Int: CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>] = [:]
    var imageContinuations: [Int: CheckedContinuation<OfflineArticleImageCache.Artifact, Error>] = [:]
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(root: URL) { self.root = root }
    private func signal() {
        let ready = waiters.filter { $0.0 <= urls.count }; waiters.removeAll { $0.0 <= urls.count }; ready.forEach { $0.1.resume() }
    }
    func audio(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        let id = urls.count; urls.append(url)
        return try await withCheckedThrowingContinuation { audioContinuations[id] = $0; signal() }
    }
    func image(_ url: URL) async throws -> OfflineArticleImageCache.Artifact {
        let id = urls.count; urls.append(url)
        return try await withCheckedThrowingContinuation { imageContinuations[id] = $0; signal() }
    }
    func waitForStarts(_ count: Int) async { if urls.count < count { await withCheckedContinuation { waiters.append((count, $0)) } } }
    func failAudio(_ id: Int) -> Bool {
        guard let continuation = audioContinuations.removeValue(forKey: id) else { return false }
        continuation.resume(throwing: URLError(.notConnectedToInternet)); return true
    }
    func resolveAudio(_ id: Int) throws {
        let file = root.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: file)
        let response = HTTPURLResponse(url: urls[id], statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mp4"])!
        audioContinuations.removeValue(forKey: id)?.resume(returning: .init(temporaryURL: file, response: response))
    }
    func resolveImage(_ id: Int, bytes: [UInt8], mime: String = "image/jpeg") throws {
        let response = HTTPURLResponse(url: urls[id], statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!
        imageContinuations.removeValue(forKey: id)?.resume(returning: .init(data: Data(bytes), response: response))
    }
}

private enum MediaStorageFailure: Error { case conflict }
