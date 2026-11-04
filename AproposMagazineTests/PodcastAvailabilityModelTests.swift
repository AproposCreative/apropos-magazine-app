import Combine
import XCTest
@testable import Apropos

@MainActor
final class PodcastAvailabilityModelTests: XCTestCase {
    func testEnglishWithdrawalCannotBorrowDanishAudioAliasWithSharedSlug() throws {
        let raw = "0123456789abcdef01234567", englishID = "en_0123456789abcdef01234567"
        let danish = Article(id: raw, name: "Dansk", slug: "story", content: "", intro: "", topicID: "music")
        let english = Article(id: englishID, name: "English", slug: "story", content: "", intro: "", topicID: "music",
            contentLanguage: .english, sourceArticleID: raw, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
        let identities = PodcastAvailabilityService.danishAudioIdentities(from: [english, danish])
        XCTAssertEqual(identities.map(\.id), [raw])
        let mirrors: [(id: String, data: [String: Any])] = [
            (raw, ["id": raw, "fieldData": ["slug": "story"]]),
            (englishID, ["id": englishID, "contentLanguage": "en", "sourceArticleID": raw,
                "cmsLocaleId": ArticleContentLanguage.englishCMSLocaleID,
                "publicationState": "withdrawn", "fieldData": ["slug": "story"]])]
        let model = PodcastAvailabilityModel()
        model.recordIdentities(identities)
        let mirrorIdentities = PodcastAvailabilityService.danishAudioMirrorIdentities(from: mirrors)
        XCTAssertEqual(mirrorIdentities.map(\.id), [raw])
        model.recordIdentities(mirrorIdentities)
        let legacy = episode(slug: "story")
        model.recordEpisodes([legacy])
        model.setWithdrawn([englishID])
        XCTAssertTrue(model.allows(legacy))
        let plan = model.playbackPlan(current: legacy, articleID: raw, queue: [legacy])
        XCTAssertFalse(plan.stopCurrent)
        XCTAssertEqual(plan.queue.map(\.id), [legacy.id])
        model.setWithdrawn([raw, englishID])
        XCTAssertFalse(model.allows(legacy), "The original Danish withdrawal remains authoritative")
    }

    private func episode(_ id: String = "episode", articleID: String? = nil, slug: String? = "story", url: String = "a.mp3") -> PodcastEpisode {
        PodcastEpisode(id: id, articleId: articleID, articleSlug: slug, title: "Shared title", subtitle: nil,
                       audioURL: URL(string: "https://fixtures.example.invalid/" + url), productionSourceURL: nil,
                       duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)
    }

    func testExplicitWithdrawnIDBlocksStartQueueAndCurrentRegardlessOfSlug() {
        let model = PodcastAvailabilityModel(withdrawnIDs: ["A"])
        let blocked = episode(articleID: "A", slug: "unrelated")
        let allowed = episode("other", articleID: "B")
        XCTAssertFalse(model.allows(blocked))
        let plan = model.playbackPlan(current: blocked, articleID: nil, queue: [blocked, allowed])
        XCTAssertTrue(plan.stopCurrent)
        XCTAssertEqual(plan.queue.map(\.id), ["other"])
    }

    func testOldAndCurrentSlugAliasesBlockLegacyEpisodesAfterRestart() throws {
        var snapshot = PodcastAvailabilityModel.Snapshot()
        let model = PodcastAvailabilityModel(save: { snapshot = $0 })
        model.recordIdentities([("A", "  Old-Slug "), ("A", "new-slug")])
        model.setWithdrawn(["A"])
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
                                                                                  from: JSONEncoder().encode(snapshot)), withdrawnIDs: ["A"])
        XCTAssertFalse(restored.allows(episode(slug: "OLD-SLUG")))
        XCTAssertFalse(restored.allows(episode(slug: "new-slug")))
        XCTAssertTrue(restored.allows(episode(slug: "different")))
    }

    func testExplicitNewOwnerOfRecycledSlugIsNotBlockedByOldOwner() {
        let model = PodcastAvailabilityModel(withdrawnIDs: ["old-owner"])
        model.recordIdentities([("old-owner", "recycled")])
        XCTAssertTrue(model.allows(episode(articleID: "new-owner", slug: "recycled")))
        XCTAssertFalse(model.allows(episode(slug: "recycled")))
    }

    func testTitlesNeverAuthorizeOrDenyAnUnrelatedEpisode() {
        let model = PodcastAvailabilityModel(withdrawnIDs: ["A"])
        model.recordIdentities([("A", "story")])
        XCTAssertTrue(model.allows(episode("other", slug: "unrelated")))
        XCTAssertFalse(model.allows(episode("story", slug: nil)))
        XCTAssertFalse(model.allows(episode(articleID: "invalid/path")))
    }

    func testKnownAudioCannotReappearAfterImmediateRepublicationOrModelRestart() throws {
        var snapshot = PodcastAvailabilityModel.Snapshot()
        let model = PodcastAvailabilityModel(save: { snapshot = $0 })
        let old = episode(articleID: "A")
        model.recordEpisodes([old])
        model.setWithdrawn(["A"])
        model.setWithdrawn([])
        XCTAssertFalse(model.allows(old))
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
                                                                                  from: JSONEncoder().encode(snapshot)))
        XCTAssertFalse(restored.allows(old))
        let regenerated = episode(articleID: "A", url: "regenerated.mp3")
        restored.acceptManifest([old, regenerated])
        XCTAssertFalse(restored.allows(old))
        XCTAssertTrue(restored.allows(regenerated))
    }

    func testPlaybackOverrideIsRetainedForRevocationWithoutManifestIdentity() {
        let model = PodcastAvailabilityModel()
        let old = episode(slug: nil)
        model.recordPlayback(old, articleID: "A")
        model.setWithdrawn(["A"])
        model.setWithdrawn([])
        XCTAssertFalse(model.allows(old))
    }

    func testSynchronousWithdrawalEdgeRequestsStopBeforeRepublication() {
        let model = PodcastAvailabilityModel()
        let old = episode(articleID: "A")
        model.recordEpisodes([old])
        var stops: [Bool] = []
        let subscription = model.changes.sink { stops.append(model.playbackPlan(current: old, articleID: nil, queue: [old]).stopCurrent) }
        model.setWithdrawn(["A"])
        model.setWithdrawn([])
        XCTAssertEqual(stops, [true, true])
        withExtendedLifetime(subscription) {}
    }

    func testEmptyManifestIsPersistedAndDoesNotPermitFallbackEpisode() throws {
        var snapshot = PodcastAvailabilityModel.Snapshot()
        let model = PodcastAvailabilityModel(save: { snapshot = $0 })
        let old = episode()
        XCTAssertTrue(model.allows(old))
        model.acceptManifest([old])
        model.acceptManifest([])
        XCTAssertFalse(model.allows(old))
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
                                                                                  from: JSONEncoder().encode(snapshot)))
        XCTAssertFalse(restored.allows(old))
        XCTAssertTrue(restored.playbackPlan(current: old, articleID: nil, queue: [old]).stopCurrent)
    }

    func testManifestRemovalAndURLReplacementRemoveStaleQueueAndCurrent() {
        let model = PodcastAvailabilityModel()
        let old = episode(), replacement = episode(url: "new.mp3"), other = episode("other", slug: "other")
        model.acceptManifest([replacement, other])
        let plan = model.playbackPlan(current: old, articleID: nil, queue: [old, replacement, other])
        XCTAssertTrue(plan.stopCurrent)
        XCTAssertEqual(plan.queue, [replacement, other])
        XCTAssertFalse(model.allows(old))
    }

    func testDelayedIdentityArrivalRevokesAlreadyKnownLegacyAudio() {
        let model = PodcastAvailabilityModel(withdrawnIDs: ["A"])
        let old = episode(slug: "story")
        model.recordEpisodes([old])
        XCTAssertTrue(model.allows(old))
        model.recordIdentities([("A", "story")])
        XCTAssertFalse(model.allows(old))
        model.setWithdrawn([])
        XCTAssertFalse(model.allows(old))
    }

    func testIdentityBatchPersistsOnceAndUnchangedMetadataDoesNotRewrite() {
        var saves = 0
        let model = PodcastAvailabilityModel(save: { _ in saves += 1 })
        let identities = (0..<100).map { ("id-\($0)", Optional("slug-\($0)")) }
        model.recordIdentities(identities)
        XCTAssertEqual(saves, 1)
        model.recordIdentities(identities)
        XCTAssertEqual(saves, 1)
        model.recordIdentities([("invalid/path", "ignored")])
        XCTAssertEqual(saves, 1)
    }
}

