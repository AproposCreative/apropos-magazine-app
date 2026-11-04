import Combine
import XCTest
@testable import Apropos

/// Actual runtime/model/cloud/two-stage transport, with typed journal callbacks
/// and held provider operations. Every test owns its records and continuations.
@MainActor
final class FavoritesDurablePipelineTests: XCTestCase {
    private func article(_ id: String = "article", revision: String = "r1") -> Article {
        Article(id: id, name: "Artikel " + id, slug: id, content: "<p>Never journal this body</p>", intro: "Private intro",
                topicID: "topic", isDraft: false, lastPublished: "2026-10-20T12:00:00Z", contentRevision: revision)
    }
    private func ready(_ h: PipelineHarness, _ runtime: FavoritesRuntime, uid: String = "A") async {
        let count = h.drain.calls.count + 1
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: uid)
        await h.drain.waitForStarts(count)
        h.drain.finish(count - 1)
        await wait(runtime.model) { $0.recoveryReady }
    }
    private func wait(_ model: FavoritesModel, file: StaticString = #filePath, line: UInt = #line,
                      _ predicate: @escaping (FavoritesSnapshot) -> Bool) async {
        if predicate(model.snapshot) { return }
        let expectation = XCTestExpectation(description: "Actual post-state publication")
        var fulfilled = false
        let subscription = model.changes.sink { snapshot in
            if !fulfilled && predicate(snapshot) { fulfilled = true;expectation.fulfill() }
        }
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
    private func proof(_ runtime: FavoritesRuntime, articles: [Article]) throws {
        let ticket = try XCTUnwrap(runtime.model.observationTicket())
        XCTAssertTrue(runtime.model.applyRemote(.init(articles: articles, isFromCache: false, hasPendingWrites: false), ticket: ticket))
    }
    private func completeProviders(_ h: PipelineHarness, favorite index: Int = 0, profile profileIndex: Int = 0) async {
        h.favorite.finish(index)
        await h.profile.waitForStarts(profileIndex + 1)
        h.profile.finish(profileIndex)
    }

    func testRestartRestoresAddAndFreshDrainPrecedesTwoActualProviderStages() async throws {
        let h = PipelineHarness();defer { h.close() }
        let first = h.runtime();first.prepareIfNeeded();first.changeAccountContext(userID: "A")
        await h.drain.waitForStarts(1)
        first.setFavorite(article(), enabled: true);await first.model.waitForStorage()
        XCTAssertEqual(h.journal.records.values.first?.pending.map(\.enabled), [true])
        XCTAssertTrue(h.favorite.calls.isEmpty)
        first.suspendForAccountChange();h.drain.finish(0)
        let restored = h.runtime();restored.prepareIfNeeded();restored.changeAccountContext(userID: "A")
        await h.drain.waitForStarts(2)
        XCTAssertEqual(restored.model.snapshot.articles.map(\.id), ["article"])
        XCTAssertEqual(restored.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertFalse(restored.model.snapshot.serverConfirmed)
        XCTAssertNil(restored.model.observationTicket(), "Pre-drain listener proof has no authority")
        XCTAssertTrue(h.favorite.calls.isEmpty)
        h.drain.finish(1);await h.favorite.waitForStarts(1)
        try proof(restored, articles: [])
        XCTAssertEqual(restored.model.snapshot.articles.map(\.id), ["article"])
        XCTAssertEqual(h.favorite.calls[0], .init(uid: "A", articleID: "article", enabled: true))
        await completeProviders(h);await restored.model.waitForStorage()
        XCTAssertEqual(restored.model.snapshot.pendingArticleIDs, ["article"], "A provider ACK alone is not server-list proof")
        try proof(restored, articles: [article()]);await restored.model.waitForStorage()
        await wait(restored.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertEqual(h.profile.calls, [.init(uid: "A", articleID: "article", enabled: true)])
        XCTAssertTrue(try XCTUnwrap(h.journal.records[FavoritesContext.confirmed(userID: "A").namespace!]).pending.isEmpty)
    }
    func testRestartRestoresRemovalTombstoneDespiteOldServerAndCacheMembership() async throws {
        let h = PipelineHarness();defer { h.close() };let first = h.runtime()
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        h.journal.records[namespace] = .init(base: [.init(article())])
        first.prepareIfNeeded();first.changeAccountContext(userID: "A");await h.drain.waitForStarts(1)
        first.setFavorite(article(), enabled: false);await first.model.waitForStorage()
        XCTAssertEqual(h.journal.records.values.first?.pending.map(\.enabled), [false])
        first.suspendForAccountChange();h.drain.finish(0)
        let restored = h.runtime();restored.prepareIfNeeded();restored.changeAccountContext(userID: "A");await h.drain.waitForStarts(2)
        XCTAssertNil(restored.model.observationTicket())
        h.drain.finish(1);await h.favorite.waitForStarts(1)
        let ticket = try XCTUnwrap(restored.model.observationTicket())
        XCTAssertTrue(restored.model.applyRemote(.init(articles: [article()], isFromCache: true, hasPendingWrites: false), ticket: ticket))
        try proof(restored, articles: [article()]);XCTAssertTrue(restored.model.snapshot.articles.isEmpty)
        XCTAssertEqual(restored.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertFalse(h.favorite.calls[0].enabled)
        await completeProviders(h);try proof(restored, articles: []);await restored.model.waitForStorage()
        await wait(restored.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertTrue(restored.model.snapshot.articles.isEmpty);XCTAssertFalse(h.profile.calls[0].enabled)
    }
    func testActualFileJournalCarriesRemovalAcrossFreshRuntimeWithoutUploadingTheOldAdd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let h = PipelineHarness();defer { h.close() }
        let uid = "original-owner-not-stored-in-journal", namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
        let first = h.runtime(storage: FavoritesFileJournal(rootDirectory: root).storage)
        first.prepareIfNeeded();first.changeAccountContext(userID: uid);await first.model.waitForStorage();await h.drain.waitForStarts(1)
        first.setFavorite(article(), enabled: true);await first.model.waitForStorage()
        first.suspendForAccountChange();h.drain.finish(0)
        let second = h.runtime(storage: FavoritesFileJournal(rootDirectory: root).storage)
        second.prepareIfNeeded();second.changeAccountContext(userID: uid);await second.model.waitForStorage();await h.drain.waitForStarts(2)
        XCTAssertEqual(second.model.snapshot.articles.map(\.id), ["article"])
        second.setFavorite(article(), enabled: false);await second.model.waitForStorage()
        second.suspendForAccountChange();h.drain.finish(1)
        let restored = h.runtime(storage: FavoritesFileJournal(rootDirectory: root).storage)
        restored.prepareIfNeeded();restored.changeAccountContext(userID: uid);await restored.model.waitForStorage();await h.drain.waitForStarts(3)
        XCTAssertTrue(restored.model.snapshot.articles.isEmpty);XCTAssertEqual(restored.model.snapshot.pendingArticleIDs, ["article"])
        let bytes = try Data(contentsOf: root.appendingPathComponent(namespace.recordBinding + ".json"))
        let record = try FavoritesRecordCodec.decode(bytes, namespace: namespace)
        XCTAssertEqual(record.pending.map(\.enabled), [false])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(uid));XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Never journal this body"))
        XCTAssertTrue(h.favorite.calls.isEmpty)
        h.drain.finish(2);await h.favorite.waitForStarts(1)
        XCTAssertEqual(h.favorite.calls, [.init(uid: uid, articleID: "article", enabled: false)])
        await completeProviders(h);try proof(restored, articles: []);await restored.model.waitForStorage()
        await wait(restored.model) { $0.pendingArticleIDs.isEmpty }
    }
    func testFailedAdmissionNeverDispatchesAndHeldStartedCommitStillOwnsTheBoundary() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        h.journal.holdWrites = true
        let before = h.journal.registeredWrites
        runtime.setFavorite(article(), enabled: true);await h.journal.waitForWrites(before + 1)
        XCTAssertTrue(h.favorite.calls.isEmpty)
        h.journal.finishNextWrite(succeed: false);await runtime.model.waitForStorage()
        XCTAssertEqual(runtime.model.snapshot.state, .writeFailed);XCTAssertTrue(h.favorite.calls.isEmpty)
        runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation)
        await h.journal.waitForWrites(before + 2)
        h.journal.finishNextWrite()
        await h.journal.waitForWrites(before + 3)
        XCTAssertTrue(h.favorite.calls.isEmpty, "The started-attempt record must finish before SDK work")
        h.journal.finishNextWrite(succeed: false)
        await runtime.model.waitForStorage()
        XCTAssertTrue(h.favorite.calls.isEmpty);XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"])
    }
    func testServerProofBeforeACKCannotRetireUntilRetirementRecordActuallyCommits() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        try proof(runtime, articles: [article()]);await runtime.model.waitForStorage()
        h.favorite.finish(0);await h.profile.waitForStarts(1)
        h.journal.holdWrites = true;let before = h.journal.registeredWrites
        h.profile.finish(0);await h.journal.waitForWrites(before + 1)
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertFalse(try XCTUnwrap(h.journal.records.values.first).pending.isEmpty)
        h.journal.finishNextWrite(succeed: false);await runtime.model.waitForStorage()
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertTrue(runtime.model.snapshot.canRetry)
        h.journal.holdWrites = false;runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation)
        await runtime.model.waitForStorage()
        // The exact already-ACKed absolute choice can safely finish retirement;
        // failure never produced a false synchronized UI or lost the disk intent.
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["article"])
    }
    func testFailedRetirementKeepsDurableACKAndExplicitRetryCanFinishIt() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        h.favorite.finish(0);await h.profile.waitForStarts(1)
        let beforeACK = h.journal.registeredWrites
        h.profile.finish(0);await h.journal.waitForWrites(beforeACK + 1);await runtime.model.waitForStorage()
        XCTAssertEqual(h.journal.records.values.first?.pending.first?.phase, .acknowledged)
        h.journal.holdWrites = true;let beforeRetirement = h.journal.registeredWrites
        try proof(runtime, articles: [article()]);await h.journal.waitForWrites(beforeRetirement + 2)
        h.journal.finishNextWrite();h.journal.finishNextWrite(succeed: false);await runtime.model.waitForStorage()
        XCTAssertEqual(h.journal.records.values.first?.pending.first?.phase, .acknowledged)
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"]);XCTAssertTrue(runtime.model.snapshot.canRetry)
        h.journal.holdWrites = false;runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation)
        try proof(runtime, articles: [article()]);await runtime.model.waitForStorage()
        await wait(runtime.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertTrue(try XCTUnwrap(h.journal.records.values.first).pending.isEmpty)
        XCTAssertEqual(h.favorite.calls.count, 1);XCTAssertEqual(h.profile.calls.count, 1)
    }
    func testSameOwnerReturnCannotBypassOldActualWriteOrUseItsReceiptForNewRemoval() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        let oldAccess = try XCTUnwrap(runtime.offline?.captureAccess(articleID: "article"))
        runtime.changeAccountContext(userID: nil);runtime.changeAccountContext(userID: "A")
        await h.drain.waitForStarts(2)
        runtime.setFavorite(article(), enabled: false)
        h.drain.finish(1);await runtime.model.waitForStorage()
        XCTAssertEqual(h.favorite.calls.count, 1);XCTAssertFalse(runtime.offline?.isCurrent(oldAccess) ?? true)
        h.favorite.finish(0);await h.favorite.waitForStarts(2)
        XCTAssertTrue(h.profile.calls.isEmpty, "The old add must not acquire a fresh profile effect after same-UID return")
        XCTAssertFalse(h.favorite.calls[1].enabled)
        await completeProviders(h, favorite: 1);try proof(runtime, articles: []);await runtime.model.waitForStorage()
        await wait(runtime.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }
    func testHeldAdmissionAcrossAccountRoundTripKeepsDiskOrderAndOnlyLatestRemovalDispatches() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        h.journal.holdWrites = true;let before = h.journal.registeredWrites
        runtime.setFavorite(article(), enabled: true);await h.journal.waitForWrites(before + 1)
        runtime.changeAccountContext(userID: nil);runtime.changeAccountContext(userID: "A")
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty, "Visible old-owner state clears before held storage callbacks")
        h.journal.finishNextWrite();await h.drain.waitForStarts(2)
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["article"])
        runtime.setFavorite(article(), enabled: false);await h.journal.waitForWrites(before + 2)
        h.drain.finish(1)
        XCTAssertTrue(h.favorite.calls.isEmpty)
        h.journal.finishNextWrite();await h.journal.waitForWrites(before + 3)
        XCTAssertTrue(h.favorite.calls.isEmpty, "Latest tombstone still needs its started-attempt commit")
        h.journal.finishNextWrite();await h.favorite.waitForStarts(1)
        XCTAssertEqual(h.favorite.calls, [.init(uid: "A", articleID: "article", enabled: false)])
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        XCTAssertEqual(h.journal.records.values.first?.pending.map(\.enabled), [false])
    }
    func testGlobalTransportLimitAndRepeatedRetryRetainActualSlots() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        for index in 0..<8 { runtime.setFavorite(article("a-\(index)"), enabled: true) }
        await h.favorite.waitForStarts(4)
        for _ in 0..<12 { runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation) }
        await runtime.model.waitForStorage()
        XCTAssertEqual(h.favorite.calls.count, 4);XCTAssertEqual(h.favorite.activeCount, 4)
        h.favorite.finish(0);await h.profile.waitForStarts(1)
        XCTAssertEqual(h.favorite.calls.count, 4, "The favorite receipt cannot release a slot while profile write remains actual")
        h.profile.finish(0);await h.favorite.waitForStarts(5)
        XCTAssertEqual(h.favorite.activeCount, 4)
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs.count, 8)
    }
    func testWithdrawalPreservesUnknownStartedObligationAndRevokesOfflineAuthority() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        let access = try XCTUnwrap(runtime.offline?.captureAccess(articleID: "article"))
        h.allowed = false;runtime.model.reconcileAvailability();await runtime.model.waitForStorage()
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty);XCTAssertFalse(runtime.offline?.isCurrent(access) ?? true)
        let record = try XCTUnwrap(h.journal.records.values.first)
        XCTAssertTrue(record.requiresRecovery);XCTAssertFalse(record.pending.isEmpty, "Hidden membership cannot erase an unknown provider operation")
        h.favorite.finish(0);await runtime.model.waitForStorage()
        XCTAssertTrue(h.profile.calls.isEmpty)
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }
    func testColdPresentArrivingAndReplacedLocalProfilesNeverBlockOrReceiveMirrorPatches() async throws {
        for timing in 0..<5 {
            let h = PipelineHarness();defer { h.close() };let runtime = h.runtime()
            let original = PipelineHarness.LocalProfile(uid: "A", loadID: UUID(), bookmarks: ["local-original"])
            let replacement = PipelineHarness.LocalProfile(uid: "A", loadID: UUID(), bookmarks: ["local-replacement"])
            if timing == 1 || timing == 3 { h.localProfile = original }
            await ready(h, runtime);runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
            if timing == 2 { h.localProfile = replacement }
            h.favorite.finish(0);await h.profile.waitForStarts(1)
            if timing == 3 { h.localProfile = replacement }
            let beforeACK = h.journal.registeredWrites
            h.profile.finish(0);await h.journal.waitForWrites(beforeACK + 1);await runtime.model.waitForStorage()
            if timing == 4 { h.localProfile = replacement }
            try proof(runtime, articles: [article()]);await runtime.model.waitForStorage()
            await wait(runtime.model) { $0.pendingArticleIDs.isEmpty }
            let expected: PipelineHarness.LocalProfile? = timing == 0 ? nil : (timing == 1 ? original : replacement)
            XCTAssertEqual(h.localProfile, expected, "Mirror must not fabricate or patch a separately loaded profile")
            XCTAssertEqual(h.serverProfiles["A"], .init(name: "Existing A profile", bookmarks: ["article"]))
            XCTAssertEqual(h.profile.calls, [.init(uid: "A", articleID: "article", enabled: true)])
        }
    }
    func testIdentityReadReentryRejectsOldMirrorAfterOtherOwnerSameOwnerReturnOrOppositeIntent() async throws {
        for transition in 0..<3 {
            let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
            runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
            let reentered = expectation(description: "Identity seam reenters before remote mirror")
            h.onMirrorIdentity = {
                h.onMirrorIdentity = nil
                if transition == 0 { runtime.changeAccountContext(userID: "B") }
                else if transition == 1 { runtime.changeAccountContext(userID: nil);runtime.changeAccountContext(userID: "A") }
                else { runtime.setFavorite(self.article(), enabled: false) }
                reentered.fulfill()
            }
            h.favorite.finish(0);await fulfillment(of: [reentered], timeout: 3)
            await runtime.model.waitForStorage()
            XCTAssertTrue(h.profile.calls.isEmpty)
            XCTAssertEqual(h.serverProfiles["A"]?.bookmarks, [])
            XCTAssertNil(h.localProfile)
            if transition == 2 { XCTAssertTrue(runtime.model.snapshot.articles.isEmpty);XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"]) }
        }
    }
    func testHeldOriginalMirrorKeepsSlotUntilReturnAndCannotACKNewOppositeIntent() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();await ready(h, runtime)
        let local = PipelineHarness.LocalProfile(uid: "A", loadID: UUID(), bookmarks: ["unrelated-local"]);h.localProfile = local
        runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        h.favorite.finish(0);await h.profile.waitForStarts(1)
        runtime.setFavorite(article(), enabled: false);await runtime.model.waitForStorage()
        XCTAssertEqual(h.favorite.calls.count, 1);XCTAssertEqual(h.profile.activeCount, 1)
        h.profile.finish(0);await h.favorite.waitForStarts(2)
        XCTAssertEqual(h.favorite.calls[1], .init(uid: "A", articleID: "article", enabled: false))
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertEqual(h.serverProfiles["A"]?.bookmarks, ["article"], "An original provider operation already started may return; it cannot ACK the new removal")
        await completeProviders(h, favorite: 1, profile: 1)
        try proof(runtime, articles: []);await runtime.model.waitForStorage();await wait(runtime.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertEqual(h.serverProfiles["A"]?.bookmarks, []);XCTAssertEqual(h.localProfile, local)
    }
    func testMissingServerProfileFailsWithoutCreatingBlankProfileThenRetriesAfterRealProfileCreation() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime();h.serverProfiles.removeValue(forKey: "A")
        await ready(h, runtime);runtime.setFavorite(article(), enabled: true);await h.favorite.waitForStarts(1)
        await completeProviders(h);await wait(runtime.model) { $0.state == .cloudFailed }
        XCTAssertNil(h.localProfile);XCTAssertNil(h.serverProfiles["A"])
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"])
        XCTAssertEqual(h.journal.records.values.first?.pending.first?.phase, .failed)
        h.serverProfiles["A"] = .init(name: "Profile created by the proper profile flow", bookmarks: ["unrelated"])
        runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation);await h.favorite.waitForStarts(2)
        await completeProviders(h, favorite: 1, profile: 1)
        try proof(runtime, articles: [article()]);await runtime.model.waitForStorage();await wait(runtime.model) { $0.pendingArticleIDs.isEmpty }
        XCTAssertEqual(h.serverProfiles["A"], .init(name: "Profile created by the proper profile flow", bookmarks: ["unrelated", "article"]))
        XCTAssertNil(h.localProfile)
    }
    func testRecoveryRetriesKeepOneActualDrainAndReadFailureNeverOverwritesUnknownRecord() async throws {
        let h = PipelineHarness();defer { h.close() };let runtime = h.runtime()
        h.journal.readFailure = PipelineFailure.storage
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: "A")
        runtime.setFavorite(article(), enabled: true)
        for _ in 0..<5 { runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation) }
        XCTAssertTrue(h.drain.calls.isEmpty);XCTAssertEqual(h.journal.registeredWrites, 0)
        h.journal.readFailure = nil;runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation)
        await h.drain.waitForStarts(1)
        for _ in 0..<12 { runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation) }
        await runtime.model.waitForStorage()
        XCTAssertEqual(h.drain.calls.count, 1);XCTAssertEqual(h.drain.activeCount, 1)
        h.drain.finish(0, succeed: false)
        await wait(runtime.model) { $0.canRetry }
        runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation);await h.drain.waitForStarts(2)
        XCTAssertEqual(h.drain.activeCount, 1);XCTAssertTrue(h.favorite.calls.isEmpty)
    }
}

