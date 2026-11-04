import Combine
import XCTest
@testable import Apropos

@MainActor
final class FavoritesOfflineLibraryDownloadTests: XCTestCase {
    private enum Failure: Error { case fetch }
    @MainActor private final class Harness {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
        var fetches: [(String, @MainActor (Result<Article, Error>) -> Void)] = []
        var completed = Set<Int>()
        var maximumActive = 0
        var writes = 0
        var containsHook: (() -> Void)?
        var synchronousResult: ((String) -> Result<Article, Error>)?
        lazy var model = FavoritesModel(storage: .init(read: { namespace, complete in
            complete(.success(self.records[namespace]))
        }, write: { namespace, record, expectedRevision, complete in
            guard self.records[namespace]?.recordRevision == expectedRevision else {
                complete(.failure(Failure.fetch)); return
            }
            self.records[namespace] = record; complete(.success(()))
        }))
        lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { self.bodies[$0] }, write: { key, article in
                self.writes += 1; self.bodies[key] = article
            }, contains: { key in
                self.containsHook?(); return self.bodies[key] != nil
            }), permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in },
                audioAsset: { _ in nil }, audioIsCached: { _ in false },
                pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in },
                scheduleRetry: { _, _ in {} }))
        var fetch: FavoritesOfflineCoordinator.FetchBody {
            { id, complete in
                let index = self.fetches.count
                self.fetches.append((id, complete))
                self.maximumActive = max(self.maximumActive, self.fetches.count - self.completed.count)
                if let result = self.synchronousResult?(id) {
                    self.complete(index, result)
                }
            }
        }
        func select(_ uid: String?) {
            model.changeContext(to: .confirmed(userID: uid)); offline.synchronizeCurrentMembership()
        }
        func save(_ id: String, revision: String = "r1") throws -> FavoritesOfflineCoordinator.AccessTicket {
            _ = model.setFavorite(Self.article(id, revision: revision), enabled: true)
            return try XCTUnwrap(offline.captureAccess(articleID: id))
        }
        func complete(_ index: Int, _ result: Result<Article, Error>) {
            completed.insert(index); fetches[index].1(result)
        }
        static func article(_ id: String, revision: String = "r1") -> Article {
            Article(id: id, name: id, slug: id, content: "<p>Offline \(id)</p>",
                    intro: "", topicID: "topic", contentRevision: revision)
        }
    }

    func testFiniteLibraryQueueDrainsTenMembersThroughFourActualSlots() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<10).map { try h.save("article-\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        XCTAssertEqual(h.fetches.count, 4)
        for ticket in tickets { XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending) }
        for index in 0..<10 {
            XCTAssertLessThan(index, h.fetches.count)
            let id = h.fetches[index].0
            h.complete(index, .success(Harness.article(id)))
        }
        XCTAssertEqual(h.fetches.map(\.0), tickets.map(\.articleID))
        XCTAssertEqual(h.maximumActive, 4); XCTAssertEqual(h.writes, 10)
        for ticket in tickets { XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available) }
        XCTAssertEqual(h.offline.libraryBodySummary.available, 10)
        XCTAssertEqual(h.offline.libraryBodySummary.pending, 0)
    }

    func testQueuedCacheHitsAndDuplicateLeasesNeverStartExtraFetches() throws {
        let h = Harness(); h.select("A")
        let a = try h.save("a"), b = try h.save("b")
        h.bodies[a.contentKey] = Harness.article("a")
        XCTAssertTrue(h.offline.requestBodies(tickets: [a, a, b, b], fetch: h.fetch))
        XCTAssertEqual(h.fetches.map(\.0), ["b"])
        XCTAssertEqual(h.offline.bodyState(ticket: a), .available)
        h.complete(0, .success(Harness.article("b")))
        XCTAssertEqual(h.writes, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 2)
    }

    func testFailureIsOneAttemptAndDoesNotStopRemainingMembers() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<7).map { try h.save("a\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        h.complete(0, .failure(Failure.fetch))
        for index in 1..<7 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.fetches.count, 7)
        XCTAssertEqual(h.offline.bodyState(ticket: tickets[0]), .failed)
        XCTAssertEqual(h.offline.libraryBodySummary.failed, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 6)
        XCTAssertEqual(h.maximumActive, 4)
    }

    func testNewestRequestReplacesOnlyWaitingEntriesAndKeepsStartedWork() throws {
        let h = Harness(); h.select("A")
        let first = try (0..<8).map { try h.save("old\($0)") }
        let newer = try [h.save("new0"), h.save("new1")]
        XCTAssertTrue(h.offline.requestBodies(tickets: first, fetch: h.fetch))
        XCTAssertTrue(h.offline.requestBodies(tickets: newer, fetch: h.fetch))
        XCTAssertEqual(h.fetches.count, 4)
        h.complete(0, .success(Harness.article("old0")))
        h.complete(1, .success(Harness.article("old1")))
        XCTAssertEqual(h.fetches.map(\.0), ["old0", "old1", "old2", "old3", "new0", "new1"])
        for index in 2..<6 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.writes, 6)
        XCTAssertEqual(h.offline.bodyState(ticket: first[4]), .checking)
        XCTAssertEqual(h.maximumActive, 4)
    }

    func testRemovedReaddedAndNewRevisionCannotBeAdoptedByOldWaitingTickets() throws {
        let h = Harness(); h.select("A")
        let first = try (0..<7).map { try h.save("a\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: first, fetch: h.fetch))
        for index in 4..<7 { _ = h.model.setFavorite(Harness.article("a\(index)"), enabled: false) }
        h.offline.synchronizeCurrentMembership()
        let readded = try h.save("a4"), revised = try h.save("a5", revision: "r2")
        h.complete(0, .success(Harness.article("a0")))
        XCTAssertEqual(h.fetches.count, 4, "Neither a same-ID new membership nor its new revision inherits old queued work")
        XCTAssertNil(h.offline.body(readded)); XCTAssertNil(h.offline.body(revised))
        XCTAssertFalse(h.offline.isCurrent(first[4])); XCTAssertFalse(h.offline.isCurrent(first[5]))
        XCTAssertEqual(h.writes, 1)
    }

    func testAccountRoundTripRetainsStalePhysicalSlotsUntilEachActualCallback() throws {
        let h = Harness(); h.select("A")
        let first = try (0..<7).map { try h.save("old\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: first, fetch: h.fetch))
        h.select("B")
        let next = try (0..<3).map { try h.save("new\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: next, fetch: h.fetch))
        XCTAssertEqual(h.fetches.count, 4, "Account revocation must not free noncancellable transports")
        h.complete(0, .success(Harness.article("old0")))
        XCTAssertEqual(h.fetches.map(\.0).last, "new0"); XCTAssertEqual(h.writes, 0)
        // A duplicated old callback cannot free another slot or schedule more.
        h.fetches[0].1(.failure(Failure.fetch)); XCTAssertEqual(h.fetches.count, 5)
        h.complete(1, .failure(Failure.fetch)); h.complete(2, .success(Harness.article("old2")))
        XCTAssertEqual(h.fetches.suffix(3).map(\.0), ["new0", "new1", "new2"])
        for index in 3..<7 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.writes, 3); XCTAssertEqual(h.maximumActive, 4)
        h.select("A")
        XCTAssertFalse(h.offline.isCurrent(first[0]))
        XCTAssertEqual(h.fetches.count, 7)
    }

    func testLibraryQueueSharesCapacityWithOrdinarySingleBodyRequests() throws {
        let h = Harness(); h.select("A")
        let ordinary = try (0..<4).map { try h.save("single\($0)") }
        let queued = try (0..<3).map { try h.save("queued\($0)") }
        for ticket in ordinary { XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetch)) }
        XCTAssertTrue(h.offline.requestBodies(tickets: queued, fetch: h.fetch))
        XCTAssertEqual(h.fetches.count, 4)
        XCTAssertEqual(h.offline.libraryBodySummary.failed, 0)
        for ticket in queued { XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending) }
        for index in 0..<7 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.maximumActive, 4); XCTAssertEqual(h.writes, 7)
    }

    func testIndependentDetailSaveDoesNotReleaseItsHeldPhysicalFetchSlotEarly() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<6).map { try h.save("a\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        XCTAssertTrue(h.offline.saveBody(Harness.article("a0"), ticket: tickets[0]))
        XCTAssertEqual(h.fetches.count, 4)
        h.complete(0, .failure(Failure.fetch))
        XCTAssertEqual(h.fetches.count, 5)
        XCTAssertEqual(h.offline.bodyState(ticket: tickets[0]), .available)
        for index in 1..<6 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.writes, 6); XCTAssertEqual(h.maximumActive, 4)
    }

    func testSynchronousResultsDrainWithoutRecursiveOverfetchOrRetry() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<40).map { try h.save("a\($0)") }
        h.synchronousResult = { .success(Harness.article($0)) }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        XCTAssertEqual(h.fetches.count, 40); XCTAssertEqual(h.writes, 40)
        XCTAssertEqual(h.maximumActive, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 40)
    }

    func testPublicationCanCancelWaitingQueueBeforeAnyFetchStarts() throws {
        let h = Harness(); h.select("A")
        let ticket = try h.save("a")
        var once = true
        let observation = h.offline.bodyChanges.sink {
            guard once else { return }; once = false
            XCTAssertTrue(h.offline.requestBodies(tickets: [], fetch: h.fetch))
        }
        XCTAssertFalse(h.offline.requestBodies(tickets: [ticket], fetch: h.fetch))
        XCTAssertTrue(h.fetches.isEmpty); XCTAssertEqual(h.writes, 0)
        withExtendedLifetime(observation) {}
    }

    func testStorageHookCanReplaceQueueWithoutStartingTheOldEntry() throws {
        let h = Harness(); h.select("A")
        let old = try h.save("old"), new = try h.save("new")
        h.containsHook = {
            h.containsHook = nil
            XCTAssertTrue(h.offline.requestBodies(tickets: [new], fetch: h.fetch))
        }
        XCTAssertFalse(h.offline.requestBodies(tickets: [old], fetch: h.fetch))
        XCTAssertEqual(h.fetches.map(\.0), ["new"])
        h.complete(0, .success(Harness.article("new")))
        XCTAssertEqual(h.writes, 1); XCTAssertNil(h.offline.body(old))
    }

    func testOversizedQueueIsRejectedWithoutReplacingTheAcceptedWaitingWork() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<6).map { try h.save("a\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        XCTAssertFalse(h.offline.requestBodies(
            tickets: Array(repeating: tickets[0], count: FavoritesRecordCodec.maximumEntries + 1), fetch: h.fetch))
        for index in 0..<6 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.fetches.map(\.0), tickets.map(\.articleID))
        XCTAssertEqual(h.maximumActive, 4); XCTAssertEqual(h.writes, 6)
    }

    func testExplicitReleaseCancelsOnlyWaitingQueueAndLateCallbacksCannotRestoreIt() throws {
        let h = Harness(); h.select("A")
        let tickets = try (0..<7).map { try h.save("a\($0)") }
        XCTAssertTrue(h.offline.requestBodies(tickets: tickets, fetch: h.fetch))
        h.offline.releaseCurrentAccess()
        for index in 0..<4 { h.complete(index, .success(Harness.article(h.fetches[index].0))) }
        XCTAssertEqual(h.fetches.count, 4); XCTAssertEqual(h.writes, 0)
        XCTAssertFalse(h.offline.isCurrent(tickets[0]))
    }
}
