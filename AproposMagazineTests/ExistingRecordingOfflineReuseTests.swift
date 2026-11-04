import Foundation
import XCTest
@testable import Apropos

/// Existing public recording bytes enter only the real accepted-catalog,
/// favorite-membership and durable-cache path. No service or player is started.
@MainActor
final class ExistingRecordingOfflineReuseTests: XCTestCase {
    private let revision = "cms-sha256-v1:" + String(repeating: "a", count: 64)

    func testAcceptedLegacyRecordingSavesThroughCurrentFavoriteWithoutInventingProducerRevision() async throws {
        let bytes = Data("existing-recording-fixture-no-render".utf8)
        let fixture = try RecordingFixture(bytes: bytes, mime: "audio/mp4")
        defer { fixture.cleanup() }
        let article = Article(id: "article", name: "Artikel", slug: "story", content: "<p>Aktuel tekst</p>",
            intro: "", topicID: "topic", lastPublished: "2026-11-02T10:00:00Z", contentRevision: revision)
        let raw = PodcastEpisode(id: "ai-story", articleId: nil, articleSlug: "story", title: "Artikel",
            subtitle: nil, audioURL: URL(string: "https://audio.example.test/existing.m4a"),
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil,
            isAINarration: true, sourceContentRevision: nil)
        let availability = PodcastAvailabilityModel(approvedRevision: { _ in self.revision })
        availability.acceptManifest([raw])
        availability.recordIdentities([(article.id, article.slug)])
        let owner = SavedRecordingOwner(cache: fixture.cache, availability: availability, episodes: [raw])
        owner.model.changeContext(to: .confirmed(userID: "A"))
        _ = owner.model.setFavorite(article, enabled: true)
        let ticket = try XCTUnwrap(owner.offline.captureAccess(articleID: article.id))
        XCTAssertTrue(owner.offline.saveBody(article, ticket: ticket))
        XCTAssertTrue(owner.offline.hasBody(articleID: article.id, expectedRevision: revision))
        XCTAssertTrue(availability.allows(raw, articleID: article.id))

        // Current 152 fails here: a streamable accepted legacy recording never
        // reaches the save pipeline because it has no producer CMS revision.
        let asset = try XCTUnwrap(owner.offline.acceptedAudioAsset(ticket),
            "An accepted existing recording must be reusable without creating another recording")
        XCTAssertNil(raw.sourceContentRevision)
        XCTAssertNotEqual(asset.sourceRevision, article.bodyRevision,
            "The saved text revision must not become a fabricated producer recording revision")
        try await waitUntil { fixture.cache.isDownloaded(for: asset) }
        XCTAssertTrue(owner.offline.audioDownloaded(articleID: article.id, expectedRevision: revision, expectedAsset: asset))
        let local = fixture.cache.resolvePlaybackURL(for: asset)
        XCTAssertEqual(local.cacheResult, .hit)
        XCTAssertTrue(local.url.isFileURL)
        XCTAssertEqual(try Data(contentsOf: local.url), bytes)
        let requested = await fixture.transport.requests
        XCTAssertEqual(requested, [try XCTUnwrap(raw.audioURL)])
    }

    func testExistingMP3KeepsMP3FilenameAndIdenticalBytesAcrossColdValidation() async throws {
        // Byte preservation/integrity fixture, not a decoded-audio quality test.
        let bytes = Data([0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0, 0xff, 0xfb, 0x90, 0x64])
        let fixture = try RecordingFixture(bytes: bytes, mime: "audio/mpeg")
        defer { fixture.cleanup() }
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: "existing-human", canonicalArticleID: "article",
            kind: .human, sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/existing.mp3")!))
        fixture.cache.pinAndDownload(pinKey: "favorites-v1:A", leaseID: UUID(), asset: asset)
        try await waitUntil { fixture.cache.isDownloaded(for: asset) }
        let local = fixture.cache.resolvePlaybackURL(for: asset)
        XCTAssertEqual(local.cacheResult, .hit)
        XCTAssertEqual(try Data(contentsOf: local.url), bytes)
        // Current 152 always calls every committed recording .m4a.
        XCTAssertEqual(local.url.pathExtension, "mp3", "Keep the existing recording format; never transcode it")
        let cold = fixture.reopen()
        let prepared = await cold.prepare(asset)
        XCTAssertTrue(prepared)
        XCTAssertEqual(try Data(contentsOf: cold.resolvePlaybackURL(for: asset).url), bytes)
        let requested = await fixture.transport.requests
        XCTAssertEqual(requested, [asset.remoteURL], "Cold validation must not fetch or generate another recording")
    }

