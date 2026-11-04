import XCTest
import Combine
@testable import Apropos

@MainActor
final class OfflineLibraryStatusTests: XCTestCase {
    private enum Failure: Error { case storage }
    @MainActor private final class Harness {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
        var reads = 0
        var indexes = 0
        var failModelRead = false
        var failRead = false
        var probes: [(String, @MainActor (Result<Bool, Error>) -> Void)] = []
        var holdProbes = true
        var allowed = true
        var onPermit: (() -> Void)?
        var onProbe: (() -> Void)?
        var probeDepth = 0
        var maximumProbeDepth = 0
        var failWrite = false
        var fetches: [(String, @MainActor (Result<Article, Error>) -> Void)] = []
        var fetchBody: FavoritesOfflineCoordinator.FetchBody {
            { id, completion in self.fetches.append((id, completion)) }
        }
        lazy var model = FavoritesModel(storage: .init(read: { namespace, complete in
            complete(self.failModelRead ? .failure(Failure.storage) : .success(self.records[namespace]))
        }, write: { namespace, record, expectedRevision, complete in
            guard self.records[namespace]?.recordRevision == expectedRevision else {
                complete(.failure(Failure.storage)); return
            }
            self.records[namespace] = record; complete(.success(()))
        }))
        lazy var offline = FavoritesOfflineCoordinator(model: model, storage: .init(read: { key in
            self.reads += 1
            if self.failRead { throw Failure.storage }
            return self.bodies[key]
        }, write: { key, article in
            if self.failWrite { throw Failure.storage }
            self.bodies[key] = article
        }, contains: { key in
            self.indexes += 1; return self.bodies[key] != nil
        }, probe: { key, complete in
            self.probeDepth += 1
            self.maximumProbeDepth = max(self.maximumProbeDepth, self.probeDepth)
            defer { self.probeDepth -= 1 }
            self.probes.append((key, complete)); self.onProbe?()
            if !self.holdProbes { complete(.success(self.bodies[key] != nil)) }
        }), permitsBody: { _ in self.onPermit?(); return self.allowed }, effects: .init(
            cacheImages: { _, _ in }, audioAsset: { _ in nil }, audioIsCached: { _ in false },
            pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        func select(_ uid: String?) {
            model.changeContext(to: .confirmed(userID: uid)); offline.synchronizeCurrentMembership()
        }
        func add(_ article: Article, stored: Bool = true) throws -> FavoritesOfflineCoordinator.AccessTicket {
            _ = model.setFavorite(article, enabled: true)
            let ticket = try XCTUnwrap(offline.captureAccess(articleID: article.id))
            if stored { bodies[ticket.contentKey] = article }
            return ticket
        }
    }
    private func article(_ id: String, revision: String? = "r1", name: String? = nil) -> Article {
        Article(id: id, name: name ?? "Gemte ord \(id)", slug: id, content: "<p>Indhold</p>",
                intro: "", topicID: "topic", contentRevision: revision)
    }

    func testRepeatedOfflineSettingsCountDoesNotReadStorageDuringRendering() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<12 { _ = try h.add(article("article-\(index)")) }
        // Before: snapshot.articles.filter { hasBody(id, revision) }.count
        // made 1,200 synchronous index reads for these 100 redraws (root-run
        // before result). The real replacement explicitly prepares once.
        XCTAssertNotNil(h.offline.prepareLibraryBodyStatus())
        for index in 0..<12 { h.probes[index].1(.success(true)) }
        let prepared = h.probes.count
        for _ in 0..<100 {
            XCTAssertEqual(h.offline.libraryBodySummary.available, 12)
            XCTAssertEqual(h.offline.libraryBodySummary.total, 12)
        }
        XCTAssertEqual(h.reads, 0)
        XCTAssertEqual(h.indexes, 0, "Rendering the offline library must not read 12 body indexes on each redraw")
        XCTAssertEqual(h.probes.count, prepared, "Rendering must not schedule hidden work")
    }

