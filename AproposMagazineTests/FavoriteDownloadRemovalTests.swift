import Foundation
import FirebaseCore
import XCTest
@testable import Apropos

/// Real runtime/model, production adapter composition and temporary disk stores.
/// Transports hold local continuations; no URLSession, Firebase or player starts.
@MainActor
final class FavoriteDownloadRemovalTests: XCTestCase {
    func testRemovingCompletedFavoriteDeletesOnlyItsBodyImagesAndAudioFiles() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        let h = try RemovalHarness(); defer { h.close() }
        let a = removalArticle("a"), b = removalArticle("b")
        let first = try h.save(a), other = try h.save(b)
        try await h.finishMedia()
        try h.seedLegacyBody(a, ticket: first); try h.seedLegacyBody(b, ticket: other)
        try h.assertComplete(a, ticket: first); try h.assertComplete(b, ticket: other)
        let aFiles = try h.files(first, asset: removalAsset(a))
        let bFiles = try h.files(other, asset: removalAsset(b))
        XCTAssertGreaterThanOrEqual(aFiles.count, 8)
        XCTAssertGreaterThanOrEqual(bFiles.count, 8)

        // All production remove controls ultimately issue this exact API call.
        XCTAssertNotNil(h.runtime.setFavorite(a, enabled: false))
        await h.runtime.model.waitForStorage()
        let removed = try await eventually { try h.files(first, asset: removalAsset(a)).isEmpty }
        XCTAssertTrue(removed, "Explicit favorite removal must physically remove its body/size, image mapping/bytes and audio receipt/bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.imageDirectory.appendingPathComponent(first.contentKey).path))
        XCTAssertNil(h.offline.captureAccess(articleID: a.id))
        XCTAssertTrue(try h.files(first, asset: removalAsset(a)).isEmpty)
        XCTAssertEqual(try h.files(other, asset: removalAsset(b)), bFiles,
            "Another saved article's bytes and receipts must remain exactly unchanged")
        try h.assertComplete(b, ticket: other)

        let coldBodies = OfflineManager.BodyStorage(directory: h.bodyDirectory, legacyDirectory: h.legacyBodyDirectory)
        XCTAssertNil(try coldBodies.read(first.contentKey), "The retained legacy body must not resurrect on a cold read")
        let coldAudio = h.coldAudio()
        let restored = await coldAudio.prepare(removalAsset(a))
        XCTAssertFalse(restored, "A fresh validator must not recover the removed recording from a retained receipt")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testRemovingWhileMediaIsInFlightRejectsLateDiskRecreation() async throws {
        let h = try RemovalHarness(); defer { h.close() }
        let article = removalArticle("a"), asset = removalAsset(article)
        let old = try h.save(article, storeBody: false)
        var bodyCompletion: (@MainActor (Result<Article, Error>) -> Void)?
        XCTAssertTrue(h.offline.requestBody(ticket: old, fetch: { _, completion in bodyCompletion = completion }))
        XCTAssertNotNil(bodyCompletion)
        let started = try await eventually { h.transport.pendingAudioCount > 0 && h.transport.pendingImageCount > 0 }
        XCTAssertTrue(started, "Both real cache adapters must reach their held local transports before removal")

        XCTAssertNotNil(h.runtime.setFavorite(article, enabled: false))
        bodyCompletion?(.success(article))
        try await h.finishMedia()
        let removed = try await eventually { try h.files(old, asset: asset).isEmpty }
        XCTAssertTrue(removed, "Late completed media must not recreate files after explicit removal")
        XCTAssertFalse(h.offline.isCurrent(old))
        XCTAssertNil(h.offline.captureAccess(articleID: article.id))
        XCTAssertFalse(h.offline.saveBody(article, ticket: old))
        XCTAssertFalse(h.audio.isPinned(articleId: old.pinKey))
        XCTAssertTrue(try h.files(old, asset: asset).isEmpty)
        XCTAssertFalse(try h.bodies.contains(old.contentKey))
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testRemoveThenReaddKeepsNewLeaseAndRejectsOriginalLateBody() async throws {
        let h = try RemovalHarness(); defer { h.close() }
        let article = removalArticle("a"), asset = removalAsset(article)
        let old = try h.save(article, storeBody: false)
        var oldBodyCompletion: (@MainActor (Result<Article, Error>) -> Void)?
        XCTAssertTrue(h.offline.requestBody(ticket: old, fetch: { _, completion in oldBodyCompletion = completion }))
        let started = try await eventually { h.transport.pendingAudioCount > 0 && h.transport.pendingImageCount > 0 }
        XCTAssertTrue(started)
        XCTAssertNotNil(h.runtime.setFavorite(article, enabled: false))
        let current = try h.save(article)
        XCTAssertNotEqual(old.leaseID, current.leaseID)
        XCTAssertFalse(h.offline.isCurrent(old)); XCTAssertTrue(h.offline.isCurrent(current))
        let stale = removalArticle(article.id, name: "Old delayed body must not replace the newly saved article")
        oldBodyCompletion?(.success(stale))
        try await h.finishMedia()

        try h.assertComplete(article, ticket: current)
        XCTAssertEqual(h.offline.body(current)?.name, article.name)
        XCTAssertTrue(h.audio.isPinned(articleId: current.pinKey))
        XCTAssertTrue(h.offline.audioDownloaded(articleID: article.id, expectedAsset: asset))
        XCTAssertFalse(h.offline.saveBody(stale, ticket: old))
        XCTAssertTrue(h.offline.isCurrent(current))
        XCTAssertFalse(try h.files(current, asset: asset).isEmpty)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testAccountSwitchKeepsDownloadedBytesWithoutGrantingTheOtherOwnerAccess() async throws {
        let h = try RemovalHarness(); defer { h.close() }
        let a = removalArticle("a"), b = removalArticle("b")
        let first = try h.save(a)
        try await h.finishMedia(); try h.seedLegacyBody(a, ticket: first)
        try h.assertComplete(a, ticket: first)
        let original = try h.files(first, asset: removalAsset(a))
        let starts = h.transport.audioStarts

        h.runtime.suspendForAccountChange()
        XCTAssertNil(h.offline.captureAccess(articleID: a.id))
        XCTAssertEqual(try h.files(first, asset: removalAsset(a)), original)
        h.runtime.changeAccountContext(userID: "local-owner-b")
        XCTAssertNil(h.offline.body(articleID: a.id))
        let second = try h.save(b)
        try await h.finishMedia()
        try h.assertComplete(b, ticket: second)
        let other = try h.files(second, asset: removalAsset(b))
        XCTAssertEqual(try h.files(first, asset: removalAsset(a)), original)

        h.runtime.changeAccountContext(userID: "local-owner-a")
        let restored = try XCTUnwrap(h.offline.captureAccess(articleID: a.id))
        let ready = try await eventually { h.offline.audioDownloaded(articleID: a.id, expectedAsset: removalAsset(a)) }
        XCTAssertTrue(ready)
        XCTAssertNotEqual(restored.leaseID, first.leaseID)
        XCTAssertNotNil(h.offline.body(restored))
        XCTAssertEqual(try h.files(first, asset: removalAsset(a)), original)
        XCTAssertEqual(try h.files(second, asset: removalAsset(b)), other)
        XCTAssertEqual(h.transport.audioStarts, starts + 1, "Only B downloads; returning to A reuses its still-owned public file")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testResolverReentryCannotRemoveNewlyReaddedSameRevisionDownloads() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        let h = try RemovalHarness(); defer { h.close() }
        let a = removalArticle("a"), b = removalArticle("b")
        let old = try h.save(a), other = try h.save(b)
        try await h.finishMedia()
        try h.assertComplete(a, ticket: old); try h.assertComplete(b, ticket: other)
        let otherFiles = try h.files(other, asset: removalAsset(b))
        let replacement = removalArticle(a.id, name: "Saved again during descriptor lookup")
        var lookupCount = 0
        var replacementTicket: FavoritesOfflineCoordinator.AccessTicket?
        var callbackError: Error?

        // Keep membership and public disk bytes, but force removal capture to
        // resolve the accepted descriptor without an already held audio pin.
        h.offline.releaseCurrentAccess()
        h.hooks.beforeAudioAsset = { article in
            guard article.id == a.id else { return }
            h.hooks.beforeAudioAsset = nil
            lookupCount += 1
            do {
                XCTAssertNotNil(h.runtime.setFavorite(a, enabled: false))
                replacementTicket = try h.save(replacement)
            } catch { callbackError = error }
        }

        let staleRemoval = h.runtime.setFavorite(a, enabled: false)
        if let callbackError { throw callbackError }
        XCTAssertEqual(lookupCount, 1, "The real cold asset resolver must perform the nested remove/re-save")
        XCTAssertNil(staleRemoval, "The original tap must not remove the membership created during its lookup")
        let current = try XCTUnwrap(replacementTicket)
        XCTAssertEqual(current.contentKey, old.contentKey, "The replacement deliberately reuses the exact same revision and disk key")
        XCTAssertNotEqual(current.leaseID, old.leaseID)
        XCTAssertTrue(h.offline.isCurrent(current)); XCTAssertFalse(h.offline.isCurrent(old))
        try await h.finishMedia()

        try h.assertComplete(replacement, ticket: current)
        XCTAssertEqual(try h.bodies.read(current.contentKey)?.name, replacement.name)
        XCTAssertEqual(h.offline.body(current)?.name, replacement.name)
        XCTAssertTrue(h.audio.isPinned(articleId: current.pinKey))
        XCTAssertFalse(h.offline.saveBody(a, ticket: old))
        XCTAssertEqual(try h.files(other, asset: removalAsset(b)), otherFiles)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testReaddDuringFinalAudioCleanupPreservesNewPinAndActualFiles() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        let h = try RemovalHarness(); defer { h.close() }
        let a = removalArticle("a"), b = removalArticle("b")
        let old = try h.save(a), other = try h.save(b)
        try await h.finishMedia()
        try h.assertComplete(a, ticket: old); try h.assertComplete(b, ticket: other)
        let otherFiles = try h.files(other, asset: removalAsset(b))
        let originalAudio = try h.files(old, asset: removalAsset(a)).filter { $0.key.hasPrefix("audio/assets-v2/") }
        XCTAssertGreaterThanOrEqual(originalAudio.count, 2)
        let oldBody = h.bodyDirectory.appendingPathComponent(old.contentKey + ".json")
        let replacement = removalArticle(a.id, name: "Saved again inside final audio cleanup")
        var cleanupCount = 0
        var replacementTicket: FavoritesOfflineCoordinator.AccessTicket?
        var callbackError: Error?

        h.hooks.beforeAudioProvider = {
            // Earlier ordinary unpin calls this same production provider. Only
            // reenter after body removal, at the final per-asset cleanup effect.
            guard h.runtime.model.membershipTicket(articleID: a.id) == nil,
                  !FileManager.default.fileExists(atPath: oldBody.path) else { return }
            h.hooks.beforeAudioProvider = nil
            cleanupCount += 1
            do {
                replacementTicket = try h.save(replacement)
                XCTAssertTrue(h.audio.isPinned(articleId: try XCTUnwrap(replacementTicket).pinKey))
            } catch { callbackError = error }
        }

        let removal = try XCTUnwrap(h.runtime.setFavorite(a, enabled: false))
        if let callbackError { throw callbackError }
        XCTAssertEqual(cleanupCount, 1, "The actual cache provider must re-save before removeUnpinnedAudio executes")
        let current = try XCTUnwrap(replacementTicket)
        XCTAssertEqual(current.contentKey, old.contentKey)
        XCTAssertNotEqual(current.leaseID, old.leaseID)
        XCTAssertFalse(h.runtime.model.isCurrent(removal))
        XCTAssertTrue(h.offline.isCurrent(current)); XCTAssertFalse(h.offline.isCurrent(old))
        try await h.finishMedia()

        try h.assertComplete(replacement, ticket: current)
        XCTAssertEqual(try h.bodies.read(current.contentKey)?.name, replacement.name)
        XCTAssertEqual(h.offline.body(current)?.name, replacement.name)
        XCTAssertTrue(h.audio.isPinned(articleId: current.pinKey))
        XCTAssertFalse(h.offline.saveBody(a, ticket: old))
        XCTAssertEqual(try h.files(current, asset: removalAsset(a)).filter { $0.key.hasPrefix("audio/assets-v2/") }, originalAudio,
            "The new pin must protect the exact recording bytes and receipt from the old cleanup")
        XCTAssertEqual(try h.files(other, asset: removalAsset(b)), otherFiles)
        XCTAssertNil(FirebaseApp.allApps)
    }

    private func eventually(_ condition: () throws -> Bool) async throws -> Bool {
        for _ in 0..<200 {
            if try condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try condition()
    }
}

private func removalArticle(_ id: String, name: String? = nil) -> Article {
    Article(id: id, name: name ?? "Local saved article " + id, slug: id, content: "<p>Local body " + id + "</p>",
        intro: "Only temporary test bytes", topicID: "local",
        mobileImageURL: URL(string: "https://images.example.invalid/" + id + ".jpg"),
        isDraft: false, isArchived: false, lastPublished: "2026-11-03T12:00:00Z", contentRevision: "r1")
}

private func removalAsset(_ article: Article) -> PodcastAudioAsset {
    PodcastAudioAsset(episodeID: "local-audio-" + article.id, canonicalArticleID: article.id,
        kind: .human, sourceRevision: article.bodyRevision!,
        remoteURL: URL(string: "https://audio.example.invalid/" + article.id + ".m4a")!)!
}

@MainActor
private final class RemovalHooks {
    var beforeAudioAsset: (@MainActor (Article) -> Void)?
    var beforeAudioProvider: (@MainActor () -> Void)?
}

@MainActor
private final class RemovalHarness {
    let root: URL
    let bodyDirectory: URL
    let legacyBodyDirectory: URL
    let imageDirectory: URL
    let audioDirectory: URL
    let bodies: OfflineManager.BodyStorage
    let images: OfflineArticleImageCache
    let audio: PodcastAudioCache
    let transport: RemovalTransport
    let runtime: FavoritesRuntime
    let hooks: RemovalHooks
    private let defaults: UserDefaults
    private let suite: String
    var offline: FavoritesOfflineCoordinator { runtime.offline! }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FavoriteDownloadRemoval-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        bodyDirectory = root.appendingPathComponent("bodies")
        legacyBodyDirectory = root.appendingPathComponent("legacy-bodies")
        imageDirectory = root.appendingPathComponent("images")
        audioDirectory = root.appendingPathComponent("audio")
        let bodies = OfflineManager.BodyStorage(directory: bodyDirectory, legacyDirectory: legacyBodyDirectory)
        self.bodies = bodies
        let transport = RemovalTransport(directory: root.appendingPathComponent("transport")); self.transport = transport
        let images = OfflineArticleImageCache(cacheDirectory: imageDirectory,
            download: { try await transport.image($0) }, online: { false }, contentKey: { _, _ in nil })
        self.images = images
        suite = "FavoriteDownloadRemoval-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let audio = PodcastAudioCache(cacheDirectory: audioDirectory, defaults: defaults,
            download: { try await transport.audio($0) })
        self.audio = audio
        let hooks = RemovalHooks(); self.hooks = hooks
        let journal = RemovalJournal()
        runtime = FavoritesRuntime(disabled: false, requiresAccountForSaving: true,
            storageFactory: { journal.storage }, drainPendingWrites: { _ in }, writeFavorite: { _, _ in },
            offlineFactory: { model in
                OfflineManager.makeFavoritesCoordinator(model: model, bodies: bodies, images: { images },
                    audio: { hooks.beforeAudioProvider?(); return audio },
                    permitsBody: { _ in true }, audioAsset: { article in
                        hooks.beforeAudioAsset?(article); return removalAsset(article)
                    }, scheduleRetry: { _, _ in {} })
            }, profileSet: { _, _, _ in })
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "local-owner-a")
    }

    func save(_ article: Article, storeBody: Bool = true) throws -> FavoritesOfflineCoordinator.AccessTicket {
        XCTAssertNotNil(runtime.setFavorite(article, enabled: true))
        let ticket = try XCTUnwrap(offline.captureAccess(articleID: article.id))
        if storeBody { XCTAssertTrue(offline.saveBody(article, ticket: ticket)) }
        return ticket
    }

    func seedLegacyBody(_ article: Article, ticket: FavoritesOfflineCoordinator.AccessTicket) throws {
        let legacy = OfflineManager.BodyStorage(directory: legacyBodyDirectory)
        try legacy.write(ticket.contentKey, article: article)
        XCTAssertTrue(try legacy.contains(ticket.contentKey))
    }

    func finishMedia() async throws {
        for _ in 0..<400 {
            try transport.completePending()
            if audio.downloadActivity.active == 0 && audio.downloadActivity.waiting == 0
                && audio.validationActivity.active == 0 && audio.validationActivity.waiting == 0
                && images.downloadActivity == 0 && transport.pendingAudioCount == 0 && transport.pendingImageCount == 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("The bounded local transports did not settle")
    }

    func assertComplete(_ article: Article, ticket: FavoritesOfflineCoordinator.AccessTicket,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try bodies.contains(ticket.contentKey), file: file, line: line)
        XCTAssertEqual(try bodies.read(ticket.contentKey)?.id, article.id, file: file, line: line)
        let image = images.localFileURL(forRemote: article.mobileImageURL!.absoluteString, contentKey: ticket.contentKey)
        XCTAssertNotNil(image, file: file, line: line)
        if let image { XCTAssertFalse(try Data(contentsOf: image).isEmpty, file: file, line: line) }
        let asset = removalAsset(article)
        XCTAssertTrue(offline.audioDownloaded(articleID: article.id, expectedAsset: asset), file: file, line: line)
        let playback = audio.resolvePlaybackURL(for: asset)
        XCTAssertEqual(playback.cacheResult, .hit, file: file, line: line)
        if playback.cacheResult == .hit { XCTAssertFalse(try Data(contentsOf: playback.url).isEmpty, file: file, line: line) }
        let receipt = audioDirectory.appendingPathComponent("assets-v2").appendingPathComponent(asset.key + ".json")
        XCTAssertEqual(try PodcastAudioReceipt.decode(Data(contentsOf: receipt), expectedAsset: asset).asset, asset, file: file, line: line)
    }

    func files(_ ticket: FavoritesOfflineCoordinator.AccessTicket, asset: PodcastAudioAsset) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var result: [String: Data] = [:]
        for case let path as URL in enumerator {
            let body = [ticket.contentKey + ".json", ticket.contentKey + ".json.size"].contains(path.lastPathComponent)
                && [bodyDirectory, legacyBodyDirectory].map { $0.standardizedFileURL.path }.contains(path.deletingLastPathComponent().standardizedFileURL.path)
            let image = path.path.hasPrefix(imageDirectory.appendingPathComponent(ticket.contentKey).path + "/")
            let audio = path.deletingLastPathComponent().standardizedFileURL.path == audioDirectory.appendingPathComponent("assets-v2").standardizedFileURL.path
                && (path.lastPathComponent == asset.key + ".json" || path.lastPathComponent.hasPrefix(asset.key + "-"))
            guard body || image || audio else { continue }
            do {
                guard try path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                result[String(path.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: path)
            } catch {
                // An actual asynchronous deletion can retire an enumerated
                // file between stat and read. Every other disk error is real.
                let error = error as NSError
                let gone = error.domain == NSCocoaErrorDomain
                    && [CocoaError.Code.fileNoSuchFile.rawValue, CocoaError.Code.fileReadNoSuchFile.rawValue].contains(error.code)
                    || error.domain == NSPOSIXErrorDomain && error.code == 2
                if !gone { throw error }
            }
        }
        return result
    }

    func coldAudio() -> PodcastAudioCache {
        PodcastAudioCache(cacheDirectory: audioDirectory, defaults: defaults,
            download: { _ in throw RemovalFailure.unexpectedDownload })
    }

    func close() {
        hooks.beforeAudioAsset = nil; hooks.beforeAudioProvider = nil
        audio.removeAllCachedFiles(); images.removeAllCachedImages(); transport.cancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class RemovalJournal {
    private var records: [FavoritesNamespace: FavoritesRecord] = [:]
    var storage: FavoritesModel.Storage {
        .init(read: { [self] namespace, complete in complete(.success(records[namespace])) },
            write: { [self] namespace, record, expected, complete in
                guard records[namespace]?.recordRevision == expected else { complete(.failure(RemovalFailure.journalConflict)); return }
                records[namespace] = record; complete(.success(()))
            })
    }
}

private enum RemovalFailure: Error { case journalConflict, unexpectedDownload }

/// Cancellation deliberately does not finish a held download: the tests deliver
/// its actual late callback. Locking keeps these local continuations Sendable.
private final class RemovalTransport: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private var next = 0
    private var closed = false
    private var audioRequests = 0
    private var audioWork: [Int: (URL, CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>)] = [:]
    private var imageWork: [Int: (URL, CheckedContinuation<OfflineArticleImageCache.Artifact, Error>)] = [:]
    init(directory: URL) { self.directory = directory }
    var pendingAudioCount: Int { lock.withLock { audioWork.count } }
    var pendingImageCount: Int { lock.withLock { imageWork.count } }
    var audioStarts: Int { lock.withLock { audioRequests } }

    func audio(_ url: URL) async throws -> PodcastAudioCache.DownloadArtifact {
        try await withCheckedThrowingContinuation { complete in
            lock.withLock {
                guard !closed else { complete.resume(throwing: CancellationError()); return }
                let id = next; next += 1; audioRequests += 1; audioWork[id] = (url, complete)
            }
        }
    }
    func image(_ url: URL) async throws -> OfflineArticleImageCache.Artifact {
        try await withCheckedThrowingContinuation { complete in
            lock.withLock {
                guard !closed else { complete.resume(throwing: CancellationError()); return }
                let id = next; next += 1; imageWork[id] = (url, complete)
            }
        }
    }
    func completePending() throws {
        let work = lock.withLock { () -> ([(URL, CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>)], [(URL, CheckedContinuation<OfflineArticleImageCache.Artifact, Error>)]) in
            let value = (Array(audioWork.values), Array(imageWork.values)); audioWork.removeAll(); imageWork.removeAll(); return value
        }
        for (url, complete) in work.0 {
            let file = directory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = Data([1, 2, 3, 4]); try data.write(to: file)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "audio/mp4", "Content-Length": String(data.count)])!
                complete.resume(returning: .init(temporaryURL: file, response: response))
            } catch { complete.resume(throwing: error) }
        }
        for (url, complete) in work.1 {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"])!
            complete.resume(returning: .init(data: Data([5, 6, 7]), response: response))
        }
    }
    func cancel() {
        let work = lock.withLock { () -> ([(URL, CheckedContinuation<PodcastAudioCache.DownloadArtifact, Error>)], [(URL, CheckedContinuation<OfflineArticleImageCache.Artifact, Error>)]) in
            closed = true
            let value = (Array(audioWork.values), Array(imageWork.values)); audioWork.removeAll(); imageWork.removeAll(); return value
        }
        for (_, complete) in work.0 { complete.resume(throwing: CancellationError()) }
        for (_, complete) in work.1 { complete.resume(throwing: CancellationError()) }
    }
}