    func testAcceptedCanonicalRecordingForBothKindsHasNoInventedSourceAndRoundTrips() throws {
        for ai in [false, true] {
            let raw = recording(articleID: "article", ai: ai)
            let model = PodcastAvailabilityModel(approvedRevision: { _ in self.revision })
            model.acceptManifest([raw])
            let asset = try XCTUnwrap(PodcastRepository.acceptedAudioAsset(for: article(), in: [raw], availability: model, permits: { $0.isPubliclyPublished }))
            XCTAssertEqual(asset.binding, .acceptedRecording(articleID: "article", articleSlug: "story"))
            XCTAssertNil(asset.sourceRevision); XCTAssertNil(raw.sourceContentRevision)
            XCTAssertEqual(try JSONDecoder().decode(PodcastAudioAsset.self, from: JSONEncoder().encode(asset)), asset)
            let producer = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: "article",
                kind: ai ? .ai : .human, sourceRevision: revision, remoteURL: try XCTUnwrap(raw.audioURL)))
            XCTAssertNotEqual(producer.key, asset.key)
        }
    }

    func testOfflineSelectionRejectsTitleFallbackForeignIdentityAndEqualPriorityAmbiguity() {
        let current = article()
        let cases = [
            [recording(slug: nil)],
            [recording(articleID: "another")],
            [recording(slug: "different")],
            [recording(id: "first"), recording(id: "second")],
            [recording(), recording()]
        ]
        for rows in cases {
            let model = PodcastAvailabilityModel(); model.acceptManifest(rows)
            XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: current, in: rows, availability: model, permits: { _ in true }))
        }
        let model = PodcastAvailabilityModel(), raw = recording()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story"), ("another", "story")])
        XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: current, in: [raw], availability: model, permits: { _ in true }))
    }

    func testEnglishRecordingNeedsExactRawCanonicalNamespaceAndValidArticleLocale() throws {
        let rawID = String(repeating: "a", count: 24), englishID = "en_" + String(repeating: "a", count: 24)
        let english = Article(id: englishID, name: "Artikel", slug: "story", content: "Text", intro: "", topicID: "topic",
            lastPublished: "2026-11-02T10:00:00Z", contentRevision: revision, contentLanguage: .english,
            sourceArticleID: rawID, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        for row in [recording(), recording(articleID: rawID)] {
            let model = PodcastAvailabilityModel(); model.acceptManifest([row])
            model.recordIdentities([(rawID, "story"), (englishID, "story")])
            XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: english, in: [row], availability: model, permits: { _ in true }))
            XCTAssertNil(model.audioAsset(for: row, articleID: englishID))
        }
        let exact = recording(articleID: englishID, ai: true), model = PodcastAvailabilityModel()
        model.acceptManifest([exact])
        XCTAssertNotNil(PodcastRepository.acceptedAudioAsset(for: english, in: [exact], availability: model, permits: { _ in true }))
        let invalidLocale = Article(id: englishID, name: "Artikel", slug: "story", content: "Text", intro: "", topicID: "topic",
            lastPublished: "2026-11-02T10:00:00Z", contentRevision: revision, contentLanguage: .english,
            sourceArticleID: rawID, cmsLocaleId: ArticleContentLanguage.danishCMSLocaleID)
        XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: invalidLocale, in: [exact], availability: model, permits: { _ in true }))
    }

    func testDeclaredInvalidOrStaleProducerSourceNeverDowngradesToRecording() {
        for ai in [false, true] {
            for declared in ["", " bad\nsource "] {
                var raw = recording(articleID: "article", ai: ai); raw.sourceContentRevision = declared
                let model = PodcastAvailabilityModel(); model.acceptManifest([raw])
                XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: article(), in: [raw], availability: model, permits: { _ in true }))
            }
            var raw = recording(ai: ai); raw.sourceContentRevision = revision
            let model = PodcastAvailabilityModel(); model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
            XCTAssertNil(model.audioAsset(for: raw, articleID: "article"), "A declared revision without its raw canonical ID is not recording-only")
            raw = recording(articleID: "article", ai: ai); raw.sourceContentRevision = revision
            model.acceptManifest([raw])
            XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: article(revision: "cms-sha256-v1:" + String(repeating: "b", count: 64)),
                in: [raw], availability: model, permits: { _ in true }))
        }
    }

    func testEnglishReadCannotPolluteDanishRecordingAliasAndBreakLaterReuse() throws {
        let rawID = String(repeating: "a", count: 24), englishID = "en_" + String(repeating: "a", count: 24)
        let english = Article(id: englishID, name: "Artikel", slug: "story", content: "Text", intro: "", topicID: "topic",
            lastPublished: "2026-11-02T10:00:00Z", contentRevision: revision, contentLanguage: .english,
            sourceArticleID: rawID, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        let danishRecording = recording(), englishRecording = recording(id: "english", articleID: englishID)
        let model = PodcastAvailabilityModel(); model.acceptManifest([danishRecording, englishRecording])
        let before = try XCTUnwrap(PodcastRepository.acceptedAudioAsset(for: article(), in: [danishRecording],
            availability: model, permits: { _ in true }))
        XCTAssertNotNil(PodcastRepository.acceptedAudioAsset(for: english, in: [englishRecording], availability: model, permits: { _ in true }))
        XCTAssertNil(model.snapshot.aliasesByID[englishID], "EN exact identity must not enter the DA slug alias ledger")
        XCTAssertEqual(PodcastRepository.acceptedAudioAsset(for: article(), in: [danishRecording], availability: model, permits: { _ in true }), before)
    }

    func testRawLegacyEpisodeStatusUsesExactAcceptedAssetAndCurrentFavoriteWithoutSharedServices() async throws {
        let fixture = try RecordingFixture(bytes: Data([1, 2, 3]), mime: "audio/mp4")
        defer { fixture.cleanup() }
        let raw = recording(), model = PodcastAvailabilityModel()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
        let owner = SavedRecordingOwner(cache: fixture.cache, availability: model, episodes: [raw])
        owner.model.changeContext(to: .confirmed(userID: "A")); _ = owner.model.setFavorite(article(), enabled: true)
        let ticket = try XCTUnwrap(owner.offline.captureAccess(articleID: "article"))
        XCTAssertTrue(owner.offline.saveBody(article(), ticket: ticket))
        let asset = try XCTUnwrap(owner.offline.acceptedAudioAsset(ticket))
        try await waitUntil { fixture.cache.isDownloaded(for: asset) }
        let manager = OfflineManager(coordinator: owner.offline, audioAsset: { model.audioAsset(for: $0, articleID: $1) })
        XCTAssertNil(raw.articleId)
        XCTAssertTrue(manager.isAudioDownloaded(episode: raw), "Raw catalog rows need no caller-invented canonical ID")
        XCTAssertFalse(manager.isAudioDownloaded(episode: raw, articleID: "another"))
        XCTAssertFalse(manager.isAudioDownloaded(episode: recording(id: "unaccepted")))
        owner.model.changeContext(to: .confirmed(userID: "B")); owner.offline.synchronizeCurrentMembership()
        XCTAssertFalse(manager.isAudioDownloaded(episode: raw), "Public bytes cannot grant another owner's library access")
        owner.model.changeContext(to: .confirmed(userID: nil)); _ = owner.model.setFavorite(article(), enabled: true)
        owner.offline.synchronizeCurrentMembership()
        XCTAssertFalse(manager.isAudioDownloaded(episode: raw), "The existing confirmed-account guard still applies")
        model.setWithdrawn(["article"])
        XCTAssertFalse(manager.isAudioDownloaded(episode: raw))
    }

    func testRecordingReplacementAndWithdrawalRetainExactCleanupAndTombstoneDenials() throws {
        var invalidated = false
        let model = PodcastAvailabilityModel(wasInvalidated: { _ in invalidated }), raw = recording()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
        let old = try XCTUnwrap(model.audioAsset(for: raw, articleID: "article"))
        let replacement = recording(id: raw.id, slug: "different")
        model.recordIdentities([("another", "different")]); model.acceptManifest([replacement])
        let next = try XCTUnwrap(model.audioAsset(for: replacement, articleID: "another"))
        XCTAssertNotEqual(old.key, next.key)
        model.recordEpisodes([raw])
        XCTAssertEqual(model.availableAudioAssets, [next]); XCTAssertTrue(model.unavailableAudioAssets.contains(old))
        model.setWithdrawn(["another"]); invalidated = true; model.setWithdrawn([])
        XCTAssertNil(model.audioAsset(for: replacement, articleID: "another"))
        let unseen = recording(id: "unseen", slug: "different")
        model.acceptManifest([unseen]); XCTAssertNil(model.audioAsset(for: unseen, articleID: "another"))
        model.acceptManifest([]); XCTAssertTrue(model.availableAudioAssets.isEmpty)
    }

    func testOldSnapshotOrCallerEnrichmentCannotInventAcceptedRecordingBinding() throws {
        let raw = recording(ai: true), model = PodcastAvailabilityModel()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(model.snapshot)) as? [String: Any])
        var bindings = try XCTUnwrap(snapshot["manifestBindings"] as? [String: [String: Any]])
        for key in Array(bindings.keys) { bindings[key]?.removeValue(forKey: "recording") }
        snapshot["manifestBindings"] = bindings
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
            from: JSONSerialization.data(withJSONObject: snapshot)))
        restored.seedCachedManifest([raw])
        let enriched = PodcastRepository.enriched(raw, with: article())
        XCTAssertTrue(restored.allows(enriched, articleID: "article"))
        XCTAssertNil(restored.audioAsset(for: enriched, articleID: "article"))
        restored.acceptManifest([raw])
        XCTAssertNotNil(restored.audioAsset(for: enriched, articleID: "article"))
    }

    func testRecordingReuseStillRequiresCurrentBodyTicketAndConfirmedAccount() async throws {
        let fixture = try RecordingFixture(bytes: Data([1, 2, 3]), mime: "audio/mp4")
        defer { fixture.cleanup() }
        let raw = recording(), model = PodcastAvailabilityModel()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
        let owner = SavedRecordingOwner(cache: fixture.cache, availability: model, episodes: [raw])
        owner.model.changeContext(to: .confirmed(userID: nil)); _ = owner.model.setFavorite(article(), enabled: true)
        XCTAssertNil(owner.offline.captureAccess(articleID: "article"), "Public bytes are not guest offline membership")
        owner.model.changeContext(to: .confirmed(userID: "A")); _ = owner.model.setFavorite(article(), enabled: true)
        let old = try XCTUnwrap(owner.offline.captureAccess(articleID: "article"))
        let recordingAsset = try XCTUnwrap(owner.offline.acceptedAudioAsset(old))
        _ = owner.model.setFavorite(article(), enabled: false)
        let updated = article(revision: "cms-sha256-v1:" + String(repeating: "b", count: 64))
        _ = owner.model.setFavorite(updated, enabled: true); owner.offline.synchronizeCurrentMembership()
        let next = try XCTUnwrap(owner.offline.captureAccess(articleID: "article"))
        XCTAssertNotEqual(old.leaseID, next.leaseID); XCTAssertFalse(owner.offline.cacheAudio(old, asset: recordingAsset))
        XCTAssertFalse(owner.offline.saveBody(article(), ticket: next))
        XCTAssertEqual(owner.offline.acceptedAudioAsset(next), recordingAsset, "Recording identity is independent of current text version")
        owner.model.changeContext(to: .confirmed(userID: "B")); owner.offline.synchronizeCurrentMembership()
        owner.model.changeContext(to: .confirmed(userID: "A")); owner.offline.synchronizeCurrentMembership()
        XCTAssertFalse(owner.offline.isCurrent(next)); XCTAssertFalse(owner.offline.cacheAudio(next, asset: recordingAsset))
        owner.permitted = false
        XCTAssertNil(owner.offline.captureAccess(articleID: "article"))
        owner.offline.synchronizeCurrentMembership()
        try await waitUntil { fixture.cache.downloadActivity.active == 0 }
    }

    func testNewRecordingAssociationDoesNotExpandAutomaticPrefetchOrConsumeItsObservationLedger() throws {
        let raw = recording(articleID: "article"), model = PodcastAvailabilityModel()
        model.acceptManifest([raw])
        XCTAssertNil(model.audioAsset(for: raw, allowsAcceptedRecording: false))
        XCTAssertTrue(model.availableAudioAssets.isEmpty)
        let accepted = try XCTUnwrap(model.audioAsset(for: raw))
        let assets = PodcastRepository.assetsToPrefetch(from: [accepted], diskCacheEnabled: true,
            prefetchEnabled: true, wifiOnly: false, allowsHeavyDownloads: true, limit: 64)
        XCTAssertTrue(assets.isEmpty)
    }

    func testOldV2MP3ReceiptStillOpensItsOriginalM4AFilenameWithoutImportingURLOnlyFiles() async throws {
        let fixture = try RecordingFixture(bytes: Data([4, 5, 6]), mime: "audio/mpeg")
        defer { fixture.cleanup() }
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: "existing", canonicalArticleID: "article", kind: .human,
            sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/old.mp3")!))
        let bytes = Data([4, 5, 6]), receipt = try PodcastAudioReceipt(asset: asset, byteCount: 3,
            sha256: "787c798e39a5bc1910355bae6d0cd87a36b2e10fd0202a83e3bb6b005da83472")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: receipt.encoded()) as? [String: Any])
        object.removeValue(forKey: "fileExtension")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let old = try PodcastAudioReceipt.decode(oldData, expectedAsset: asset)
        XCTAssertTrue(old.fileName.hasSuffix(".m4a")); XCTAssertNil(old.fileExtension)
        let directory = fixture.root.appendingPathComponent("assets-v2")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent(old.fileName))
        try oldData.write(to: directory.appendingPathComponent(asset.key + ".json"))
        let prepared = await fixture.cache.prepare(asset)
        XCTAssertTrue(prepared); XCTAssertEqual(try Data(contentsOf: fixture.cache.resolvePlaybackURL(for: asset).url), bytes)
        let requests = await fixture.transport.requests; XCTAssertTrue(requests.isEmpty)
        for suffix in ["../mp3", "MP3", "m3u8", ""] {
            object["fileExtension"] = suffix
            XCTAssertThrowsError(try PodcastAudioReceipt.decode(JSONSerialization.data(withJSONObject: object), expectedAsset: asset))
        }
    }

    func testMP3BytesCountAgainstBudgetAndCannotEvictAnotherPinnedRecording() async throws {
        let fixture = try RecordingFixture(bytes: Data([1, 2, 3, 4]), mime: "audio/mpeg", maximumBytes: 6)
        defer { fixture.cleanup() }
        let first = try XCTUnwrap(PodcastAudioAsset(episodeID: "first", canonicalArticleID: "first", kind: .human,
            sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/first.mp3")!))
        let second = try XCTUnwrap(PodcastAudioAsset(episodeID: "second", canonicalArticleID: "second", kind: .human,
            sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/second.m4a")!))
        fixture.cache.pinAndDownload(pinKey: "favorites-v1:first-owner", leaseID: UUID(), asset: first)
        try await waitUntil { fixture.cache.isDownloaded(for: first) }
        fixture.cache.pinAndDownload(pinKey: "favorites-v1:second-owner", leaseID: UUID(), asset: second)
        try await waitUntil { fixture.cache.downloadActivity.active == 0 && fixture.cache.downloadState(for: second) == .storageLimit }
        XCTAssertTrue(fixture.cache.isDownloaded(for: first)); XCTAssertFalse(fixture.cache.isDownloaded(for: second))
        XCTAssertEqual(fixture.cache.totalCacheSizeBytes(), 4)
        XCTAssertEqual(try Data(contentsOf: fixture.cache.resolvePlaybackURL(for: first).url), Data([1, 2, 3, 4]))
    }

    func testPlaybackIdentityKeepsUnboundStreamingNilAndResolvesOnlyExactAcceptedRecording() throws {
        let raw = recording(ai: true)
        let unbound = try XCTUnwrap(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: nil))
        XCTAssertNil(unbound.articleID)
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: try XCTUnwrap(raw.audioURL), isOnline: true))
        XCTAssertFalse(PodcastPlaybackPolicy.canStart(playbackURL: try XCTUnwrap(raw.audioURL), isOnline: false))
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: "article", kind: .ai,
            acceptedRecordingArticleID: nil, acceptedRecordingSlug: "story", remoteURL: try XCTUnwrap(raw.audioURL)))
        let identity = try XCTUnwrap(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: asset))
        XCTAssertEqual(identity.articleID, "article")
        XCTAssertNil(raw.articleId); XCTAssertNil(raw.sourceContentRevision); XCTAssertNil(asset.sourceRevision)
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: "another", acceptedAsset: asset))
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: recording(id: "other", ai: true), requestedArticleID: nil, acceptedAsset: asset))
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: recording(), requestedArticleID: nil, acceptedAsset: asset), "Kind substitution is not the accepted recording")
    }

    func testProducerPlaybackIdentityStillRejectsWrongSourceURLAndCanonicalCaller() throws {
        var raw = recording(articleID: "article", ai: true); raw.sourceContentRevision = revision
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: "article", kind: .ai,
            sourceRevision: revision, remoteURL: try XCTUnwrap(raw.audioURL)))
        XCTAssertEqual(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: asset)?.articleID, "article")
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: "another", acceptedAsset: asset))
        let wrongSource = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: "article", kind: .ai,
            sourceRevision: "cms-sha256-v1:" + String(repeating: "b", count: 64), remoteURL: try XCTUnwrap(raw.audioURL)))
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: wrongSource))
        let wrongURL = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: "article", kind: .ai,
            sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/another.m4a")!))
        XCTAssertNil(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: wrongURL))
    }

    func testRawPlaybackIdentitySurvivesColdPreparationAndOwnsSessionProgressAndDeferredLease() async throws {
        let bytes = Data([5, 6, 7]), fixture = try RecordingFixture(bytes: Data([5, 6, 7]), mime: "audio/mp4")
        defer { fixture.cleanup() }
        let raw = recording(ai: true), model = PodcastAvailabilityModel()
        model.acceptManifest([raw]); model.recordIdentities([("article", "story")])
        let owner = SavedRecordingOwner(cache: fixture.cache, availability: model, episodes: [raw])
        owner.model.changeContext(to: .confirmed(userID: "A")); _ = owner.model.setFavorite(article(), enabled: true)
        let access = try XCTUnwrap(owner.offline.captureAccess(articleID: "article"))
        XCTAssertTrue(owner.offline.saveBody(article(), ticket: access))
        let asset = try XCTUnwrap(owner.offline.acceptedAudioAsset(access))
        try await waitUntil { fixture.cache.isDownloaded(for: asset) }
        let identity = try XCTUnwrap(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: asset))
        XCTAssertEqual(identity.articleID, access.articleID)

        var progressBytes: [PodcastProgressNamespace: Data] = [:]
        let progress = PodcastPlaybackProgressStore(storage: .init(read: { progressBytes[$0] }, write: { progressBytes[$0] = $1 }))
        let sessions = PodcastPlaybackSessionCoordinator(store: progress, effects: .init(cancelCallbacks: {}, stopPlayback: {},
            clearPresentation: {}, clearNowPlaying: {}, deactivateAudio: {}))
        progress.onContextInvalidated = { [weak sessions] in sessions?.contextInvalidated() }
        progress.changeContext(to: .confirmed(userID: "A"))
        let origin = sessions.contextTicket, cold = fixture.reopen()
        XCTAssertFalse(cold.isDownloaded(for: asset))
        let preparation = try XCTUnwrap(sessions.beginPreparation(asset: asset, accessIsCurrent: { owner.offline.isCurrent(access) }))
        let prepared = await sessions.prepare(preparation) { await cold.prepare(asset) }
        XCTAssertEqual(prepared, true)
        XCTAssertTrue(sessions.consumePreparation(preparation))
        let reentry = try XCTUnwrap(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: identity.articleID, acceptedAsset: asset))
        XCTAssertEqual(reentry, identity)
        let local = cold.resolvePlaybackURL(for: asset)
        XCTAssertEqual(local.cacheResult, .hit); XCTAssertTrue(local.url.isFileURL)
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: local.url, isOnline: false))
        XCTAssertEqual(try Data(contentsOf: local.url), bytes)
        let session = try XCTUnwrap(sessions.beginSession(episodeID: raw.id, articleID: reentry.articleID, expectedContext: origin))
        XCTAssertTrue(sessions.save(session.ticket, seconds: 45, duration: 600))
        XCTAssertEqual(progress.snapshot.lastPlayedArticleID, access.articleID)
        XCTAssertEqual(progress.snapshot.position(for: raw.id), 45)
        XCTAssertTrue(PodcastPlaybackPolicy.canReuseItem(current: raw, requested: raw, currentArticleID: reentry.articleID,
            requestedArticleID: identity.articleID, currentAudioURL: raw.audioURL, itemHasFailed: false))
        owner.model.changeContext(to: .confirmed(userID: "B")); owner.offline.synchronizeCurrentMembership()
        XCTAssertFalse(owner.offline.cacheAudio(access, asset: asset), "Deferred work keeps its original favorite lease")
        progress.changeContext(to: .confirmed(userID: "B"))
        XCTAssertFalse(sessions.isCurrent(session.ticket)); XCTAssertFalse(sessions.save(session.ticket, seconds: 99, duration: 600))
    }

    private func article(revision: String? = nil) -> Article {
        Article(id: "article", name: "Artikel", slug: "story", content: "<p>Aktuel tekst</p>", intro: "", topicID: "topic",
            lastPublished: "2026-11-02T10:00:00Z", contentRevision: revision ?? self.revision)
    }
    private func recording(id: String = "existing", articleID: String? = nil, slug: String? = "story", ai: Bool = false) -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: articleID, articleSlug: slug, title: "Artikel", subtitle: nil,
            audioURL: URL(string: "https://audio.example.test/existing.m4a"), productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: [], publishedDate: nil, isAINarration: ai, sourceContentRevision: nil)
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2_000 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Injected recording download did not settle", file: file, line: line)
        throw URLError(.timedOut)
    }
}

