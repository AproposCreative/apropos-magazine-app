import XCTest
@testable import Apropos

/// The same preparation/session boundary used by PodcastPlayerManager, with
/// local effects. These tests do not instantiate AVPlayer or start downloads.
@MainActor
final class PodcastPlaybackRecoveryTests: XCTestCase {
    @MainActor private final class Fixture {
        let admission = ReaderLegacyWriteAdmission(isAllowed: true)
        var records: [PodcastProgressNamespace: Data] = [:]
        var effects: [String] = []
        var workCalls = 0
        var onEffect: (() -> Void)?
        var cancelHook: (() -> Void)?
        lazy var store = PodcastPlaybackProgressStore(storage: .init(
            read: { [unowned self] in records[$0] }, write: { [unowned self] in records[$0] = $1 }),
            legacyAdmission: admission)
        lazy var player = PodcastPlaybackSessionCoordinator(store: store, effects: .init(
            cancelCallbacks: { [unowned self] in effects.append("cancel"); onEffect?() },
            stopPlayback: { [unowned self] in effects.append("stop"); onEffect?() },
            clearPresentation: { [unowned self] in effects.append("presentation"); onEffect?() },
            clearNowPlaying: { [unowned self] in effects.append("now-playing"); onEffect?() },
            deactivateAudio: { [unowned self] in effects.append("audio"); onEffect?() }))
        init() {
            _ = player
            store.onContextInvalidated = { [weak self] in self?.player.contextInvalidated() }
            store.changeContext(to: .guest)
        }
        func asset() -> PodcastAudioAsset {
            PodcastAudioAsset(episodeID: "episode", canonicalArticleID: "article", kind: .human,
                sourceRevision: "cms-sha256-v1:" + String(repeating: "a", count: 64),
                remoteURL: URL(string: "https://audio.example.invalid/a.m4a")!)!
        }
        func prepare() throws -> PodcastPlaybackSessionCoordinator.PreparationTicket {
            try XCTUnwrap(player.beginPreparation(asset: asset(), accessIsCurrent: { true }))
        }
    }
    @MainActor private final class Gate {
        let entered: XCTestExpectation
        var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        func release() { let old = continuation; continuation = nil; old?.resume() }
    }

    func testPureClosedGateRejectsOwnerlessPreparationBeforeAnyHook() {
        let f = Fixture(); f.admission.setAllowed(false)
        XCTAssertNil(f.player.beginPreparation(asset: f.asset(), routeIsCurrent: {
            XCTFail("Closed route hook"); return true
        }, accessIsCurrent: { XCTFail("Closed access hook"); return true }))
        XCTAssertNil(f.player.beginSession(episodeID: "episode", articleID: "article"))
        XCTAssertTrue(f.effects.isEmpty); XCTAssertTrue(f.records.isEmpty)
    }

    func testPreparationRechecksPureGateAfterRouteAndAccessHooksBeforeAdoption() {
        for closesRoute in [true, false] {
            let f = Fixture()
            var accessCalls = 0
            let request = f.player.beginPreparation(asset: f.asset(), routeIsCurrent: {
                if closesRoute { f.admission.setAllowed(false) }; return true
            }, accessIsCurrent: { accessCalls += 1; if !closesRoute { f.admission.setAllowed(false) }; return true })
            XCTAssertEqual(accessCalls, closesRoute ? 0 : 1)
            XCTAssertNil(request); XCTAssertTrue(f.effects.isEmpty); XCTAssertTrue(f.records.isEmpty)
        }
    }

    func testOwnerlessPreparationAndConsumedResultRejectGateBeforeRuntimeObserver() throws {
        for consumed in [false, true] {
            let f = Fixture(), request = try f.prepare()
            if consumed { XCTAssertTrue(f.player.consumePreparation(request)) }
            f.admission.setAllowed(false)
            XCTAssertFalse(f.player.isCurrent(request))
            XCTAssertFalse(f.player.isCurrentPreparationResult(request))
            XCTAssertNil(f.player.beginSession(episodeID: "episode", articleID: "article"))
        }
    }

