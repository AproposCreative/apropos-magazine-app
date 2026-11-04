import Combine
import XCTest
@testable import Apropos

@MainActor
final class PodcastAcceptedAssetTests: XCTestCase {
    private func revision(_ value: String = "a") -> String { "cms-sha256-v1:" + String(repeating: value, count: 64) }
    private func episode(_ value: String? = "a", id: String? = "article", ai: Bool = false) -> PodcastEpisode {
        var result = PodcastEpisode(id: "episode", articleId: id, articleSlug: "story", title: "Titel", subtitle: nil,
            audioURL: URL(string: "https://audio.example.com/same.m4a"), productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: [], publishedDate: nil)
        result.isAINarration = ai; result.sourceContentRevision = value.map(revision); return result
    }
    private func article(_ value: String = "a") -> Article {
        Article(id: "article", name: "Titel", slug: "story", content: "", intro: "", topicID: "topic",
                lastPublished: "2026-10-20T12:00:00Z", contentRevision: revision(value))
    }
    func testLegacyAndUnacceptedHumanMediaStreamWithoutVerifiedOfflineAsset() {
        let model = PodcastAvailabilityModel(), legacy = episode(nil), bound = episode()
        model.recordEpisodes([legacy, bound])
        XCTAssertTrue(model.allows(legacy)); XCTAssertTrue(model.allows(bound))
        XCTAssertNil(model.audioAsset(for: legacy)); XCTAssertNil(model.audioAsset(for: bound))
        XCTAssertTrue(model.availableAudioAssets.isEmpty)
        model.acceptManifest([legacy]); XCTAssertTrue(model.allows(legacy))
        let recording = model.audioAsset(for: legacy)
        XCTAssertNotNil(recording); XCTAssertNil(recording?.sourceRevision); XCTAssertNil(legacy.sourceContentRevision)
        if let recording { XCTAssertEqual(recording.binding, .acceptedRecording(articleID: "article", articleSlug: "story")) }
    }
    func testBothMediaKindsRequireExactAcceptedRawSourceBinding() throws {
        for ai in [false, true] {
            let model = PodcastAvailabilityModel(), current = episode(ai: ai), old = episode("b", ai: ai)
            model.acceptManifest([current])
            let asset = try XCTUnwrap(model.audioAsset(for: current, articleID: "article"))
            XCTAssertEqual(asset.sourceRevision, revision()); XCTAssertEqual(asset.canonicalArticleID, "article")
            XCTAssertEqual(asset.kind, ai ? .ai : .human)
            XCTAssertNil(model.audioAsset(for: old)); XCTAssertNil(model.audioAsset(for: current, articleID: "other"))
        }
    }
    func testAliasOrEnrichedCanonicalIDCannotCreateMissingRawManifestProvenance() {
        let model = PodcastAvailabilityModel(), raw = episode(id: nil)
        model.recordIdentities([("article", "story")]); model.acceptManifest([raw])
        let enriched = PodcastRepository.enriched(raw, with: article())
        XCTAssertEqual(enriched.articleId, "article")
        XCTAssertNil(model.audioAsset(for: raw, articleID: "article"))
        XCTAssertNil(model.audioAsset(for: enriched, articleID: "article"))
        XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: article(), in: [raw], availability: model, permits: { _ in true }))
    }
    func testActualRepositoryFactoryNeverRelabelsAcceptedR1URLAsArticleR2() throws {
        let model = PodcastAvailabilityModel(), raw = episode()
        model.acceptManifest([raw])
        let asset = try XCTUnwrap(PodcastRepository.acceptedAudioAsset(for: article(), in: [raw], availability: model, permits: { _ in true }))
        XCTAssertEqual(asset.sourceRevision, revision())
        XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: article("b"), in: [raw], availability: model, permits: { _ in true }))
        XCTAssertNil(PodcastRepository.acceptedAudioAsset(for: article(), in: [raw], availability: model, permits: { _ in false }))
    }
    func testSameURLSourceReplacementKeepsOldImmutableCleanupDescriptorAndNewAsset() throws {
        let model = PodcastAvailabilityModel(), old = episode(), new = episode("b")
        model.acceptManifest([old]); let oldAsset = try XCTUnwrap(model.audioAsset(for: old))
        var observed: [(Set<PodcastAudioAsset>, Set<PodcastAudioAsset>)] = []
        let subscription = model.changes.sink { observed.append((model.availableAudioAssets, model.unavailableAudioAssets)) }
        model.acceptManifest([new]); let newAsset = try XCTUnwrap(model.audioAsset(for: new))
        XCTAssertEqual(oldAsset.remoteURL, newAsset.remoteURL); XCTAssertNotEqual(oldAsset.key, newAsset.key)
        XCTAssertEqual(model.availableAudioAssets, [newAsset]); XCTAssertEqual(model.unavailableAudioAssets, [oldAsset])
        XCTAssertEqual(observed.last?.0, [], "Unused new catalog entries do not consume cleanup observations")
        XCTAssertEqual(observed.last?.1, [oldAsset])
        withExtendedLifetime(subscription) {}
    }
    func testStaleHumanCacheOrPlaybackCannotOverwriteNewAcceptedCleanupIdentity() throws {
        let model = PodcastAvailabilityModel(), old = episode(), new = episode("b")
        model.acceptManifest([old]); let oldAsset = try XCTUnwrap(model.audioAsset(for: old))
        model.acceptManifest([new]); let newAsset = try XCTUnwrap(model.audioAsset(for: new))
        model.recordEpisodes([old]); model.recordPlayback(old, articleID: "article")
        XCTAssertTrue(model.allows(old), "Streaming compatibility stays independent of strict offline provenance")
        XCTAssertNil(model.audioAsset(for: old))
        XCTAssertEqual(model.availableAudioAssets, [newAsset]); XCTAssertEqual(model.unavailableAudioAssets, [oldAsset])
    }
    func testSameURLKindReplacementInvalidatesOnlyOldAssetKey() throws {
        let model = PodcastAvailabilityModel(), human = episode(), ai = episode(ai: true)
        model.acceptManifest([human]); let oldAsset = try XCTUnwrap(model.audioAsset(for: human))
        model.acceptManifest([ai]); let newAsset = try XCTUnwrap(model.audioAsset(for: ai))
        XCTAssertNotEqual(oldAsset.key, newAsset.key)
        XCTAssertEqual(model.unavailableAudioAssets, [oldAsset]); XCTAssertEqual(model.availableAudioAssets, [newAsset])
    }
    func testConfirmedArticleRevisionRevokesOldAssetUntilMatchingManifestSourceArrives() throws {
        var approved = revision()
        let model = PodcastAvailabilityModel(approvedRevision: { _ in approved }), old = episode()
        model.acceptManifest([old]); let oldAsset = try XCTUnwrap(model.audioAsset(for: old))
        approved = revision("b"); model.refreshArticleRevisions()
        XCTAssertNil(model.audioAsset(for: old)); XCTAssertEqual(model.unavailableAudioAssets, [oldAsset])
        let new = episode("b"); model.acceptManifest([new])
        XCTAssertEqual(model.audioAsset(for: new)?.sourceRevision, approved)
        XCTAssertFalse(model.unavailableAudioAssets.contains(try XCTUnwrap(model.audioAsset(for: new))))
    }
    func testWithdrawalAndManifestRemovalKeepExactCleanupEvidenceWithoutRegrant() throws {
        let model = PodcastAvailabilityModel(), raw = episode()
        model.acceptManifest([raw]); let asset = try XCTUnwrap(model.audioAsset(for: raw))
        model.setWithdrawn(["article"]); XCTAssertNil(model.audioAsset(for: raw)); XCTAssertEqual(model.unavailableAudioAssets, [asset])
        model.setWithdrawn([]); model.acceptManifest([episode("b")])
        XCTAssertNil(model.audioAsset(for: episode("b")), "Existing URL revocation cannot be evaded by source metadata")
        model.acceptManifest([]); XCTAssertTrue(model.availableAudioAssets.isEmpty); XCTAssertTrue(model.unavailableAudioAssets.contains(asset))
    }
    func testMalformedBoundSourceCannotProduceOfflineDescriptor() {
        let model = PodcastAvailabilityModel(); var raw = episode()
        raw.sourceContentRevision = " bad\nsource "
        model.acceptManifest([raw]); XCTAssertTrue(model.allows(raw)); XCTAssertNil(model.audioAsset(for: raw))
        raw.isAINarration = true; model.acceptManifest([raw]); XCTAssertNil(model.audioAsset(for: raw))
    }
    func testLargeUntouchedCatalogDoesNotConsumeUsedAssetLedgerAndExhaustionRetainsEveryDenial() throws {
        let model = PodcastAvailabilityModel()
        let catalog = (0..<600).map { index -> PodcastEpisode in
            var value = PodcastEpisode(id: "episode-\(index)", articleId: "article-\(index)", articleSlug: nil,
                title: "Artikel", subtitle: nil, audioURL: URL(string: "https://audio.example.com/\(index).m4a"),
                productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
            value.sourceContentRevision = revision(); return value
        }
        model.acceptManifest(catalog)
        for _ in 0..<10 { XCTAssertTrue(model.availableAudioAssets.isEmpty) }
        XCTAssertFalse(model.offlineAssetEvidenceExhausted)
        var handedOut = Set<PodcastAudioAsset>()
        for raw in catalog.prefix(PodcastAvailabilityModel.maximumObservedAudioAssets) {
            handedOut.insert(try XCTUnwrap(model.audioAsset(for: raw)))
        }
        XCTAssertFalse(model.offlineAssetEvidenceExhausted)
        XCTAssertEqual(model.availableAudioAssets, handedOut)
        XCTAssertNil(model.audioAsset(for: catalog[PodcastAvailabilityModel.maximumObservedAudioAssets]))
        XCTAssertTrue(model.offlineAssetEvidenceExhausted)
        XCTAssertTrue(model.availableAudioAssets.isEmpty)
        XCTAssertEqual(model.unavailableAudioAssets, handedOut)
        XCTAssertEqual(handedOut.count, 512)
        model.acceptManifest([catalog[0]])
        XCTAssertNil(model.audioAsset(for: catalog[0]), "Exhaustion must not silently reset or forget old denials")
        XCTAssertTrue(model.allows(catalog[0]), "Streaming compatibility remains available")
    }
    func testPrefetchDeduplicatesExactAssetsAndPreservesDifferentRevisionsOnSameURL() throws {
        let model = PodcastAvailabilityModel(), old = episode(), new = episode("b")
        model.acceptManifest([old]); let a = try XCTUnwrap(model.audioAsset(for: old))
        model.acceptManifest([new]); let b = try XCTUnwrap(model.audioAsset(for: new))
        let assets = PodcastRepository.assetsToPrefetch(from: [a, a, b], diskCacheEnabled: true, prefetchEnabled: true,
            wifiOnly: false, allowsHeavyDownloads: true, limit: 3)
        XCTAssertEqual(assets, [a, b]); XCTAssertNotEqual(assets[0].key, assets[1].key)
    }
}
