import XCTest
import FirebaseCore
import Combine
@testable import Apropos

@MainActor
final class OfflineBodyStorageProbeTests: XCTestCase {
    private let key = String(repeating: "a", count: 64)

    private func probe(_ storage: OfflineManager.BodyStorage, key: String) async -> Result<Bool, Error> {
        await withCheckedContinuation { continuation in
            storage.probe(key) { result in
                XCTAssertTrue(Thread.isMainThread, "Display results must return to their main-actor owner")
                continuation.resume(returning: result)
            }
        }
    }

    private func article() -> Article {
        Article(id: "probe", name: "Lokal artikel", slug: "probe", content: "<p>Gemte ord</p>",
                intro: "", topicID: "culture", contentRevision: "local-r1")
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("offline-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Obtain the real descriptor through the existing account/membership
    /// boundary rather than reproducing the content-key algorithm in this test.
    private func contentKey(for article: Article) throws -> String {
        let model = FavoritesModel(storage: .init(read: { _ in nil }, write: { _, _ in }))
        model.changeContext(to: .confirmed(userID: "body-probe-reader"))
        XCTAssertNotNil(model.setFavorite(article, enabled: true))
        let coordinator = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { _ in nil }, write: { _, _ in }), permitsBody: { _ in true },
            effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                audioIsCached: { _ in false }, pinAudio: { _, _, _ in },
                releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        return try XCTUnwrap(coordinator.captureAccess(articleID: article.id)).contentKey
    }

    private func coordinator(model: FavoritesModel, storage: OfflineManager.BodyStorage) -> FavoritesOfflineCoordinator {
        FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { try storage.read($0) }, write: { try storage.write($0, article: $1) },
                contains: { try storage.contains($0) }, probe: { key, done in storage.probe(key, complete: done) }),
            permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in },
                audioAsset: { _ in nil }, audioIsCached: { _ in false }, pinAudio: { _, _, _ in },
                releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
    }

    private func prepare(_ ticket: FavoritesOfflineCoordinator.AccessTicket,
                         coordinator: FavoritesOfflineCoordinator) async {
        let done = expectation(description: "Actual body-storage probe completed")
        var completed = false
        let observation = coordinator.bodyChanges.sink {
            let state = coordinator.bodyState(ticket: ticket)
            if !completed, state == .available || state == .notDownloaded || state == .failed {
                completed = true
                done.fulfill()
            }
        }
        XCTAssertTrue(coordinator.prepareBodyStatus(ticket: ticket, force: true))
        await fulfillment(of: [done], timeout: 5)
        observation.cancel()
    }

    func testMatchingLengthCorruptJSONDoesNotClaimReadableBody() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let path = root.appendingPathComponent(key + ".json")
        let original = try Data(contentsOf: path)
        try Data(repeating: 120, count: original.count).write(to: path, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: path).count, original.count)
        XCTAssertFalse(try storage.contains(key), "A matching byte count cannot prove decodable article text")
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get(), "The actual background status adapter must reject corrupt text")
        XCTAssertThrowsError(try storage.read(key))
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testMatchingLengthWrongRevisionDoesNotClaimCurrentBody() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let path = root.appendingPathComponent(key + ".json")
        let original = try Data(contentsOf: path)
        let replacement = Data(String(decoding: original, as: UTF8.self)
            .replacingOccurrences(of: "\"local-r1\"", with: "\"local-r2\"").utf8)
        XCTAssertEqual(replacement.count, original.count)
        XCTAssertEqual(try JSONDecoder().decode(Article.self, from: replacement).bodyRevision, "local-r2")
        try replacement.write(to: path, options: .atomic)
        XCTAssertFalse(try storage.contains(key), "A decodable different revision cannot satisfy the current descriptor")
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertThrowsError(try storage.read(key), "Opening must reject the same wrong descriptor as status")
    }

    func testMatchingLengthWrongArticleDoesNotClaimCurrentBody() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let path = root.appendingPathComponent(key + ".json")
        let original = try Data(contentsOf: path)
        let replacement = Data(String(decoding: original, as: UTF8.self)
            .replacingOccurrences(of: "\"probe\"", with: "\"other\"").utf8)
        XCTAssertEqual(replacement.count, original.count)
        XCTAssertEqual(try JSONDecoder().decode(Article.self, from: replacement).id, "other")
        try replacement.write(to: path, options: .atomic)
        XCTAssertFalse(try storage.contains(key), "Another article's bytes cannot satisfy this descriptor")
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertThrowsError(try storage.read(key))
    }

    func testDecodedEmptyBodyDoesNotClaimReadableText() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        let bytes = try JSONEncoder().encode(article().strippingBodyContent())
        try bytes.write(to: root.appendingPathComponent(key + ".json"), options: .atomic)
        try Data(String(bytes.count).utf8).write(to: root.appendingPathComponent(key + ".json.size"), options: .atomic)
        XCTAssertFalse(try storage.contains(key), "Metadata-only article JSON is not downloaded text")
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertThrowsError(try storage.read(key))
    }

    func testActualProbeWorkRunsOffMainAndReturnsOriginalKeyOnMainWithoutServices() async throws {
        let storage = OfflineManager.BodyStorage(probeCheck: { key in
            XCTAssertFalse(Thread.isMainThread, "Filesystem status validation must not run on the drawing thread")
            return key == "original-key"
        })
        let result = await probe(storage, key: "original-key")
        XCTAssertTrue(try result.get())
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testSavedBodyAndMarkerAreAcceptedByActualBackgroundAdapter() async throws {
        let storage = OfflineManager.BodyStorage(directory: try directory())
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let result = await probe(storage, key: key)
        XCTAssertTrue(try result.get())
        XCTAssertEqual(try storage.read(key)?.content, article().content)
    }

    func testRemovedBodyIsNotAvailableEvenWhenMarkerSurvives() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        try FileManager.default.removeItem(at: root.appendingPathComponent(key + ".json"))
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertNil(try storage.read(key))
    }

    func testChangedBodyLengthIsRejectedByFreshProbe() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let before = await probe(storage, key: key)
        XCTAssertTrue(try before.get())
        try Data("changed".utf8).write(to: root.appendingPathComponent(key + ".json"), options: .atomic)
        let after = await probe(storage, key: key)
        XCTAssertFalse(try after.get())
    }

    func testMissingMarkerDoesNotClaimAvailabilityFromBodyBytesAlone() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        try FileManager.default.removeItem(at: root.appendingPathComponent(key + ".json.size"))
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
    }

    func testOversizedAndMalformedMarkersAreRejectedWithoutReadingFullBody() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        for marker in [String(repeating: "1", count: 21), "-1", "unknown", "999999999"] {
            try Data(marker.utf8).write(to: root.appendingPathComponent(key + ".json.size"), options: .atomic)
            let result = await probe(storage, key: key)
            XCTAssertFalse(try result.get(), marker)
        }
    }

    func testInvalidKeyFailsWithoutCreatingFilesystemContent() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let result = await probe(storage, key: "../unowned")
        if case .success = result { XCTFail("Invalid original key must be rejected") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testMatchingSizeIndexIsNotADecodeOrAccessProof() async throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let invalid = Data("not-json".utf8)
        try invalid.write(to: root.appendingPathComponent(key + ".json"))
        try Data(String(invalid.count).utf8).write(to: root.appendingPathComponent(key + ".json.size"))
        let result = await probe(storage, key: key)
        // Before 152 this deliberately documented the size-only index. The
        // reproduced false-ready bug requires decoding and descriptor proof too.
        XCTAssertFalse(try result.get(), "A matching size index is not readable downloaded text")
        XCTAssertThrowsError(try storage.read(key), "Actual opening must still decode content independently")
    }

    func testValid151BodyIsCopiedExactlyAndColdReadableFromDurableDirectory() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        let key = try contentKey(for: article())
        let old = OfflineManager.BodyStorage(directory: legacy)
        try old.write(key, article: article())
        let oldBody = legacy.appendingPathComponent(key + ".json"), oldMarker = oldBody.appendingPathExtension("size")
        let bodyBytes = try Data(contentsOf: oldBody), markerBytes = try Data(contentsOf: oldMarker)
        let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        let result = await probe(storage, key: key)
        XCTAssertTrue(try result.get())
        let newBody = durable.appendingPathComponent(key + ".json"), newMarker = newBody.appendingPathExtension("size")
        XCTAssertEqual(try Data(contentsOf: newBody), bodyBytes)
        XCTAssertEqual(try Data(contentsOf: newMarker), markerBytes)
        XCTAssertEqual(try Data(contentsOf: oldBody), bodyBytes, "Ordinary migration preserves the 151 source")
        XCTAssertEqual(try Data(contentsOf: oldMarker), markerBytes)
        XCTAssertEqual(try durable.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try newBody.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try newMarker.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #if os(iOS) && !targetEnvironment(simulator)
        // The simulator reports no protection attribute for these real files.
        // Backup exclusion is checked above; physical lock/protection remains
        // a separate device acceptance rather than a simulator pass claim.
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: newBody.path)[.protectionKey] as? FileProtectionType,
                       .completeUntilFirstUserAuthentication)
        #endif
        // Simulate the OS evicting only the old cache after promotion.
        try FileManager.default.removeItem(at: legacy)
        let cold = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        XCTAssertEqual(try cold.read(key)?.content, article().content)
        XCTAssertTrue(try cold.contains(key))
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testLegacy151WrongRevisionAndCorruptSameSizeAreNotPromoted() async throws {
        for corruptJSON in [false, true] {
            let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
            let key = try contentKey(for: article())
            try OfflineManager.BodyStorage(directory: legacy).write(key, article: article())
            let path = legacy.appendingPathComponent(key + ".json"), marker = path.appendingPathExtension("size")
            let original = try Data(contentsOf: path), markerBytes = try Data(contentsOf: marker)
            let changed = corruptJSON ? Data(repeating: 120, count: original.count) :
                Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"local-r1\"", with: "\"local-r2\"").utf8)
            XCTAssertEqual(changed.count, original.count)
            try changed.write(to: path, options: .atomic)
            let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
            let result = await probe(storage, key: key)
            XCTAssertFalse(try result.get())
            XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path), "Invalid old bytes must never be promoted")
            XCTAssertEqual(try Data(contentsOf: path), changed)
            XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
            XCTAssertThrowsError(try storage.read(key))
        }
    }

    func testLegacy151WithoutMarkerIsNotPromotedAndInjectedDirectoryStaysIsolated() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        let key = try contentKey(for: article())
        try OfflineManager.BodyStorage(directory: legacy).write(key, article: article())
        let path = legacy.appendingPathComponent(key + ".json")
        let bytes = try Data(contentsOf: path)
        let isolated = OfflineManager.BodyStorage(directory: durable)
        XCTAssertNil(try isolated.read(key), "An injected store cannot discover any implicit real or fixture cache")
        try FileManager.default.removeItem(at: path.appendingPathExtension("size"))
        let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertNil(try storage.read(key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testLegacyMigrationNeverReplacesExistingWrongDurableDescriptorOrMarker() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        let key = try contentKey(for: article())
        try OfflineManager.BodyStorage(directory: legacy).write(key, article: article())
        let legacyBody = legacy.appendingPathComponent(key + ".json")
        let legacyBytes = try Data(contentsOf: legacyBody)
        try OfflineManager.BodyStorage(directory: durable).write(key, article: article())
        let current = durable.appendingPathComponent(key + ".json"), marker = current.appendingPathExtension("size")
        let original = try Data(contentsOf: current), markerBytes = try Data(contentsOf: marker)
        let wrong = Data(String(decoding: original, as: UTF8.self)
            .replacingOccurrences(of: "\"local-r1\"", with: "\"local-r2\"").utf8)
        XCTAssertEqual(wrong.count, original.count)
        try wrong.write(to: current, options: .atomic)
        let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertThrowsError(try storage.read(key))
        XCTAssertEqual(try Data(contentsOf: current), wrong)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(try Data(contentsOf: legacyBody), legacyBytes, "Compare the actual source bytes, not a second JSON encoding")
    }

    func testLegacyMigrationCannotReplaceDanglingDurableSymlink() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        let key = try contentKey(for: article())
        try OfflineManager.BodyStorage(directory: legacy).write(key, article: article())
        try OfflineDownloadLocations.prepareDirectory(durable)
        let current = durable.appendingPathComponent(key + ".json"), outside = root.appendingPathComponent("unrelated-target")
        try FileManager.default.createSymbolicLink(at: current, withDestinationURL: outside)
        let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertThrowsError(try storage.read(key))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: current.path), outside.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: durable.path), [key + ".json"],
                       "Exclusive publication must preserve the winner and clean only its own staging files")
    }

    func testLegacySymlinkIsNotPromotedAsARegularDownloadedBody() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        let key = try contentKey(for: article())
        try OfflineManager.BodyStorage(directory: legacy).write(key, article: article())
        let old = legacy.appendingPathComponent(key + ".json"), outside = root.appendingPathComponent("unrelated-body")
        let bytes = try Data(contentsOf: old)
        try FileManager.default.moveItem(at: old, to: outside)
        try FileManager.default.createSymbolicLink(at: old, withDestinationURL: outside)
        let storage = OfflineManager.BodyStorage(directory: durable, legacyDirectory: legacy)
        let result = await probe(storage, key: key)
        XCTAssertFalse(try result.get())
        XCTAssertNil(try? storage.read(key), "Both an absent body and a rejected read must remain unavailable")
        XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path))
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: old.path), outside.path)
    }

    func testWriteRejectsWrongDescriptorWithoutReplacingValidatedText() throws {
        let root = try directory(), storage = OfflineManager.BodyStorage(directory: root)
        let key = try contentKey(for: article())
        try storage.write(key, article: article())
        let path = root.appendingPathComponent(key + ".json"), marker = path.appendingPathExtension("size")
        let bytes = try Data(contentsOf: path), markerBytes = try Data(contentsOf: marker)
        let wrong = Article(id: article().id, name: "Ny revision", slug: "probe", content: "<p>Andre ord</p>",
                            intro: "", topicID: "culture", contentRevision: "local-r2")
        XCTAssertThrowsError(try storage.write(key, article: wrong))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(try storage.read(key)?.content, article().content)
    }

    func testPersistedMembershipColdReopenReadsDurableTextAfter151CacheEviction() async throws {
        let root = try directory(), legacy = root.appendingPathComponent("cache-151"), durable = root.appendingPathComponent("durable")
        var records: [FavoritesNamespace: Data] = [:]
        func makeModel() -> FavoritesModel {
            let model = FavoritesModel(storage: .init(read: { records[$0] }, write: { records[$0] = $1 }))
            model.changeContext(to: .confirmed(userID: "durable-reader-A"))
            return model
        }
        let firstModel = makeModel()
        XCTAssertNotNil(firstModel.setFavorite(article(), enabled: true))
        let first = coordinator(model: firstModel, storage: .init(directory: legacy))
        let original = try XCTUnwrap(first.captureAccess(articleID: article().id))
        XCTAssertTrue(first.saveBody(article(), ticket: original))

        let coldModel = makeModel()
        let cold = coordinator(model: coldModel, storage: .init(directory: durable, legacyDirectory: legacy))
        let current = try XCTUnwrap(cold.captureAccess(articleID: article().id))
        await prepare(current, coordinator: cold)
        XCTAssertEqual(cold.bodyState(ticket: current), .available)
        XCTAssertEqual(cold.libraryBodySummary.available, 1)
        XCTAssertEqual(cold.body(articleID: article().id)?.content, article().content)
        XCTAssertTrue(cold.isCurrent(current))
        try FileManager.default.removeItem(at: legacy)

        let reopenedModel = makeModel()
        let reopened = coordinator(model: reopenedModel, storage: .init(directory: durable, legacyDirectory: legacy))
        let reopenedTicket = try XCTUnwrap(reopened.captureAccess(articleID: article().id))
        await prepare(reopenedTicket, coordinator: reopened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(reopened.bodyState(ticket: reopenedTicket), .available)
        XCTAssertTrue(reopened.hasBody(articleID: article().id, expectedRevision: article().bodyRevision))
        XCTAssertEqual(reopened.body(articleID: article().id)?.content, article().content)
        reopenedModel.changeContext(to: .confirmed(userID: "durable-reader-B"))
        reopened.synchronizeCurrentMembership()
        XCTAssertFalse(reopened.isCurrent(reopenedTicket))
        XCTAssertNil(reopened.body(articleID: article().id), "Reusable bytes do not grant another account access")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testActualColdCoordinatorNeverReportsCorruptStaleOrEmptyBodyAvailable() async throws {
        for invalid in ["corrupt", "revision", "article", "empty"] {
            let root = try directory()
            var records: [FavoritesNamespace: Data] = [:]
            func makeModel() -> FavoritesModel {
                let model = FavoritesModel(storage: .init(read: { records[$0] }, write: { records[$0] = $1 }))
                model.changeContext(to: .confirmed(userID: "body-proof-reader"))
                return model
            }
            let initialModel = makeModel()
            XCTAssertNotNil(initialModel.setFavorite(article(), enabled: true))
            let storage = OfflineManager.BodyStorage(directory: root)
            let initial = coordinator(model: initialModel, storage: storage)
            let ticket = try XCTUnwrap(initial.captureAccess(articleID: article().id))
            XCTAssertTrue(initial.saveBody(article(), ticket: ticket))
            let path = root.appendingPathComponent(ticket.contentKey + ".json")
            let bytes = try Data(contentsOf: path)
            let replacement: Data
            switch invalid {
            case "corrupt": replacement = Data(repeating: 120, count: bytes.count)
            case "revision": replacement = Data(String(decoding: bytes, as: UTF8.self)
                .replacingOccurrences(of: "\"local-r1\"", with: "\"local-r2\"").utf8)
            case "article": replacement = Data(String(decoding: bytes, as: UTF8.self)
                .replacingOccurrences(of: "\"probe\"", with: "\"other\"").utf8)
            default: replacement = try JSONEncoder().encode(article().strippingBodyContent())
            }
            if invalid != "empty" { XCTAssertEqual(replacement.count, bytes.count) }
            try replacement.write(to: path, options: .atomic)
            try Data(String(replacement.count).utf8).write(to: path.appendingPathExtension("size"), options: .atomic)

            let coldModel = makeModel()
            let cold = coordinator(model: coldModel, storage: .init(directory: root))
            let coldTicket = try XCTUnwrap(cold.captureAccess(articleID: article().id))
            await prepare(coldTicket, coordinator: cold)
            XCTAssertTrue(cold.isCurrent(coldTicket), invalid)
            XCTAssertEqual(cold.bodyState(ticket: coldTicket), .notDownloaded, invalid)
            XCTAssertEqual(cold.libraryBodySummary.available, 0, invalid)
            XCTAssertEqual(cold.libraryOfflineSummary.textAvailable, 0, invalid)
            XCTAssertEqual(cold.libraryOfflineSummary.ready, 0, invalid)
            XCTAssertNil(cold.body(articleID: article().id), invalid)
        }
        XCTAssertNil(FirebaseApp.allApps)
    }
}
