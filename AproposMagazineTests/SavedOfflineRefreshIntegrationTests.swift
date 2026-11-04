import FirebaseCore
import XCTest
@testable import Apropos

/// Actual VM feed completion, favorite journal and disk body storage, with held
/// local transports. No Firebase configuration, reachability or media service.
@MainActor
final class SavedOfflineRefreshIntegrationTests: XCTestCase {
    @MainActor private final class Fixture {
        let identity = CanonicalSessionState()
        let availability: ArticleAvailabilityModel
        let directory: URL
        let bodies: OfflineManager.BodyStorage
        var records: [FavoritesNamespace: Data] = [:]
        var uid: String? = "offline-reader-A"
        var favoriteUID: String? = "offline-reader-A"
        var onCanonicalRead: (() -> Void)?
        var onCanDownload: (() -> Void)?
        var feed: ArticleViewModel.ReadCompletion<[Article]>?
        var bodyFetches: [(String, ArticleViewModel.ReadCompletion<Article>)] = []
        var holdFavoriteReads: Bool
        var favoriteReads: [(FavoritesNamespace, @MainActor (Result<FavoritesRecord?, Error>) -> Void)] = []
        lazy var favorites = makeModel()
        lazy var offline = makeOffline(favorites)
        lazy var vm: ArticleViewModel = {
            var effects = ArticleViewModel.ReadEffects()
            effects.canDownloadSavedBodies = { [unowned self] in onCanDownload?(); return true }
            effects.feed = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.feed = done
            }
            effects.article = { [unowned self] id, permission, done in
                XCTAssertTrue(permission()); self.bodyFetches.append((id, done))
            }
            return ArticleViewModel(startup: .application, identity: identity,
                actualUserID: { [unowned self] in uid }, readEffects: effects,
                availabilityModel: availability, favoriteObservationModel: favorites,
                favoriteOffline: offline, favoriteCanonicalUserID: { [unowned self] in
                    let value = favoriteUID; onCanonicalRead?(); return value
                })
        }()