@MainActor
private final class SavedRecordingOwner {
    private var records: [FavoritesNamespace: FavoritesRecord] = [:]
    private var bodies: [String: Article] = [:]
    private let cache: PodcastAudioCache
    private let availability: PodcastAvailabilityModel
    private let episodes: [PodcastEpisode]
    var permitted = true
    lazy var model = FavoritesModel(storage: .init(read: { namespace, complete in
        complete(.success(self.records[namespace]))
    }, write: { namespace, record, expectedRevision, complete in
        guard self.records[namespace]?.recordRevision == expectedRevision else {
            complete(.failure(URLError(.cannotWriteToFile))); return
        }
        self.records[namespace] = record
        complete(.success(()))
    }))
    lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
        storage: .init(read: { self.bodies[$0] }, write: { self.bodies[$0] = $1 }, contains: { self.bodies[$0] != nil }),
        permitsBody: { self.permitted && $0.isPubliclyPublished }, effects: .init(cacheImages: { _, _ in }, audioAsset: {
            PodcastRepository.acceptedAudioAsset(for: $0, in: self.episodes, availability: self.availability,
                permits: { $0.isPubliclyPublished })
        }, audioIsCached: { self.cache.isDownloaded(for: $0) }, pinAudio: {
            self.cache.pinAndDownload(pinKey: $0, leaseID: $1, asset: $2)
        }, releaseAudio: { self.cache.releasePinKeepingBytes(pinKey: $0, leaseID: $1, onlyIfAsset: $2) },
        scheduleRetry: { _, _ in {} }))
    init(cache: PodcastAudioCache, availability: PodcastAvailabilityModel, episodes: [PodcastEpisode]) {
        self.cache = cache; self.availability = availability; self.episodes = episodes
    }
}