    func testConsumedResultRechecksGateAfterOriginalAccessHook() throws {
        let f = Fixture()
        var closeInHook = false
        let request = try XCTUnwrap(f.player.beginPreparation(asset: f.asset(), accessIsCurrent: {
            if closeInHook { f.admission.setAllowed(false) }; return true
        }))
        XCTAssertTrue(f.player.consumePreparation(request))
        closeInHook = true
        XCTAssertFalse(f.player.isCurrentPreparationResult(request))
    }

    func testOwnerlessContextStopCancelsPreparationAndClearsOnlyItsPresentationOnce() throws {
        let f = Fixture(), request = try f.prepare()
        f.onEffect = {
            XCTAssertNil(f.player.beginPreparation(asset: f.asset(), accessIsCurrent: { true }))
            XCTAssertNil(f.player.beginSession(episodeID: "nested", articleID: nil))
            f.player.close() // Teardown cannot recurse or repeat effects.
        }
        f.admission.setAllowed(false); f.store.revokeForRecovery()
        XCTAssertEqual(f.effects, ["cancel", "presentation"])
        XCTAssertFalse(f.player.isCurrent(request)); XCTAssertTrue(f.records.isEmpty)
        f.player.close(); XCTAssertEqual(f.effects, ["cancel", "presentation"])
    }

    func testPlayingContextStopStillPerformsCompleteTeardownWithClosedGate() throws {
        let f = Fixture(), owner = try XCTUnwrap(f.player.beginSession(episodeID: "episode", articleID: "article")).ticket
        XCTAssertTrue(f.player.save(owner, seconds: 42, duration: 600))
        let old = f.records
        f.onEffect = {
            XCTAssertFalse(f.player.save(owner, seconds: 90, duration: 600))
            XCTAssertFalse(f.player.complete(owner))
            XCTAssertFalse(f.player.perform(ifCurrent: owner) { XCTFail("Old system effect") })
        }
        f.admission.setAllowed(false); f.store.revokeForRecovery()
        XCTAssertEqual(f.effects, ["cancel", "stop", "presentation", "now-playing", "audio"])
        XCTAssertEqual(f.records, old)
    }

    func testClosedRequestDoesNotBeginInjectedPreparationWork() async throws {
        let f = Fixture(), request = try f.prepare()
        f.admission.setAllowed(false)
        let result = await f.player.prepare(request) { f.workCalls += 1; return true }
        XCTAssertNil(result); XCTAssertEqual(f.workCalls, 0)
    }

    func testCancellationInsideAdmissionHookCannotStartPreparationWork() async throws {
        let f = Fixture()
        let request = try XCTUnwrap(f.player.beginPreparation(asset: f.asset(), accessIsCurrent: { f.cancelHook?(); return true }))
        let task = Task { await f.player.prepare(request) { f.workCalls += 1; return true } }
        f.cancelHook = { task.cancel() }
        let result = await task.value
        f.cancelHook = nil
        XCTAssertNil(result); XCTAssertEqual(f.workCalls, 0)
    }

    func testLatePreparationReplyAfterRecoveryDenialCannotBecomeFailureOrSuccess() async throws {
        for value in [false, true] {
            let f = Fixture(), request = try f.prepare(), gate = Gate(expectation(description: "Original work held"))
            let task = Task { await f.player.prepare(request) { f.workCalls += 1; await gate.wait(); return value } }
            await fulfillment(of: [gate.entered], timeout: 2)
            f.admission.setAllowed(false); f.store.revokeForRecovery()
            gate.release()
            let result = await task.value
            XCTAssertNil(result); XCTAssertEqual(f.workCalls, 1)
            XCTAssertFalse(f.player.isCurrentPreparationResult(request))
        }
    }

