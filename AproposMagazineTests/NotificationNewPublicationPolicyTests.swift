import CryptoKit
import XCTest
@testable import Apropos

/// Written against the installed154 API before the155 policy correction.
/// No Firebase, APNs, notification-center object or production transport exists.
@MainActor
final class NotificationNewPublicationPolicyTests: XCTestCase {
    private final class Memory {
        var bytes: Data?
        var badgeClears = 0
        var removed: [[String]] = []
        var opened: [String] = []
        var archives: [Data] = []
        var captureBadge = false
        var badgeRequests: [Int] = []
        var badgeCompletions: [(@MainActor (Bool) -> Void)] = []
        func effects() -> NotificationInboxModel.Effects {
            var effects = NotificationInboxModel.Effects(load: { self.bytes }, save: { self.bytes = $0 }, delivered: { done in
                MainActor.assumeIsolated { done([]) }
            },
                  removeDelivered: { self.removed.append($0) }, clearBadge: { done in
                self.badgeClears += 1
                MainActor.assumeIsolated { done(true) }
            }, open: { self.opened.append($0.identifier); return true })
            effects.archiveLegacy = { self.archives.append($0) }
            effects.now = { Date(timeIntervalSince1970: 0) }
            if captureBadge {
                effects.setBadge = { count, done in self.badgeRequests.append(count); self.badgeCompletions.append(done) }
            }
            return effects
        }
    }
    private func article(_ n: Int, title: String = "Public article", published: String = "2026-11-01T12:00:00Z") -> Article {
        Article(id: String(format: "%024x", n), name: title, slug: "article-\(n)", content: "", intro: "", topicID: "",
                isDraft: false, isArchived: false, createdOn: "2026-10-01T12:00:00Z",
                lastPublished: published, contentRevision: "fixture-\(n)")
    }
    private func reconcile(_ model: NotificationInboxModel, _ articles: [Article]) {
        model.reconcilePublishedArticles(articles, stillCurrent: { true }, permitsArticle: { _ in true })
    }
    private func received(_ article: Article, deliveryID: String, date: Double) -> NotificationInboxItem {
        NotificationInboxItem.make(id: deliveryID, title: "Ny artikel", body: article.name ?? "",
            date: Date(timeIntervalSince1970: date), userInfo: ["type": "new_article", "article_id": article.id,
                                                              "article_slug": article.slug ?? ""])!
    }