extension PodcastAvailabilityModelTests {
    func testSharedAudioURLIsNotPurgedWhileAnotherKnownEpisodeIsAllowed() {
        let model = PodcastAvailabilityModel()
        let blocked = episode("blocked", articleID: "A"), allowed = episode("allowed", articleID: "B")
        model.recordEpisodes([blocked, allowed])
        model.setWithdrawn(["A"])
        XCTAssertFalse(model.allows(blocked))
        XCTAssertTrue(model.allows(allowed))
        XCTAssertTrue(model.unavailableAudioURLs.isEmpty)
        XCTAssertEqual(model.availableAudioURLs, [allowed.audioURL!])
        model.setWithdrawn(["A", "B"])
        XCTAssertEqual(model.unavailableAudioURLs, [allowed.audioURL!])
    }
}

extension PodcastAvailabilityModelTests {
    func testOlderDiskManifestCannotOverwritePersistedEmptyOrNewerMembership() throws {
        var snapshot = PodcastAvailabilityModel.Snapshot()
        let model = PodcastAvailabilityModel(save: { snapshot = $0 })
        let old = episode(), new = episode(url: "new.mp3")
        model.seedCachedManifest([old])
        XCTAssertTrue(model.allows(old))
        for accepted in [[], [new]] {
            model.acceptManifest(accepted)
            let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
                                                                                      from: JSONEncoder().encode(snapshot)))
            restored.seedCachedManifest([old])
            XCTAssertFalse(restored.allows(old))
            XCTAssertEqual(restored.allows(new), !accepted.isEmpty)
        }
    }
}