    func testCancelledPhysicalPreparationCannotPublishItsLateReply() async throws {
        let f = Fixture(), request = try f.prepare(), gate = Gate(expectation(description: "Cancellation while physically held"))
        let task = Task { await f.player.prepare(request) { f.workCalls += 1; await gate.wait(); return true } }
        await fulfillment(of: [gate.entered], timeout: 2)
        task.cancel(); gate.release()
        let result = await task.value
        XCTAssertNil(result); XCTAssertEqual(f.workCalls, 1)
    }

    func testOldPreparationReplyDoesNotDisturbNewAccountPreparation() async throws {
        let f = Fixture(), old = try f.prepare(), gate = Gate(expectation(description: "A response held"))
        let task = Task { await f.player.prepare(old) { await gate.wait(); return true } }
        await fulfillment(of: [gate.entered], timeout: 2)
        f.store.changeContext(to: .confirmed(userID: "B")); f.store.changeContext(to: .guest)
        let fresh = try f.prepare()
        gate.release(); let result = await task.value
        XCTAssertNil(result); XCTAssertFalse(f.player.discardPreparation(old))
        XCTAssertTrue(f.player.isCurrent(fresh))
    }

    func testCurrentPreparationPreservesPositiveAndNegativeResultsWithoutStartingPlayer() async throws {
        for value in [false, true] {
            let f = Fixture(), request = try f.prepare()
            let result = await f.player.prepare(request) { f.workCalls += 1; return value }
            XCTAssertEqual(result, value); XCTAssertEqual(f.workCalls, 1)
            XCTAssertTrue(f.effects.isEmpty); XCTAssertTrue(f.records.isEmpty)
        }
    }
    func testPreparationPublicationRollsBackSetterThatFinishesAfterRecoveryCloses() throws {
        for isResult in [false, true] {
            let f = Fixture(), request = try f.prepare()
            if isResult { XCTAssertTrue(f.player.consumePreparation(request)) }
            var visible = false, clears = 0
            let accepted = f.player.performPreparationPublication(request, isResult: isResult, publish: {
                // Adversarial injected publication finishes after its observer.
                // The manager's current modal/error didSet setters assign first;
                // this is a defensive boundary test, not a reproduction of them.
                f.admission.setAllowed(false); f.store.revokeForRecovery()
                visible = true
            }, clearClosedPresentation: { clears += 1; visible = false })
            XCTAssertFalse(accepted); XCTAssertFalse(visible); XCTAssertEqual(clears, 1)
        }
    }

    func testOldPublicationCannotClearReplacementWithValidPlaybackAccess() throws {
        let f = Fixture(), old = try f.prepare()
        var fresh: PodcastPlaybackSessionCoordinator.PreparationTicket?
        var clears = 0
        let accepted = f.player.performPreparationPublication(old, publish: {
            f.store.changeContext(to: .confirmed(userID: "B"))
            fresh = f.player.beginPreparation(asset: f.asset(), accessIsCurrent: { true })
        }, clearClosedPresentation: { clears += 1 })
        XCTAssertFalse(accepted); XCTAssertEqual(clears, 0)
        XCTAssertTrue(f.player.isCurrent(try XCTUnwrap(fresh)))
    }

    func testClosedPublicationDoesNotExecuteSetterOrUnrelatedCleanup() throws {
        let f = Fixture(), request = try f.prepare()
        f.admission.setAllowed(false)
        XCTAssertFalse(f.player.performPreparationPublication(request,
            publish: { XCTFail("Old setter started") }, clearClosedPresentation: { XCTFail("Unowned cleanup") }))
    }

    func testCurrentPreparationPublicationKeepsExistingPresentation() throws {
        let f = Fixture(), request = try f.prepare()
        var visible = false
        XCTAssertTrue(f.player.performPreparationPublication(request, publish: { visible = true },
            clearClosedPresentation: { XCTFail("Current publication cleared") }))
        XCTAssertTrue(visible)
    }

}