    func testFirstFreshCatalogEstablishesBaselineWithoutHistoricalMessages() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        reconcile(model, [article(1), article(2)])
        XCTAssertTrue(model.items.isEmpty, "First inventory is a baseline, not two received publications")
        XCTAssertEqual(model.unreadCount, 0)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertTrue(cold.items.isEmpty)
        XCTAssertEqual(memory.badgeClears, 0)
    }

    func testOnlyNewIdentityAfterBaselineAnnouncesAndCorrectionsNeverReplay() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let old = article(1), new = article(2, published: "2026-11-03T09:00:00Z")
        reconcile(model, [old])
        reconcile(model, [old, new])
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [new.id])
        model.markRead("article-publication:" + new.id)
        reconcile(model, [article(1, title: "An old corrected headline", published: "2026-11-03T10:00:00Z"),
                          article(2, title: "A corrected new headline", published: "2026-11-03T10:01:00Z")])
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [new.id])
        XCTAssertEqual(model.unreadCount, 0)
    }

    func testColdBaselineAndCanonicalDeletionDoNotReplayHistoricalRows() {
        let memory = Memory(), first = NotificationInboxModel(effects: memory.effects())
        let old = article(1), new = article(2, published: "2026-11-03T09:00:00Z")
        reconcile(first, [old])
        let cold = NotificationInboxModel(effects: memory.effects())
        reconcile(cold, [old, new])
        XCTAssertEqual(cold.items.compactMap { $0.target?.identifier }, [new.id])
        cold.delete("article-publication:" + new.id)
        let again = NotificationInboxModel(effects: memory.effects())
        reconcile(again, [old, new])
        XCTAssertTrue(again.items.isEmpty)
    }

    func testForegroundAndInboxRefreshNeverClearUnreadBadgeOrMarkMessagesRead() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), new = article(3)
        model.receive(received(new, deliveryID: "real-delivery", date: 100))
        memory.badgeClears = 0
        model.refresh(); model.refresh()
        XCTAssertEqual(model.unreadCount, 1)
        XCTAssertEqual(memory.badgeClears, 0, "An inbox visit must not reset the app icon to zero")
    }

    func testOpeningOneOfTwoUnreadMessagesDoesNotClearTheRemainingBadge() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let first = article(4), newest = article(5)
        model.receive(received(first, deliveryID: "first-delivery", date: 100))
        model.receive(received(newest, deliveryID: "newest-delivery", date: 200))
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [newest.id, first.id])
        memory.badgeClears = 0
        XCTAssertTrue(model.open("article-publication:" + newest.id))
        XCTAssertEqual(model.unreadCount, 1)
        XCTAssertEqual(memory.badgeClears, 0, "One remaining unread publication still needs a badge")
    }

    func testRealReceivedNotificationSurvivesSilentBaselineAndDuplicateDelivery() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), real = article(6)
        model.receive(received(real, deliveryID: "actual-receipt", date: 100))
        reconcile(model, [article(1), article(2), real])
        model.receive(received(real, deliveryID: "duplicate-receipt", date: 101))
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [real.id])
        XCTAssertEqual(model.unreadCount, 1)
    }

    func testEachNamespaceGetsItsOwnSilentBaselineIncludingAnEmptyNamespace() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let da = article(10), en = english(10), newerEN = english(11, published: "2026-11-03T12:00:00Z")
        model.reconcilePublishedArticles([da, en], verifiedLanguages: [.danish], stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertTrue(model.items.isEmpty)
        model.reconcilePublishedArticles([en], verifiedLanguages: [.english], stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertTrue(model.items.isEmpty)
        model.reconcilePublishedArticles([article(11), en, newerEN], verifiedLanguages: [.english],
                                         stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [newerEN.id])
        XCTAssertTrue(model.visibleItems(language: .danish).isEmpty)
        let empty = NotificationInboxModel(effects: Memory().effects())
        empty.reconcilePublishedArticles([], verifiedLanguages: [.danish], stillCurrent: { true }, permitsArticle: { _ in true })
        reconcile(empty, [da]); XCTAssertEqual(empty.items.count, 1)
    }

    func testPreviouslyMissingOldArticleAndLaterRepublishDoNotBecomeNewAnnouncements() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        reconcile(model, [article(1, published: "2026-11-02T12:00:00Z")])
        reconcile(model, [article(1), article(2, published: "2026-10-01T12:00:00Z")])
        XCTAssertTrue(model.items.isEmpty)
        reconcile(model, [article(2, published: "2026-11-03T12:00:00Z")])
        XCTAssertTrue(model.items.isEmpty, "Known identity corrections and republishes never replay")
    }

    func testAmbiguous154RowsArchiveWithoutErasingRawUnknownFieldsAndRestoreOnlyReceipt() throws {
        let memory = Memory(), old = article(12)
        var ambiguous = try XCTUnwrap(NotificationInboxItem.publishedArticle(old)); ambiguous.isRead = true
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ambiguous))
        let marker = String(repeating: "a", count: 64)
        let original = try JSONSerialization.data(withJSONObject: ["version": 1, "items": [row], "read": [],
            "dismissed": [marker], "unknown154Field": ["must": "SURVIVE_EXACTLY"]], options: [.sortedKeys])
        memory.bytes = original
        let model = NotificationInboxModel(effects: memory.effects())
        reconcile(model, [old])
        XCTAssertTrue(model.items.isEmpty); XCTAssertEqual(memory.archives, [original])
        XCTAssertTrue(String(decoding: try XCTUnwrap(memory.bytes), as: UTF8.self).contains(marker))
        let cold = NotificationInboxModel(effects: memory.effects())
        reconcile(cold, [old]); XCTAssertTrue(cold.items.isEmpty)
        cold.receive(received(old, deliveryID: "actual-UN-witness", date: 200))
        XCTAssertEqual(cold.items.first?.origin, .received)
        XCTAssertEqual(cold.items.first?.isRead, true)
        XCTAssertEqual(memory.archives.first, original)
    }

    func testExtensionReceiptCanRestoreFirstBaselineWithoutHistoricalBackfill() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects()), real = article(13)
        let witness = NotificationUnreadStore.Event(key: "article-publication:" + real.id, languageCode: "da", date: Date(timeIntervalSince1970: 200))
        model.reconcilePublishedArticles([article(1), real], verifiedLanguages: [.danish], receivedWitnesses: [witness],
                                         stillCurrent: { true }, permitsArticle: { _ in true })
        XCTAssertEqual(model.items.compactMap { $0.target?.identifier }, [real.id])
        XCTAssertEqual(model.items.first?.origin, .received)
    }

    func testBadgeRequestsAreSingleFlightAndSameCountWithNewIdentityStillDrains() {
        let memory = Memory(); memory.captureBadge = true
        let model = NotificationInboxModel(effects: memory.effects()), first = article(14), next = article(15)
        model.receive(received(first, deliveryID: "one", date: 100))
        model.markRead("article-publication:" + first.id)
        model.receive(received(next, deliveryID: "two", date: 200))
        XCTAssertEqual(memory.badgeRequests, [1])
        memory.badgeCompletions.removeFirst()(false)
        XCTAssertEqual(memory.badgeRequests, [1, 1], "Changed read/event deltas must be applied even at the same count")
        XCTAssertNil(model.issue, "An obsolete failure cannot own the current warning")
        XCTAssertEqual(model.badgeInput.received.map(\.key), ["article-publication:" + next.id])
        XCTAssertTrue(model.badgeInput.read.contains("article-publication:" + first.id))
        memory.badgeCompletions.removeFirst()(true)
        model.refresh()
        XCTAssertEqual(memory.badgeRequests.last, 1)
        XCTAssertFalse(memory.badgeRequests.contains(0), "Visiting the inbox never clears a remaining unread item")
        memory.badgeCompletions.removeFirst()(true)
    }

    func testBadgeLanguageUsesVisibleArticleNamespaceAndAudioRemainsCommon() {
        let memory = Memory(); memory.captureBadge = true
        let model = NotificationInboxModel(effects: memory.effects()), da = article(16), en = english(16)
        model.receive(received(da, deliveryID: "da", date: 100)); finishBadges(memory)
        model.receive(received(en, deliveryID: "en", date: 101)); finishBadges(memory)
        model.synchronizeBadge(language: .english); finishBadges(memory)
        XCTAssertEqual(memory.badgeRequests.last, 1)
        model.markRead("article-publication:" + en.id); finishBadges(memory)
        XCTAssertEqual(memory.badgeRequests.last, 0)
        model.synchronizeBadge(language: .danish); finishBadges(memory)
        XCTAssertEqual(memory.badgeRequests.last, 1)
        let audio = NotificationInboxItem.make(id: "audio", title: "Podcast", body: "Audio", date: Date(),
            userInfo: ["type": "new_podcast", "article_id": da.id, "podcast_title": "Podcast"])!
        model.receive(audio); finishBadges(memory)
        XCTAssertEqual(memory.badgeRequests.last, 2)
        model.synchronizeBadge(language: .english); finishBadges(memory)
        XCTAssertEqual(memory.badgeRequests.last, 1, "Audio keeps its existing shared visibility")
    }

    func testActualArchiveWriterRetainsExactBytesAndNeverOverwritesDifferentExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationArchive-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("{\"unknown\":\"keep raw bytes and spaces\"}\n".utf8)
        try NotificationInboxRuntime.archiveLegacyBytes(bytes, directory: directory)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try NotificationInboxRuntime.archiveLegacyBytes(bytes, directory: directory)
        let foreign = Data("foreign retained".utf8); try foreign.write(to: url)
        XCTAssertThrowsError(try NotificationInboxRuntime.archiveLegacyBytes(bytes, directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), foreign)
    }

    func testCoreAndExtensionShareFailClosedIdentityAdmissionWhileLegacySlugsRemainGenuine() throws {
        for (identifier, admitted) in [("en_invalid", false), ("foreign/path", false), ("bad\nidentity", false), ("legacy-article-slug", true)] {
            let memory = Memory(); memory.captureBadge = true
            let model = NotificationInboxModel(effects: memory.effects())
            let info: [AnyHashable: Any] = ["type": "new_article", "article_id": identifier]
            let date = Date(timeIntervalSince1970: 100)
            let item = try XCTUnwrap(NotificationInboxItem.make(id: "delivery", title: "Title", body: "Body", date: date, userInfo: info))
            model.receive(item)
            let extensionEvent = NotificationUnreadStore.event(userInfo: info, requestIdentifier: "delivery", date: date)
            XCTAssertEqual(model.badgeInput.received.first, extensionEvent)
            XCTAssertEqual(memory.badgeRequests.last, admitted ? 1 : 0)
        }
    }

    private func english(_ number: Int, published: String = "2026-11-01T12:00:00Z") -> Article {
        let raw = String(format: "%024x", number)
        return Article(id: "en_" + raw, name: "English", slug: "article-\(number)", content: "", intro: "", topicID: "",
                       isDraft: false, isArchived: false, lastPublished: published, contentLanguage: .english,
                       sourceArticleID: raw, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
    }
    private func finishBadges(_ memory: Memory) {
        var attempts = 0
        while !memory.badgeCompletions.isEmpty, attempts < 5 {
            attempts += 1; memory.badgeCompletions.removeFirst()(true)
        }
        XCTAssertTrue(memory.badgeCompletions.isEmpty)
    }
}

