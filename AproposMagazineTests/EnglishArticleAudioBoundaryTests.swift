import XCTest
@testable import Apropos

/// Uses the actual favorite model, body storage adapter and download coordinator.
/// No player, shared runtime, Firebase or network is constructed.
@MainActor
final class EnglishArticleAudioBoundaryTests: XCTestCase {
    private static let sourceID = "0123456789abcdef01234567"

    private func article(_ language: ArticleContentLanguage, revision: String = "text-r1") -> Article {
        Article(id: language == .english ? "en_" + Self.sourceID : Self.sourceID,
            name: language == .english ? "An English article" : "En dansk artikel",
            slug: "same-story", content: "<p>Saved text</p>", intro: "", topicID: "culture",
            lastPublished: "2026-11-03T10:00:00Z", contentRevision: revision,
            contentLanguage: language, sourceArticleID: language == .english ? Self.sourceID : nil,
            cmsLocaleId: language == .english ? ArticleContentLanguage.englishCMSLocaleID : nil)
    }

    func testEnglishBodyIsSavedReadyWithoutAnyAudioLookupDownloadOrRetry() throws {
        let h = Harness(); h.select("local-reader")
        let text = article(.english), ticket = try XCTUnwrap(h.save(text))
        XCTAssertTrue(h.offline.saveBody(text, ticket: ticket))
        XCTAssertEqual(h.offline.body(articleID: text.id)?.content, text.content)
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertNil(h.offline.audioState(ticket: ticket))
        XCTAssertEqual(h.offline.libraryOfflineSummary.ready, 1)
        XCTAssertEqual(h.offline.libraryOfflineSummary.textAvailable, 1)
        XCTAssertEqual(h.offline.libraryOfflineSummary.awaitingAudio, 0)
        XCTAssertEqual(h.audioLookups, 0)
        XCTAssertTrue(h.pins.isEmpty)
        XCTAssertTrue(h.retries.isEmpty)
        h.offline.synchronizeCurrentMembership()
        XCTAssertFalse(h.offline.cacheAudio(ticket))
        XCTAssertEqual(h.audioLookups, 0)
        XCTAssertTrue(h.pins.isEmpty)
        XCTAssertTrue(h.retries.isEmpty)
    }