extension PodcastAvailabilityModelTests {
    func testConflictingPublicPlaybackIdentitiesAreRejectedBeforeRecordingAnyOwnership() {
        let model = PodcastAvailabilityModel()
        let audio = episode(articleID: "B")
        XCTAssertFalse(model.allows(audio, articleID: "A"))
        XCTAssertTrue(model.allows(audio, articleID: "B"))
        model.recordPlayback(audio, articleID: "A")
        model.setWithdrawn(["A"])
        XCTAssertTrue(model.allows(audio))
        XCTAssertTrue(model.snapshot.revokedKeys.isEmpty)
        for invalid in ["invalid/path", " "] {
            XCTAssertFalse(model.allows(audio, articleID: invalid))
        }
    }
}

extension PodcastAvailabilityModelTests {
    private func hash(_ digit: String) -> String { "cms-sha256-v1:" + String(repeating: digit, count: 64) }
    private func ai(_ digit: String = "a", url: String = "a.mp3") -> PodcastEpisode {
        var value = episode("ai-A", articleID: "A", url: url)
        value.isAINarration = true
        value.sourceContentRevision = hash(digit)
        return value
    }
    private func sourceArticle(_ digit: String) -> Article {
        Article(id: "A", name: "Story", slug: "story", content: "Body", intro: "", topicID: "music",
                lastPublished: "2026-10-20T10:00:00Z", contentRevision: hash(digit))
    }