// Regression of the retained deletion boundary across model and extension storage.
@MainActor
final class NotificationTombstoneOrderTests: XCTestCase {
    private final class Memory {
        var bytes: Data?
        func effects() -> NotificationInboxModel.Effects {
            .init(load: { self.bytes }, save: { self.bytes = $0 }, delivered: { done in
                MainActor.assumeIsolated { done([]) }
            }, removeDelivered: { _ in }, clearBadge: { done in
                MainActor.assumeIsolated { done(true) }
            }, open: { _ in true }, setBadge: { _, done in
                MainActor.assumeIsolated { done(true) }
            }, now: { Date(timeIntervalSince1970: 0) })
        }
    }
    private struct Markers: Decodable { let dismissed: [String] }

    func testSuppressedDuplicateReceiptKeepsUIDeletionAndSharedBadgeExpiryAligned() throws {
        try assertDeletionAndBadgeAgree(useHeldWitness: false)
    }

    func testHeldReceiptWitnessKeepsUIDeletionAndSharedBadgeExpiryAligned() throws {
        try assertDeletionAndBadgeAgree(useHeldWitness: true)
    }

    private func assertDeletionAndBadgeAgree(useHeldWitness: Bool) throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationTombstones-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appStore = NotificationUnreadStore(directory: directory)
        let extensionStore = NotificationUnreadStore(directory: directory)
        model.reconcilePublishedArticles([], verifiedLanguages: [.danish], stillCurrent: { true }, permitsArticle: { _ in true })
        var heldWitness: NotificationUnreadStore.Event?

