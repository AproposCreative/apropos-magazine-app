import XCTest
@testable import Apropos

/// The real runtime → coordinator → two-stage transport, with memory providers.
@MainActor
final class FavoritesRuntimeStartupTests: XCTestCase {
    typealias Guard = FavoritesCloudCoordinator.Guard
    @MainActor private final class Fixture {
        var allow = true
        var authority = UUID()
        var captures = 0
        var captureHook: (() -> Void)?
        var favoriteHook: (() -> Void)?
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var drains: [String] = []
        var favorites: [String] = []
        var mirrors: [String] = []
        var favoriteGuards: [Guard] = []
        var mirrorGuards: [Guard] = []
        var holdFavorite = false
        var holdMirror = false
        var favoriteReply: CheckedContinuation<Void, Never>?
        var mirrorReply: CheckedContinuation<Void, Never>?
        lazy var runtime = FavoritesRuntime(disabled: false, requiresAccountForSaving: false, storageFactory: { [self] in
            .init(read: { [self] ns, done in done(.success(records[ns])) },
                  write: { [self] ns, record, expected, done in
                guard records[ns]?.recordRevision == expected else { done(.failure(FavoritesJournalFailure.staleRevision)); return }
                records[ns] = record; done(.success(()))
            })
        }, capturePermission: { [self] in
            captures += 1
            let original = authority
            captureHook?()
            guard allow else { return nil }
            return { [self] in allow && authority == original }
        }, drainPendingWrites: { [self] uid, current in
            guard current() else { throw CancellationError() }
            drains.append(uid)
        }, writeFavorite: { [self] _, uid, current in
            guard current() else { throw CancellationError() }
            favorites.append(uid); favoriteGuards.append(current)
            favoriteHook?()
            if holdFavorite { await withCheckedContinuation { favoriteReply = $0 } }
        }, offlineFactory: { model in
            FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }),
                permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in },
                scheduleRetry: { _, _ in {} }))
        }, profileSet: { [self] _, uid, _, current in
            guard current() else { throw CancellationError() }
            mirrors.append(uid); mirrorGuards.append(current)
            if holdMirror { await withCheckedContinuation { mirrorReply = $0 } }
        })
        func start(_ uid: String? = "a") { runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: uid) }
        func finish() {
            allow = false
            favoriteReply?.resume(); favoriteReply = nil
            mirrorReply?.resume(); mirrorReply = nil
        }
    }
    private func article() -> Article {
        Article(id: "article", name: "Titel", slug: "artikel", content: "<p>Tekst</p>", intro: "", topicID: "kultur",
                isDraft: false, lastPublished: "2026-10-20T12:00:00Z", contentRevision: "revision-1")
    }
    private func settle() async { for _ in 0..<40 { await Task.yield() } }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<3000 { if condition() { return }; await Task.yield() }
        XCTFail("Local pipeline did not reach expected state", file: file, line: line)
    }
    private func ready(_ f: Fixture) async { f.start(); await wait { f.runtime.model.snapshot.recoveryReady } }

    func testConstructionAndGuestDoNotCaptureAuthorityOrStartProviders() async {
        let f = Fixture(); defer { f.finish() }
        _ = f.runtime
        XCTAssertEqual(f.captures, 0)
        f.start(nil); f.runtime.setFavorite(article(), enabled: true)
        await settle()
        XCTAssertEqual(f.captures, 0); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertTrue(f.favorites.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        XCTAssertEqual(f.runtime.model.snapshot.articles.map(\.id), ["article"])
    }
    func testClosedStartupKeepsLocalChoiceAndOnlyExplicitRetryOpensTransport() async {
        let f = Fixture(); defer { f.finish() }
        f.allow = false; f.start(); f.runtime.setFavorite(article(), enabled: true)
        await settle()
        XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.favorites.isEmpty)
        XCTAssertEqual(f.runtime.model.snapshot.pendingArticleIDs, ["article"])
        f.allow = true; await settle()
        XCTAssertTrue(f.drains.isEmpty)
        f.runtime.retryCurrentChanges(generation: f.runtime.model.snapshot.generation)
        await wait { f.mirrors.count == 1 }
        XCTAssertEqual(f.favorites, ["a"]); XCTAssertEqual(f.mirrors, ["a"])
    }
    func testOneDispatchCaptureIsSharedAcrossBothPhysicalStages() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f)
        let before = f.captures
        f.runtime.setFavorite(article(), enabled: true)
        await wait { f.mirrors.count == 1 }
        XCTAssertEqual(f.captures - before, 1)
        XCTAssertEqual(f.favorites, ["a"]); XCTAssertEqual(f.mirrors, ["a"])
    }
    func testRevocationBetweenFavoriteAndMirrorKeepsIntentWithoutSecondWrite() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f)
        f.favoriteHook = { f.allow = false }
        f.runtime.setFavorite(article(), enabled: true)
        await wait { f.favorites.count == 1 }
        await settle(); await f.runtime.model.waitForStorage()
        XCTAssertTrue(f.mirrors.isEmpty)
        XCTAssertEqual(f.runtime.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertEqual(f.records.values.flatMap(\.pending).first?.phase, .failed)
    }
    func testHeldFavoriteCannotBorrowSameUIDAfterAccountRoundTrip() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f); f.holdFavorite = true
        f.runtime.setFavorite(article(), enabled: true)
        await wait { f.favoriteReply != nil }
        let oldGeneration = f.runtime.model.snapshot.generation
        f.allow = false
        f.runtime.changeAccountContext(userID: "b"); f.runtime.changeAccountContext(userID: "a")
        XCTAssertNotEqual(oldGeneration, f.runtime.model.snapshot.generation)
        f.favoriteReply?.resume(); f.favoriteReply = nil
        await settle()
        XCTAssertTrue(f.mirrors.isEmpty)
        XCTAssertFalse(f.favoriteGuards[0]())
        XCTAssertEqual(f.runtime.model.snapshot.pendingArticleIDs, ["article"])
    }
    func testRevokedMirrorCompletionCannotAcknowledgeOriginalIntent() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f); f.holdMirror = true
        f.runtime.setFavorite(article(), enabled: true)
        await wait { f.mirrorReply != nil }
        f.authority = UUID()
        f.mirrorReply?.resume(); f.mirrorReply = nil
        await settle(); await f.runtime.model.waitForStorage()
        XCTAssertEqual(f.records.values.flatMap(\.pending).first?.phase, .failed)
        XCTAssertEqual(f.runtime.model.snapshot.pendingArticleIDs, ["article"])
    }
    func testCaptureReentryCannotMoveOriginalDispatchToNewOwner() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f)
        f.captureHook = {
            f.captureHook = nil; f.allow = false
            f.runtime.changeAccountContext(userID: "b")
        }
        f.runtime.setFavorite(article(), enabled: true)
        await settle()
        XCTAssertTrue(f.favorites.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        XCTAssertEqual(f.runtime.model.context, .confirmed(userID: "b"))
        XCTAssertTrue(f.runtime.model.snapshot.articles.isEmpty)
    }
    func testExplicitRetryCreatesFreshAttemptWithoutRevivingDeniedGuard() async {
        let f = Fixture(); defer { f.finish() }
        await ready(f)
        f.favoriteHook = { f.allow = false }
        f.runtime.setFavorite(article(), enabled: true)
        await wait { f.favorites.count == 1 }
        await settle(); await f.runtime.model.waitForStorage()
        let old = f.favoriteGuards[0]
        XCTAssertFalse(old())
        f.favoriteHook = nil; f.allow = true
        XCTAssertFalse(old(), "Observed denial cannot revive on an equal current UID")
        f.runtime.retryCurrentChanges(generation: f.runtime.model.snapshot.generation)
        await wait { f.mirrors.count == 1 }
        XCTAssertEqual(f.favorites.count, 2)
        XCTAssertEqual(f.mirrors, ["a"])
    }
}