    func testAIRequiresAcceptedCanonicalStrongProvenanceAndCannotDowngradeToHuman() {
        let model = PodcastAvailabilityModel()
        let valid = ai()
        XCTAssertFalse(model.allows(valid), "A caller's source label is not accepted manifest membership")
        model.acceptManifest([valid])
        XCTAssertTrue(model.allows(valid))
        var mislabeled = valid; mislabeled.isAINarration = false
        XCTAssertFalse(model.allows(mislabeled))
        var recording = valid; recording.sourceContentRevision = nil
        model.acceptManifest([recording])
        XCTAssertTrue(model.allows(recording), "A raw canonical catalog association is not a producer revision claim")
        let recordedAsset = model.audioAsset(for: recording)
        XCTAssertNotNil(recordedAsset); XCTAssertNil(recordedAsset?.sourceRevision); XCTAssertNil(recording.sourceContentRevision)
        if let recordedAsset { XCTAssertEqual(recordedAsset.binding, .acceptedRecording(articleID: "A", articleSlug: "story")) }
        for invalidRevision in ["", "updated:2026-10-20", hash("G"), hash("a") + " "] as [String?] {
            var invalid = valid; invalid.sourceContentRevision = invalidRevision
            model.acceptManifest([invalid])
            XCTAssertFalse(model.allows(invalid))
        }
        var missingID = valid
        missingID = PodcastEpisode(id: valid.id, articleId: nil, articleSlug: "story", title: valid.title,
            subtitle: nil, audioURL: valid.audioURL, productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil, isAINarration: true, sourceContentRevision: valid.sourceContentRevision)
        model.acceptManifest([missingID])
        XCTAssertFalse(model.allows(missingID, articleID: "A"), "An override cannot invent manifest provenance")
    }

    func testArticleCorrectionStopsOldAIWithoutAnyManifestRefreshAndRejectsLatePublication() {
        let articles = ArticleAvailabilityModel(schedule: { _ in {} })
        articles.trackPublicationIDs(["A"])
        articles.recordPublications([sourceArticle("a")], ticket: articles.beginRead())
        let audio = PodcastAvailabilityModel(approvedRevision: { articles.approvedRevision(for: $0) },
                                            wasInvalidated: { articles.wasInvalidated($0) })
        let old = ai(), human = episode("human", articleID: "B")
        audio.acceptManifest([old, human])
        XCTAssertTrue(audio.allows(old))
        var stops: [Bool] = []
        let subscription = articles.changes.sink { _ in
            audio.refreshArticleRevisions()
            stops.append(audio.playbackPlan(current: old, articleID: "A", queue: [old, human]).stopCurrent)
        }
        let obsoleteTicket = articles.beginRead()
        articles.recordPublications([sourceArticle("b")], ticket: articles.beginRead())
        XCTAssertEqual(stops, [true])
        XCTAssertFalse(audio.allows(old))
        XCTAssertEqual(audio.playbackPlan(current: old, articleID: "A", queue: [old, human]).queue, [human])
        articles.recordPublications([sourceArticle("a")], ticket: obsoleteTicket)
        XCTAssertEqual(articles.approvedRevision(for: "A"), hash("b"))
        XCTAssertFalse(audio.allows(old))
        withExtendedLifetime(subscription) {}
    }

    func testNewMediaAheadOfArticleConfirmationWaitsWithoutPermanentRevocation() {
        var revision = hash("a")
        let model = PodcastAvailabilityModel(approvedRevision: { _ in revision })
        let new = ai("b", url: "new.mp3")
        model.acceptManifest([new])
        XCTAssertFalse(model.allows(new))
        XCTAssertTrue(model.snapshot.revokedKeys.isEmpty)
        revision = hash("b"); model.refreshArticleRevisions()
        XCTAssertTrue(model.allows(new))
    }

    func testStaleCacheAndPlaybackCopyCannotOverwriteAcceptedMediaBindingOrKind() {
        let model = PodcastAvailabilityModel()
        let old = ai(), new = ai("b") // Same id/URL; only authoritative metadata changed.
        model.acceptManifest([new])
        XCTAssertTrue(model.allows(new))
        model.recordEpisodes([old]); model.recordPlayback(old, articleID: "A")
        model.seedCachedManifest([old])
        XCTAssertFalse(model.allows(old))
        XCTAssertTrue(model.allows(new))
        XCTAssertEqual(model.availableAudioURLs, [new.audioURL!])
        XCTAssertTrue(model.unavailableArticleAudio.isEmpty)
    }