        for number in 1...200 {
            publish(number, model: model)
            _ = try apply(model, store: appStore)
            if number == 1 {
                let source = receipt(1, transport: "initial-real-receipt")
                let event = try XCTUnwrap(NotificationUnreadStore.event(userInfo: source.info,
                    requestIdentifier: source.item.id, date: source.item.date))
                let snapshot = try extensionStore.apply(received: [event], languageCode: "da")
                heldWitness = try XCTUnwrap(snapshot.unread.first { $0.key == key(1) })
            }
            model.delete(key(number))
            _ = try apply(model, store: appStore)
        }
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(try extensionStore.snapshot(languageCode: "da").count, 0)

        if useHeldWitness {
            model.reconcilePublishedArticles([article(1)], verifiedLanguages: [.danish],
                receivedWitnesses: [try XCTUnwrap(heldWitness)], stillCurrent: { true }, permitsArticle: { _ in true })
        } else {
            model.receive(receipt(1, transport: "suppressed-duplicate").item)
        }
        XCTAssertTrue(model.items.isEmpty, "The still-retained deletion suppresses this old receipt")
        XCTAssertEqual(try apply(model, store: appStore).count, 0)

        publish(201, model: model)
        _ = try apply(model, store: appStore)
        model.delete(key(201))
        _ = try apply(model, store: appStore)
        let markers = try JSONDecoder().decode(Markers.self, from: XCTUnwrap(memory.bytes))
        let firstHash = SHA256.hash(data: Data(key(1).utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(markers.dismissed.count, 200)
        XCTAssertFalse(markers.dismissed.contains(firstHash), "The UI's original deletion has expired")
        publish(1, model: model)
        XCTAssertTrue(model.items.isEmpty, "A known catalog identity never becomes historical backfill")

        let actual = receipt(1, transport: "new-actual-receipt-after-expiry")
        let actualEvent = try XCTUnwrap(NotificationUnreadStore.event(userInfo: actual.info,
            requestIdentifier: actual.item.id, date: actual.item.date))
        let extensionBadge = try extensionStore.apply(received: [actualEvent], languageCode: "da")
        model.receive(actual.item)
        XCTAssertEqual(model.items.first?.origin, .received)
        XCTAssertEqual(model.unreadCount, 1)
        let appBadge = try apply(model, store: appStore)
        XCTAssertEqual(extensionBadge.count, 1, "Extension badge must agree with the newly admitted actual receipt")
        XCTAssertEqual(appBadge.count, model.unreadCount, "UI and shared badge cannot disagree after the same retained-history boundary")
        XCTAssertEqual(appBadge.unread.map(\.key), model.badgeInput.received.map(\.key))
    }

    private func apply(_ model: NotificationInboxModel, store: NotificationUnreadStore) throws -> NotificationUnreadStore.Projection {
        let input = model.badgeInput
        return try store.apply(received: input.received, read: input.read, deleted: input.deleted, languageCode: "da")
    }
    private func publish(_ number: Int, model: NotificationInboxModel) {
        model.reconcilePublishedArticles([article(number)], verifiedLanguages: [.danish],
                                         stillCurrent: { true }, permitsArticle: { _ in true })
    }
    private func id(_ number: Int) -> String { String(format: "%024x", number) }
    private func key(_ number: Int) -> String { "article-publication:" + id(number) }
    private func article(_ number: Int) -> Article {
        Article(id: id(number), name: "Article \(number)", slug: "article-\(number)", content: "", intro: "", topicID: "",
                isDraft: false, isArchived: false, lastPublished: "2026-11-03T10:00:00Z")
    }
    private func receipt(_ number: Int, transport: String) -> (item: NotificationInboxItem, info: [AnyHashable: Any]) {
        let info: [AnyHashable: Any] = ["type": "new_article", "article_id": id(number)]
        let item = NotificationInboxItem.make(id: transport, title: "New article", body: "Article \(number)",
            date: Date(timeIntervalSince1970: 1_800_000_000), userInfo: info)!
        return (item, info)
    }
}