    func testColdSummaryAndIdentityDoNotCreateLeasesOrScheduleWork() {
        let h = Harness(); h.select(nil)
        for index in 0..<12 { _ = h.model.setFavorite(article("a\(index)"), enabled: true) }
        var permitCalls = 0; h.onPermit = { permitCalls += 1 }
        for _ in 0..<100 {
            let summary = h.offline.libraryBodySummary
            XCTAssertEqual(summary.total, 12); XCTAssertEqual(summary.checking, 12)
            XCTAssertEqual(summary.available, 0); XCTAssertTrue(summary.isLoaded)
            XCTAssertEqual(h.offline.libraryMembershipIdentity.members.count, 12)
        }
        XCTAssertEqual(permitCalls, 0, "A cold render must not capture leases")
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.indexes, 0); XCTAssertTrue(h.probes.isEmpty)
    }

    func testUnknownFailedInitialReadAndMissingRevisionAreNotConfirmedEmptyLibrary() {
        let h = Harness()
        XCTAssertFalse(h.offline.libraryBodySummary.isLoaded)
        XCTAssertNil(h.offline.prepareLibraryBodyStatus())
        h.failModelRead = true; h.select("A")
        XCTAssertFalse(h.offline.libraryBodySummary.isLoaded)
        XCTAssertNil(h.offline.prepareLibraryBodyStatus())
        h.failModelRead = false; h.select(nil)
        XCTAssertTrue(h.offline.libraryBodySummary.isLoaded)
        XCTAssertEqual(h.offline.libraryBodySummary.total, 0)
        _ = h.model.setFavorite(article("unknown", revision: nil), enabled: true)
        XCTAssertNotNil(h.offline.prepareLibraryBodyStatus())
        let summary = h.offline.libraryBodySummary
        XCTAssertEqual(summary.total, 1); XCTAssertEqual(summary.checking, 1)
        XCTAssertEqual(summary.notDownloaded, 0)
        XCTAssertEqual(summary.available, 0); XCTAssertTrue(h.probes.isEmpty)
    }