    func testBindingsAndArticleAuthorityRoundTripSeparatelyWithoutResurrectingOldAI() throws {
        var articleState = ArticleAvailabilityModel.Snapshot()
        var audioState = PodcastAvailabilityModel.Snapshot()
        let articles = ArticleAvailabilityModel(save: { articleState = $0 }, schedule: { _ in {} })
        articles.trackPublicationIDs(["A"])
        articles.recordPublications([sourceArticle("a")], ticket: articles.beginRead())
        let audio = PodcastAvailabilityModel(approvedRevision: { articles.approvedRevision(for: $0) }, save: { audioState = $0 })
        let old = ai()
        audio.acceptManifest([old])
        articles.recordPublications([sourceArticle("b")], ticket: articles.beginRead())
        let restoredArticles = ArticleAvailabilityModel(snapshot: try JSONDecoder().decode(ArticleAvailabilityModel.Snapshot.self,
            from: JSONEncoder().encode(articleState)), schedule: { _ in {} })
        let restoredAudio = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
            from: JSONEncoder().encode(audioState)), approvedRevision: { restoredArticles.approvedRevision(for: $0) })
        restoredAudio.seedCachedManifest([old]); restoredAudio.recordEpisodes([old])
        XCTAssertFalse(restoredAudio.allows(old))
        let new = ai("b", url: "new.mp3")
        restoredAudio.acceptManifest([new])
        XCTAssertTrue(restoredAudio.allows(new))
    }

    func testLegacySnapshotMigrationPreservesDenialsAliasesAndAuthoritativeEmptyMembership() throws {
        let human = episode("human", articleID: "B"), old = ai()
        let data = try JSONSerialization.data(withJSONObject: ["aliasesByID": ["A": ["old-story"]],
            "revokedKeys": [PodcastAvailabilityModel.key(old)],
            "manifestKeys": [PodcastAvailabilityModel.key(old), PodcastAvailabilityModel.key(human)]])
        let snapshot = try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self, from: data)
        XCTAssertNil(snapshot.manifestBindings)
        let model = PodcastAvailabilityModel(snapshot: snapshot)
        XCTAssertTrue(model.allows(human))
        XCTAssertFalse(model.allows(old))
        XCTAssertEqual(model.snapshot.aliasesByID["A"], ["old-story"])
        model.acceptManifest([old, human])
        XCTAssertFalse(model.allows(old), "New source metadata cannot evade the old revocation key")
        let emptyData = Data("{\"aliasesByID\":{},\"revokedKeys\":[],\"manifestKeys\":[]}".utf8)
        let empty = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self, from: emptyData))
        empty.seedCachedManifest([human])
        XCTAssertFalse(empty.allows(human))
    }

    func testLegacyAIWaitsForFreshManifestBindingWithoutResettingOtherMembership() throws {
        let old = ai(), human = episode("human", articleID: "B")
        let data = try JSONSerialization.data(withJSONObject: ["manifestKeys": [PodcastAvailabilityModel.key(old), PodcastAvailabilityModel.key(human)]])
        let model = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self, from: data))
        model.seedCachedManifest([old, human])
        XCTAssertFalse(model.allows(old))
        XCTAssertTrue(model.allows(human))
        model.acceptManifest([old, human])
        XCTAssertTrue(model.allows(old))
    }

    func testInvalidatedArticleNeedsFreshApprovalButHumanPodcastDoesNotUseAIRevision() {
        var confirmed: String?
        let model = PodcastAvailabilityModel(approvedRevision: { _ in confirmed }, wasInvalidated: { _ in true })
        let audio = ai(), human = episode("human", articleID: "B")
        model.acceptManifest([audio, human])
        XCTAssertFalse(model.allows(audio))
        XCTAssertTrue(model.allows(human))
        confirmed = audio.sourceContentRevision; model.refreshArticleRevisions()
        XCTAssertTrue(model.allows(audio))
    }

    func testPublicationTrackingIsLimitedToRegisteredSafeIDs() {
        let articles = ArticleAvailabilityModel(schedule: { _ in {} })
        articles.trackPublicationIDs(["A", "invalid/path"])
        let other = Article(id: "unvisited", name: "Other", slug: "other", content: "", intro: "", topicID: "music", lastPublished: "2026-10-20T10:00:00Z")
        articles.recordPublications([sourceArticle("a"), other], ticket: articles.beginRead())
        XCTAssertEqual(articles.approvedRevision(for: "A"), hash("a"))
        XCTAssertNil(articles.approvedRevision(for: other.id))
    }

    func testManifestUpdatePublishesNewBindingAtomicallyAndKeepsUnrelatedSharedURLUsable() {
        let model = PodcastAvailabilityModel(approvedRevision: { id in id == "A" ? self.hash("b") : nil })
        let old = ai(), new = ai("b", url: "new.mp3"), human = episode("human", articleID: "B")
        model.acceptManifest([old, human])
        XCTAssertEqual(model.unavailableArticleAudio, [.init(articleID: "A", url: old.audioURL!)])
        XCTAssertTrue(model.unavailableAudioURLs.isEmpty, "Allowed human still uses the shared old URL")
        var allowedAtPublication: [Bool] = []
        let subscription = model.changes.sink { allowedAtPublication.append(model.allows(new)) }
        model.acceptManifest([new, human])
        XCTAssertEqual(allowedAtPublication, [true])
        XCTAssertFalse(model.allows(old))
        withExtendedLifetime(subscription) {}
    }
}

