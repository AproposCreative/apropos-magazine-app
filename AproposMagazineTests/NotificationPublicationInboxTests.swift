import Combine
import CryptoKit
import XCTest
@testable import Apropos

@MainActor
final class NotificationPublicationInboxTests: XCTestCase {
    private var baselineModels: [NotificationInboxModel] = []
    private final class Memory {
        var bytes: Data?
        var saves = 0
        var badges = 0
        var deliveries = 0
        var pending: [(@MainActor ([NotificationInboxItem]) -> Void)] = []
        var removed: [[String]] = []
        var opened: [NotificationInboxItem.Target] = []
        var failSave = false
        var archives: [Data] = []
        func effects() -> NotificationInboxModel.Effects {
            .init(load: { self.bytes }, save: {
                if self.failSave { throw CocoaError(.fileWriteUnknown) }
                self.saves += 1; self.bytes = $0
            }, delivered: { self.deliveries += 1; self.pending.append($0) },
                  removeDelivered: { self.removed.append($0) }, clearBadge: { done in
                self.badges += 1
                // This synchronous fixture effect is invoked by the model's
                // MainActor-isolated clearBadge method.
                MainActor.assumeIsolated { done(true) }
            }, open: { self.opened.append($0); return true }, setBadge: { _, done in
                self.badges += 1; MainActor.assumeIsolated { done(true) }
            }, archiveLegacy: { self.archives.append($0) }, now: { Date(timeIntervalSince1970: 0) })
        }
    }
    private struct LegacyStore: Codable {
        let version: Int
        let items: [NotificationInboxItem]
        let read: [String]
        let dismissed: [String]
    }
    private func id(_ number: Int) -> String { String(format: "%024x", number) }
    private func article(_ number: Int, language: ArticleContentLanguage = .danish,
                         title: String = "En publiceret artikel", published: String = "2026-11-02T16:31:32.090Z",
                         draft: Bool = false, archived: Bool = false) -> Article {
        let raw = id(number)
        return Article(id: language == .english ? "en_" + raw : raw, name: title,
                       slug: "article-\(number)", content: "", intro: "", topicID: "culture",
                       isDraft: draft, isArchived: archived, createdOn: "2026-11-01T10:00:00Z",
                       lastPublished: published, contentRevision: "fixture-\(number)",
                       contentLanguage: language, sourceArticleID: language == .english ? raw : nil,
                       cmsLocaleId: language.cmsLocaleID)
    }
    private func push(_ article: Article, delivery: String, type: String = "new_article",
                      podcastTitle: String? = nil, date: TimeInterval = 1_800_000_000) -> NotificationInboxItem {
        var info: [AnyHashable: Any] = ["type": type, "article_id": article.id,
                                      "article_slug": article.slug ?? ""]
        if let podcastTitle { info["podcast_title"] = podcastTitle }
        return NotificationInboxItem.make(id: delivery, title: "En besked", body: "Publiceret",
                                          date: Date(timeIntervalSince1970: date), userInfo: info)!
    }
    private func coverArticle(_ number: Int, language: ArticleContentLanguage = .danish,
                              thumb: String? = "https://images.example.org/article-cover.jpg",
                              mobile: String? = nil, cover: String? = nil,
                              draft: Bool = false, archived: Bool = false,
                              revision: String = "cover-r1") -> Article {
        let raw = id(number)
        return Article(id: language == .english ? "en_" + raw : raw, name: "En artikel med cover",
            slug: "cover-\(number)", content: "", intro: "", topicID: "culture",
            mobileImageURL: mobile.flatMap(URL.init(string:)), thumbURL: thumb.flatMap(URL.init(string:)),
            coverURL: cover.flatMap(URL.init(string:)), isDraft: draft, isArchived: archived,
            lastPublished: "2026-11-02T16:31:32.090Z", contentRevision: revision,
            contentLanguage: language, sourceArticleID: language == .english ? raw : nil,
            cmsLocaleId: language.cmsLocaleID)
    }
    private func reconcile(_ model: NotificationInboxModel, _ articles: [Article]) {
        //155 tests start from a confirmed empty baseline, then publish new rows.
        baseline(model)
        model.reconcilePublishedArticles(articles, stillCurrent: { true }, permitsArticle: { _ in true })
    }
    private func baseline(_ model: NotificationInboxModel) {
        guard !baselineModels.contains(where: { $0 === model }) else { return }
        baselineModels.append(model)
        model.reconcilePublishedArticles([], verifiedLanguages: [.danish, .english],
                                         stillCurrent: { true }, permitsArticle: { _ in true })
    }
    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testNewPublicationAfterBaselineWithoutPushOrAudioStillOpensAfterColdStart() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let published = article(1, title: "Behemoth og Dimmu Borgir i KB Hallen")
        reconcile(model, [published])
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.unreadCount, 1)
        XCTAssertEqual(memory.deliveries, 0); XCTAssertEqual(memory.badges, 1); XCTAssertTrue(memory.removed.isEmpty)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.id, "article-publication:" + published.id)
        XCTAssertEqual(item.target?.type, "new_article"); XCTAssertNil(item.target?.podcastTitle)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items, model.items); XCTAssertTrue(cold.open(item.id))
        XCTAssertEqual(memory.opened.last?.identifier, published.id)
        XCTAssertEqual(memory.opened.last?.payload.isPodcastNotification, false)
    }

    func testPushFirstAndFeedFirstCoalesceWhileAudioRemainsSeparate() {
        for pushFirst in [false, true] {
            let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(2)
            if pushFirst { model.receive(push(published, delivery: "transport-one")) }
            reconcile(model, [published])
            model.receive(push(published, delivery: "transport-two"))
            reconcile(model, [published, published])
            XCTAssertEqual(model.items.count, 1)
            model.receive(push(published, delivery: "audio", type: "new_narration", podcastTitle: "Oplæsning"))
            XCTAssertEqual(model.items.count, 2)
            XCTAssertEqual(model.items.filter { $0.target?.payload.isArticleNotification == true }.count, 1)
            XCTAssertEqual(model.items.first { $0.id == "audio" }?.target?.payload.isPodcastNotification, true)
        }
    }

    func testKnownReceivedArticleWithoutPayloadImageGetsCoverOnFreshReconcileWithoutNewAnnouncement() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let cover = try XCTUnwrap(URL(string: "https://images.example.org/current-cover.jpg"))
        let published = Article(id: id(400), name: "En allerede kendt artikel", slug: "known-article",
            content: "", intro: "", topicID: "culture", thumbURL: cover,
            isDraft: false, isArchived: false, lastPublished: "2026-11-02T16:31:32.090Z",
            contentRevision: "current-cover-r1", contentLanguage: .danish,
            cmsLocaleId: ArticleContentLanguage.danish.cmsLocaleID)
        // A first current inventory is silent. The row exists only because an
        // actual editorial notification arrived without an image payload field.
        model.reconcilePublishedArticles([published], verifiedLanguages: [.danish],
            stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertTrue(model.items.isEmpty)
        model.receive(push(published, delivery: "received-without-artwork"))
        let original = try XCTUnwrap(model.items.first)
        XCTAssertNil(original.articleImageURL)
        model.markRead(original.id)
        let badges = memory.badges
        let badgeKeys = model.badgeInput.received.map(\.key)
        let readKeys = model.badgeInput.read
        let deletedKeys = model.badgeInput.deleted

        model.reconcilePublishedArticles([published], verifiedLanguages: [.danish],
            stillCurrent: { true }, permitsArticle: { _ in true })

        let enriched = try XCTUnwrap(model.items.first)
        XCTAssertEqual(enriched.articleImageURL, cover)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(enriched.id, original.id); XCTAssertEqual(enriched.target, original.target)
        XCTAssertEqual(enriched.title, original.title); XCTAssertEqual(enriched.body, original.body)
        XCTAssertEqual(enriched.date, original.date); XCTAssertEqual(enriched.origin, .received)
        XCTAssertTrue(enriched.isRead); XCTAssertEqual(model.unreadCount, 0)
        XCTAssertEqual(memory.badges, badges, "Artwork hydration is not a new unread publication")
        XCTAssertEqual(model.badgeInput.received.map(\.key), badgeKeys)
        XCTAssertEqual(model.badgeInput.read, readKeys); XCTAssertEqual(model.badgeInput.deleted, deletedKeys)
        XCTAssertTrue(memory.opened.isEmpty); XCTAssertEqual(memory.deliveries, 0)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items.first?.articleImageURL, cover)
        XCTAssertEqual(cold.items.first?.target, original.target)
        XCTAssertEqual(cold.items.first?.date, original.date); XCTAssertEqual(cold.unreadCount, 0)
    }

    func testFeedBeforePushArtworkProjectionRetainsTheActualMessageAndColdReadTruth() throws {
        let published = coverArticle(401)
        let received = push(published, delivery: "feed-before-push")
        let values = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([received], from: [published],
            permitsArticle: { _ in true }))
        let enriched = try XCTUnwrap(values.first)
        XCTAssertEqual(enriched.articleImageURL, published.thumbURL)
        XCTAssertEqual(enriched.id, received.id); XCTAssertEqual(enriched.target, received.target)
        XCTAssertEqual(enriched.title, received.title); XCTAssertEqual(enriched.body, received.body)
        XCTAssertEqual(enriched.date, received.date); XCTAssertEqual(enriched.origin, received.origin)
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(enriched)
        let key = try XCTUnwrap(model.items.first?.id)
        XCTAssertEqual(model.badgeInput.received.map(\.key), [key])
        model.markRead(key)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items.count, 1); XCTAssertEqual(cold.items.first?.articleImageURL, published.thumbURL)
        XCTAssertEqual(cold.unreadCount, 0); XCTAssertEqual(cold.items.first?.origin, .received)
    }

    func testArtworkProjectionRequiresExactCanonicalIdentityLanguageAndUnambiguousSlug() throws {
        let da = coverArticle(402), en = coverArticle(402, language: .english,
            thumb: "https://images.example.org/english-cover.jpg")
        let daPush = push(da, delivery: "da"), enPush = push(en, delivery: "en")
        let accepted = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([daPush, enPush], from: [da, en],
            permitsArticle: { _ in true }))
        XCTAssertEqual(accepted.map(\.articleImageURL), [da.thumbURL, en.thumbURL])
        let contradictorySlug = try XCTUnwrap(NotificationInboxItem.make(id: "wrong-slug", title: "Artikel", body: "Besked",
            date: Date(), userInfo: ["type": "new_article", "article_id": da.id, "article_slug": "different-article"]))
        let slugOnly = try XCTUnwrap(NotificationInboxItem.make(id: "slug-only", title: "Artikel", body: "Besked",
            date: Date(), userInfo: ["type": "new_article", "article_slug": da.slug!]))
        let malformedEN = try XCTUnwrap(NotificationInboxItem.make(id: "bad-en", title: "Artikel", body: "Besked",
            date: Date(), userInfo: ["type": "new_article", "article_id": "en_bad", "article_slug": da.slug!]))
        for (items, articles) in [([daPush], [en]), ([enPush], [da]),
                                  ([contradictorySlug, slugOnly, malformedEN], [da, en]),
                                  ([daPush], [da, coverArticle(402, thumb: "https://images.example.org/conflicting.jpg")])] {
            let rejected = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork(items, from: articles,
                permitsArticle: { _ in true }))
            XCTAssertTrue(rejected.allSatisfy { $0.articleImageURL == nil })
            XCTAssertEqual(rejected.map(\.target), items.map(\.target))
        }
    }

    func testArtworkProjectionCannotPromoteGenericPrivateAudioOrUnpublishedRows() throws {
        let published = coverArticle(403)
        let generic = try XCTUnwrap(NotificationInboxItem.make(id: "text-only", title: "En besked", body: "Hele teksten",
            date: Date(), userInfo: [:]))
        let privateItem = try XCTUnwrap(NotificationInboxItem.make(id: "private", title: "Privat", body: "Privat",
            date: Date(), userInfo: ["type": "new_article", "article_id": published.id, "uid": "other-owner"]))
        let audio = push(published, delivery: "audio", type: "new_narration", podcastTitle: "Lydudgave")
        let original = [generic, privateItem, audio]
        let projected = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork(original, from: [published],
            permitsArticle: { _ in true }))
        XCTAssertEqual(projected, original)
        XCTAssertNil(projected[0].target); XCTAssertNil(projected[1].target)
        XCTAssertTrue(projected[2].target?.payload.isPodcastNotification == true)
        for denied in [coverArticle(403, draft: true), coverArticle(403, archived: true)] {
            let result = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([push(published, delivery: "public")],
                from: [denied], permitsArticle: { _ in true }))
            XCTAssertNil(result.first?.articleImageURL)
        }
    }

    func testArtworkProjectionUsesCurrentAvailabilityAndOnlyValidatedImageURLs() throws {
        let availability = ArticleAvailabilityModel(), original = coverArticle(404)
        availability.trackPublicationIDs([original.id])
        availability.recordPublications([original], ticket: availability.beginRead())
        XCTAssertEqual(availability.approvedRevision(for: original.id), original.bodyRevision)
        let message = push(original, delivery: "current-availability")
        func project(_ article: Article) throws -> NotificationInboxItem {
            try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([message], from: [article],
                permitsArticle: { availability.permitsBody($0) })?.first)
        }
        XCTAssertEqual(try project(original).articleImageURL, original.thumbURL)
        let newer = coverArticle(404, revision: "cover-r2")
        availability.recordPublications([newer], ticket: availability.beginRead())
        XCTAssertEqual(availability.approvedRevision(for: newer.id), newer.bodyRevision)
        XCTAssertFalse(availability.permitsBody(original))
        XCTAssertNil(try project(original).articleImageURL, "An older approved-revision mismatch cannot supply artwork")
        XCTAssertEqual(try project(newer).articleImageURL, newer.thumbURL)
        availability.recordWithdrawals([newer.id], ticket: availability.beginRead())
        XCTAssertNil(try project(newer).articleImageURL)

        let fallback = coverArticle(405, thumb: "http://images.example.org/unsafe.jpg",
            mobile: "https://images.example.org/mobile.jpg")
        let fallbackValue = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([push(fallback, delivery: "fallback")],
            from: [fallback], permitsArticle: { _ in true })?.first)
        XCTAssertEqual(fallbackValue.articleImageURL, fallback.mobileImageURL)
        for unsafe in ["http://images.example.org/a.jpg", "file:///tmp/a.jpg",
                       "https://user:password@images.example.org/a.jpg",
                       "https://images.example.org/" + String(repeating: "a", count: 2_100)] {
            let source = coverArticle(406, thumb: unsafe)
            let result = try XCTUnwrap(NotificationInboxItem.enrichingArticleArtwork([push(source, delivery: "unsafe")],
                from: [source], permitsArticle: { _ in true })?.first)
            XCTAssertNil(result.articleImageURL)
        }
    }

    func testFreshArtworkReplacementAndRemovalPreserveMessageHistoryAndDeletion() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), original = coverArticle(407)
        model.reconcilePublishedArticles([original], verifiedLanguages: [.danish],
            stillCurrent: { true }, permitsArticle: { _ in true })
        model.receive(push(original, delivery: "received"))
        let row = try XCTUnwrap(model.items.first)
        model.markRead(row.id)
        let badges = memory.badges
        for current in [original, coverArticle(407, thumb: "https://images.example.org/replaced.jpg"),
                        coverArticle(407, thumb: nil)] {
            model.reconcilePublishedArticles([current], verifiedLanguages: [.danish],
                stillCurrent: { true }, permitsArticle: { _ in true })
            XCTAssertEqual(model.items.first?.articleImageURL, current.thumbURL)
            XCTAssertEqual(model.items.first?.id, row.id); XCTAssertEqual(model.items.first?.target, row.target)
            XCTAssertEqual(model.items.first?.title, row.title); XCTAssertEqual(model.items.first?.body, row.body)
            XCTAssertEqual(model.items.first?.date, row.date); XCTAssertEqual(model.items.first?.isRead, true)
            XCTAssertEqual(model.items.first?.origin, .received); XCTAssertEqual(model.items.count, 1)
            XCTAssertEqual(memory.badges, badges)
            XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items, model.items)
        }
        model.delete(row.id)
        model.reconcilePublishedArticles([original], verifiedLanguages: [.danish],
            stillCurrent: { true }, permitsArticle: { _ in true })
        model.receive(push(original, delivery: "late-duplicate"))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(NotificationInboxModel(effects: memory.effects()).items.isEmpty)
    }

    func testArtworkOnlyCatchupCannotOverwriteRevocationNewerReceiptOrUserDeletion() throws {
        for action in ["revoke", "receive", "delete"] {
            let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), source = coverArticle(408)
            model.reconcilePublishedArticles([source], verifiedLanguages: [.danish],
                stillCurrent: { true }, permitsArticle: { _ in true })
            model.receive(push(source, delivery: "original"))
            let row = try XCTUnwrap(model.items.first), stored = memory.bytes
            let newerImage = try XCTUnwrap(URL(string: "https://images.example.org/newer-receipt.jpg"))
            let newer = try XCTUnwrap(NotificationInboxItem.make(id: "newer", title: row.title, body: row.body,
                date: row.date, userInfo: ["type": "new_article", "article_id": source.id,
                    "article_slug": source.slug!, "thumbnail_url": newerImage.absoluteString]))
            var current = true, entered = false
            let observer = model.objectWillChange.sink {
                guard !entered else { return }; entered = true
                switch action {
                case "revoke": current = false
                case "receive": model.receive(newer)
                default: model.delete(row.id)
                }
            }
            model.reconcilePublishedArticles([source], verifiedLanguages: [.danish],
                stillCurrent: { current }, permitsArticle: { _ in true })
            XCTAssertTrue(entered)
            if action == "delete" { XCTAssertTrue(model.items.isEmpty) }
            else if action == "receive" { XCTAssertEqual(model.items.first?.articleImageURL, newerImage) }
            else { XCTAssertNil(model.items.first?.articleImageURL); XCTAssertEqual(memory.bytes, stored) }
            XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items, model.items)
            withExtendedLifetime(observer) {}
        }
    }

    func testArtworkProjectionStopsWhenPermissionReentersAndRevokesItsSource() {
        let source = coverArticle(409), message = push(source, delivery: "held")
        var current = true, calls = 0
        let result = NotificationInboxItem.enrichingArticleArtwork([message], from: [source],
            stillCurrent: { current }, permitsArticle: { _ in calls += 1; current = false; return true })
        XCTAssertNil(result); XCTAssertEqual(calls, 1)
        XCTAssertNil(message.articleImageURL)
    }

    func testCanonicalReadAndDeleteSurviveLatePushAndColdCatchup() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(3)
        reconcile(model, [published]); let key = try XCTUnwrap(model.items.first?.id)
        model.markRead(key)
        model.receive(push(published, delivery: "later-message")); reconcile(model, [published])
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.unreadCount, 0)
        XCTAssertEqual(memory.removed.last, [key])
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.unreadCount, 0); cold.delete(key)
        cold.receive(push(published, delivery: "another-message")); reconcile(cold, [published])
        XCTAssertTrue(cold.items.isEmpty)
        let secondCold = NotificationInboxModel(effects: memory.effects())
        reconcile(secondCold, [published]); XCTAssertTrue(secondCold.items.isEmpty)
    }

    func testHeldDeliveredSnapshotCannotOverwriteFreshCanonicalCatchup() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(4, title: "Frisk titel")
        model.refresh(); let held = memory.pending.removeFirst()
        reconcile(model, [published]); held([push(published, delivery: "held-older-push")])
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.items.first?.title, "Frisk titel")
        XCTAssertFalse(model.refreshing)
    }

    func testKnownLegacyTargetMigratesReadAndDismissMarkersWithoutGuessingUnknownHashes() throws {
        let memory = Memory(), readArticle = article(5), deletedArticle = article(6), discovered = article(7)
        let legacyRead = push(readArticle, delivery: "known-old-read")
        let legacyDeleted = push(deletedArticle, delivery: "known-old-deleted")
        let unknown = hash("opaque-v1-deletion-with-no-target")
        memory.bytes = try JSONEncoder().encode(LegacyStore(version: 1, items: [legacyRead, legacyDeleted],
            read: [hash(legacyRead.id)], dismissed: [hash(legacyDeleted.id), unknown]))
        let model = NotificationInboxModel(effects: memory.effects())
        reconcile(model, [readArticle, deletedArticle, discovered])
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first { $0.target?.identifier == readArticle.id }?.isRead, true)
        XCTAssertFalse(model.items.contains { $0.target?.identifier == deletedArticle.id })
        // There is no target to reconstruct for an already-deleted opaque v1
        // hash. First backfill can discover an article; the original hash stays.
        XCTAssertTrue(model.items.contains { $0.target?.identifier == discovered.id })
        let stored = try JSONDecoder().decode(LegacyStore.self, from: XCTUnwrap(memory.bytes))
        XCTAssertTrue(stored.dismissed.contains(unknown))
        XCTAssertTrue(stored.dismissed.contains(hash(legacyDeleted.id)))
        XCTAssertTrue(stored.dismissed.contains(hash("article-publication:" + deletedArticle.id)))
    }

    func testAllVerifiedLanguagesIngestTogetherAndVisibleArticleIdentityStaysExact() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let da = article(8), en = article(8, language: .english, title: "An English article")
        reconcile(model, [da, en])
        let generic = NotificationInboxItem.make(id: "general", title: "Lokalt", body: "Text", date: Date(), userInfo: [:])!
        model.receive(generic); model.receive(push(da, delivery: "audio", type: "new_podcast", podcastTitle: "Podcast"))
        XCTAssertEqual(model.items.count, 4)
        let danish = model.visibleItems(language: .danish), english = model.visibleItems(language: .english)
        XCTAssertTrue(danish.contains { $0.target?.identifier == da.id && $0.target?.payload.isArticleNotification == true })
        XCTAssertFalse(danish.contains { $0.target?.identifier == en.id })
        XCTAssertFalse(english.contains { $0.target?.identifier == da.id && $0.target?.payload.isArticleNotification == true })
        XCTAssertEqual(english.first { $0.target?.identifier == en.id }?.body, "Read the article")
        for values in [danish, english] { XCTAssertTrue(values.contains { $0.id == "audio" }); XCTAssertTrue(values.contains { $0.id == "general" }) }
    }

    func testUnavailableDraftArchivedMalformedAndConflictingSourcesAreNotAdmitted() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let denied = article(9), duplicateA = article(13), duplicateB = article(13, title: "Conflicting snapshot")
        model.reconcilePublishedArticles([denied, article(10, draft: true), article(11, archived: true),
            article(12, published: "invalid"), duplicateA, duplicateB], stillCurrent: { true },
            permitsArticle: { $0.id != denied.id })
        XCTAssertTrue(model.items.isEmpty)
        let malformed = Article(id: "en_" + id(14), name: "Wrong namespace", slug: "wrong", content: "", intro: "", topicID: "",
                                isDraft: false, lastPublished: "2026-11-02T16:00:00Z", contentLanguage: .danish)
        reconcile(model, [malformed]); XCTAssertTrue(model.items.isEmpty)
    }

    func testRevokedOrReentrantAdmissionCannotPersistTheOlderBatch() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        var current = false
        model.reconcilePublishedArticles([article(15)], stillCurrent: { current }, permitsArticle: { _ in true })
        XCTAssertEqual(memory.saves, 0); XCTAssertTrue(model.items.isEmpty)
        current = true
        model.reconcilePublishedArticles([article(15)], stillCurrent: { current }, permitsArticle: { _ in current = false; return true })
        XCTAssertEqual(memory.saves, 0); XCTAssertTrue(model.items.isEmpty)
        var nested = false
        model.reconcilePublishedArticles([article(15)], stillCurrent: { true }, permitsArticle: { _ in
            if !nested { nested = true; self.reconcile(model, [self.article(16)]) }
            return true
        })
        XCTAssertEqual(model.items.map { $0.target?.identifier }, [id(16)])
    }

    func testNewPublicationsAfterSilentBaselineKeepNewestHundred() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let formatter = ISO8601DateFormatter()
        let articles = (1...110).map { number in
            article(number, published: formatter.string(from: Date(timeIntervalSince1970: Double(number))))
        }
        reconcile(model, Array(articles.reversed()))
        XCTAssertEqual(model.items.count, 100)
        XCTAssertEqual(model.items.first?.target?.identifier, id(110))
        XCTAssertFalse(model.items.contains { $0.target?.identifier == id(10) })
        XCTAssertTrue(model.items.contains { $0.target?.identifier == id(11) })
        XCTAssertEqual(memory.deliveries, 0); XCTAssertEqual(memory.badges, 1); XCTAssertTrue(memory.removed.isEmpty)
    }

    func testRepublishDoesNotResetReadTruthOrOriginalAnnouncementDate() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), original = article(17)
        reconcile(model, [original]); let item = try XCTUnwrap(model.items.first); model.markRead(item.id)
        reconcile(model, [article(17, title: "Corrected headline", published: "2026-11-03T18:00:00Z")])
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.items.first?.date, item.date)
        XCTAssertEqual(model.items.first?.title, original.name, "A correction is not a new publication message")
        XCTAssertEqual(model.unreadCount, 0)
        model.receive(push(original, delivery: "republish-push")); XCTAssertEqual(model.unreadCount, 0)
    }

    func testCatchupSaveFailureIsVisibleAndCorruptHistoryIsNeverOverwritten() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        reconcile(model, [article(18)]); let previous = try XCTUnwrap(memory.bytes)
        memory.failSave = true; reconcile(model, [article(19)])
        XCTAssertNotNil(model.issue); XCTAssertEqual(memory.bytes, previous)
        XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items.count, 1)
        let broken = Memory(); broken.bytes = Data("invalid".utf8)
        let corrupt = NotificationInboxModel(effects: broken.effects()); reconcile(corrupt, [article(18)])
        XCTAssertNotNil(corrupt.issue); XCTAssertEqual(broken.bytes, Data("invalid".utf8)); XCTAssertEqual(broken.saves, 0)
    }

    func testPrivatePayloadCannotAcquirePublicPersistenceThroughCanonicalDeduplication() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(20)
        let privateItem = try XCTUnwrap(NotificationInboxItem.make(id: "private", title: "PRIVATE_ACCOUNT", body: "PRIVATE_BODY",
            date: Date(), userInfo: ["type": "new_article", "article_id": published.id, "uid": "private-owner"]))
        model.receive(privateItem); reconcile(model, [published])
        XCTAssertEqual(model.items.count, 2)
        let text = String(decoding: try XCTUnwrap(memory.bytes), as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE")); XCTAssertFalse(text.contains("private-owner"))
        XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items.count, 1)
    }

    func testUnclassifiedDeliveryCannotImpersonateReservedArticleIdentity() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(21)
        reconcile(model, [published])
        let reserved = try XCTUnwrap(model.items.first?.id)
        let unrelated = try XCTUnwrap(NotificationInboxItem.make(id: reserved, title: "PRIVATE_UNCLASSIFIED",
            body: "Private", date: Date(), userInfo: [:]))
        model.receive(unrelated)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first { $0.id == reserved }?.target?.identifier, published.id)
        XCTAssertFalse(String(decoding: try XCTUnwrap(memory.bytes), as: UTF8.self).contains("PRIVATE_UNCLASSIFIED"))
        XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items.first?.id, reserved)
    }

    func testWillChangeRevocationRejectsTheWholeCatchupBeforePublicationOrSave() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        baseline(model); memory.saves = 0
        var current = true
        let observer = model.objectWillChange.sink { current = false }
        model.reconcilePublishedArticles([article(22), article(23)], stillCurrent: { current }, permitsArticle: { _ in true })
        XCTAssertTrue(model.items.isEmpty); XCTAssertEqual(memory.saves, 0)
        XCTAssertEqual(memory.badges, 0); XCTAssertEqual(memory.deliveries, 0)
        withExtendedLifetime(observer) {}
    }

    func testWillChangeNestedReceiveWinsWithoutOlderCatchupOverwritingOrPersistingIt() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), newest = article(24)
        baseline(model); memory.saves = 0
        var entered = false
        let observer = model.objectWillChange.sink {
            guard !entered else { return }; entered = true
            model.receive(self.push(newest, delivery: "newer-push"))
        }
        reconcile(model, [article(22), article(23)])
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [newest.id])
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items, model.items)
        XCTAssertEqual(memory.saves, 1)
        withExtendedLifetime(observer) {}
    }

    func testWillChangeNestedFreshCatchupWinsAndHundredRowCommitHasBoundedNotifications() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), newest = article(25)
        baseline(model)
        var entered = false
        let observer = model.objectWillChange.sink {
            guard !entered else { return }; entered = true
            self.reconcile(model, [newest])
        }
        reconcile(model, [article(22), article(23)])
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [newest.id])
        XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items, model.items)
        withExtendedLifetime(observer) {}

        let bounded = NotificationInboxModel(effects: Memory().effects())
        var notifications = 0
        let counter = bounded.objectWillChange.sink { notifications += 1 }
        reconcile(bounded, (1...100).map { article($0) })
        XCTAssertEqual(bounded.items.count, 100)
        XCTAssertEqual(notifications, 1, "One catchup commit must not notify once per article")
        withExtendedLifetime(counter) {}
    }

    func testWillChangeNestedUserReadOrDeleteWinsOverOlderCatchup() throws {
        for delete in [false, true] {
            let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), published = article(26)
            reconcile(model, [published]); let key = try XCTUnwrap(model.items.first?.id)
            var entered = false
            let observer = model.objectWillChange.sink {
                guard !entered else { return }; entered = true
                if delete { model.delete(key) } else { model.markRead(key) }
            }
            reconcile(model, [article(26, title: "Older candidate"), article(27)])
            if delete { XCTAssertTrue(model.items.isEmpty) }
            else { XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.items.first?.isRead, true) }
            XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items, model.items)
            withExtendedLifetime(observer) {}
        }
    }

    func testCanonicalDeletionGuaranteeFollowsExistingTwoHundredMarkerRetention() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        for number in 1...200 {
            reconcile(model, [article(number)])
            model.delete("article-publication:" + id(number))
        }
        let first = hash("article-publication:" + id(1))
        let retained = try JSONDecoder().decode(LegacyStore.self, from: XCTUnwrap(memory.bytes))
        XCTAssertEqual(retained.dismissed.count, 200); XCTAssertTrue(retained.dismissed.contains(first))
        reconcile(model, [article(1)]); XCTAssertTrue(model.items.isEmpty)
        reconcile(model, [article(201)]); model.delete("article-publication:" + id(201))
        let expired = try JSONDecoder().decode(LegacyStore.self, from: XCTUnwrap(memory.bytes))
        XCTAssertEqual(expired.dismissed.count, 200); XCTAssertFalse(expired.dismissed.contains(first))
        let cold = NotificationInboxModel(effects: memory.effects())
        reconcile(cold, [article(1)])
        XCTAssertTrue(cold.items.isEmpty, "A known catalog identity is not a new publication after marker expiry")
        cold.receive(push(article(1), delivery: "genuine-after-retained-deletion-expiry"))
        XCTAssertEqual(cold.items.first?.target?.identifier, id(1), "A new actual receipt can outlive bounded deletion history")
        XCTAssertEqual(cold.items.first?.origin, .received)
        XCTAssertEqual(cold.badgeInput.received.map(\.key), ["article-publication:" + id(1)])
    }

    func testWillChangeObserverCanAlwaysRequestCatchupWithoutRecursivePublication() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), newest = article(28)
        baseline(model)
        var notifications = 0
        let observer = model.objectWillChange.sink {
            notifications += 1
            // Fail-safe bounds a broken implementation; no entered flag hides
            // whether another publication recursively invokes this observer.
            guard notifications < 5 else { return }
            self.reconcile(model, [newest])
        }
        reconcile(model, [article(29)])
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [newest.id])
        withExtendedLifetime(observer) {}
    }

    func testNewerEmptyCatchupInsideWillChangePreventsFirstOlderBatchCommit() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        baseline(model); memory.saves = 0
        var notifications = 0
        let observer = model.objectWillChange.sink {
            notifications += 1
            guard notifications < 5 else { return }
            self.reconcile(model, [])
        }
        reconcile(model, [article(30)])
        XCTAssertEqual(notifications, 1); XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(NotificationInboxModel(effects: memory.effects()).items, [])
        XCTAssertEqual(memory.saves, 1, "Only the newer empty catchup may persist")
        withExtendedLifetime(observer) {}
    }
}
