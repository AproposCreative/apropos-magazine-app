import XCTest
import Combine
@testable import Apropos

@MainActor
final class FavoritesOfflineCoordinatorTests: XCTestCase {
    private enum Failure: Error { case storage }
    @MainActor private final class Harness {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
        var reads = 0
        var writes = 0
        var indexes = 0
        var failWrite = false
        var failAfterWrite = false
        var omitWrite = false
        var failRead = false
        var failContains = false
        var onContains: (() -> Void)?
        var holdProbes = false
        var onProbe: (() -> Void)?
        var probes: [(String, @MainActor (Result<Bool, Error>) -> Void)] = []
        var fetches: [(String, @MainActor (Result<Article, Error>) -> Void)] = []
        var fetchBody: FavoritesOfflineCoordinator.FetchBody {
            { id, completion in self.fetches.append((id, completion)) }
        }
        var allowed = true
        var images: [String] = []
        var pins: [(String, UUID, PodcastAudioAsset)] = []
        var releases: [(String, UUID, PodcastAudioAsset)] = []
        var retries: [() -> Void] = []
        var cancellations = 0
        var audio: URL? = URL(string: "https://audio.example.com/a.m4a")!
        var cached = false
        var audioRevision = "r1"
        var audioArticleOverride: String?
        var onAudioResolve: (() -> Void)?
        var onCached: (() -> Void)?
        func asset(for article: Article) -> PodcastAudioAsset? {
            onAudioResolve?()
            guard let audio else { return nil }
            return PodcastAudioAsset(episodeID: "episode-" + article.id,
                canonicalArticleID: audioArticleOverride ?? article.id, kind: .human,
                sourceRevision: audioRevision, remoteURL: audio)
        }
        var onRead: (() -> Void)?
        var onWrite: (() -> Void)?
        var onPin: (() -> Void)?
        var onPermit: (() -> Void)?
        lazy var model = FavoritesModel(storage: .init(read: { namespace, completion in completion(.success(self.records[namespace])) },
            write: { namespace, record, expectedRevision, completion in
                guard self.records[namespace]?.recordRevision == expectedRevision else { completion(.failure(Failure.storage));return }
                self.records[namespace] = record;completion(.success(()))
            }))
        lazy var offline = FavoritesOfflineCoordinator(model: model, storage: .init(read: { key in
            self.reads += 1; self.onRead?(); if self.failRead { throw Failure.storage }; return self.bodies[key]
        }, write: { key, article in
            self.writes += 1; self.onWrite?(); if self.failWrite { throw Failure.storage }
            if !self.omitWrite { self.bodies[key] = article }
            if self.failAfterWrite { throw Failure.storage }
        }, contains: { key in
            self.indexes += 1; self.onContains?(); if self.failContains { throw Failure.storage }; return self.bodies[key] != nil
        }, probe: { key, completion in
            self.probes.append((key, completion)); self.onProbe?()
            guard !self.holdProbes else { return }
            self.indexes += 1; self.onContains?()
            completion(self.failContains ? .failure(Failure.storage) : .success(self.bodies[key] != nil))
        }), permitsBody: { _ in
            self.onPermit?(); return self.allowed
        }, effects: .init(cacheImages: { _, key in self.images.append(key) }, audioAsset: { self.asset(for: $0) }, audioIsCached: { _ in self.onCached?(); return self.cached }, pinAudio: { key, lease, url in
            self.pins.append((key, lease, url)); self.onPin?()
        }, releaseAudio: { key, lease, url in self.releases.append((key, lease, url)) }, scheduleRetry: { _, callback in
            self.retries.append(callback); return { self.cancellations += 1 }
        }))
        func select(_ uid: String?) { model.changeContext(to: .confirmed(userID: uid)); offline.synchronizeCurrentMembership() }
        func save(_ article: Article) -> FavoritesOfflineCoordinator.AccessTicket? {
            _ = model.setFavorite(article, enabled: true)
            return offline.captureAccess(articleID: article.id)
        }
    }
    private func article(_ id: String = "a", revision: String? = "r1", name: String = "Artikel") -> Article {
        Article(id: id, name: name, slug: id, content: "<p>Indhold</p>", intro: "", topicID: "topic", contentRevision: revision)
    }
    func testUnresolvedContextNeverReadsWritesOrStartsMedia() {
        let h = Harness()
        XCTAssertNil(h.offline.captureAccess(articleID: "a")); XCTAssertNil(h.offline.body(articleID: "a"))
        h.offline.synchronizeCurrentMembership()
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.writes, 0); XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
    }
    func testPublicBodyBytesNeverAuthorizeOtherOwnerAndRoundTripRejectsOldTicket() throws {
        let h = Harness(); h.select("A")
        let old = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.saveBody(article(), ticket: old))
        h.select(nil); XCTAssertNil(h.offline.body(articleID: "a")); XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
        h.select("B"); XCTAssertNil(h.offline.body(articleID: "a")); XCTAssertFalse(h.offline.saveBody(article(), ticket: old))
        h.select("A"); XCTAssertNotNil(h.offline.body(articleID: "a")); XCTAssertFalse(h.offline.isCurrent(old))
        XCTAssertEqual(h.bodies.count, 1)
    }
    func testStatusUsesInjectedSmallIndexWithoutLoadingBody() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        for _ in 0..<100 { XCTAssertTrue(h.offline.hasBody(articleID: "a", expectedRevision: "r1")) }
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.indexes, 100)
        XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: "r2"))
    }
    func testRepeatedBodyStateDisplayQueriesNeverReadStorage() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        for _ in 0..<100 { XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking) }
        XCTAssertEqual(h.reads, 0, "Rendering status must not read the body")
        XCTAssertEqual(h.indexes, 0, "Rendering status must not synchronously read the persisted size index")
    }
    func testSameRevisionEnrichmentAndSynchronizePreserveOriginalAcceptedAccess() throws {
        let h = Harness(); h.select(nil); let original = try XCTUnwrap(h.save(article()))
        let member = try XCTUnwrap(h.model.membershipTicket(articleID: "a"))
        XCTAssertTrue(h.model.updateMetadata(article(name: "Ny titel"), ticket: member))
        h.offline.synchronizeCurrentMembership()
        XCTAssertEqual(h.offline.captureAccess(articleID: "a"), original)
        XCTAssertTrue(h.offline.saveBody(article(name: "Ny titel"), ticket: original))
    }
    func testMissingRevisionCannotAdoptLegacyOrSpeculativeBody() {
        let h = Harness(); h.select(nil)
        XCTAssertNil(h.save(article(revision: nil))); XCTAssertTrue(h.offline.currentBodies.isEmpty)
        XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: nil))
    }
    func testDifferentRevisionOrArticleBodyCannotWriteOrPin() throws {
        let h = Harness(); h.select(nil); let original = try XCTUnwrap(h.save(article()))
        XCTAssertFalse(h.offline.saveBody(article(revision: "r2"), ticket: original))
        XCTAssertFalse(h.offline.saveBody(article("b"), ticket: original))
        XCTAssertEqual(h.writes, 0); XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
    }
    func testRemoveReaddSameArticleInvalidatesBodyAndRetryOrigin() throws {
        let h = Harness(); h.audio = nil; h.select(nil); let old = try XCTUnwrap(h.save(article()))
        XCTAssertFalse(h.offline.cacheAudio(old)); let retry = try XCTUnwrap(h.retries.last)
        _ = h.model.setFavorite(article(), enabled: false); h.offline.synchronizeCurrentMembership()
        let new = try XCTUnwrap(h.save(article())); XCTAssertNotEqual(old, new)
        h.audio = URL(string: "https://audio.example.com/a.m4a")!; retry()
        XCTAssertTrue(h.pins.isEmpty); XCTAssertFalse(h.offline.saveBody(article(), ticket: old))
    }
    func testDelayedMissingManifestRetryCannotGainOwnerAfterAtoGuestToA() throws {
        let h = Harness(); h.audio = nil; h.select("A"); let old = try XCTUnwrap(h.save(article()))
        _ = h.offline.cacheAudio(old); let retry = try XCTUnwrap(h.retries.last)
        h.select(nil); h.select("A"); h.audio = URL(string: "https://audio.example.com/a.m4a")!; retry()
        XCTAssertTrue(h.pins.isEmpty); XCTAssertGreaterThan(h.cancellations, 0)
    }
    func testStorageFailureNeverStartsMediaOrAdvertisesBody() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article())); h.failWrite = true
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket)); XCTAssertTrue(h.pins.isEmpty); XCTAssertTrue(h.images.isEmpty)
        XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: "r1"))
    }
    func testFavoriteRemainsSelectedWhenItsOfflineBodyWriteFails() throws {
        let h = Harness(); h.select(nil)
        let ticket = try XCTUnwrap(h.save(article()))
        h.failWrite = true
        let stored = h.offline.saveBody(article(), ticket: ticket)
        XCTAssertFalse(stored, "The caller receives only the failed write result in the original implementation")
        XCTAssertEqual(h.model.snapshot.articles.map(\.id), ["a"], "A favorite choice is not proof that its body was stored")
        XCTAssertTrue(h.offline.isCurrent(ticket))
        XCTAssertNil(h.offline.body(ticket))
        XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: "r1"))
        XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
    }
    func testBodyRequestWaitsForPhysicalFetchAndDeduplicatesTheOriginalLease() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
        XCTAssertFalse(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertFalse(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.fetches.count, 1); XCTAssertEqual(h.fetches.first?.0, "a")
        XCTAssertEqual(h.writes, 0); XCTAssertEqual(h.reads, 0)
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertEqual(h.writes, 1); XCTAssertEqual(h.images.count, 1)
    }
    func testFetchFailureIsVisibleAndExplicitRetryUsesTheSameOriginalTicket() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.failure(Failure.storage))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertEqual(h.writes, 0); XCTAssertEqual(h.model.snapshot.articles.map(\.id), ["a"])
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
        h.fetches[1].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertFalse(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.fetches.count, 2)
    }
    func testCandidateStorageFailureDoesNotSilentlyStartFallbackFetch() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article())); h.failWrite = true
        XCTAssertFalse(h.offline.requestBody(ticket: ticket, candidate: article(), fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertEqual(h.fetches.count, 0); XCTAssertEqual(h.writes, 1)
        h.failWrite = false
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
    }
    func testPartialStorageFailureRemainsFailedDespiteAnExistingIndexUntilExplicitRetry() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article())); h.failAfterWrite = true
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket))
        XCTAssertNotNil(h.bodies[ticket.contentKey])
        XCTAssertTrue(h.offline.hasBody(articleID: "a", expectedRevision: "r1"), "The original cheap index alone can see partial bytes")
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
        h.failAfterWrite = false
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
    }
    func testSuccessfulWriteCallbackWithoutIndexedBodyDoesNotPublishAvailable() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article())); h.omitWrite = true
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
    }
    func testStoredDetailBodySupersedesBothLateFetchFailureAndLateSuccess() throws {
        for lateSuccess in [false, true] {
            let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
            XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
            let detail = article(name: "Detail result")
            XCTAssertTrue(h.offline.saveBody(detail, ticket: ticket))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
            h.fetches[0].1(lateSuccess ? .success(article(name: "Old fetch")) : .failure(Failure.storage))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
            XCTAssertEqual(h.bodies[ticket.contentKey]?.name, "Detail result")
            XCTAssertEqual(h.writes, 1)
        }
    }
    func testMismatchedIndependentDetailSaveCannotHideAnAlreadyStoredBody() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.saveBody(article(name: "Accepted"), ticket: ticket))
        XCTAssertFalse(h.offline.saveBody(article(revision: "r2"), ticket: ticket))
        XCTAssertFalse(h.offline.saveBody(article("foreign"), ticket: ticket))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertEqual(h.bodies[ticket.contentKey]?.name, "Accepted"); XCTAssertEqual(h.writes, 1)
    }
    func testMismatchedIndependentDetailSaveCannotCancelThePendingValidFetch() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertFalse(h.offline.saveBody(article(revision: "r2"), ticket: ticket))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available); XCTAssertEqual(h.writes, 1)
    }
    func testExplicitMismatchedCandidateFailsWithoutFetchingOrWriting() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertFalse(h.offline.requestBody(ticket: ticket, candidate: article(revision: "r2"), fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertEqual(h.fetches.count, 0); XCTAssertEqual(h.writes, 0)
    }
    func testDuplicateOldFetchCompletionCannotFinishTheExplicitRetry() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.failure(Failure.storage))
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending); XCTAssertEqual(h.writes, 0)
        h.fetches[1].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available); XCTAssertEqual(h.writes, 1)
    }
    func testFetchedWrongArticleRevisionEmptyOrOversizedBodyFailsWithoutWrites() throws {
        let invalid = [article("wrong"), article(revision: "r2"), article().replacingBodyContent(""),
                       article().replacingBodyContent(String(repeating: "x", count: FavoritesOfflineCoordinator.maximumBodyBytes + 1))]
        for value in invalid {
            let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
            XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
            h.fetches[0].1(.success(value))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
            XCTAssertEqual(h.writes, 0); XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
        }
    }
    func testRemovalAndReadditionCannotAdoptAnOldFetchOrItsRetry() throws {
        let h = Harness(); h.select(nil); let old = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: old, fetch: h.fetchBody))
        _ = h.model.setFavorite(article(), enabled: false); h.offline.synchronizeCurrentMembership()
        let next = try XCTUnwrap(h.save(article()))
        XCTAssertNotEqual(old.leaseID, next.leaseID)
        h.fetches[0].1(.success(article()))
        XCTAssertNil(h.offline.bodyState(ticket: old))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .checking)
        XCTAssertFalse(h.offline.retryBody(ticket: old, fetch: h.fetchBody)); XCTAssertEqual(h.writes, 0)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: next))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .notDownloaded)
        XCTAssertTrue(h.offline.retryBody(ticket: next, fetch: h.fetchBody))
        h.fetches[1].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .available)
    }
    func testAccountRoundTripRejectsOldFetchSuccessAndFailure() throws {
        for success in [false, true] {
            let h = Harness(); h.select("A"); let old = try XCTUnwrap(h.save(article()))
            XCTAssertTrue(h.offline.requestBody(ticket: old, fetch: h.fetchBody))
            h.select("B"); h.select("A")
            let next = try XCTUnwrap(h.offline.captureAccess(articleID: "a"))
            h.fetches[0].1(success ? .success(article()) : .failure(Failure.storage))
            XCTAssertNil(h.offline.bodyState(ticket: old))
            XCTAssertEqual(h.offline.bodyState(ticket: next), .checking)
            XCTAssertFalse(h.offline.retryBody(ticket: old, fetch: h.fetchBody)); XCTAssertEqual(h.writes, 0)
        }
    }
    func testRevisionReplacementCannotAcceptOldFetchedBody() throws {
        let h = Harness(); h.select(nil); let old = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: old, fetch: h.fetchBody))
        _ = h.model.setFavorite(article(), enabled: false)
        let next = try XCTUnwrap(h.save(article(revision: "r2"))); h.offline.synchronizeCurrentMembership()
        h.fetches[0].1(.success(article()))
        XCTAssertNil(h.offline.bodyState(ticket: old))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .checking)
        XCTAssertEqual(h.writes, 0)
    }
    func testWithdrawalBeforeFetchReturnCannotStoreOrPublishAvailable() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        h.allowed = false; h.offline.synchronizeCurrentMembership()
        h.fetches[0].1(.success(article()))
        XCTAssertNil(h.offline.bodyState(ticket: ticket)); XCTAssertEqual(h.writes, 0)
        XCTAssertFalse(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
    }
    func testFourPhysicalSlotsRemainOccupiedAcrossAccountChangeUntilActualCallback() throws {
        let h = Harness(); h.select("A")
        for index in 0..<4 {
            let ticket = try XCTUnwrap(h.save(article("a\(index)")))
            XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        }
        h.select("B"); let next = try XCTUnwrap(h.save(article("b")))
        XCTAssertFalse(h.offline.requestBody(ticket: next, fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .failed); XCTAssertEqual(h.fetches.count, 4)
        h.fetches[0].1(.success(article("a0")))
        XCTAssertEqual(h.writes, 0)
        XCTAssertTrue(h.offline.retryBody(ticket: next, fetch: h.fetchBody))
        XCTAssertEqual(h.fetches.count, 5)
        h.fetches[4].1(.success(article("b")))
        XCTAssertEqual(h.offline.bodyState(ticket: next), .available)
    }
    func testPendingPublicationAccountSwitchPreventsPhysicalFetchStart() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        var entered = false
        let observation = h.offline.bodyChanges.sink {
            guard !entered else { return }; entered = true; h.select("B")
        }
        XCTAssertFalse(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertTrue(entered); XCTAssertEqual(h.fetches.count, 0); XCTAssertEqual(h.writes, 0)
        XCTAssertNil(h.offline.bodyState(ticket: ticket))
        withExtendedLifetime(observation) {}
    }
    func testPendingSavePublicationRevocationPreventsStorageWrite() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        var entered = false
        let observation = h.offline.bodyChanges.sink {
            guard !entered else { return }; entered = true; h.select("B")
        }
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket))
        XCTAssertTrue(entered); XCTAssertEqual(h.writes, 0)
        XCTAssertNil(h.offline.bodyState(ticket: ticket))
        withExtendedLifetime(observation) {}
    }
    func testExplicitProbeReadsIndexOnceAndDisplayQueriesRemainPure() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        for _ in 0..<40 { XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available) }
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.indexes, 1)
        h.onContains = { h.onContains = nil; h.select("B") }
        XCTAssertFalse(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        XCTAssertNil(h.offline.bodyState(ticket: ticket)); XCTAssertEqual(h.reads, 0)
    }
    func testPartialWriteFailureDoesNotLetOlderFetchOverwriteTheExplicitFailure() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        h.failAfterWrite = true
        XCTAssertFalse(h.offline.saveBody(article(name: "Partial detail"), ticket: ticket))
        h.failAfterWrite = false
        h.fetches[0].1(.success(article(name: "Old fetch")))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertEqual(h.writes, 1); XCTAssertEqual(h.bodies[ticket.contentKey]?.name, "Partial detail")
    }
    func testStoredBodyIsReusedWithoutFetchAndMissingIndexWithdrawsAvailability() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.saveBody(article(), ticket: ticket))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody)); XCTAssertEqual(h.fetches.count, 0)
        h.bodies.removeValue(forKey: ticket.contentKey)
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available, "A display query alone never performs revalidation I/O")
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody)); XCTAssertEqual(h.fetches.count, 1)
    }
    func testDelayedProbeKeepsColdStatusAndCoalescesRepeatedPreparations() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        for index in 0..<20 { XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: index % 2 == 0)) }
        XCTAssertEqual(h.probes.count, 1); XCTAssertEqual(h.indexes, 0); XCTAssertEqual(h.reads, 0)
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket)); XCTAssertEqual(h.probes.count, 1)
        h.probes[0].1(.success(false))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available, "Only the first physical callback owns completion")
    }
    func testProbeFailureDoesNotAdvertiseDownloadedContentAndExplicitRetryStillWorks() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        h.probes[0].1(.failure(Failure.storage))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
        XCTAssertTrue(h.offline.retryBody(ticket: ticket, fetch: h.fetchBody))
        h.fetches[0].1(.success(article()))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
    }
    func testExplicitInvalidationClearsDisplayButOldProbeCannotRestoreIt() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertTrue(h.offline.invalidateBodyStatus(ticket: ticket))
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertEqual(h.probes.count, 2)
        h.probes[1].1(.success(false))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
    }
    func testExplicitInvalidationThenForceProbeSupersedesOldResultAndRetainsBothPhysicalSlots() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertTrue(h.offline.invalidateBodyStatus(ticket: ticket))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        XCTAssertEqual(h.probes.count, 2)
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        h.probes[1].1(.success(false))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
    }
    func testProbeCompletionCannotOverrideLaterSaveSuccessOrFailure() throws {
        for fails in [false, true] {
            let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
            h.failAfterWrite = fails
            XCTAssertEqual(h.offline.saveBody(article(), ticket: ticket), !fails)
            let expected: FavoritesOfflineCoordinator.BodyState = fails ? .failed : .available
            h.probes[0].1(.success(fails))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), expected)
            if fails {
                XCTAssertFalse(h.offline.prepareBodyStatus(ticket: ticket, force: true))
                XCTAssertFalse(h.offline.invalidateBodyStatus(ticket: ticket))
                XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
            }
        }
    }
    func testProbeCannotFinishOrReplaceLaterBodyFetch() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertFalse(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
        h.fetches[0].1(.failure(Failure.storage))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .failed)
        XCTAssertEqual(h.probes.count, 1)
    }
    func testFourPhysicalProbesSurviveAccountSwitchAndOnlyLatestWaitingLeaseStarts() throws {
        let h = Harness(); h.holdProbes = true; h.select("A")
        for index in 0..<4 {
            let ticket = try XCTUnwrap(h.save(article("a\(index)")))
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        }
        h.select("B")
        let earlier = try XCTUnwrap(h.save(article("earlier"))), latest = try XCTUnwrap(h.save(article("latest")))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: earlier))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: latest))
        XCTAssertEqual(h.probes.count, 4, "Revocation must not free physically outstanding probes")
        h.probes[0].1(.success(true))
        XCTAssertEqual(h.probes.count, 5); XCTAssertEqual(h.probes[4].0, latest.contentKey)
        XCTAssertEqual(h.offline.bodyState(ticket: earlier), .checking)
        h.probes[0].1(.success(true)); XCTAssertEqual(h.probes.count, 5)
        h.probes[4].1(.success(true)); XCTAssertEqual(h.offline.bodyState(ticket: latest), .available)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: earlier)); XCTAssertEqual(h.probes.count, 6)
        h.probes[5].1(.success(false)); XCTAssertEqual(h.offline.bodyState(ticket: earlier), .notDownloaded)
    }
    func testRemovedAndReaddedFavoriteNeverAdoptsOldProbeResult() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let old = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: old))
        _ = h.model.setFavorite(article(), enabled: false); h.offline.synchronizeCurrentMembership()
        let current = try XCTUnwrap(h.save(article()))
        h.probes[0].1(.success(true))
        XCTAssertNil(h.offline.bodyState(ticket: old)); XCTAssertEqual(h.offline.bodyState(ticket: current), .checking)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: current)); h.probes[1].1(.success(false))
        XCTAssertEqual(h.offline.bodyState(ticket: current), .notDownloaded)
    }
    func testRevisionReplacementAccountRoundTripAndWithdrawalRejectOldProbes() throws {
        for transition in 0..<3 {
            let h = Harness(); h.holdProbes = true; h.select("A"); let old = try XCTUnwrap(h.save(article()))
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: old))
            if transition == 0 {
                _ = h.model.setFavorite(article(), enabled: false); _ = h.save(article(revision: "r2"))
            } else if transition == 1 { h.select("B"); h.select("A") }
            else { h.allowed = false }
            h.offline.synchronizeCurrentMembership()
            h.probes[0].1(.success(true))
            XCTAssertNil(h.offline.bodyState(ticket: old))
            if transition != 2 {
                let current = try XCTUnwrap(h.offline.captureAccess(articleID: "a"))
                XCTAssertEqual(h.offline.bodyState(ticket: current), .checking)
            }
        }
    }
    func testInvalidationPublicationSaveWinsBeforeForcedProbeCanStart() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        var entered = false
        let observation = h.offline.bodyChanges.sink {
            guard !entered else { return }; entered = true
            XCTAssertTrue(h.offline.saveBody(self.article(), ticket: ticket))
        }
        XCTAssertFalse(h.offline.prepareBodyStatus(ticket: ticket, force: true))
        XCTAssertEqual(h.probes.count, 0); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        withExtendedLifetime(observation) {}
    }
    func testProbeAdapterReentryCannotPublishForAnotherAccount() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        h.onProbe = { h.onProbe = nil; h.select("B") }
        XCTAssertFalse(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertNil(h.offline.bodyState(ticket: ticket)); XCTAssertEqual(h.probes.count, 1)
    }
    func testActualReadFailureOrMismatchedDataWithdrawsPreviouslyAvailableDisplay() throws {
        for failure in 0..<3 {
            let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
            h.bodies[ticket.contentKey] = article(); XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
            if failure == 0 { h.failRead = true }
            else if failure == 1 { h.bodies[ticket.contentKey] = article(revision: "wrong") }
            else { h.bodies.removeValue(forKey: ticket.contentKey) }
            XCTAssertNil(h.offline.body(ticket))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
        }
    }
    func testActualContainsFailureWithdrawsDisplayAndInvalidatesMemoryBody() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.saveBody(article(), ticket: ticket))
        h.failContains = true; h.bodies.removeValue(forKey: ticket.contentKey)
        XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: "r1"))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
        XCTAssertNil(h.offline.body(ticket), "A known failed validation must not leave a usable stale memory entry")
    }
    func testKnownInvalidReadCannotBeRestoredByPositiveIndexAndExplicitFetchRepairsIt() throws {
        for mismatch in [false, true] {
            let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
            h.bodies[ticket.contentKey] = mismatch ? article(revision: "corrupt-revision") : article()
            h.failRead = !mismatch
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
            XCTAssertNil(h.offline.body(ticket))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
            h.probes[0].1(.success(true))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded, "Known decoding/revision failure outranks the old size observation")
            XCTAssertFalse(h.offline.hasBody(articleID: "a", expectedRevision: "r1"))
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true)); XCTAssertEqual(h.probes.count, 1)
            let indexes = h.indexes
            XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
            XCTAssertEqual(h.indexes, indexes, "A positive weak index must not skip the explicit repair fetch")
            XCTAssertEqual(h.fetches.count, 1); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
            h.failRead = false; h.fetches[0].1(.success(article()))
            XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
            XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true)); XCTAssertEqual(h.probes.count, 2)
            h.probes[1].1(.success(true)); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        }
    }
    func testAcceptedDecodedReadClearsOnlyItsLeaseInvalidEvidence() throws {
        let h = Harness(); h.holdProbes = true; h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article(revision: "mismatched")
        XCTAssertNil(h.offline.body(ticket)); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .notDownloaded)
        h.bodies[ticket.contentKey] = article(name: "Valid replacement")
        XCTAssertEqual(h.offline.body(ticket)?.name, "Valid replacement")
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket, force: true)); XCTAssertEqual(h.probes.count, 1)
        h.probes[0].1(.success(true)); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
    }
    func testInvalidReadEvidenceDoesNotLeakToReplacementMembership() throws {
        let h = Harness(); h.select(nil); let old = try XCTUnwrap(h.save(article()))
        h.bodies[old.contentKey] = article(revision: "mismatched")
        XCTAssertNil(h.offline.body(old))
        _ = h.model.setFavorite(article(), enabled: false); h.offline.synchronizeCurrentMembership()
        let current = try XCTUnwrap(h.save(article()))
        h.bodies[current.contentKey] = article()
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: current))
        XCTAssertEqual(h.probes.count, 1); XCTAssertEqual(h.offline.bodyState(ticket: current), .available)
        XCTAssertNil(h.offline.bodyState(ticket: old))
    }
    func testReentrantActualReadFailureCannotDowngradeNewSave() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.onRead = {
            h.onRead = nil
            XCTAssertTrue(h.offline.saveBody(self.article(name: "New detail"), ticket: ticket))
        }
        h.failRead = true
        XCTAssertNil(h.offline.body(ticket))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available)
        XCTAssertEqual(h.bodies[ticket.contentKey]?.name, "New detail")
    }
    func testColdExplicitRequestReusesStoredBodyAndCachedAvailableNeverHidesEviction() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .checking)
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.offline.bodyState(ticket: ticket), .available); XCTAssertEqual(h.fetches.count, 0)
        h.bodies.removeValue(forKey: ticket.contentKey)
        XCTAssertTrue(h.offline.requestBody(ticket: ticket, fetch: h.fetchBody))
        XCTAssertEqual(h.fetches.count, 1); XCTAssertEqual(h.offline.bodyState(ticket: ticket), .pending)
    }
    func testBodyProbeNeverLoadsFullBodyOrStartsImagesAudioOrNetworkFetch() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        h.bodies[ticket.contentKey] = article()
        XCTAssertTrue(h.offline.prepareBodyStatus(ticket: ticket))
        XCTAssertEqual(h.reads, 0); XCTAssertEqual(h.writes, 0); XCTAssertEqual(h.fetches.count, 0)
        XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
    }
    func testReentrantWriteSwitchCannotPinOrPublishBodyForNewOwner() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        h.onWrite = { h.select("B") }
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket)); XCTAssertTrue(h.images.isEmpty); XCTAssertTrue(h.pins.isEmpty)
        XCTAssertNil(h.offline.body(articleID: "a")); XCTAssertEqual(h.bodies.count, 1)
    }
    func testReentrantPublicationPolicyCannotAuthorizeWriteAfterContextSwitch() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        h.onPermit = { h.onPermit = nil; h.select("B") }
        XCTAssertFalse(h.offline.saveBody(article(), ticket: ticket)); XCTAssertEqual(h.writes, 0)
    }
    func testReentrantPinSwitchReleasesOnlyOriginalLeaseAndKeepsPublicBytes() throws {
        let h = Harness(); h.select("A"); let old = try XCTUnwrap(h.save(article()))
        h.onPin = { h.onPin = nil; h.select("B") }
        XCTAssertFalse(h.offline.cacheAudio(old))
        XCTAssertFalse(h.releases.isEmpty); XCTAssertTrue(h.releases.allSatisfy { $0.0 == old.pinKey && $0.1 == old.leaseID })
        XCTAssertEqual(h.model.context, .confirmed(userID: "B"))
    }
    func testWithdrawalImmediatelyDeniesBytesAndSynchronizeReleasesExactPin() throws {
        let h = Harness(); h.select(nil); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.saveBody(article(), ticket: ticket)); h.cached = true
        XCTAssertTrue(h.offline.audioDownloaded(articleID: "a", expectedRevision: "r1"))
        h.allowed = false
        XCTAssertNil(h.offline.body(articleID: "a")); XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
        h.offline.synchronizeCurrentMembership(); XCTAssertEqual(h.releases.last?.1, ticket.leaseID)
        XCTAssertEqual(h.bodies.count, 1)
    }
    func testAudioStatusRequiresCurrentMembershipRevisionAndResolvedURL() throws {
        let h = Harness(); h.select(nil); _ = try XCTUnwrap(h.save(article())); h.cached = true
        XCTAssertTrue(h.offline.audioDownloaded(articleID: "a", expectedRevision: "r1", expectedAsset: h.asset(for: article())))
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a", expectedRevision: "old"))
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a", expectedAsset: PodcastAudioAsset(episodeID: "episode-a", canonicalArticleID: "a", kind: .human, sourceRevision: "r1", remoteURL: URL(string: "https://audio.example.com/old.m4a")!)!))
        h.select("B"); XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
    }
    func testSynchronizeNeverPreloadsBodiesAndBodyMemoryIsBounded() throws {
        let h = Harness(); h.select(nil)
        var tickets: [FavoritesOfflineCoordinator.AccessTicket] = []
        for id in ["a", "b", "c"] { let ticket = try XCTUnwrap(h.save(article(id))); h.bodies[ticket.contentKey] = article(id); tickets.append(ticket) }
        h.offline.synchronizeCurrentMembership(); XCTAssertEqual(h.reads, 0)
        for ticket in tickets { XCTAssertNotNil(h.offline.body(ticket)) }
        XCTAssertEqual(h.reads, 3)
        XCTAssertNotNil(h.offline.body(tickets[0])); XCTAssertEqual(h.reads, 4)
    }
    func testOriginalReadCannotReturnBodyAfterSynchronousOwnerSwitch() throws {
        let h = Harness(); h.select("A"); let original = try XCTUnwrap(h.save(article())); h.bodies[original.contentKey] = article()
        h.onRead = { h.onRead = nil; h.select("B") }
        XCTAssertNil(h.offline.body(original)); XCTAssertEqual(h.model.context, .confirmed(userID: "B"))
    }
    func testSameURLStaleSourceCannotBeRelabeledForNewMemberRevision() throws {
        let h = Harness();h.select(nil)
        let original = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.cacheAudio(original));h.cached = true
        let observerBefore = h.pins.count
        _ = h.model.setFavorite(article(), enabled: false)
        let replacement = try XCTUnwrap(h.save(article(revision: "r2")))
        h.offline.synchronizeCurrentMembership()
        XCTAssertFalse(h.offline.cacheAudio(original))
        XCTAssertFalse(h.offline.cacheAudio(replacement))
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a", expectedRevision: "r2"))
        XCTAssertEqual(h.pins.count, observerBefore)
        h.audioRevision = "r2"
        XCTAssertTrue(h.offline.cacheAudio(replacement))
        XCTAssertEqual(h.pins.last?.2.sourceRevision, "r2")
    }
    func testMissingAcceptedAssetReleasesOnlyExactOldLeaseAndNeverShowsCachedURL() throws {
        let h = Harness();h.select(nil);let ticket = try XCTUnwrap(h.save(article()))
        let asset = try XCTUnwrap(h.asset(for: article()))
        XCTAssertTrue(h.offline.cacheAudio(ticket));h.cached = true;h.audio = nil
        h.offline.synchronizeCurrentMembership()
        XCTAssertEqual(h.releases.count, 1);XCTAssertEqual(h.releases[0].1, ticket.leaseID)
        XCTAssertEqual(h.releases[0].2, asset)
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
    }
    func testDeferredOriginalAssetCannotAdoptReplacementAtSameMemberRevision() throws {
        let h = Harness();h.select(nil);let ticket = try XCTUnwrap(h.save(article()))
        let old = try XCTUnwrap(h.asset(for: article()))
        XCTAssertTrue(h.offline.cacheAudio(ticket, asset: old))
        h.audio = URL(string: "https://audio.example.com/replacement.m4a")!
        let replacement = try XCTUnwrap(h.asset(for: article()))
        XCTAssertFalse(h.offline.cacheAudio(ticket, asset: old))
        XCTAssertTrue(h.offline.cacheAudio(ticket, asset: replacement))
        XCTAssertEqual(h.releases.last?.2, old);XCTAssertEqual(h.pins.last?.2, replacement)
        let pins = h.pins.count
        XCTAssertFalse(h.offline.cacheAudio(ticket, asset: old));XCTAssertEqual(h.pins.count, pins)
    }
    func testDescriptorMustMatchOriginalCanonicalArticleAndRevision() throws {
        let h = Harness();h.select(nil);let ticket = try XCTUnwrap(h.save(article()))
        h.audioArticleOverride = "other"
        XCTAssertFalse(h.offline.cacheAudio(ticket));h.cached = true
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
        XCTAssertTrue(h.pins.isEmpty)
    }
    func testResolverAndCachedStatusReentryCannotGrantAnotherOwnerAsset() throws {
        let h = Harness();h.select("A");let ticket = try XCTUnwrap(h.save(article()))
        h.onAudioResolve = { h.onAudioResolve = nil;h.select("B") }
        XCTAssertFalse(h.offline.cacheAudio(ticket));XCTAssertTrue(h.pins.isEmpty)
        h.select("A");_ = h.offline.captureAccess(articleID: "a");h.cached = true
        h.onCached = { h.onCached = nil;h.select("B") }
        XCTAssertFalse(h.offline.audioDownloaded(articleID: "a"))
    }
    func testPinSideEffectSourceReplacementReleasesOnlyOriginalDescriptor() throws {
        let h = Harness();h.select(nil);let ticket = try XCTUnwrap(h.save(article()))
        let original = try XCTUnwrap(h.asset(for: article()))
        h.onPin = { h.onPin = nil;h.audio = URL(string: "https://audio.example.com/new.m4a")! }
        XCTAssertFalse(h.offline.cacheAudio(ticket));XCTAssertEqual(h.releases.last?.2, original)
        XCTAssertTrue(h.offline.cacheAudio(ticket));XCTAssertNotEqual(h.pins.last?.2, original)
    }

    func testReassertedPinCanAdmitReplacementWithoutOldCleanupRemovingIt() throws {
        let h = Harness(); h.select("A"); let ticket = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.cacheAudio(ticket))
        let old = try XCTUnwrap(h.asset(for: article()))
        var replacement: PodcastAudioAsset?
        h.onPin = {
            h.onPin = nil
            h.audio = URL(string: "https://audio.example.com/new-current.m4a")!
            replacement = h.asset(for: self.article())
            XCTAssertTrue(h.offline.cacheAudio(ticket))
        }
        XCTAssertFalse(h.offline.cacheAudio(ticket, asset: old))
        let current = try XCTUnwrap(replacement)
        XCTAssertEqual(h.pins.last?.2, current)
        XCTAssertTrue(h.releases.allSatisfy { $0.2 == old })
        let releases = h.releases.count
        XCTAssertTrue(h.offline.cacheAudio(ticket, asset: current))
        XCTAssertEqual(h.releases.count, releases)
        XCTAssertFalse(h.offline.cacheAudio(ticket, asset: old))
    }

    func testReassertedPinLosesOriginalAccountAndPreservesNewOwner() throws {
        let h = Harness(); h.select("A"); let old = try XCTUnwrap(h.save(article()))
        XCTAssertTrue(h.offline.cacheAudio(old))
        var new: FavoritesOfflineCoordinator.AccessTicket?
        h.onPin = {
            h.onPin = nil; h.select("B"); new = h.save(self.article())
            if let new { XCTAssertTrue(h.offline.cacheAudio(new)) }
        }
        XCTAssertFalse(h.offline.cacheAudio(old))
        let current = try XCTUnwrap(new)
        XCTAssertNotEqual(old.leaseID, current.leaseID)
        XCTAssertEqual(h.pins.last?.1, current.leaseID)
        XCTAssertTrue(h.releases.allSatisfy { $0.1 == old.leaseID })
        XCTAssertTrue(h.offline.cacheAudio(current)); XCTAssertFalse(h.offline.cacheAudio(old))
    }

}
