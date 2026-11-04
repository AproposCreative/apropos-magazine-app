import FirebaseCore
import XCTest
@testable import Apropos

/// The actual article retry method uses its normal injected model/coordinator
/// and inert read effects. No shared manager, repository, SDK or network starts.
@MainActor
final class SavedOfflineRetryViewModelTests: XCTestCase {
    @MainActor private final class Fixture {
        let identity = CanonicalSessionState()
        let availability = ArticleAvailabilityModel(schedule: { _ in {} })
        let article = Article(id: "retry-story", name: "Artikel", slug: "retry-story", content: "<p>Lokal tekst.</p>",
            intro: "", topicID: "film", isDraft: false, lastPublished: "2026-11-01T08:00:00Z", contentRevision: "retry-r1")
        var records: [FavoritesNamespace: Data] = [:]
        var uid: String? = "retry-A"
        var canonicalUID: String? = "retry-A"
        var online = true
        var bodyRequests = 0, recoveries = 0, catalogRequests = 0, writes = 0
        var onBodyRequest: (() -> Void)?
        var onRecovery: (() -> Void)?
        var catalogCalled: (() -> Void)?
        var heldBodies: [ArticleViewModel.ReadCompletion<Article>] = []
        lazy var model = FavoritesModel(storage: .init(read: { [unowned self] in records[$0] },
            write: { [unowned self] in records[$0] = $1 }))
        lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { _ in nil }, write: { [unowned self] _, _ in writes += 1 }, contains: { _ in false }),
            permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in },
                scheduleRetry: { _, _ in {} }))
        lazy var vm: ArticleViewModel = {
            var effects = ArticleViewModel.ReadEffects()
            effects.canDownloadSavedBodies = { [unowned self] in online }
            effects.article = { [unowned self] _, permission, done in
                XCTAssertTrue(permission())
                bodyRequests += 1
                onBodyRequest?()
                heldBodies.append(done)
            }
            effects.recoverSavedAudioDownloads = { [unowned self] permission in
                XCTAssertTrue(permission())
                recoveries += 1
                onRecovery?()
            }
            effects.refreshSavedAudioCatalog = { [unowned self] permission in
                XCTAssertTrue(permission())
                catalogRequests += 1
                catalogCalled?()
            }
            return ArticleViewModel(startup: .application, identity: identity, actualUserID: { [unowned self] in uid },
                readEffects: effects, availabilityModel: availability, favoriteObservationModel: model,
                favoriteOffline: offline, favoriteCanonicalUserID: { [unowned self] in canonicalUID })
        }()

        func select(_ uid: String?) {
            self.uid = uid; canonicalUID = uid
            identity.adopt(uid.map { .init(uid: $0, email: "retry@example.invalid", isEmailVerified: true) })
            model.changeContext(to: .confirmed(userID: uid))
            offline.synchronizeCurrentMembership()
        }
        func prepare() throws -> FavoritesOfflineCoordinator.AccessTicket {
            select("retry-A")
            XCTAssertNotNil(model.setFavorite(article, enabled: true))
            let ticket = try XCTUnwrap(offline.captureAccess(articleID: article.id))
            XCTAssertTrue(offline.prepareBodyStatus(ticket: ticket))
            XCTAssertEqual(offline.bodyState(ticket: ticket), .notDownloaded)
            _ = vm
            return ticket
        }
        func flush() async { for _ in 0..<12 { await Task.yield() } }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testActualRetryStartsOneOriginalBodyRecoveryAndOneCatalogRequestForCurrentOwner() async throws {
        let f = Fixture(), ticket = try f.prepare()
        let catalog = expectation(description: "Actual VM requests the current owner's catalog once")
        f.catalogCalled = { catalog.fulfill() }
        f.vm.retryOfflineContent(ticket: ticket)
        await fulfillment(of: [catalog], timeout: 3)
        XCTAssertEqual(f.bodyRequests, 1)
        XCTAssertEqual(f.recoveries, 1)
        XCTAssertEqual(f.catalogRequests, 1)
        XCTAssertTrue(f.offline.isCurrent(ticket))
        XCTAssertEqual(f.offline.bodyState(ticket: ticket), .pending)
        XCTAssertEqual(f.writes, 0)
    }

    func testActualBodyRetryOwnerSwitchCannotBecomeTheNextOwnersAudioRecovery() async throws {
        let f = Fixture(), original = try f.prepare()
        f.onBodyRequest = { [unowned f] in f.select("retry-B") }
        f.vm.retryOfflineContent(ticket: original)
        await f.flush()
        XCTAssertEqual(f.bodyRequests, 1)
        XCTAssertEqual(f.model.context, .confirmed(userID: "retry-B"))
        XCTAssertFalse(f.offline.isCurrent(original))
        XCTAssertEqual(f.recoveries, 0)
        XCTAssertEqual(f.catalogRequests, 0)
        XCTAssertEqual(f.writes, 0)
    }

    func testActualBodyRetryReaddCannotRecaptureAReplacementMembership() async throws {
        let f = Fixture(), original = try f.prepare()
        f.onBodyRequest = { [unowned f] in
            _ = f.model.setFavorite(f.article, enabled: false)
            f.offline.synchronizeCurrentMembership()
            _ = f.model.setFavorite(f.article, enabled: true)
            f.offline.synchronizeCurrentMembership()
        }
        f.vm.retryOfflineContent(ticket: original)
        await f.flush()
        XCTAssertEqual(f.bodyRequests, 1)
        XCTAssertFalse(f.offline.isCurrent(original))
        XCTAssertNotNil(f.offline.captureAccess(articleID: f.article.id))
        XCTAssertEqual(f.recoveries, 0)
        XCTAssertEqual(f.catalogRequests, 0)
        XCTAssertEqual(f.writes, 0)
    }

    func testActualRetryRechecksActualUIDAndConnectivityAfterBodyHook() async throws {
        for ownerChange in [false, true] {
            let f = Fixture(), original = try f.prepare()
            f.onBodyRequest = { [unowned f] in
                if ownerChange { f.uid = "retry-B" } else { f.online = false }
            }
            f.vm.retryOfflineContent(ticket: original)
            await f.flush()
            XCTAssertEqual(f.bodyRequests, 1)
            XCTAssertEqual(f.recoveries, 0)
            XCTAssertEqual(f.catalogRequests, 0)
            XCTAssertEqual(f.writes, 0)
        }
    }

    func testActualAudioRecoveryOwnerSwitchCannotStartTheNextOwnersCatalog() async throws {
        let f = Fixture(), original = try f.prepare()
        f.onRecovery = { [unowned f] in f.select("retry-B") }
        f.vm.retryOfflineContent(ticket: original)
        await f.flush()
        XCTAssertEqual(f.bodyRequests, 1)
        XCTAssertEqual(f.recoveries, 1, "The original recovery began before its injected hook changed account")
        XCTAssertEqual(f.catalogRequests, 0)
        XCTAssertFalse(f.offline.isCurrent(original))
        XCTAssertEqual(f.writes, 0)
    }
}
