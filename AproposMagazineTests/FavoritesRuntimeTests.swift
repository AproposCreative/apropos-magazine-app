import Combine
import XCTest
import FirebaseCore
@testable import Apropos

final class FavoritesRuntimeTests: XCTestCase {
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var factories = 0
        var reads = 0
        var writes = 0
        var profile: [(String, Bool, String)] = []
        var cloud: [(String, Bool, String)] = []
        var onFactory: (@MainActor () -> Void)?
        var onProfile: (@MainActor () -> Void)?
        var failWrites = false
        var failDrain = false
        var drainCalls: [String] = []
        var profileExpectation: XCTestExpectation?
        enum Failure: Error { case write }
        func runtime(disabled: Bool = false) -> FavoritesRuntime {
            FavoritesRuntime(disabled: disabled, requiresAccountForSaving: false, storageFactory: { [self] in
                factories += 1
                onFactory?()
                return .init(read: { [self] namespace, completion in reads += 1;completion(.success(records[namespace])) },
                             write: { [self] namespace, record, expectedRevision, completion in
                    writes += 1
                    guard !failWrites, records[namespace]?.recordRevision == expectedRevision else { completion(.failure(Failure.write));return }
                    records[namespace] = record;completion(.success(()))
                })
            }, drainPendingWrites: { [self] uid in
                drainCalls.append(uid)
                if failDrain { throw Failure.write }
            }, writeFavorite: { [self] mutation, uid in
                cloud.append((mutation.articleID, mutation.enabled, uid))
            }, offlineFactory: { [self] model in
                factories += 1
                return FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }),
                    permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                    audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in },
                    scheduleRetry: { _, _ in {} }))
            }, profileSet: { [self] ticket, uid, model in
                try await FavoritesProfileMirror.perform(model: model, ticket: ticket, expectedUserID: uid,
                    effects: .init(identity: {
                        let current = model.context == .confirmed(userID: uid) ? uid : nil
                        return .init(actualUID: current, canonicalUID: current)
                    }, updateExisting: { [self] originalUID, article, enabled in
                        profile.append((article, enabled, originalUID));onProfile?();profileExpectation?.fulfill();profileExpectation = nil
                    }))
            })
        }
    }
    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: id, slug: id, content: "<p>Public body</p>", intro: "", topicID: "topic",
                isDraft: false, lastPublished: "2026-10-20T12:00:00Z", contentRevision: "revision-1")
    }
    @MainActor func testDisabledAndUnpreparedRuntimeDoesNotOpenStoresOrServices() {
        XCTAssertNil(FirebaseApp.allApps)
        let memory = Memory(), runtime = memory.runtime(disabled: true)
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: "reader-a")
        runtime.setFavorite(article(), enabled: true);runtime.retryMutation(articleID: "article")
        runtime.retryCurrentChanges(generation: runtime.model.snapshot.generation)
        runtime.suspendForAccountChange()
        XCTAssertEqual(memory.factories, 0)
        XCTAssertEqual(memory.reads, 0)
        XCTAssertNil(runtime.offline)
        XCTAssertEqual(runtime.model.context, .unresolved)
        let unprepared = memory.runtime()
        unprepared.changeAccountContext(userID: nil);unprepared.setFavorite(article(), enabled: true)
        XCTAssertEqual(memory.factories, 0)
        XCTAssertTrue(memory.profile.isEmpty)
        XCTAssertNil(FirebaseApp.allApps)
    }
    @MainActor func testPrepareIsReentrantAndReadsOnlyAfterCanonicalContext() {
        let memory = Memory(), runtime = memory.runtime()
        memory.onFactory = { [weak runtime] in runtime?.prepareIfNeeded();runtime?.changeAccountContext(userID: nil) }
        runtime.prepareIfNeeded();runtime.prepareIfNeeded()
        XCTAssertEqual(memory.factories, 2)
        XCTAssertEqual(memory.reads, 0)
        runtime.changeAccountContext(userID: "reader-a")
        XCTAssertEqual(memory.reads, 1)
        runtime.changeAccountContext(userID: "reader-a")
        XCTAssertEqual(memory.reads, 1)
    }
    @MainActor func testGuestAndOwnerSnapshotsAreSeparateAndGuestHasNoRemoteEffects() async {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: nil)
        runtime.setFavorite(article("guest"), enabled: true)
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["guest"])
        XCTAssertTrue(memory.profile.isEmpty)
        runtime.changeAccountContext(userID: "reader-a")
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        let profile = expectation(description: "Both actual provider stages complete")
        memory.profileExpectation = profile
        runtime.setFavorite(article("a"), enabled: true)
        await fulfillment(of: [profile], timeout: 3)
        await runtime.model.waitForStorage()
        XCTAssertEqual(memory.profile.map { $0.2 }, ["reader-a"])
        XCTAssertEqual(memory.cloud.map { $0.2 }, ["reader-a"])
        runtime.changeAccountContext(userID: "reader-b")
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        runtime.changeAccountContext(userID: nil)
        XCTAssertEqual(runtime.model.snapshot.articles.map(\.id), ["guest"])
    }
    @MainActor func testPublicationSwitchCancelsOriginalCloudAndProfileEffects() async {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: "reader-a")
        let subscription = runtime.model.changes.sink { snapshot in
            if snapshot.articles.contains(where: { $0.id == "a" }) { runtime.changeAccountContext(userID: "reader-b") }
        }
        runtime.setFavorite(article("a"), enabled: true)
        await runtime.model.waitForStorage()
        withExtendedLifetime(subscription) {}
        XCTAssertTrue(memory.profile.isEmpty)
        XCTAssertTrue(memory.cloud.isEmpty)
        XCTAssertEqual(runtime.model.context, .confirmed(userID: "reader-b"))
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
    }
    @MainActor func testProfilePublicationReentryCannotApplyOldReceiptAfterSameUIDReturns() async {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: "reader-a")
        let profile = expectation(description: "Original profile stage reenters the same UID with a new epoch")
        memory.profileExpectation = profile
        memory.onProfile = {
            memory.onProfile = nil;memory.failDrain = true
            runtime.suspendForAccountChange();runtime.changeAccountContext(userID: "reader-a")
        }
        runtime.setFavorite(article(), enabled: true)
        await fulfillment(of: [profile], timeout: 3)
        await runtime.model.waitForStorage()
        XCTAssertEqual(memory.profile.count, 1)
        XCTAssertEqual(memory.cloud.count, 1)
        XCTAssertEqual(runtime.model.context, .confirmed(userID: "reader-a"))
        XCTAssertEqual(runtime.model.snapshot.pendingArticleIDs, ["article"], "An old receipt cannot retire the restored durable intent")
        XCTAssertFalse(runtime.model.snapshot.recoveryReady)
    }
    @MainActor func testOriginalNoticeRetryDoesNotReadOrWriteNewOwner() {
        let memory = Memory(), runtime = memory.runtime()
        runtime.prepareIfNeeded();runtime.changeAccountContext(userID: nil)
        memory.failWrites = true
        runtime.setFavorite(article(), enabled: true)
        let generation = runtime.model.snapshot.generation
        XCTAssertTrue(runtime.model.snapshot.canRetry)
        runtime.changeAccountContext(userID: "reader-b")
        let before = (memory.reads, memory.writes)
        memory.failWrites = false
        runtime.retryCurrentChanges(generation: generation)
        XCTAssertEqual(memory.reads, before.0)
        XCTAssertEqual(memory.writes, before.1)
        XCTAssertTrue(runtime.model.snapshot.articles.isEmpty)
        XCTAssertTrue(memory.profile.isEmpty)
    }
}
