import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class ArticleHTMLPreparationTests: XCTestCase {
    private typealias Worker = ArticleHTMLPreparationWorker<Int, Int>
    private actor Gate {
        let started: XCTestExpectation
        private var continuation: CheckedContinuation<Int, Never>?
        init(_ started: XCTestExpectation) { self.started = started }
        func wait(_ value: Int) async -> Int {
            await withCheckedContinuation { self.continuation = $0; self.started.fulfill() }
        }
        func finish(_ value: Int) { continuation?.resume(returning: value); continuation = nil }
    }
    private func drain(_ worker: Worker) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while worker.isWorking && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(worker.isWorking)
    }

    func testLatestPendingReplacesIntermediateRequestWhilePhysicalJobRemainsHeld() async {
        let worker = Worker(), started = expectation(description: "first physically started")
        let gate = Gate(started), committed = expectation(description: "latest committed")
        var values: [Int] = []
        worker.submit(1, work: { value, _ in await gate.wait(value) }, isCurrent: { true }) { value, _ in values.append(value) }
        await fulfillment(of: [started], timeout: 2)
        worker.submit(2, work: { _, _ in XCTFail("Replaced pending work must not start"); return 2 }, isCurrent: { true }) { _, _ in XCTFail() }
        worker.submit(3, work: { value, _ in XCTAssertFalse(Thread.isMainThread); return value }, isCurrent: { true }) { value, _ in
            values.append(value); committed.fulfill()
        }
        XCTAssertTrue(worker.isWorking); XCTAssertTrue(worker.hasPending)
        await gate.finish(1)
        await fulfillment(of: [committed], timeout: 2)
        await drain(worker); XCTAssertEqual(values, [3])
    }
    func testInvalidationRetainsPhysicalSlotAndDropsBothOldOutputAndPending() async {
        let worker = Worker(), started = expectation(description: "started"), gate = Gate(started)
        worker.submit(1, work: { value, _ in await gate.wait(value) }, isCurrent: { true }) { _, _ in XCTFail("Invalidated output") }
        await fulfillment(of: [started], timeout: 2)
        worker.submit(2, work: { _, _ in XCTFail("Invalidated pending"); return 2 }, isCurrent: { true }) { _, _ in XCTFail() }
        worker.invalidate()
        XCTAssertTrue(worker.isWorking); XCTAssertFalse(worker.hasPending)
        await gate.finish(1); await drain(worker)
    }
    func testDetachedWorkObservesCancellationWithoutWaitingForActor() async {
        let worker = Worker(), started = expectation(description: "started"), gate = Gate(started)
        let cancelled = expectation(description: "cancellation visible in worker")
        worker.submit(1, work: { value, isCancelled in
            _ = await gate.wait(value)
            XCTAssertTrue(isCancelled()); cancelled.fulfill(); return nil
        }, isCurrent: { true }) { _, _ in XCTFail() }
        await fulfillment(of: [started], timeout: 2)
        worker.invalidate(); await gate.finish(1)
        await fulfillment(of: [cancelled], timeout: 2); await drain(worker)
    }
    func testOriginalGenerationCannotReviveAfterAccountRoundtrip() async {
        let worker = Worker(), started = expectation(description: "started"), gate = Gate(started)
        var generation = UUID(); let original = generation
        let discarded = expectation(description: "stale discarded")
        worker.submit(1, work: { value, _ in await gate.wait(value) }, isCurrent: { generation == original },
            discard: { discarded.fulfill() }) { _, _ in XCTFail("A→B→A must not revive original lease") }
        await fulfillment(of: [started], timeout: 2)
        generation = UUID(); generation = UUID()
        await gate.finish(1); await fulfillment(of: [discarded], timeout: 2); await drain(worker)
    }
    func testRejectedCurrentResultAllowsSameInputRetry() async {
        let worker = Worker(), rejected = expectation(description: "discard"), accepted = expectation(description: "retry")
        worker.submit(4, work: { value, _ in value }, isCurrent: { false }, discard: { rejected.fulfill() }) { _, _ in XCTFail() }
        await fulfillment(of: [rejected], timeout: 2); await drain(worker)
        worker.submit(4, work: { value, _ in value }, isCurrent: { true }) { value, _ in XCTAssertEqual(value, 4); accepted.fulfill() }
        await fulfillment(of: [accepted], timeout: 2); await drain(worker)
    }
    func testReentrantOwnershipHookCannotCommitAnInvalidatedResult() async {
        let worker = Worker()
        worker.submit(1, work: { value, _ in value }, isCurrent: { worker.invalidate(); return true }) { _, _ in XCTFail() }
        await drain(worker)
    }
    func testCommitFinalGuardRejectsSynchronousReplacement() async {
        let worker = Worker(), accepted = expectation(description: "replacement")
        worker.submit(1, work: { value, _ in value }, isCurrent: { true }) { _, stillCurrent in
            worker.submit(2, work: { value, _ in value }, isCurrent: { true }) { value, _ in
                XCTAssertEqual(value, 2); accepted.fulfill()
            }
            XCTAssertFalse(stillCurrent())
        }
        await fulfillment(of: [accepted], timeout: 2); await drain(worker)
    }
    func testPurePreparationPreservesCSSCreditLazyImagesAndExplicitWidth() async throws {
        let request = ArticleHTMLPreparation.Input(html: "<style>p{color:red}</style><img src='https://cdn.website-files.com/a.jpg?q=1'><p>Foto: ÆØÅ</p><img src='https://cdn.website-files.com/b.jpg'>",
            targetImageWidth: 640, bodyFontSize: 23, documentID: "fixture-doc", contentKey: nil)
        let output = await Task.detached { ArticleHTMLPreparation.prepare(request, cache: nil) }.value
        let prepared = try XCTUnwrap(output)
        XCTAssertFalse(prepared.html.contains("color:red"))
        XCTAssertTrue(prepared.html.contains("apropos-image-credit")); XCTAssertTrue(prepared.html.contains("Foto: ÆØÅ"))
        XCTAssertTrue(prepared.html.contains("w=640")); XCTAssertTrue(prepared.html.contains("q=85"))
        XCTAssertTrue(prepared.html.contains("data-src=")); XCTAssertTrue(prepared.document.contains("23.0px"))
        XCTAssertTrue(prepared.document.contains("content=\"fixture-doc\"")); XCTAssertNil(prepared.baseURL)
        XCTAssertNil(FirebaseApp.allApps)
    }
    func testCancelledPreparationDoesNoCacheOrHTMLWork() async {
        let request = ArticleHTMLPreparation.Input(html: "<p>Unprocessed</p>", targetImageWidth: 640,
            bodyFontSize: 18, documentID: "cancelled", contentKey: nil)
        let result = await Task.detached { ArticleHTMLPreparation.prepare(request, cache: nil, isCancelled: { true }) }.value
        XCTAssertNil(result)
    }
    func testIdentityDistinguishesRevisionSessionAccessAndLiteralUnicode() {
        func identity(_ html: String, generation: UUID? = nil, revision: String = "r1", session: UUID? = nil) -> HTMLTextView.PreparationIdentity {
            .init(html: html, articleID: "article", revision: revision, fontSize: 18, imageWidth: 640,
                sessionID: session, accessGeneration: generation, resumeOwner: "reader", historyIdentity: nil)
        }
        XCTAssertNotEqual(identity("café"), identity("cafe\u{301}"))
        XCTAssertNotEqual(identity("same"), identity("same", revision: "r2"))
        XCTAssertNotEqual(identity("same"), identity("same", session: UUID()))
        XCTAssertNotEqual(identity("same", generation: UUID()), identity("same", generation: UUID()))
        XCTAssertEqual(identity("same"), identity("same"))
    }
    func testCapturedOfflineAccessUsesActualMembershipGenerationNotContentKey() throws {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        let model = FavoritesModel(storage: .init(read: { namespace, done in done(.success(records[namespace])) },
            write: { namespace, record, _, done in records[namespace] = record; done(.success(())) }))
        let article = Article(id: "a", name: "Artikel", slug: "a", content: "<p>Lokalt</p>", intro: "", topicID: "topic", contentRevision: "r1")
        model.changeContext(to: .confirmed(userID: "A")); _ = model.setFavorite(article, enabled: true)
        let bridge = FavoritesOfflineCoordinator(model: model, storage: .init(read: { _ in nil }, write: { _, _ in }),
            permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} }))
        let original = OfflineArticleImageCache.preparationAccess(bridge: bridge, articleID: "a", revision: "r1")
        XCTAssertNotNil(original.contentKey); XCTAssertTrue(original.isCurrent())
        model.changeContext(to: .confirmed(userID: "B")); bridge.synchronizeCurrentMembership()
        model.changeContext(to: .confirmed(userID: "A")); bridge.synchronizeCurrentMembership()
        let replacement = OfflineArticleImageCache.preparationAccess(bridge: bridge, articleID: "a", revision: "r1")
        XCTAssertEqual(original.contentKey, replacement.contentKey)
        XCTAssertNotEqual(original.generation, replacement.generation)
        XCTAssertFalse(original.isCurrent()); XCTAssertTrue(replacement.isCurrent())
        XCTAssertNil(OfflineArticleImageCache.preparationAccess(bridge: bridge, articleID: "a", revision: "old").contentKey)
        XCTAssertNil(FirebaseApp.allApps)
    }
    func testAsyncPreparationDoesNotAdoptLegacyKeyOnlyAuthority() throws {
        let cache = OfflineArticleImageCache(cacheDirectory: FileManager.default.temporaryDirectory,
            download: { _ in XCTFail(); throw URLError(.unsupportedURL) }, online: { false },
            contentKey: { _, _ in String(repeating: "a", count: 64) })
        XCTAssertNil(cache.capturePreparationAccess(articleID: "a", revision: "r1").contentKey)
        XCTAssertNil(FirebaseApp.allApps)
    }
}
