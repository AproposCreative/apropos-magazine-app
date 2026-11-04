import XCTest
@testable import Apropos

@MainActor
final class NotificationInboxModelTests: XCTestCase {
    private final class Memory {
        var bytes: Data?
        var pending: [(@MainActor ([NotificationInboxItem]) -> Void)] = []
        var removed: [[String]] = []
        var badgeCallbacks: [(@MainActor (Bool) -> Void)] = []
        var failSave = false
        var opens: [String] = []
        func effects() -> NotificationInboxModel.Effects {
            .init(load: { self.bytes }, save: {
                if self.failSave { throw CocoaError(.fileWriteUnknown) }
                self.bytes = $0
            }, delivered: { self.pending.append($0) }, removeDelivered: { self.removed.append($0) },
            clearBadge: { self.badgeCallbacks.append($0) }, open: { self.opens.append($0.identifier); return true },
                  setBadge: { _, done in self.badgeCallbacks.append(done) })
        }
    }
    private func item(_ id: String, type: String? = "new_article", body: String = "En redaktionel besked", date: Double = 100) -> NotificationInboxItem {
        var info: [String: Any] = ["article_id": "article-\(id)"]
        if let type { info["type"] = type }
        return NotificationInboxItem.make(id: id, title: "Titel \(id)", body: body,
            date: Date(timeIntervalSince1970: date), userInfo: info)!
    }
    func testRefreshDeduplicatesAndReadStateSurvivesColdPublicReload() throws {
        let memory = Memory(), value = item("one")
        let model = NotificationInboxModel(effects: memory.effects())
        model.receive(value); model.refresh(); memory.pending.removeFirst()([value, value])
        XCTAssertEqual(model.items.map(\.id), ["one"]); XCTAssertEqual(model.unreadCount, 1)
        model.markRead("one")
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items.map(\.id), ["one"]); XCTAssertEqual(cold.unreadCount, 0)
        cold.refresh(); memory.pending.removeFirst()([value])
        XCTAssertEqual(cold.unreadCount, 0); XCTAssertEqual(memory.removed, [["one"]])
    }
    func testUnknownAndOwnerBoundTextNeverPersistsOrRoutes() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let unknown = item("manual", type: nil, body: "SENSITIVE_MANUAL_TEXT")
        let owner = NotificationInboxItem.make(id: "owned", title: "SENSITIVE_ACCOUNT_TEXT", body: "private",
            date: Date(timeIntervalSince1970: 100), userInfo: ["type": "new_article", "article_id": "a", "uid": "A"])!
        model.receive(unknown); model.receive(owner)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertTrue(model.items.allSatisfy { $0.target == nil })
        XCTAssertFalse(model.open("owned")); XCTAssertTrue(memory.opens.isEmpty)
        let bytes = try XCTUnwrap(memory.bytes), text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("SENSITIVE")); XCTAssertFalse(text.contains("owned"))
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertTrue(cold.items.isEmpty)
    }
    func testOnlyFourEditorialKindsArePersistableAndTargeted() {
        for type in ["new_article", "breaking_news", "new_podcast", "new_narration"] {
            XCTAssertTrue(item(type, type: type).canPersist)
        }
        for type in ["general", "test", "recommendation", "", "NEW_ARTICLE"] {
            XCTAssertFalse(item("one", type: type).canPersist)
        }
        XCTAssertFalse(item("one", type: nil).canPersist)
    }
    func testNewerRefreshWinsAndDirectArrivalSurvivesOlderSnapshot() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.refresh(); model.refresh()
        let old = memory.pending.removeFirst(), current = memory.pending.removeFirst()
        current([item("current")]); old([item("old")])
        XCTAssertEqual(model.items.map(\.id), ["current"])
        model.refresh(); let late = memory.pending.removeFirst()
        model.receive(item("manual", type: nil, date: 200))
        late([item("current")])
        XCTAssertEqual(Set(model.items.map(\.id)), ["current", "manual"])
    }
    func testMarkAllCapturesOnlyExistingIDsAndLateNewArrivalRemainsUnread() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(item("one")); model.refresh(); let held = memory.pending.removeFirst()
        model.markAllRead(); model.receive(item("two", date: 200)); held([item("one"), item("two", date: 200)])
        XCTAssertEqual(model.items.first(where: { $0.id == "one" })?.isRead, true)
        XCTAssertEqual(model.items.first(where: { $0.id == "two" })?.isRead, false)
        XCTAssertEqual(model.unreadCount, 1); XCTAssertEqual(memory.removed, [["one"]])
    }
    func testDeleteCannotBeResurrectedByHeldSnapshotOrColdReload() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(item("one")); model.refresh(); let held = memory.pending.removeFirst()
        model.delete("one"); held([item("one")])
        XCTAssertTrue(model.items.isEmpty)
        let cold = NotificationInboxModel(effects: memory.effects())
        cold.refresh(); memory.pending.removeFirst()([item("one")])
        XCTAssertTrue(cold.items.isEmpty); XCTAssertEqual(memory.removed, [["one"]])
    }
    func testPersistenceFailureIsVisibleAndColdModelUsesLastWrittenBytes() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(item("one")); memory.failSave = true
        model.markRead("one")
        XCTAssertNotNil(model.issue); XCTAssertEqual(model.unreadCount, 0)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.unreadCount, 1)
    }
    func testLatestBadgeAttemptOwnsItsError() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.clearBadge(); model.clearBadge()
        XCTAssertEqual(memory.badgeCallbacks.count, 1, "Only one OS badge request is in flight")
        let old = memory.badgeCallbacks.removeFirst()
        old(false)
        let current = memory.badgeCallbacks.removeFirst()
        current(true)
        XCTAssertNil(model.issue)
        model.clearBadge(); memory.badgeCallbacks.removeFirst()(false)
        XCTAssertNotNil(model.issue)
    }
    func testMalformedAndOversizedPayloadsAreRejectedOrSanitized() {
        XCTAssertNil(NotificationInboxItem.make(id: "", title: "title", body: "body", date: Date(), userInfo: [:]))
        XCTAssertNil(NotificationInboxItem.make(id: "x", title: " ", body: "\n", date: Date(), userInfo: [:]))
        XCTAssertNil(NotificationInboxItem.make(id: "x", title: "title", body: "body", date: Date(timeIntervalSince1970: .infinity), userInfo: [:]))
        let bounded = NotificationInboxItem.make(id: "x", title: String(repeating: "å", count: 1000),
            body: String(repeating: "b", count: 3000), date: Date(), userInfo: ["type": "new_article", "article_id": String(repeating: "a", count: 300)])!
        XCTAssertEqual(bounded.title.count, 240); XCTAssertEqual(bounded.body.count, 1600); XCTAssertNil(bounded.target)
        let memory = Memory(); memory.bytes = Data("broken".utf8)
        let corrupt = NotificationInboxModel(effects: memory.effects()); corrupt.receive(item("one"))
        XCTAssertNotNil(corrupt.issue); XCTAssertEqual(memory.bytes, Data("broken".utf8))
    }
    func testPublicRetentionIsBoundedAndOpeningUsesExistingTypedTarget() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        for i in 0..<110 { model.receive(item("\(i)", date: Double(i))) }
        XCTAssertEqual(model.items.count, 100); XCTAssertEqual(model.items.first?.id, "109")
        XCTAssertFalse(model.items.contains { $0.id == "0" })
        XCTAssertTrue(model.open("109")); XCTAssertEqual(memory.opens, ["article-109"])
        XCTAssertEqual(model.items.first?.isRead, true)
        XCTAssertFalse(model.open("missing"))
    }
    func testPersistedPublicReadTruthSurvivesBoundedMarkerRotation() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let retained = item("retained", date: 100_000_000)
        model.receive(retained); model.markRead(retained.id)
        for number in 0..<205 {
            let transient = item("manual-\(number)", type: nil, date: Double(number))
            model.receive(transient); model.markRead(transient.id)
        }
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items.count, 1)
        XCTAssertEqual(cold.items.first?.id, retained.id)
        XCTAssertEqual(cold.unreadCount, 0)
        cold.refresh(); memory.pending.removeFirst()([retained])
        XCTAssertEqual(cold.unreadCount, 0)
    }
    func testSuccessfulSaveAndBadgeRetryClearOnlyTheirOwnRecoverableWarning() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(item("one")); memory.badgeCallbacks.removeFirst()(true)
        memory.failSave = true; model.markRead("one")
        XCTAssertNotNil(model.issue)
        memory.failSave = false; model.refresh(); memory.pending.removeFirst()([])
        XCTAssertNil(model.issue)
        let prior = memory.badgeCallbacks; memory.badgeCallbacks.removeAll()
        prior.last?(false)
        memory.badgeCallbacks.removeFirst()(false)
        XCTAssertNotNil(model.issue)
        model.clearBadge(); memory.badgeCallbacks.removeFirst()(true)
        XCTAssertNil(model.issue)

        let damaged = Memory(); damaged.bytes = Data("bad".utf8)
        let corrupt = NotificationInboxModel(effects: damaged.effects())
        let warning = corrupt.issue
        corrupt.clearBadge(); damaged.badgeCallbacks.removeFirst()(false)
        XCTAssertEqual(corrupt.issue, warning)
        corrupt.clearBadge(); damaged.badgeCallbacks.removeFirst()(true)
        XCTAssertEqual(corrupt.issue, warning)
    }
    func testDuplicateStoredIdentifiersAndOversizedRawStorageAreRejectedWithoutOverwrite() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.receive(item("one"))
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.bytes)) as? [String: Any])
        var items = try XCTUnwrap(stored["items"] as? [[String: Any]])
        items.append(items[0]); stored["items"] = items
        memory.bytes = try JSONSerialization.data(withJSONObject: stored)
        let original = memory.bytes
        let corrupt = NotificationInboxModel(effects: memory.effects())
        XCTAssertTrue(corrupt.items.isEmpty); XCTAssertNotNil(corrupt.issue)
        corrupt.receive(item("two")); XCTAssertEqual(memory.bytes, original)

        let huge = Memory(); huge.bytes = Data(repeating: 32, count: 1_500_001)
        let bounded = NotificationInboxModel(effects: huge.effects())
        XCTAssertTrue(bounded.items.isEmpty); XCTAssertNotNil(bounded.issue)
    }

    func testCombiningScalarInputCannotBypassByteBounds() {
        let huge = "a" + String(repeating: "\u{0301}", count: 20_000)
        let value = NotificationInboxItem.make(id: "unicode", title: huge, body: huge,
            date: Date(), userInfo: ["type": "new_article", "article_id": "valid"])!
        XCTAssertLessThanOrEqual(value.title.utf8.count, 1_000)
        XCTAssertLessThanOrEqual(value.body.utf8.count, 6_500)
        XCTAssertTrue(value.canPersist)
    }

    func testDismissedDeliveryIsNotOpenedAndEmptyIsKnownOnlyAfterSnapshot() {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        model.refresh()
        XCTAssertTrue(model.refreshing); XCTAssertTrue(model.items.isEmpty)
        memory.pending.removeFirst()([])
        XCTAssertFalse(model.refreshing); XCTAssertTrue(model.items.isEmpty)
        model.receive(item("dismissed"), opened: false)
        model.receive(item("opened"), opened: true)
        XCTAssertEqual(model.items.first(where: { $0.id == "dismissed" })?.isRead, false)
        XCTAssertEqual(model.items.first(where: { $0.id == "opened" })?.isRead, true)
        XCTAssertEqual(model.unreadCount, 1)
        XCTAssertTrue(memory.opens.isEmpty)
    }

    func testArticleImageMetadataKeepsVersionOneColdCompatibilityAndReadTruth() throws {
        let memory = Memory()
        // The original v1 input remains readable without an artwork key.
        // Version 155 writes v2 provenance/baseline state after a genuine receipt.
        memory.bytes = Data(#"{"version":1,"items":[{"id":"cover","title":"Original titel","body":"Original besked","date":0,"target":{"identifier":"article-cover","type":"new_article"},"isRead":true}],"read":[],"dismissed":[]}"#.utf8)
        let model = NotificationInboxModel(effects: memory.effects())
        XCTAssertNil(model.issue); XCTAssertEqual(model.items.count, 1)
        XCTAssertNil(model.items.first?.articleImageURL); XCTAssertEqual(model.unreadCount, 0)
        let image = "https://images.example.org/article.jpg"
        model.receive(imageItem(["type": "new_article", "article_id": "article-cover", "thumbnail_url": image]))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.bytes)) as? [String: Any])
        XCTAssertEqual(stored["version"] as? Int, 2)
        let values = try XCTUnwrap(stored["items"] as? [[String: Any]])
        XCTAssertEqual(values.first?["articleImageURL"] as? String, image)
        XCTAssertEqual(values.first?["origin"] as? String, "received")
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertNil(cold.issue); XCTAssertEqual(cold.items.count, 1)
        XCTAssertEqual(cold.items.first?.articleImageURL?.absoluteString, image)
        XCTAssertEqual(cold.items.first?.target?.identifier, "article-cover")
        XCTAssertEqual(cold.unreadCount, 0)
    }

    func testArticleImagesRespectAdmissionAndRejectUnsafeOrOversizedURLs() {
        let image = "https://images.example.org/article.jpg"
        for type in ["new_article", "breaking_news", "new_narration"] {
            let value = imageItem(["type": type, "article_id": "a", "thumbnail_url": image])
            XCTAssertEqual(value.articleImageURL?.absoluteString, image)
            XCTAssertTrue(value.canPersist)
        }
        for type in ["new_podcast", "general", "test", "NEW_ARTICLE"] {
            XCTAssertNil(imageItem(["type": type, "article_id": "a", "thumbnail_url": image]).articleImageURL)
        }
        XCTAssertNil(imageItem(["type": "new_article", "thumbnail_url": image]).articleImageURL)
        for ownerKey in ["uid", "user_id", "userId", "owner_uid"] {
            let value = imageItem(["type": "new_article", "article_id": "a", ownerKey: "A", "thumbnail_url": image])
            XCTAssertNil(value.articleImageURL); XCTAssertNil(value.target); XCTAssertFalse(value.canPersist)
        }
        let ownedNested = imageItem(["type": "new_article", "article_id": "a", "thumbnail_url": image,
                                    "data": ["uid": "A"]])
        XCTAssertNil(ownedNested.articleImageURL); XCTAssertNil(ownedNested.target)
        for raw in ["http://images.example.org/a.jpg", "file:///tmp/a.jpg", "data:image/png;base64,AAAA",
                    "/relative/image.jpg", "https://user:password@images.example.org/a.jpg",
                    "https://images.example.org/" + String(repeating: "å", count: 1_100)] {
            let value = imageItem(["type": "new_article", "article_id": "a", "thumbnail_url": raw])
            XCTAssertNil(value.articleImageURL, raw)
            XCTAssertEqual(value.body, "Beskeden bevares"); XCTAssertTrue(value.canPersist)
        }
    }

    func testNoImageDuplicateAndDeliveredSnapshotDoNotEraseExistingCanonicalCover() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let articleID = "0123456789abcdef01234567"
        let cover = try XCTUnwrap(URL(string: "https://images.example.org/received-cover.jpg"))
        let withCover = try XCTUnwrap(NotificationInboxItem.make(id: "transport-with-cover",
            title: "Samme artikelbesked", body: "Den oprindelige besked", date: Date(timeIntervalSince1970: 100),
            userInfo: ["type": "new_article", "article_id": articleID, "article_slug": "same-article",
                       "thumbnail_url": cover.absoluteString]))
        let withoutCover = try XCTUnwrap(NotificationInboxItem.make(id: "transport-without-cover",
            title: withCover.title, body: withCover.body, date: Date(timeIntervalSince1970: 200),
            userInfo: ["type": "new_article", "article_id": articleID, "article_slug": "same-article"]))
        model.receive(withCover)
        let canonicalID = try XCTUnwrap(model.items.first?.id)
        model.markRead(canonicalID)
        model.receive(withoutCover)
        XCTAssertEqual(model.items.first?.articleImageURL, cover, "Payload omission must not erase known artwork")

        // Isolate the delivered-snapshot order as well: its no-image copy is
        // current for this refresh, rather than fenced by a later direct push.
        model.receive(withCover)
        model.refresh()
        let delivered = memory.pending.removeFirst()
        delivered([withoutCover, withoutCover])

        XCTAssertEqual(model.items.first?.articleImageURL, cover)
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.items.first?.id, canonicalID)
        XCTAssertEqual(model.items.first?.target, withCover.target)
        XCTAssertEqual(model.items.first?.title, withCover.title); XCTAssertEqual(model.items.first?.body, withCover.body)
        XCTAssertEqual(model.items.first?.date, withCover.date); XCTAssertEqual(model.items.first?.isRead, true)
        XCTAssertEqual(model.unreadCount, 0)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertEqual(cold.items.first?.articleImageURL, cover)
        XCTAssertEqual(cold.items.first?.isRead, true); XCTAssertEqual(cold.items.first?.date, withCover.date)
        XCTAssertTrue(memory.opens.isEmpty)
    }

    func testArticleImageCandidatesUseFallbackAndNormalizedNestedAndFCMFields() throws {
        let thumb = "https://images.example.org/thumb.jpg", cover = "https://images.example.org/cover.jpg"
        let direct = imageItem(["type": "new_article", "article_id": "a", "thumbnail_url": " \n" + thumb + " \n",
                               "cover_url": cover, "image": "https://images.example.org/other.jpg"])
        XCTAssertEqual(direct.articleImageURL?.absoluteString, thumb)
        let fallback = imageItem(["type": "new_article", "article_id": "a", "thumbnail_url": "http://bad.example/a.jpg",
                                 "cover_url": cover, "fcm_options": ["image": thumb]])
        XCTAssertEqual(fallback.articleImageURL?.absoluteString, cover)
        let imageField = imageItem(["type": "breaking_news", "article_id": "a", "cover_url": "invalid",
                                   "image": thumb, "fcm_options": ["image": cover]])
        XCTAssertEqual(imageField.articleImageURL?.absoluteString, thumb)
        let fcm = imageItem(["type": "new_narration", "article_id": "a", "fcm_options": ["image": cover]])
        XCTAssertEqual(fcm.articleImageURL?.absoluteString, cover)
        let nested: [String: Any] = ["type": "new_article", "article_id": "nested", "thumbnail_url": thumb]
        XCTAssertEqual(imageItem(["data": nested]).articleImageURL?.absoluteString, thumb)
        let json = try JSONSerialization.data(withJSONObject: nested)
        let normalized = imageItem(["type": "new_podcast", "article_id": "old", "thumbnail_url": cover,
                                    "data": String(decoding: json, as: UTF8.self)])
        XCTAssertEqual(normalized.target?.identifier, "nested")
        XCTAssertEqual(normalized.articleImageURL?.absoluteString, thumb)
    }

    func testInvalidStoredArticleImageIsDiscardedWithoutLosingMessageOrReadState() throws {
        let seed = Memory(), model = NotificationInboxModel(effects: seed.effects())
        model.receive(imageItem(["type": "new_article", "article_id": "article-cover",
                                 "thumbnail_url": "https://images.example.org/good.jpg"]))
        model.receive(item("second")); model.markRead("cover")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(seed.bytes)) as? [String: Any])
        let toxic: [Any] = ["http://bad.example/a.jpg", "file:///tmp/private.jpg",
                            "https://user:secret@images.example.org/a.jpg",
                            "https://images.example.org/" + String(repeating: "a", count: 2_100),
                            ["unexpected": "object"], 42, NSNull()]
        for raw in toxic {
            var stored = original
            var values = try XCTUnwrap(stored["items"] as? [[String: Any]])
            let index = try XCTUnwrap(values.firstIndex { $0["id"] as? String == "cover" })
            values[index]["articleImageURL"] = raw; stored["items"] = values
            let memory = Memory(); memory.bytes = try JSONSerialization.data(withJSONObject: stored)
            let cold = NotificationInboxModel(effects: memory.effects())
            XCTAssertNil(cold.issue); XCTAssertEqual(cold.items.count, 2)
            let retained = try XCTUnwrap(cold.items.first { $0.id == "cover" })
            XCTAssertEqual(retained.title, "Redaktionel titel"); XCTAssertEqual(retained.body, "Beskeden bevares")
            XCTAssertEqual(retained.target?.identifier, "article-cover")
            XCTAssertNil(retained.articleImageURL); XCTAssertTrue(retained.isRead)
            XCTAssertEqual(cold.unreadCount, 1)
            cold.refresh(); memory.pending.removeFirst()([])
            let rewritten = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.bytes)) as? [String: Any])
            let cleaned = try XCTUnwrap(rewritten["items"] as? [[String: Any]])
            XCTAssertNil(cleaned.first(where: { $0["id"] as? String == "cover" })?["articleImageURL"])
            XCTAssertNil(cold.issue)
        }
    }

    func testArticleAndAudioAnnouncementDestinationsSurviveColdInboxReconstruction() throws {
        let memory = Memory(), model = NotificationInboxModel(effects: memory.effects())
        let article = try XCTUnwrap(NotificationInboxItem.make(id: "article-announcement", title: "Ny artikel",
            body: "Artiklen er tilgængelig", date: Date(timeIntervalSince1970: 100), userInfo: [
                "article_id": "article-1", "article_slug": "article-one", "article_name": "En artikel",
                "type": "new_narration", "click_action": "OPEN_ARTICLE",
            ]))
        let narration = try XCTUnwrap(NotificationInboxItem.make(id: "narration-announcement", title: "Lyt til artiklen",
            body: "Oplæsningen er klar", date: Date(timeIntervalSince1970: 200), userInfo: [
                "article_id": "article-1", "article_slug": "article-one", "podcast_title": "En artikel",
                "type": "new_narration", "click_action": "OPEN_ARTICLE",
            ]))
        model.receive(article); model.receive(narration); model.markRead(article.id)
        let cold = NotificationInboxModel(effects: memory.effects())
        XCTAssertNil(cold.issue); XCTAssertEqual(cold.items.count, 2)
        let restoredArticle = try XCTUnwrap(cold.items.first { $0.id == article.id })
        let restoredNarration = try XCTUnwrap(cold.items.first { $0.id == narration.id })
        XCTAssertEqual(restoredArticle.target?.payload.isArticleNotification, true)
        XCTAssertEqual(restoredArticle.target?.payload.isPodcastNotification, false)
        XCTAssertEqual(restoredNarration.target?.payload.isPodcastNotification, true)
        XCTAssertEqual(restoredNarration.target?.payload.isArticleNotification, false)
        XCTAssertTrue(restoredArticle.isRead); XCTAssertFalse(restoredNarration.isRead)
        XCTAssertEqual(restoredArticle.target?.identifier, "article-1")
        XCTAssertEqual(restoredNarration.target?.slug, "article-one")
    }

    func testLegacyInboxTargetsAndMalformedOptionalAudioMetadataKeepArticleReadState() throws {
        let image = "https://images.example.org/article.jpg"
        let legacy: [String: Any] = ["version": 1, "read": [], "dismissed": [], "items": [
            ["id": "legacy-narration", "title": "En gemt artikel", "body": "Den eksisterende besked bevares",
             "date": 0, "isRead": true, "articleImageURL": image,
             "target": ["identifier": "article-1", "slug": "article-one", "type": "new_narration"]],
            ["id": "legacy-podcast", "title": "En gemt episode", "body": "Lyt til episoden",
             "date": 1, "isRead": false, "target": ["identifier": "article-2", "type": "new_podcast"]],
            ["id": "legacy-article", "title": "En anden artikel", "body": "Læs artiklen",
             "date": 2, "isRead": false, "target": ["identifier": "article-3", "type": "new_article"]],
        ]]
        let invalid: [Any?] = [nil, NSNull(), ["unexpected": "object"], 42, " \n ",
                              String(repeating: "a", count: 241), String(repeating: "å", count: 600)]
        for raw in invalid {
            var stored = legacy
            var items = try XCTUnwrap(stored["items"] as? [[String: Any]])
            var target = try XCTUnwrap(items[0]["target"] as? [String: Any])
            if let raw { target["podcastTitle"] = raw }
            items[0]["target"] = target; stored["items"] = items
            let memory = Memory(); memory.bytes = try JSONSerialization.data(withJSONObject: stored)
            let model = NotificationInboxModel(effects: memory.effects())
            XCTAssertNil(model.issue); XCTAssertEqual(model.items.count, 3); XCTAssertEqual(model.unreadCount, 2)
            let article = try XCTUnwrap(model.items.first { $0.id == "legacy-narration" })
            XCTAssertEqual(article.title, "En gemt artikel"); XCTAssertEqual(article.body, "Den eksisterende besked bevares")
            XCTAssertEqual(article.target?.identifier, "article-1"); XCTAssertEqual(article.target?.slug, "article-one")
            XCTAssertTrue(article.isRead); XCTAssertEqual(article.articleImageURL?.absoluteString, image)
            XCTAssertEqual(article.target?.payload.isArticleNotification, true)
            XCTAssertEqual(article.target?.payload.isPodcastNotification, false)
            XCTAssertNil(article.target?.podcastTitle)
            XCTAssertEqual(model.items.first(where: { $0.id == "legacy-podcast" })?.target?.payload.isPodcastNotification, true)
            XCTAssertEqual(model.items.first(where: { $0.id == "legacy-article" })?.target?.payload.isArticleNotification, true)
            model.refresh(); memory.pending.removeFirst()([])
            let cold = NotificationInboxModel(effects: memory.effects())
            XCTAssertNil(cold.issue); XCTAssertEqual(cold.items.count, 3); XCTAssertEqual(cold.unreadCount, 2)
            XCTAssertEqual(cold.items.first(where: { $0.id == "legacy-narration" })?.target?.type, "new_article")
        }
    }

    private func imageItem(_ userInfo: [AnyHashable: Any]) -> NotificationInboxItem {
        NotificationInboxItem.make(id: "cover", title: "Redaktionel titel", body: "Beskeden bevares",
            date: Date(timeIntervalSince1970: 100), userInfo: userInfo)!
    }

}