extension PodcastAvailabilityModelTests {
    /// Exact field shape emitted by local 1.7 (6) producer at Git 46929d0:
    /// functions/narration.js syncManifest and scripts/podcast-auto-publish.mjs.
    /// No services or producer scripts are executed by these tests.
    private func legacyNarration() throws -> PodcastEpisode {
        let data = Data(#"{"version":1,"updatedAt":"2026-10-20T10:00:00Z","episodes":[{"id":"ai-story","articleSlug":"story","title":"Story","subtitle":"Lyt til artiklen","audioURL":"https://firebasestorage.googleapis.com/v0/b/fixture.invalid/o/podcasts%2Fnarration%2Fstory%2Fstory.m4a?alt=media&token=fixture","hosts":["Apropos Magazine"],"publishedAt":"2026-10-20T10:00:00Z","kind":"ai"}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try XCTUnwrap(decoder.decode(PodcastManifest.self, from: data).episodes.first?.toEpisode())
    }
    private func legacyArticle(_ id: String = "A", slug: String = "story") -> Article {
        Article(id: id, name: "Story", slug: slug, content: "Body", intro: "", topicID: "music",
            lastPublished: "2026-10-20T10:00:00Z")
    }

    func testLegacyProducerNarrationSurvivesCatalogFilteringAndEnrichmentForOnlinePlay() throws {
        let raw = try legacyNarration(), article = legacyArticle()
        let model = PodcastAvailabilityModel()
        XCTAssertNil(raw.articleId)
        XCTAssertNil(raw.sourceContentRevision)
        XCTAssertTrue(raw.isAINarration)
        XCTAssertTrue(raw.hasPlayableAudioURL)
        XCTAssertFalse(model.allows(raw), "Caller-only AI data is not accepted catalog membership")
        model.acceptManifest([raw])
        model.recordIdentities([(article.id, article.slug)])
        let visible = [raw].filter { model.allows($0) }
        let matched = try XCTUnwrap(PodcastRepository.bestMatch(in: visible, for: article, requirePlayableAudio: true))
        let offered = PodcastRepository.enriched(matched, with: article)
        XCTAssertEqual(offered.articleId, article.id)
        model.recordPlayback(offered, articleID: article.id)
        XCTAssertTrue(model.allows(offered, articleID: article.id))
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: try XCTUnwrap(offered.audioURL), isOnline: true))
        XCTAssertFalse(PodcastPlaybackPolicy.canStart(playbackURL: try XCTUnwrap(offered.audioURL), isOnline: false))
        let recording = try XCTUnwrap(model.audioAsset(for: raw))
        XCTAssertEqual(recording.binding, .acceptedRecording(articleID: nil, articleSlug: "story"))
        XCTAssertNil(recording.sourceRevision); XCTAssertNil(raw.sourceContentRevision)
        XCTAssertEqual(model.audioAsset(for: offered, articleID: article.id), recording)
    }

    func testLegacyCachedNarrationSurvivesRestartWithoutInventingOfflineReceipt() throws {
        let raw = try legacyNarration(), article = legacyArticle()
        let original = PodcastAvailabilityModel()
        original.acceptManifest([raw])
        original.recordIdentities([(article.id, article.slug)])
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
            from: JSONEncoder().encode(original.snapshot)))
        restored.seedCachedManifest([raw])
        restored.recordEpisodes([raw])
        let offered = PodcastRepository.enriched(raw, with: article)
        XCTAssertTrue(restored.allows(raw))
        XCTAssertTrue(restored.allows(offered, articleID: article.id))
        let recording = try XCTUnwrap(restored.audioAsset(for: offered, articleID: article.id))
        XCTAssertEqual(recording.binding, .acceptedRecording(articleID: nil, articleSlug: "story"))
        XCTAssertNil(recording.sourceRevision); XCTAssertNil(raw.sourceContentRevision)
    }

    func testLegacyNarrationCannotAcquireAnotherArticleOrAmbiguousSlug() throws {
        let raw = try legacyNarration(), article = legacyArticle()
        let model = PodcastAvailabilityModel()
        model.acceptManifest([raw])
        model.recordIdentities([(article.id, article.slug), ("B", "other-story")])
        let correct = PodcastRepository.enriched(raw, with: article)
        XCTAssertTrue(model.allows(correct))
        XCTAssertFalse(model.allows(correct, articleID: "B"))
        XCTAssertFalse(model.allows(PodcastRepository.enriched(raw, with: legacyArticle("B", slug: "other-story"))))
        model.recordIdentities([("B", "story")])
        XCTAssertFalse(model.allows(raw), "Ambiguous legacy slug cannot select a current canonical owner")
        XCTAssertFalse(model.allows(correct))
    }

    func testLegacyNarrationWithdrawalSurvivesRepublicationAndCacheReplay() throws {
        let raw = try legacyNarration(), article = legacyArticle()
        let articles = ArticleAvailabilityModel(schedule: { _ in {} })
        let model = PodcastAvailabilityModel(approvedRevision: { articles.approvedRevision(for: $0) },
            wasInvalidated: { articles.wasInvalidated($0) })
        model.acceptManifest([raw]); model.recordIdentities([(article.id, article.slug)])
        let offered = PodcastRepository.enriched(raw, with: article)
        XCTAssertTrue(model.allows(offered))
        articles.recordWithdrawals([article.id], ticket: articles.beginRead())
        model.setWithdrawn(articles.withdrawnIDs)
        XCTAssertFalse(model.allows(raw)); XCTAssertFalse(model.allows(offered))
        XCTAssertTrue(model.playbackPlan(current: offered, articleID: article.id, queue: [raw]).stopCurrent)
        articles.recordPublications([article], ticket: articles.beginRead())
        model.setWithdrawn(articles.withdrawnIDs)
        model.acceptManifest([raw]); model.recordEpisodes([raw])
        XCTAssertFalse(model.allows(raw)); XCTAssertFalse(model.allows(offered))
    }

    func testLegacyNarrationCannotReappearAfterManifestRemovalOrChangeKind() throws {
        let raw = try legacyNarration(), model = PodcastAvailabilityModel()
        model.acceptManifest([raw])
        XCTAssertTrue(model.allows(raw))
        var human = raw; human.isAINarration = false
        XCTAssertFalse(model.allows(human))
        model.acceptManifest([])
        model.seedCachedManifest([raw]); model.recordEpisodes([raw])
        XCTAssertFalse(model.allows(raw))
    }

    func testLegacyCompatibilityDoesNotAcceptPartialOrInvalidDeclaredSource() throws {
        let raw = try legacyNarration(), model = PodcastAvailabilityModel()
        model.recordIdentities([("A", "story")])
        let declaredID = PodcastRepository.enriched(raw, with: legacyArticle())
        model.acceptManifest([declaredID])
        XCTAssertTrue(model.allows(declaredID), "A raw canonical catalog association can identify an existing recording")
        XCTAssertNotNil(model.audioAsset(for: declaredID))
        XCTAssertNil(model.audioAsset(for: declaredID)?.sourceRevision, "An association must not invent producer source proof")
        XCTAssertEqual(model.audioAsset(for: declaredID)?.binding, .acceptedRecording(articleID: "A", articleSlug: "story"))
        XCTAssertNil(declaredID.sourceContentRevision)
        for invalid in ["", "updated:2026-10-20", hash("G")] {
            var value = raw; value.sourceContentRevision = invalid
            model.acceptManifest([value])
            XCTAssertFalse(model.allows(value))
        }
        var invented = raw; invented.sourceContentRevision = hash("a")
        model.acceptManifest([raw])
        XCTAssertFalse(model.allows(invented), "A caller cannot add source proof to a legacy manifest binding")
    }
}

