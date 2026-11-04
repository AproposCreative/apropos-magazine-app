import XCTest
import FirebaseCore
@testable import Apropos

@MainActor
final class FavoritesAccountAdmissionTests: XCTestCase {
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var writes = 0
        var bodyReads = 0
        var bodyWrites = 0
        var imageRequests = 0
        var audioResolutions = 0
        var permissionAllowed = true
        var permissionAvailable = true
        var captureHook: (() -> Void)?
        var permissionHook: (() -> Void)?
        var permitsBodyHook: (() -> Void)?
        var storage: FavoritesModel.Storage {
            .init(read: { [self] namespace, done in done(.success(records[namespace])) },
                  write: { [self] namespace, record, expected, done in
                guard records[namespace]?.recordRevision == expected else {
                    done(.failure(FavoritesJournalFailure.staleRevision)); return
                }
                writes += 1; records[namespace] = record; done(.success(()))
            })
        }
        func offline(_ model: FavoritesModel, requiresAccount: Bool = true) -> FavoritesOfflineCoordinator {
            FavoritesOfflineCoordinator(model: model, requiresAccount: requiresAccount,
                storage: .init(read: { [self] _ in bodyReads += 1; return nil },
                    write: { [self] _, _ in bodyWrites += 1 }),
                permitsBody: { [self] _ in permitsBodyHook?(); return true },
                effects: .init(cacheImages: { [self] _, _ in imageRequests += 1 },
                    audioAsset: { [self] _ in audioResolutions += 1; return nil },
                    audioIsCached: { _ in false }, pinAudio: { _, _, _ in },
                    releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        }
        func runtime() -> FavoritesRuntime {
            FavoritesRuntime(disabled: false, storageFactory: { [self] in storage },
                capturePermission: { [self] in
                    captureHook?()
                    guard permissionAvailable else { return nil }
                    return { [self] in permissionHook?(); return permissionAllowed }
                }, drainPendingWrites: { _, _ in }, writeFavorite: { _, _, _ in },
                offlineFactory: { [self] in offline($0) }, profileSet: { _, _, _, _ in })
        }
    }
    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: "Artikel", slug: id, content: "<p>Indhold</p>", intro: "", topicID: "topic",
            isDraft: false, lastPublished: "2026-10-20T12:00:00Z", contentRevision: "revision-1")
    }

    func testProductionDefaultDeniesGuestSaveButPreservesAndRemovesHistoricalGuestRecord() throws {
        let memory = Memory()
        let legacy = FavoritesModel(storage: memory.storage)
        legacy.changeContext(to: .guest)
        XCTAssertNotNil(legacy.setFavorite(article("legacy"), enabled: true))
        let stored = memory.records[.guest]
        let runtime = memory.runtime()
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: nil)
        let before = memory.writes
        XCTAssertNil(runtime.setFavorite(article("new"), enabled: true))
        XCTAssertEqual(memory.writes, before)
        XCTAssertEqual(memory.records[.guest], stored)
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["legacy"])
        XCTAssertNil(runtime.offline?.captureAccess(articleID: "legacy"))
        XCTAssertNotNil(runtime.setFavorite(article("legacy"), enabled: false))
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        XCTAssertEqual(memory.imageRequests, 0)
        XCTAssertEqual(memory.audioResolutions, 0)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testConfirmedAccountRequiresCurrentPermissionAndCanSaveWithoutGuestTransfer() {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "A")
        memory.permissionAllowed = false
        let before = memory.writes
        XCTAssertNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(memory.writes, before)
        memory.permissionAllowed = true
        XCTAssertNotNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["article"])
        runtime.changeAccountContext(userID: nil)
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        XCTAssertNil(memory.records[.guest])
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testUnresolvedAndUnavailableAccountPermissionDoNotMutateJournal() {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded()
        XCTAssertNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(memory.writes, 0)
        runtime.changeAccountContext(userID: "A")
        memory.permissionAvailable = false
        let before = memory.writes
        XCTAssertNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(memory.writes, before)
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }

    func testPermissionCaptureReentryCannotSaveForNewOwner() {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "A")
        memory.captureHook = { [weak runtime] in
            memory.captureHook = nil
            runtime?.changeAccountContext(userID: "B")
        }
        let before = memory.writes
        XCTAssertNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(memory.writes, before)
        XCTAssertEqual(runtime.model.context, .confirmed(userID: "B"))
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }

    func testPermissionEvaluationRoundTripCannotBorrowSameUIDGeneration() {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "A")
        let original = runtime.model.snapshot.generation
        memory.permissionHook = { [weak runtime] in
            memory.permissionHook = nil
            runtime?.suspendForAccountChange(); runtime?.changeAccountContext(userID: "A")
        }
        let before = memory.writes
        XCTAssertNil(runtime.setFavorite(article(), enabled: true))
        XCTAssertEqual(memory.writes, before)
        XCTAssertNotEqual(runtime.model.snapshot.generation, original)
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }

    func testAccountOnlyOfflineGateDeniesGuestBodyAndMediaWithoutDeletingMembership() {
        let memory = Memory(), model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .guest)
        XCTAssertNotNil(model.setFavorite(article(), enabled: true))
        let offline = memory.offline(model)
        XCTAssertNil(offline.captureAccess(articleID: "article"))
        XCTAssertNil(offline.body(articleID: "article"))
        offline.synchronizeCurrentMembership()
        XCTAssertEqual(model.snapshot.articles.map(\.id), ["article"])
        XCTAssertEqual(memory.bodyReads, 0)
        XCTAssertEqual(memory.bodyWrites, 0)
        XCTAssertEqual(memory.imageRequests, 0)
        XCTAssertEqual(memory.audioResolutions, 0)
    }

    func testOldAccountTicketAndHeldBodyCannotWriteAfterGuestTransition() throws {
        let memory = Memory(), model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A"))
        XCTAssertNotNil(model.setFavorite(article(), enabled: true))
        let offline = memory.offline(model)
        let ticket = try XCTUnwrap(offline.captureAccess(articleID: "article"))
        var reply: (@MainActor (Result<Article, Error>) -> Void)?
        XCTAssertTrue(offline.requestBody(ticket: ticket) { _, completion in reply = completion })
        XCTAssertNotNil(reply)
        model.changeContext(to: .guest)
        XCTAssertFalse(offline.isCurrent(ticket))
        XCTAssertFalse(offline.saveBody(article(), ticket: ticket))
        reply?(.success(article()))
        XCTAssertEqual(memory.bodyWrites, 0)
        XCTAssertFalse(offline.retryBody(ticket: ticket) { _, _ in XCTFail("Stale guest retry started a fetch") })
    }

    func testReentrantBodyPolicyCannotGrantTicketAfterAccountBecomesGuest() {
        let memory = Memory(), model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A"))
        XCTAssertNotNil(model.setFavorite(article(), enabled: true))
        let offline = memory.offline(model)
        memory.permitsBodyHook = {
            memory.permitsBodyHook = nil
            model.changeContext(to: .guest)
        }
        XCTAssertNil(offline.captureAccess(articleID: "article"))
        XCTAssertEqual(memory.bodyReads, 0)
        XCTAssertEqual(memory.bodyWrites, 0)
        XCTAssertEqual(memory.imageRequests, 0)
        XCTAssertEqual(memory.audioResolutions, 0)
    }
}
