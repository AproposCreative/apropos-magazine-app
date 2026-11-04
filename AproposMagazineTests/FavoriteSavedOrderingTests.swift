import XCTest
@testable import Apropos

/// Actual favorite admission, journal and codec with injected local clock/I/O.
/// No runtime singleton, Firebase, account service or production network starts.
@MainActor
final class FavoriteSavedOrderingTests: XCTestCase {
    private final class Memory {
        var bytes: [FavoritesNamespace: Data] = [:]
        var failWrite = false
        var storage: FavoritesModel.Storage {
            .init(read: { self.bytes[$0] }, write: { namespace, data in
                if self.failWrite { throw FavoritesJournalFailure.writeFailed }
                self.bytes[namespace] = data
            })
        }
    }
    private final class Clock {
        var values: [TimeInterval]
        var calls = 0
        init(_ values: [TimeInterval]) { self.values = values }
        func date() -> Date {
            let index = min(calls, values.count - 1); calls += 1
            return Date(timeIntervalSince1970: values[index])
        }
    }
    private func article(_ id: String, name: String? = nil, published: String = "2026-01-01T10:00:00Z") -> Article {
        Article(id: id, name: name ?? id, slug: id, content: "<p>Body</p>", intro: "Intro", topicID: "topic",
            isDraft: false, isArchived: false, createdOn: published, lastPublished: published, contentRevision: "r1")
    }
    private func model(_ memory: Memory, _ clock: Clock, context: FavoritesContext = .guest) -> FavoritesModel {
        let value = FavoritesModel(storage: memory.storage, now: clock.date)
        value.changeContext(to: context); return value
    }
    private func orderedIDs(_ model: FavoritesModel) -> [String] {
        FavoriteArticlesLogic.sorted(model.snapshot.articles, by: .recentlySaved).map(\.id)
    }
    private func savedAt(_ id: String, in model: FavoritesModel) -> TimeInterval? {
        model.snapshot.articles.first { $0.id == id }?.favoriteSavedAt
    }
    private func recover(_ model: FavoritesModel) async throws {
        let ticket = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(ticket))
        let recovered = await model.finishRecovery(ticket, success: true)
        XCTAssertTrue(recovered)
    }

    func testActualAddsUseSaveTimeNotTitlePublicationOrLexicographicID() {
        let clock = Clock([100, 200, 300]), value = model(Memory(), clock)
        let first = article("z", name: "A title", published: "2026-12-01T10:00:00Z")
        let second = article("a", name: "Z title", published: "2026-06-01T10:00:00Z")
        let third = article("m", name: "M title", published: "2020-01-01T10:00:00Z")
        for item in [first, second, third] { XCTAssertNotNil(value.setFavorite(item, enabled: true)) }
        XCTAssertEqual(orderedIDs(value), ["m", "a", "z"])
        XCTAssertEqual(savedAt("z", in: value), 100); XCTAssertEqual(savedAt("a", in: value), 200)
        XCTAssertEqual(savedAt("m", in: value), 300); XCTAssertEqual(clock.calls, 3)
        XCTAssertEqual(FavoriteArticlesLogic.sortPreference(rawValue: nil), .recentlySaved)
        XCTAssertEqual(FavoriteArticlesLogic.sortPreference(rawValue: "unrecognized"), .recentlySaved)
        XCTAssertEqual(FavoriteArticlesLogic.sortPreference(rawValue: "Titel Å-A"), .titleZA)
    }

    func testRemoveAndActualReSaveGetsNewTimeButDuplicateSaveDoesNotRestamp() {
        let memory = Memory(), clock = Clock([100, 200, 300]), value = model(memory, clock)
        let a = article("a"), b = article("b")
        XCTAssertNotNil(value.setFavorite(a, enabled: true)); XCTAssertNotNil(value.setFavorite(b, enabled: true))
        XCTAssertNil(value.setFavorite(a, enabled: true)); XCTAssertEqual(clock.calls, 2)
        XCTAssertNotNil(value.setFavorite(a, enabled: false)); XCTAssertEqual(clock.calls, 2)
        XCTAssertNotNil(value.setFavorite(a, enabled: true))
        XCTAssertEqual(savedAt("a", in: value), 300); XCTAssertEqual(orderedIDs(value), ["a", "b"])
    }

    func testLegacyUnknownTimesRemainNilAndBehindGenuineTimesWithDeterministicTies() throws {
        let memory = Memory(), clock = Clock([500])
        let legacy = FavoritesRecord(articles: [article("z"), article("a")])
        memory.bytes[.guest] = try FavoritesRecordCodec.encode(legacy, namespace: .guest)
        let value = model(memory, clock)
        XCTAssertNil(savedAt("a", in: value)); XCTAssertNil(savedAt("z", in: value)); XCTAssertEqual(clock.calls, 0)
        XCTAssertEqual(orderedIDs(value), ["a", "z"])
        XCTAssertNotNil(value.setFavorite(article("m"), enabled: true))
        XCTAssertEqual(orderedIDs(value), ["m", "a", "z"])
        XCTAssertNil(savedAt("a", in: value)); XCTAssertNil(savedAt("z", in: value))
    }

    func testColdJournalAndAccountChangesRetainOnlyEachOwnersActualSaveTime() throws {
        let memory = Memory(), clock = Clock([100, 200])
        let ownerA = FavoritesContext.confirmed(userID: "owner-A"), ownerB = FavoritesContext.confirmed(userID: "owner-B")
        let value = model(memory, clock, context: ownerA)
        XCTAssertNotNil(value.setFavorite(article("same"), enabled: true))
        value.changeContext(to: ownerB); XCTAssertTrue(value.snapshot.articles.isEmpty)
        XCTAssertNotNil(value.setFavorite(article("same"), enabled: true)); XCTAssertEqual(savedAt("same", in: value), 200)
        let cold = model(memory, clock, context: ownerA)
        XCTAssertEqual(savedAt("same", in: cold), 100)
        cold.changeContext(to: ownerB); XCTAssertEqual(savedAt("same", in: cold), 200)
        XCTAssertEqual(clock.calls, 2, "A cold load/account switch must not invent a new save event")
    }

    func testEditorialRefreshAndSameRevisionMetadataCannotReplaceMembershipTime() throws {
        let value = model(Memory(), Clock([100]))
        XCTAssertNotNil(value.setFavorite(article("a"), enabled: true))
        var ticket = try XCTUnwrap(value.membershipTicket(articleID: "a"))
        XCTAssertTrue(value.updateMetadata(article("a", name: "New title").withFavoriteSavedAt(999), ticket: ticket))
        XCTAssertEqual(savedAt("a", in: value), 100)
        ticket = try XCTUnwrap(value.membershipTicket(articleID: "a"))
        let newer = Article(id: "a", name: "Fresh CMS title", slug: "a", content: "New body", intro: "", topicID: "topic",
            isDraft: false, lastPublished: "2026-01-02T10:00:00Z", contentRevision: "r2").withFavoriteSavedAt(999)
        XCTAssertNotNil(value.adoptPublishedMetadata(newer, ticket: ticket, stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertEqual(savedAt("a", in: value), 100)
        XCTAssertEqual(value.snapshot.articles.first?.bodyRevision, "r2")
    }

    func testFailedJournalWriteAndExplicitRetryKeepOriginalIntentTime() throws {
        let memory = Memory(), clock = Clock([100, 200]), value = model(memory, clock)
        memory.failWrite = true
        XCTAssertNotNil(value.setFavorite(article("a"), enabled: true))
        XCTAssertEqual(value.snapshot.state, .writeFailed); XCTAssertEqual(savedAt("a", in: value), 100)
        memory.failWrite = false; value.retryStorage()
        XCTAssertEqual(value.snapshot.state, .ready); XCTAssertEqual(clock.calls, 1)
        let cold = model(memory, clock)
        XCTAssertEqual(savedAt("a", in: cold), 100); XCTAssertEqual(clock.calls, 1)
    }

    func testCloudCodecAcknowledgementAndLegacyEchoCannotEraseAcceptedSaveTime() async throws {
        let memory = Memory(), clock = Clock([100]), value = model(memory, clock, context: .confirmed(userID: "owner"))
        try await recover(value)
        let observation = try XCTUnwrap(value.observationTicket())
        let mutation = try XCTUnwrap(value.setFavorite(article("a"), enabled: true))
        let fields = FavoriteArticleDocumentCodec.encode(mutation.article)
        XCTAssertEqual(fields["savedAt"] as? Double, 100)
        XCTAssertEqual(FavoriteArticleDocumentCodec.decode(fields, documentID: "a").favoriteSavedAt, 100)
        let dispatch = await value.beginDispatch(mutation)
        let ticket = try XCTUnwrap(dispatch)
        let finished = await value.finishDispatch(ticket, result: .acknowledged)
        XCTAssertTrue(finished)
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a")], isFromCache: false, hasPendingWrites: false), ticket: observation))
        XCTAssertEqual(savedAt("a", in: value), 100)
        let cold = model(memory, clock, context: .confirmed(userID: "owner"))
        XCTAssertEqual(savedAt("a", in: cold), 100); XCTAssertEqual(clock.calls, 1)
    }

    func testMembershipTimestampDoesNotChangeEditorialEqualityHashRevisionOrCMSBytes() throws {
        let item = article("a"), saved = item.withFavoriteSavedAt(100)
        XCTAssertEqual(item, saved); XCTAssertEqual(item.hashValue, saved.hashValue)
        XCTAssertEqual(item.bodyRevision, saved.bodyRevision)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(item), try encoder.encode(saved))
        XCTAssertEqual(saved.replacingBodyContent("Replacement").favoriteSavedAt, 100)
        XCTAssertNotEqual(FavoritesRecord.Metadata(item), FavoritesRecord.Metadata(saved), "The favorite journal must still commit the new membership field")
        let record = FavoritesRecord(articles: [saved])
        let data = try FavoritesRecordCodec.encode(record, namespace: .guest)
        XCTAssertEqual(try FavoritesRecordCodec.decode(data, namespace: .guest).articles.first?.favoriteSavedAt, 100)
        XCTAssertNotEqual(item, article("a", name: "Changed editorial field"))
    }

    func testMalformedAuxiliaryDatesNeverBecomeKnownSaveTimes() throws {
        let malformed: [Any] = [true, -1, Double.infinity, "100"]
        for bad in malformed {
            XCTAssertNil(FavoriteArticleDocumentCodec.decode(["id": "a", "name": "Article", "savedAt": bad], documentID: "a").favoriteSavedAt)
        }
        let value = model(Memory(), Clock([.nan]))
        XCTAssertNil(value.setFavorite(article("a"), enabled: true)); XCTAssertTrue(value.snapshot.articles.isEmpty)
        let invalid = FavoritesRecord(articles: [article("a").withFavoriteSavedAt(-1)])
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(invalid, namespace: .guest))
    }

    func testUnconfirmedCloudEchoCannotRollBackKnownTimeButFreshRemoteMayReplaceIt() async throws {
        let memory = Memory(), clock = Clock([100]), value = model(memory, clock, context: .confirmed(userID: "owner"))
        try await recover(value)
        let observation = try XCTUnwrap(value.observationTicket())
        let mutation = try XCTUnwrap(value.setFavorite(article("a"), enabled: true))
        let dispatch = await value.beginDispatch(mutation)
        let finished = await value.finishDispatch(try XCTUnwrap(dispatch), result: .acknowledged)
        XCTAssertTrue(finished)
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(100)],
            isFromCache: false, hasPendingWrites: false), ticket: observation))
        XCTAssertTrue(value.pendingMutations.isEmpty, "Require the previously uncovered retired-intent state")
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(50)],
            isFromCache: true, hasPendingWrites: false), ticket: observation))
        XCTAssertEqual(savedAt("a", in: value), 100)
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(50)],
            isFromCache: false, hasPendingWrites: true), ticket: observation))
        XCTAssertEqual(savedAt("a", in: value), 100)
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(200)],
            isFromCache: false, hasPendingWrites: false), ticket: observation))
        XCTAssertEqual(savedAt("a", in: value), 200)
        XCTAssertEqual(model(memory, clock, context: .confirmed(userID: "owner")).snapshot.articles.first?.favoriteSavedAt, 200)
        XCTAssertEqual(clock.calls, 1)
    }

    func testStillCurrentMetadataTicketCannotRollBackFreshRemoteMembershipTime() async throws {
        let memory = Memory(), clock = Clock([100]), value = model(memory, clock, context: .confirmed(userID: "owner"))
        try await recover(value)
        let observation = try XCTUnwrap(value.observationTicket())
        let mutation = try XCTUnwrap(value.setFavorite(article("a"), enabled: true))
        let dispatch = await value.beginDispatch(mutation)
        let finished = await value.finishDispatch(try XCTUnwrap(dispatch), result: .acknowledged)
        XCTAssertTrue(finished)
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(100)],
            isFromCache: false, hasPendingWrites: false), ticket: observation))
        let heldAt100 = try XCTUnwrap(value.membershipTicket(articleID: "a"))
        XCTAssertTrue(value.applyRemote(.init(articles: [article("a").withFavoriteSavedAt(200)],
            isFromCache: false, hasPendingWrites: false), ticket: observation))
        XCTAssertTrue(value.isCurrent(heldAt100), "The same membership/revision ticket deliberately remains current")
        XCTAssertTrue(value.updateMetadata(article("a", name: "Same-revision title"), ticket: heldAt100))
        XCTAssertEqual(savedAt("a", in: value), 200)
        let published = Article(id: "a", name: "New body", slug: "a", content: "Body2", intro: "", topicID: "topic",
            isDraft: false, lastPublished: "2026-01-02T10:00:00Z", contentRevision: "r2")
        XCTAssertNotNil(value.adoptPublishedMetadata(published, ticket: heldAt100,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertEqual(savedAt("a", in: value), 200)
        XCTAssertEqual(value.snapshot.articles.first?.bodyRevision, "r2")
        XCTAssertEqual(clock.calls, 1)
    }

}