        init(old: Article, availabilitySnapshot: ArticleAvailabilityModel.Snapshot = .init(), holdFavoriteReads: Bool = false) throws {
            self.holdFavoriteReads = holdFavoriteReads
            availability = ArticleAvailabilityModel(snapshot: availabilitySnapshot, save: { _ in }, schedule: { _ in {} })
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            bodies = OfflineManager.BodyStorage(directory: directory)
            let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
            records[namespace] = try FavoritesRecordCodec.encode(.init(articles: [old]), namespace: namespace)
            identity.adopt(.init(uid: uid!, email: "offline@example.invalid", isEmailVerified: true))
        }
        func makeModel() -> FavoritesModel {
            let model = FavoritesModel(storage: .init(read: { [unowned self] namespace, complete in
                if holdFavoriteReads { favoriteReads.append((namespace, complete)) }
                else { complete(Result { try records[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) } }) }
            }, write: { [unowned self] namespace, record, expected, complete in
                complete(Result {
                    let previous = try records[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
                    guard previous?.recordRevision == expected else { throw FavoritesJournalFailure.staleRevision }
                    records[namespace] = try FavoritesRecordCodec.encode(record, namespace: namespace)
                })
            }),
                sanitize: { [unowned self] in availability.sanitized($0) })
            model.changeContext(to: .confirmed(userID: favoriteUID))
            return model
        }
        func releaseFavoriteRead() throws {
            let read = try XCTUnwrap(favoriteReads.first)
            favoriteReads.removeFirst()
            read.1(Result { try records[read.0].map { try FavoritesRecordCodec.decode($0, namespace: read.0) } })
        }
        func makeOffline(_ model: FavoritesModel) -> FavoritesOfflineCoordinator {
            FavoritesOfflineCoordinator(model: model, requiresAccount: true,
                storage: .init(read: { [unowned self] in try bodies.read($0) },
                    write: { [unowned self] in try bodies.write($0, article: $1) },
                    contains: { [unowned self] in try bodies.contains($0) }),
                permitsBody: { [unowned self] in availability.permitsBody($0) },
                effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                    audioIsCached: { _ in false }, pinAudio: { _, _, _ in },
                    releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        }
        func flush() async { for _ in 0..<30 { await Task.yield() } }
        func respond(_ articles: [Article], authoritative: Bool) async throws {
            vm.fetchArticles(forceRefresh: true)
            await flush()
            let done = try XCTUnwrap(feed); feed = nil
            if authoritative { availability.recordPublications(articles, ticket: availability.beginRead()) }
            done(.success(articles.map { $0.strippingBodyContent() }))
            await flush()
        }
        func select(_ next: String?) {
            uid = next
            favoriteUID = next
            identity.adopt(next.map { .init(uid: $0, email: "offline@example.invalid", isEmailVerified: true) })
            favorites.changeContext(to: .confirmed(userID: next))
            offline.synchronizeCurrentMembership()
        }
    }
    private func article(revision: String?) -> Article {
        Article(id: "offline-street-fixture", name: "Anmeldelse: Street Fighter (2026)",
            slug: "street-fighter-2026", content: "<p>Hele den aktuelle artikel.</p>", intro: "Intro",
            topicID: "film", isDraft: false, createdOn: "2026-10-15T10:00:00Z",
            lastPublished: "2026-10-15T11:00:00Z", lastUpdated: "2026-10-28T12:00:00Z",
            contentRevision: revision)
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testFreshFeedRepairsPersistedLegacyFavoriteAndColdOfflineBodyWithoutResaving() async throws {
        let old = article(revision: nil), current = article(revision: "cms-sha256-v1:" + String(repeating: "a", count: 64))
        let f = try Fixture(old: old)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let original = try XCTUnwrap(f.offline.captureAccess(articleID: old.id))
        try await f.respond([current], authoritative: true)
        XCTAssertEqual(f.favorites.snapshot.articles.first?.bodyRevision, current.bodyRevision)
        XCTAssertEqual(f.bodyFetches.count, 1, "Saved bodies are filled under the newly approved revision")
        guard let request = f.bodyFetches.first else { return XCTFail("No body request after fresh catalog") }
        request.1(.success(current)); await f.flush()
        XCTAssertFalse(f.offline.isCurrent(original))
        XCTAssertTrue(f.offline.hasBody(articleID: old.id, expectedRevision: current.bodyRevision))
        XCTAssertEqual(f.offline.body(articleID: old.id)?.content, current.content)
        let record = try FavoritesRecordCodec.decode(XCTUnwrap(f.records[f.favorites.context.namespace!]), namespace: f.favorites.context.namespace!)
        XCTAssertTrue(record.pending.isEmpty, "Metadata repair never creates a cloud save intent")
        let cold = f.makeModel(), coldOffline = f.makeOffline(cold)
        XCTAssertEqual(coldOffline.body(articleID: old.id)?.content, current.content)
        XCTAssertEqual(coldOffline.body(articleID: old.id)?.bodyRevision, current.bodyRevision)
    }

    func testFreshFeedBeforeFavoriteLoadRepairsAfterTheOriginalCodecReadCompletes() async throws {
        let old = article(revision: nil), current = article(revision: "fresh-before-private-load")
        let f = try Fixture(old: old, holdFavoriteReads: true)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = f.vm
        XCTAssertFalse(f.favorites.canChangeSelection)
        XCTAssertEqual(f.favoriteReads.count, 1)
        try await f.respond([current], authoritative: true)
        XCTAssertEqual(f.vm.articles.first?.bodyRevision, current.bodyRevision)
        XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
        XCTAssertTrue(f.bodyFetches.isEmpty, "A fresh public feed cannot invent membership before its private journal is loaded")

        f.holdFavoriteReads = false
        try f.releaseFavoriteRead()
        await f.flush()
        XCTAssertTrue(f.favorites.canChangeSelection)
        XCTAssertEqual(f.favorites.snapshot.articles.map(\.id), [old.id])
        XCTAssertEqual(f.favorites.snapshot.articles.first?.bodyRevision, current.bodyRevision)
        XCTAssertEqual(f.bodyFetches.count, 1, "The actual favorite publication hook must use the earlier full-source receipt exactly once")
        XCTAssertTrue(f.favorites.pendingMutations.isEmpty, "Repair is not a user re-save or cloud intent")
        let request = try XCTUnwrap(f.bodyFetches.first)
        request.1(.success(current)); await f.flush()
        XCTAssertEqual(f.bodyFetches.count, 1, "Saving the body must not start a self-sustaining refresh loop")
        XCTAssertEqual(f.offline.body(articleID: old.id)?.content, current.content)
        let cold = f.makeModel(), coldOffline = f.makeOffline(cold)
        XCTAssertEqual(coldOffline.body(articleID: old.id)?.content, current.content)
        XCTAssertEqual(coldOffline.body(articleID: old.id)?.bodyRevision, current.bodyRevision)
        let namespace = try XCTUnwrap(cold.context.namespace)
        let record = try FavoritesRecordCodec.decode(XCTUnwrap(f.records[namespace]), namespace: namespace)
        XCTAssertTrue(record.pending.isEmpty)
        XCTAssertEqual(record.base.first?.contentRevision, current.bodyRevision)
    }

    func testWithdrawalBetweenFreshFeedAndFavoriteLoadRevokesDeferredSourceRepair() async throws {
        let old = article(revision: nil), current = article(revision: "withdrawn-before-private-load")
        let f = try Fixture(old: old, holdFavoriteReads: true)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = f.vm
        try await f.respond([current], authoritative: true)
        f.availability.recordWithdrawals([current.id], ticket: f.availability.beginRead())
        let bytes = f.records
        f.holdFavoriteReads = false
        try f.releaseFavoriteRead()
        await f.flush()
        XCTAssertTrue(f.availability.withdrawnIDs.contains(current.id))
        XCTAssertFalse(f.availability.hasFreshPublicationRead(current))
        XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
        XCTAssertTrue(f.bodyFetches.isEmpty)
        XCTAssertNil(f.offline.body(articleID: current.id))
        XCTAssertEqual(f.records, bytes, "Reject the deferred receipt without purging the preserved private journal")
    }

    func testLateOriginalFavoriteLoadCannotStartAnotherAccountsBodyQueue() async throws {
        let old = article(revision: nil), current = article(revision: "fresh-before-owner-change")
        let f = try Fixture(old: old, holdFavoriteReads: true)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = f.vm
        try await f.respond([current], authoritative: true)
        f.select("offline-reader-B")
        XCTAssertEqual(f.favoriteReads.count, 2)
        let bytes = f.records
        f.holdFavoriteReads = false
        try f.releaseFavoriteRead()
        try f.releaseFavoriteRead()
        await f.flush()
        XCTAssertEqual(f.favorites.context, .confirmed(userID: "offline-reader-B"))
        XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
        XCTAssertTrue(f.bodyFetches.isEmpty)
        XCTAssertNil(f.offline.body(articleID: current.id))
        XCTAssertEqual(f.records, bytes)
    }

    func testOriginalAcknowledgementAndMembershipProofTriggerDeferredCanonicalRepair() async throws {
        let old = article(revision: nil), current = article(revision: "fresh-waits-for-original-ack")
        let f = try Fixture(old: old)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: f.uid).namespace)
        f.records[namespace] = try FavoritesRecordCodec.encode(.empty, namespace: namespace)
        let model = f.favorites
        let recovery = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(recovery))
        let recovered = await model.finishRecovery(recovery, success: true)
        XCTAssertTrue(recovered)
        let mutation = try XCTUnwrap(model.setFavorite(old, enabled: true))
        let started = await model.beginDispatch(mutation)
        let dispatch = try XCTUnwrap(started)
        try await f.respond([current], authoritative: true)
        XCTAssertTrue(f.bodyFetches.isEmpty, "An unknown old operation cannot acquire a new revision silently")
        XCTAssertEqual(model.pendingMutations.first, mutation)
        let before = try FavoritesRecordCodec.decode(XCTUnwrap(f.records[namespace]), namespace: namespace)
        XCTAssertEqual(before.pending.first?.payload.article.bodyRevision, old.bodyRevision)
        XCTAssertEqual(before.pending.first?.phase, .started)

        _ = await model.finishDispatch(dispatch, result: .acknowledged)
        await f.flush()
        XCTAssertTrue(f.bodyFetches.isEmpty, "ACK alone is not fresh server membership proof")
        let observation = try XCTUnwrap(model.observationTicket())
        let originalMembership = try XCTUnwrap(model.membershipTicket(articleID: old.id))
        // The callback may finish the original intent and synchronously adopt
        // R2, superseding applyRemote's operation before its return. Check the
        // observable journal/membership/body results rather than that token.
        _ = model.applyRemote(.init(articles: [old], isFromCache: false, hasPendingWrites: false), ticket: observation)
        await f.flush()
        XCTAssertFalse(model.isCurrent(originalMembership))
        XCTAssertEqual(model.membershipTicket(articleID: old.id)?.contentRevision, current.bodyRevision)
        XCTAssertTrue(model.pendingMutations.isEmpty)
        XCTAssertEqual(model.snapshot.articles.first?.bodyRevision, current.bodyRevision)
        XCTAssertEqual(f.bodyFetches.count, 1, "The shared favorite-change hook must resume repair after the original intention retires")
        let request = try XCTUnwrap(f.bodyFetches.first)
        request.1(.success(current)); await f.flush()
        XCTAssertEqual(f.offline.body(articleID: old.id)?.content, current.content)
        XCTAssertEqual(f.bodyFetches.count, 1)
        let stored = try FavoritesRecordCodec.decode(XCTUnwrap(f.records[namespace]), namespace: namespace)
        XCTAssertTrue(stored.pending.isEmpty)
    }

    func testUnconfirmedCatalogCannotMigrateSavedRevisionOrStartDownload() async throws {
        let old = article(revision: nil), current = article(revision: "new-unconfirmed")
        let f = try Fixture(old: old)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let member = try XCTUnwrap(f.favorites.membershipTicket(articleID: old.id))
        let bytes = f.records
        try await f.respond([current], authoritative: false)
        XCTAssertTrue(f.favorites.isCurrent(member)); XCTAssertEqual(f.records, bytes)
        XCTAssertTrue(f.bodyFetches.isEmpty)
    }

    func testCurrentServerPointReadRepairsBodyAndKeepsLateOwnerBound() async throws {
        for changeOwner in [false, true] {
            let current = article(revision: "point-read-current")
            let f = try Fixture(old: article(revision: nil))
            defer { try? FileManager.default.removeItem(at: f.directory) }
            var result: Result<Article, Error>?
            f.vm.fetchArticle(by: current.id) { result = $0 }
            let done = try XCTUnwrap(f.bodyFetches.first?.1)
            f.availability.recordPublications([current], ticket: f.availability.beginRead())
            if changeOwner { f.select("offline-reader-B") }
            done(.success(current)); await f.flush()
            if changeOwner {
                XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
                XCTAssertNil(f.offline.body(articleID: current.id))
                guard case .failure(let error) = result else { return XCTFail("Expected original read cancellation") }
                XCTAssertTrue(error is CancellationError)
            } else {
                XCTAssertEqual(f.favorites.snapshot.articles.first?.bodyRevision, current.bodyRevision)
                XCTAssertEqual(f.offline.body(articleID: current.id)?.content, current.content)
                guard case .success = result else { return XCTFail("Current server read should remain successful") }
            }
        }
    }

    func testAccountChangeWhileBodyInFlightCannotSaveForTheNewOwner() async throws {
        let current = article(revision: "cms-sha256-v1:" + String(repeating: "b", count: 64))
        let f = try Fixture(old: article(revision: nil))
        defer { try? FileManager.default.removeItem(at: f.directory) }
        try await f.respond([current], authoritative: true)
        let done = try XCTUnwrap(f.bodyFetches.first?.1)
        f.select("offline-reader-B")
        let before = f.records
        done(.success(current)); await f.flush()
        XCTAssertEqual(f.records, before)
        XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
        XCTAssertFalse(f.offline.hasBody(articleID: current.id, expectedRevision: current.bodyRevision))
    }

    func testPersistedApprovalAndUnconfirmedCacheCannotMigrateMetadata() async throws {
        let old = article(revision: nil), current = article(revision: "previously-approved")
        let f = try Fixture(old: old,
            availabilitySnapshot: .init(approvedRevisions: [current.id: current.bodyRevision!]))
        defer { try? FileManager.default.removeItem(at: f.directory) }
        // A cold persisted approval is not a full source read in this process.
        let snapshot = f.favorites.snapshot, bytes = f.records
        try await f.respond([current], authoritative: false)
        XCTAssertEqual(f.favorites.snapshot.articles, snapshot.articles)
        XCTAssertEqual(f.records, bytes); XCTAssertTrue(f.bodyFetches.isEmpty)
    }

    func testUnresolvedPublicReaderCannotRefreshAnotherCanonicalOwnersSavedData() async throws {
        for pointRead in [false, true] {
            let old = article(revision: nil), current = article(revision: "public-source-current")
            let f = try Fixture(old: old)
            defer { try? FileManager.default.removeItem(at: f.directory) }
            _ = f.favorites
            f.uid = "actual-reader-B"
            _ = f.identity.suspend()
            let bytes = f.records
            if pointRead {
                var result: Result<Article, Error>?
                f.vm.fetchArticle(by: old.id) { result = $0 }
                let done = try XCTUnwrap(f.bodyFetches.first?.1)
                f.availability.recordPublications([current], ticket: f.availability.beginRead())
                done(.success(current)); await f.flush()
                guard case .success = result else { return XCTFail("Public reading remains usable") }
            } else {
                try await f.respond([current], authoritative: true)
                XCTAssertTrue(f.bodyFetches.isEmpty)
            }
            XCTAssertEqual(f.records, bytes)
            XCTAssertEqual(f.favorites.snapshot.articles.first?.bodyRevision, old.bodyRevision)
            XCTAssertNil(f.offline.body(articleID: old.id))
        }
    }

    func testCanonicalLookupAndConnectivityHooksCannotStartWorkAfterOwnerChanges() async throws {
        for hook in [0, 1] {
            let current = article(revision: "current-before-hook")
            let f = try Fixture(old: article(revision: nil))
            defer { try? FileManager.default.removeItem(at: f.directory) }
            _ = f.favorites; _ = f.vm
            if hook == 0 {
                f.onCanonicalRead = { [unowned f] in f.onCanonicalRead = nil; f.select("offline-reader-B") }
            } else {
                f.onCanDownload = { [unowned f] in
                    if f.favorites.snapshot.articles.first?.bodyRevision == current.bodyRevision {
                        f.onCanDownload = nil; f.select("offline-reader-B")
                    }
                }
            }
            try await f.respond([current], authoritative: true)
            XCTAssertEqual(f.favoriteUID, "offline-reader-B")
            XCTAssertTrue(f.favorites.snapshot.articles.isEmpty)
            XCTAssertTrue(f.bodyFetches.isEmpty)
        }
    }
}