@MainActor
private final class PipelineHarness {
    let journal = PipelineJournal()
    let drain = PipelineLane(), favorite = PipelineLane(), profile = PipelineLane()
    struct LocalProfile: Equatable { let uid: String;let loadID: UUID;let bookmarks: Set<String> }
    struct ServerProfile: Equatable { let name: String;var bookmarks: Set<String> }
    var localProfile: LocalProfile?
    var serverProfiles: [String: ServerProfile] = ["A": .init(name: "Existing A profile", bookmarks: []),
        "B": .init(name: "Existing B profile", bookmarks: []),
        "original-owner-not-stored-in-journal": .init(name: "Existing recovery profile", bookmarks: [])]
    var onMirrorIdentity: (() -> Void)?
    var allowed = true
    private var runtimes: [FavoritesRuntime] = []
    func runtime(storage: FavoritesModel.Storage? = nil) -> FavoritesRuntime {
        let runtime = FavoritesRuntime(disabled: false, requiresAccountForSaving: false, storageFactory: { [self] in storage ?? journal.storage },
            drainPendingWrites: { [self] uid in try await drain.perform(.init(uid: uid, articleID: "", enabled: false)) },
            writeFavorite: { [self] mutation, uid in try await favorite.perform(.init(uid: uid, articleID: mutation.articleID, enabled: mutation.enabled)) },
            offlineFactory: { [self] model in
                FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }), permitsBody: { [self] _ in allowed },
                    effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil }, audioIsCached: { _ in false },
                                   pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
            }, profileSet: { [self] ticket, uid, model in
                try await FavoritesProfileMirror.perform(model: model, ticket: ticket, expectedUserID: uid,
                    effects: .init(identity: { [self] in
                        onMirrorIdentity?()
                        let current = model.context == .confirmed(userID: uid) ? uid : nil
                        return .init(actualUID: current, canonicalUID: current)
                    }, updateExisting: { [self] originalUID, id, enabled in
                        try await profile.perform(.init(uid: originalUID, articleID: id, enabled: enabled))
                        guard var existing = serverProfiles[originalUID] else { throw PipelineFailure.missingServerProfile }
                        if enabled { existing.bookmarks.insert(id) } else { existing.bookmarks.remove(id) }
                        serverProfiles[originalUID] = existing
                    }))
            },
            sanitize: { [self] article in allowed ? article : nil })
        runtimes.append(runtime);return runtime
    }
    func close() {
        runtimes.forEach { $0.suspendForAccountChange() };journal.failOutstanding();drain.failOutstanding();favorite.failOutstanding();profile.failOutstanding()
    }
}
private enum PipelineFailure: Error { case storage, provider, missingServerProfile }
@MainActor
private final class PipelineLane {
    struct Call: Equatable { let uid: String;let articleID: String;let enabled: Bool }
    private(set) var calls: [Call] = []
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var waiters: [(Int, XCTestExpectation)] = []
    var activeCount: Int { continuations.count }
    func perform(_ call: Call) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let index = calls.count;calls.append(call);continuations[index] = continuation
            let ready = waiters.filter { $0.0 <= calls.count };waiters.removeAll { $0.0 <= calls.count };ready.forEach { $0.1.fulfill() }
        }
    }
    func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        if calls.count >= count { return }
        let expectation = XCTestExpectation(description: "Actual injected provider starts \(count)");waiters.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
    func finish(_ index: Int, succeed: Bool = true) {
        let continuation = continuations.removeValue(forKey: index)
        if succeed { continuation?.resume() } else { continuation?.resume(throwing: PipelineFailure.provider) }
    }
    func failOutstanding() { let all = continuations.values;continuations = [:];all.forEach { $0.resume(throwing: PipelineFailure.provider) } }
}
@MainActor
private final class PipelineJournal {
    typealias ReadCompletion = @MainActor (Result<FavoritesRecord?, Error>) -> Void
    typealias WriteCompletion = @MainActor (Result<Void, Error>) -> Void
    private enum Operation {
        case read(FavoritesNamespace, ReadCompletion)
        case write(FavoritesNamespace, FavoritesRecord, UUID?, WriteCompletion)
    }
    var records: [FavoritesNamespace: FavoritesRecord] = [:]
    var readFailure: Error?
    var holdWrites = false { didSet { pump() } }
    private(set) var registeredWrites = 0
    private var operations: [Operation] = []
    private var pumping = false
    private var waiters: [(Int, XCTestExpectation)] = []
    var storage: FavoritesModel.Storage {
        .init(read: { [self] namespace, completion in operations.append(.read(namespace, completion));pump() },
              write: { [self] namespace, record, expected, completion in
            registeredWrites += 1;operations.append(.write(namespace, record, expected, completion))
            let ready = waiters.filter { $0.0 <= registeredWrites };waiters.removeAll { $0.0 <= registeredWrites };ready.forEach { $0.1.fulfill() };pump()
        })
    }
    private func pump() {
        guard !pumping else { return };pumping = true;defer { pumping = false }
        while let operation = operations.first {
            switch operation {
            case .read(let namespace, let completion):
                operations.removeFirst()
                if let readFailure { completion(.failure(readFailure)) } else { completion(.success(records[namespace])) }
            case .write:
                guard !holdWrites else { return };operations.removeFirst();commit(operation, succeed: true)
            }
        }
    }
    private func commit(_ operation: Operation, succeed: Bool) {
        guard case .write(let namespace, let record, let expected, let completion) = operation else { return }
        guard succeed, records[namespace]?.recordRevision == expected else { completion(.failure(PipelineFailure.storage));return }
        do {
            // Use the real strict codec at every simulated durable replacement.
            let bytes = try FavoritesRecordCodec.encode(record, namespace: namespace)
            records[namespace] = try FavoritesRecordCodec.decode(bytes, namespace: namespace)
            completion(.success(()))
        } catch { completion(.failure(error)) }
    }
    func finishNextWrite(succeed: Bool = true) {
        guard let operation = operations.first, case .write = operation else { XCTFail("No actual journal write waiting");return }
        operations.removeFirst();commit(operation, succeed: succeed);pump()
    }
    func waitForWrites(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        if registeredWrites >= count { return }
        let expectation = XCTestExpectation(description: "Typed journal write registered \(count)");waiters.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3);XCTAssertEqual(result, .completed, file: file, line: line)
    }
    func failOutstanding() {
        let all = operations;operations = []
        for operation in all {
            switch operation {
            case .read(_, let completion): completion(.failure(PipelineFailure.storage))
            case .write(_, _, _, let completion): completion(.failure(PipelineFailure.storage))
            }
        }
    }
}