    func testDanishBodyStillWaitsForAudioWhileEnglishBodyIsIndependentlyReady() throws {
        let h = Harness(); h.select("local-reader")
        let english = article(.english), danish = article(.danish)
        let enTicket = try XCTUnwrap(h.save(english)), daTicket = try XCTUnwrap(h.save(danish))
        XCTAssertTrue(h.offline.saveBody(english, ticket: enTicket))
        XCTAssertTrue(h.offline.saveBody(danish, ticket: daTicket))
        XCTAssertNil(h.offline.audioState(ticket: enTicket))
        XCTAssertEqual(h.offline.audioState(ticket: daTicket), .waitingForPublication)
        let summary = h.offline.libraryOfflineSummary
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.textAvailable, 2)
        XCTAssertEqual(summary.ready, 1)
        XCTAssertEqual(summary.awaitingAudio, 1)
        XCTAssertEqual(h.retries.count, 1, "Only the Danish article can wait for a recording")
        XCTAssertTrue(h.pins.isEmpty)
        XCTAssertEqual(h.offline.body(articleID: english.id)?.content, english.content)
        XCTAssertEqual(h.offline.body(articleID: danish.id)?.content, danish.content)
    }

    func testEnglishTextOnlyAccessStillRequiresExactOwnerAndRevision() throws {
        let h = Harness(); h.select("reader-A")
        let text = article(.english), original = try XCTUnwrap(h.save(text))
        XCTAssertTrue(h.offline.saveBody(text, ticket: original))
        XCTAssertFalse(h.offline.saveBody(article(.english, revision: "text-r2"), ticket: original))
        h.select("reader-B")
        XCTAssertNil(h.offline.body(articleID: text.id))
        XCTAssertFalse(h.offline.isCurrent(original))
        XCTAssertFalse(h.offline.saveBody(text, ticket: original))
        h.select("reader-A")
        let current = try XCTUnwrap(h.offline.captureAccess(articleID: text.id))
        XCTAssertNotEqual(current, original)
        XCTAssertEqual(h.offline.body(articleID: text.id)?.content, text.content)
        XCTAssertFalse(h.offline.isCurrent(original))
        XCTAssertTrue(h.pins.isEmpty)
    }

    func testEvenAnExplicitEnglishRecordingCannotCreateAnAudioPinOrReadinessClaim() throws {
        let h = Harness(); h.select("local-reader")
        let text = article(.english), ticket = try XCTUnwrap(h.save(text))
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: "english-recording", canonicalArticleID: text.id,
            kind: .human, sourceRevision: "text-r1", remoteURL: URL(string: "https://audio.example.test/english.m4a")!))
        h.providedAsset = asset
        XCTAssertTrue(h.offline.saveBody(text, ticket: ticket))
        XCTAssertNil(h.offline.acceptedAudioAsset(ticket))
        XCTAssertFalse(h.offline.cacheAudio(ticket, asset: asset))
        XCTAssertFalse(h.offline.audioDownloaded(articleID: text.id, expectedAsset: asset))
        XCTAssertNil(h.offline.audioState(ticket: ticket))
        XCTAssertEqual(h.offline.libraryOfflineSummary.ready, 1)
        XCTAssertEqual(h.offline.libraryOfflineSummary.audioAvailable, 0)
        XCTAssertEqual(h.audioLookups, 0)
        XCTAssertTrue(h.pins.isEmpty)
        XCTAssertTrue(h.retries.isEmpty)
    }

    func testPlaybackLanguageTableKeepsOnlyTrulyUnboundHumanPodcastsIndependent() {
        let da = episode(articleID: Self.sourceID), en = episode(articleID: "en_" + Self.sourceID)
        let legacyAI = episode(ai: true), standalone = episode()
        for language in ArticleContentLanguage.allCases {
            XCTAssertEqual(ArticleAudioLanguagePolicy.permitsPlayback(da, articleID: nil, language: language), language == .danish)
            XCTAssertFalse(ArticleAudioLanguagePolicy.permitsPlayback(en, articleID: nil, language: language))
            XCTAssertEqual(ArticleAudioLanguagePolicy.permitsPlayback(legacyAI, articleID: nil, language: language), language == .danish)
            XCTAssertTrue(ArticleAudioLanguagePolicy.permitsPlayback(standalone, articleID: nil, language: language))
            XCTAssertFalse(ArticleAudioLanguagePolicy.permitsPlayback(da, articleID: "en_" + Self.sourceID, language: language))
            XCTAssertFalse(ArticleAudioLanguagePolicy.permitsArticleID("en_malformed", language: language))
        }
        XCTAssertTrue(ArticleAudioLanguagePolicy.requiresAudio(for: article(.danish)))
        XCTAssertFalse(ArticleAudioLanguagePolicy.requiresAudio(for: article(.english)))
    }

    func testAcceptedHumanCanonicalIdentityIsCheckedAfterAssetResolution() throws {
        let raw = episode()
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: Self.sourceID,
            kind: .human, acceptedRecordingArticleID: nil, acceptedRecordingSlug: raw.articleSlug,
            remoteURL: try XCTUnwrap(raw.audioURL)))
        let identity = try XCTUnwrap(PodcastPlaybackPolicy.articleIdentity(for: raw, requestedArticleID: nil, acceptedAsset: asset))
        XCTAssertEqual(identity.articleID, Self.sourceID)
        XCTAssertTrue(ArticleAudioLanguagePolicy.permitsPlayback(raw, articleID: nil, language: .english),
            "A genuinely unbound human stream is distinct from an accepted article recording")
        XCTAssertFalse(ArticleAudioLanguagePolicy.permitsPlayback(raw, articleID: identity.articleID, language: .english))
        XCTAssertTrue(ArticleAudioLanguagePolicy.permitsPlayback(raw, articleID: identity.articleID, language: .danish))
    }

    func testActualPreparationRejectsLanguageChangeAcrossItsAsyncValidationBoundary() async throws {
        var records: [PodcastProgressNamespace: Data] = [:]
        let store = PodcastPlaybackProgressStore(storage: .init(read: { records[$0] }, write: { records[$0] = $1 }))
        store.changeContext(to: .guest)
        var effects: [String] = []
        let sessions = PodcastPlaybackSessionCoordinator(store: store, effects: .init(
            cancelCallbacks: { effects.append("cancel") }, stopPlayback: { effects.append("stop") },
            clearPresentation: { effects.append("clear") }, clearNowPlaying: { effects.append("now-playing") },
            deactivateAudio: { effects.append("deactivate") }))
        let previous = try XCTUnwrap(sessions.beginSession(episodeID: "standalone-human", articleID: nil)).ticket
        XCTAssertTrue(sessions.save(previous, seconds: 42, duration: 600))
        let originalProgress = records
        let raw = episode(ai: true, articleID: Self.sourceID)
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: raw.id, canonicalArticleID: Self.sourceID,
            kind: .ai, acceptedRecordingArticleID: Self.sourceID, acceptedRecordingSlug: raw.articleSlug,
            remoteURL: try XCTUnwrap(raw.audioURL)))
        var language = ArticleContentLanguage.danish
        let pending = try XCTUnwrap(sessions.beginPreparation(asset: asset,
            routeIsCurrent: { ArticleAudioLanguagePolicy.permitsPlayback(raw, articleID: asset.canonicalArticleID, language: language) },
            accessIsCurrent: { true }))
        var validations = 0
        let result = await sessions.prepare(pending) {
            validations += 1
            language = .english
            return true
        }
        XCTAssertEqual(validations, 1)
        XCTAssertNil(result, "Completed byte verification cannot authorize the previous language")
        XCTAssertFalse(sessions.isCurrent(pending))
        sessions.discardPreparation(pending)
        XCTAssertTrue(sessions.isCurrent(previous), "Unbound human playback is not the rejected article preparation")
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(records, originalProgress)
        language = .danish
        XCTAssertFalse(sessions.isCurrent(pending), "Switching back cannot revive a discarded request")
        language = .english
        XCTAssertNil(sessions.beginPreparation(asset: asset,
            routeIsCurrent: { ArticleAudioLanguagePolicy.permitsPlayback(raw, articleID: asset.canonicalArticleID, language: language) },
            accessIsCurrent: { true }))
        XCTAssertEqual(records, originalProgress)
        XCTAssertTrue(sessions.isCurrent(previous))
    }

    private func episode(ai: Bool = false, articleID: String? = nil) -> PodcastEpisode {
        PodcastEpisode(id: "recording", articleId: articleID, articleSlug: "same-story", title: "A recording",
            subtitle: nil, audioURL: URL(string: "https://audio.example.test/existing.m4a"),
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil,
            isAINarration: ai)
    }

    @MainActor private final class Harness {
        enum Failure: Error { case stale }
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
        var audioLookups = 0
        var providedAsset: PodcastAudioAsset?
        var pins: [PodcastAudioAsset] = []
        var retries: [() -> Void] = []
        lazy var model = FavoritesModel(storage: .init(read: { namespace, completion in
            completion(.success(self.records[namespace]))
        }, write: { namespace, record, expected, completion in
            guard self.records[namespace]?.recordRevision == expected else {
                completion(.failure(Failure.stale)); return
            }
            self.records[namespace] = record; completion(.success(()))
        }))
        lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { self.bodies[$0] }, write: { self.bodies[$0] = $1 }),
            permitsBody: { $0.hasValidContentIdentity && $0.isPubliclyPublished },
            effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in
                self.audioLookups += 1; return self.providedAsset
            }, audioIsCached: { _ in false }, pinAudio: { _, _, asset in self.pins.append(asset) },
                releaseAudio: { _, _, _ in }, scheduleRetry: { _, action in
                    self.retries.append(action); return {}
                }))
        func select(_ user: String?) {
            model.changeContext(to: .confirmed(userID: user)); offline.synchronizeCurrentMembership()
        }
        func save(_ article: Article) -> FavoritesOfflineCoordinator.AccessTicket? {
            guard model.setFavorite(article, enabled: true) != nil else { return nil }
            return offline.captureAccess(articleID: article.id)
        }
    }
}