    func testCursorVisitsEveryMemberBeyondCapacityWithoutLosingMiddleJobs() throws {
        let h = Harness(); h.select(nil)
        var keys: Set<String> = []
        for index in 0..<19 { keys.insert(try h.add(article("a\(index)")).contentKey) }
        XCTAssertNotNil(h.offline.prepareLibraryBodyStatus())
        XCTAssertEqual(h.probes.count, 4)
        for index in 0..<19 {
            XCTAssertLessThanOrEqual(h.probes.count - index, 4)
            h.probes[index].1(.success(index.isMultiple(of: 2)))
        }
        XCTAssertEqual(h.probes.count, 19); XCTAssertEqual(Set(h.probes.map(\.0)), keys)
        let summary = h.offline.libraryBodySummary
        XCTAssertEqual(summary.available, 10); XCTAssertEqual(summary.notDownloaded, 9)
        XCTAssertEqual(summary.checking, 0); XCTAssertEqual(summary.total, 19)
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.indexes, 0)
    }

    func testWaitingDetailHasPriorityAndItsLibraryEntryIsNotLostOrDuplicated() throws {
        let h = Harness(); h.select(nil)
        var tickets: [FavoritesOfflineCoordinator.AccessTicket] = []
        for index in 0..<12 { tickets.append(try h.add(article(String(format: "a%02d", index)))) }
        XCTAssertNotNil(h.offline.prepareLibraryBodyStatus())
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: tickets[11]))
        XCTAssertEqual(h.probes.count, 4)
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.probes[4].0, tickets[11].contentKey)
        for index in 1..<12 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.probes.count, 12)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 12)
    }

    func testDuplicateForcedEntryJoinsPhysicalWorkAndOldHandleCannotCancelNewRefresh() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<8 { _ = try h.add(article("a\(index)")) }
        let first = try XCTUnwrap(h.offline.prepareLibraryBodyStatus(force: true))
        XCTAssertEqual(h.offline.prepareLibraryBodyStatus(force: true), first)
        XCTAssertEqual(h.probes.count, 4)
        for index in 0..<8 { h.probes[index].1(.success(true)) }
        let next = try XCTUnwrap(h.offline.prepareLibraryBodyStatus(force: true))
        XCTAssertNotEqual(next, first); XCTAssertEqual(h.probes.count, 12)
        h.offline.cancelLibraryBodyStatus(first)
        for index in 8..<16 { h.probes[index].1(.success(false)) }
        XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 8)
        XCTAssertEqual(h.probes.count, 16)
    }

    func testCancellationRetainsFourPhysicalSlotsAndRejectsTheirLateResults() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<9 { _ = try h.add(article("a\(index)")) }
        let old = try XCTUnwrap(h.offline.prepareLibraryBodyStatus())
        h.offline.cancelLibraryBodyStatus(old)
        XCTAssertEqual(h.offline.libraryBodySummary.checking, 9)
        let next = try XCTUnwrap(h.offline.prepareLibraryBodyStatus(force: true))
        XCTAssertNotEqual(old, next); XCTAssertEqual(h.probes.count, 4)
        for index in 0..<4 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.probes.count, 8); XCTAssertEqual(h.offline.libraryBodySummary.available, 0)
        for index in 4..<13 { h.probes[index].1(.success(false)) }
        XCTAssertEqual(h.probes.count, 13); XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 9)
    }

    func testDetailJoiningLibraryProbeKeepsItsResultAfterLibraryCancellation() throws {
        let h = Harness(); h.select(nil)
        let ticket = try h.add(article("a"))
        let handle = try XCTUnwrap(h.offline.prepareLibraryBodyStatus())
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        h.offline.cancelLibraryBodyStatus(handle)
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertEqual(h.probes.count, 1)
    }

    func testAccountRoundTripRejectsOldResultsAndDoesNotReleasePhysicalCapacity() throws {
        let h = Harness(); h.select("A")
        for index in 0..<7 { _ = try h.add(article("a\(index)")) }
        let firstIdentity = h.offline.libraryMembershipIdentity
        _ = h.offline.prepareLibraryBodyStatus()
        h.select("B"); XCTAssertEqual(h.offline.libraryBodySummary.total, 0)
        h.select("A"); XCTAssertNotEqual(h.offline.libraryMembershipIdentity, firstIdentity)
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertEqual(h.probes.count, 4)
        for index in 0..<4 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.offline.libraryBodySummary.available, 0)
        for index in 4..<11 { h.probes[index].1(.success(false)) }
        XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 7)
    }

    func testRemovedReaddedAndRevisionReplacementCannotAcceptOldProbe() throws {
        for changedRevision in [false, true] {
            let h = Harness(); h.select(nil)
            let old = try h.add(article("a"))
            let identity = h.offline.libraryMembershipIdentity
            _ = h.offline.prepareLibraryBodyStatus()
            _ = h.model.setFavorite(article("a"), enabled: false); h.offline.synchronizeCurrentMembership()
            let current = try h.add(article("a", revision: changedRevision ? "r2" : "r1"))
            XCTAssertNotEqual(identity, h.offline.libraryMembershipIdentity)
            _ = h.offline.prepareLibraryBodyStatus(force: true)
            h.probes[0].1(.success(true))
            XCTAssertNil(h.offline.bodyState(ticket: old))
            XCTAssertEqual(h.offline.bodyState(ticket: current), .checking)
            h.probes[1].1(.success(false))
            XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 1)
        }
    }

    func testMetadataEnrichmentAndUnchangedMembershipDoNotRestartActiveRefresh() throws {
        let h = Harness(); h.select(nil)
        _ = try h.add(article("a"))
        let identity = h.offline.libraryMembershipIdentity
        let refresh = try XCTUnwrap(h.offline.prepareLibraryBodyStatus(force: true))
        let member = try XCTUnwrap(h.model.membershipTicket(articleID: "a"))
        let enriched = article("a", name: "Ny redaktionel titel")
        XCTAssertTrue(h.model.updateMetadata(enriched, ticket: member))
        XCTAssertEqual(h.offline.libraryMembershipIdentity, identity)
        XCTAssertEqual(h.offline.prepareLibraryBodyStatus(force: true), refresh)
        XCTAssertEqual(h.probes.count, 1)
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.libraryBodySummary.available, 1)
    }

    func testPendingFetchAndFailedWriteOutrankForcedLibraryChecks() throws {
        let h = Harness(); h.select(nil)
        let pending = try h.add(article("pending"), stored: false)
        let failed = try h.add(article("failed"), stored: false)
        XCTAssertTrue(h.offline.requestBody(ticket: pending, fetch: h.fetchBody))
        h.failWrite = true
        XCTAssertFalse(h.offline.saveBody(article("failed"), ticket: failed))
        let indexes = h.indexes
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertTrue(h.probes.isEmpty); XCTAssertEqual(h.indexes, indexes)
        XCTAssertEqual(h.offline.libraryBodySummary.pending, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.failed, 1)
        h.fetches[0].1(.failure(Failure.storage))
        XCTAssertEqual(h.offline.libraryBodySummary.failed, 2)
    }

    func testSaveAcceptedAfterLibraryCaptureOutranksBothStartedAndWaitingProbes() throws {
        let h = Harness(); h.select(nil)
        var tickets: [FavoritesOfflineCoordinator.AccessTicket] = []
        for index in 0..<7 { tickets.append(try h.add(article("a\(index)"), stored: false)) }
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertTrue(h.offline.saveBody(article("a0"), ticket: tickets[0]))
        XCTAssertTrue(h.offline.saveBody(article("a6"), ticket: tickets[6]))
        for index in 0..<6 { h.probes[index].1(.success(false)) }
        XCTAssertEqual(h.probes.count, 6, "Queued a6 must not overwrite the later confirmed save")
        XCTAssertEqual(h.offline.libraryBodySummary.available, 2)
        XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 5)
    }

    func testFetchFailureAcceptedAfterCaptureCannotBeOverwrittenByOldProbe() throws {
        let h = Harness(); h.select(nil)
        let ticket = try h.add(article("a"), stored: false)
        _ = h.offline.prepareLibraryBodyStatus()
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.failure(Failure.storage))
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.libraryBodySummary.failed, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 0)
    }

    func testKnownInvalidBodyReadCannotBeRehabilitatedByLibrarySizeProbe() throws {
        let h = Harness(); h.select(nil)
        let ticket = try h.add(article("a"))
        _ = h.offline.prepareLibraryBodyStatus()
        h.bodies[ticket.contentKey] = article("a", revision: "wrong")
        XCTAssertNil(h.offline.body(ticket))
        h.probes[0].1(.success(true))
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertEqual(h.probes.count, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.checkFailed, 0)
    }

    func testStatusProbeFailureIsDistinctAndExplicitRecheckCanRecoverWithoutDownload() throws {
        let h = Harness(); h.select(nil)
        _ = try h.add(article("a"))
        _ = h.offline.prepareLibraryBodyStatus()
        h.probes[0].1(.failure(Failure.storage))
        let failed = h.offline.libraryBodySummary
        XCTAssertEqual(failed.checkFailed, 1); XCTAssertEqual(failed.failed, 0)
        XCTAssertEqual(failed.notDownloaded, 0); XCTAssertEqual(failed.available, 0)
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertEqual(h.probes.count, 2); XCTAssertEqual(h.offline.libraryBodySummary.checking, 1)
        h.probes[1].1(.success(true))
        XCTAssertEqual(h.offline.libraryBodySummary.available, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.checkFailed, 0)
        XCTAssertTrue(h.fetches.isEmpty); XCTAssertEqual(h.reads, 0)
    }

    func testForegroundForceRechecksMissingFilesAndDoesNotReadSynchronously() throws {
        let h = Harness(); h.select(nil)
        _ = try h.add(article("a")); _ = try h.add(article("b"))
        _ = h.offline.prepareLibraryBodyStatus()
        h.probes[0].1(.success(true)); h.probes[1].1(.success(true))
        XCTAssertEqual(h.offline.libraryBodySummary.available, 2)
        h.bodies = [:]
        _ = h.offline.prepareLibraryBodyStatus(force: true)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 0)
        XCTAssertEqual(h.offline.libraryBodySummary.checking, 2)
        h.probes[2].1(.success(false)); h.probes[3].1(.success(false))
        XCTAssertEqual(h.offline.libraryBodySummary.notDownloaded, 2)
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.indexes, 0)
    }

    func testSynchronousLocalAdapterPumpsIterativelyWithoutRecursiveProbeStack() throws {
        let h = Harness(); h.select(nil); h.holdProbes = false
        for index in 0..<150 { _ = try h.add(article("a\(index)")) }
        XCTAssertNotNil(h.offline.prepareLibraryBodyStatus())
        XCTAssertEqual(h.probes.count, 150); XCTAssertEqual(h.maximumProbeDepth, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 150)
    }

    func testProbeCallbackReentryCanCancelWithoutStartingRemainingMembers() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<10 { _ = try h.add(article("a\(index)")) }
        let handle = try XCTUnwrap(h.offline.prepareLibraryBodyStatus())
        var entered = false
        let observation = h.offline.bodyChanges.sink {
            guard !entered else { return }; entered = true
            h.offline.cancelLibraryBodyStatus(handle)
        }
        h.probes[0].1(.success(true))
        for index in 1..<4 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.probes.count, 4)
        XCTAssertEqual(h.offline.libraryBodySummary.available, 1)
        XCTAssertEqual(h.offline.libraryBodySummary.checking, 9)
        withExtendedLifetime(observation) {}
    }

    func testCancellationPublicationReentryCannotReviveOuterPrepare() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<6 { _ = try h.add(article("a\(index)")) }
        _ = h.offline.prepareLibraryBodyStatus()
        _ = try h.add(article("new"))
        var entered = false
        let observation = h.offline.bodyChanges.sink {
            guard !entered else { return }; entered = true
            h.select("B")
            _ = h.offline.prepareLibraryBodyStatus()
        }
        XCTAssertNil(h.offline.prepareLibraryBodyStatus(force: true))
        XCTAssertEqual(h.offline.libraryBodySummary.total, 0)
        for index in 0..<4 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.probes.count, 4)
        withExtendedLifetime(observation) {}
    }

    func testAdmissionHookReentryRejectsOldAccountBeforeNextPhysicalStart() throws {
        let h = Harness(); h.select("A")
        for index in 0..<7 { _ = try h.add(article("a\(index)")) }
        h.onPermit = { h.onPermit = nil; h.select("B") }
        _ = h.offline.prepareLibraryBodyStatus()
        XCTAssertTrue(h.probes.isEmpty); XCTAssertEqual(h.offline.libraryBodySummary.total, 0)
    }

    func testColdLibraryMemberSurvivesReentrantDetailPriorityAfterLeaseCreation() throws {
        let h = Harness(); h.select(nil)
        _ = h.model.setFavorite(article("a"), enabled: true)
        let detail = try h.add(article("z"))
        var calls = 0
        h.onPermit = {
            calls += 1
            guard calls == 3 else { return }
            h.onPermit = nil
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: detail))
        }
        _ = h.offline.prepareLibraryBodyStatus()
        XCTAssertEqual(h.probes.count, 2)
        XCTAssertEqual(h.probes.first?.0, detail.contentKey)
        h.probes[0].1(.success(true)); h.probes[1].1(.success(true))
        XCTAssertEqual(h.offline.libraryBodySummary.available, 2)
        XCTAssertEqual(h.offline.libraryBodySummary.checking, 0)
    }

    func testDuplicateOldPhysicalCallbackDoesNotReleaseNewSlotOrChangeSummary() throws {
        let h = Harness(); h.select(nil)
        for index in 0..<9 { _ = try h.add(article("a\(index)")) }
        _ = h.offline.prepareLibraryBodyStatus()
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.probes.count, 5)
        let summary = h.offline.libraryBodySummary
        h.probes[0].1(.success(false))
        XCTAssertEqual(h.probes.count, 5); XCTAssertEqual(h.offline.libraryBodySummary, summary)
        for index in 1..<9 { h.probes[index].1(.success(true)) }
        XCTAssertEqual(h.offline.libraryBodySummary.available, 9)
    }
}