extension PodcastAvailabilityModelTests {
    func testLegacyPreCompatibilitySnapshotMigratesOnlyExistingCachedMembership() throws {
        let raw = try legacyNarration(), article = legacyArticle()
        let original = PodcastAvailabilityModel()
        original.acceptManifest([raw]); original.recordIdentities([(article.id, article.slug)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.snapshot)) as? [String: Any])
        var bindings = try XCTUnwrap(object["manifestBindings"] as? [String: [String: Any]])
        for key in bindings.keys { bindings[key]?.removeValue(forKey: "legacyArticleSlug") }
        object["manifestBindings"] = bindings
        let restored = PodcastAvailabilityModel(snapshot: try JSONDecoder().decode(PodcastAvailabilityModel.Snapshot.self,
            from: JSONSerialization.data(withJSONObject: object)))
        XCTAssertFalse(restored.allows(raw), "Old state must obtain its slug from the accepted cached catalog")
        let foreign = episode("unaccepted", articleID: "B", slug: "other", url: "foreign.mp3")
        restored.seedCachedManifest([raw, foreign]); restored.recordEpisodes([raw, foreign])
        XCTAssertTrue(restored.allows(raw))
        XCTAssertTrue(restored.allows(PodcastRepository.enriched(raw, with: article)))
        XCTAssertFalse(restored.allows(foreign), "Metadata migration must not add cached membership")
        XCTAssertNil(restored.audioAsset(for: raw))
    }

    func testLegacyAcceptedSlugCannotBeSubstitutedUnderSameEpisodeAndURL() throws {
        let raw = try legacyNarration(), model = PodcastAvailabilityModel()
        model.acceptManifest([raw]); model.recordIdentities([("A", "story"), ("B", "other-story")])
        let forged = PodcastEpisode(id: raw.id, articleId: "B", articleSlug: "other-story", title: raw.title,
            subtitle: raw.subtitle, audioURL: raw.audioURL, productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: raw.hosts, publishedDate: raw.publishedDate, isAINarration: true)
        model.recordPlayback(forged, articleID: "B")
        XCTAssertFalse(model.allows(forged, articleID: "B"))
        XCTAssertTrue(model.allows(PodcastRepository.enriched(raw, with: legacyArticle())))
    }

    func testLegacyNarrationOfPreviouslyWithdrawnArticleRemainsDeniedWithUnseenURL() throws {
        let raw = try legacyNarration()
        let model = PodcastAvailabilityModel(wasInvalidated: { $0 == "A" })
        model.recordIdentities([("A", "story")]); model.acceptManifest([raw])
        XCTAssertFalse(model.allows(raw))
        XCTAssertFalse(model.allows(PodcastRepository.enriched(raw, with: legacyArticle())))
        XCTAssertNil(model.audioAsset(for: raw))
    }
}