private struct RecordingFixture {
    let root: URL
    let suite: String
    let defaults: UserDefaults
    let cache: PodcastAudioCache
    let transport: ExistingRecordingTransport
    let maximumBytes: Int64
    init(bytes: Data, mime: String, maximumBytes: Int64 = 120 * 1024 * 1024) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ExistingRecordingOfflineReuseTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        let transport = ExistingRecordingTransport(root: root, bytes: bytes, mime: mime)
        self.transport = transport
        self.maximumBytes = maximumBytes
        cache = PodcastAudioCache(cacheDirectory: root, defaults: defaults, maxBytes: { maximumBytes }, download: { try await transport.download($0) })
    }
    func reopen() -> PodcastAudioCache {
        let transport = transport, maximumBytes = maximumBytes
        return PodcastAudioCache(cacheDirectory: root, defaults: defaults, maxBytes: { maximumBytes }, download: { try await transport.download($0) })
    }
    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor ExistingRecordingTransport {
    private let root: URL
    private let bytes: Data
    private let mime: String
    private(set) var requests: [URL] = []
    init(root: URL, bytes: Data, mime: String) { self.root = root; self.bytes = bytes; self.mime = mime }
    func download(_ url: URL) throws -> PodcastAudioCache.DownloadArtifact {
        requests.append(url)
        let file = root.appendingPathComponent(UUID().uuidString + ".download")
        try bytes.write(to: file)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": mime, "Content-Length": String(bytes.count)])!
        return .init(temporaryURL: file, response: response)
    }
}
