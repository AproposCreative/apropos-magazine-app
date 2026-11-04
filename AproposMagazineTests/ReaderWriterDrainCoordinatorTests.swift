import XCTest
@testable import Apropos

@MainActor
final class ReaderWriterDrainCoordinatorTests: XCTestCase {
    private typealias Model = ReaderWriterDrainCoordinator
    private enum SDKFailure: Error { case rejected }
    @MainActor private final class Pending<Value> {
        var result: Result<Value, Error>?
        var task: Task<Void, Never>?
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var uid: String? = "reader-A"
        var identityReads = 0
        var identityHook: (() -> Void)?
        var scheduleHook: (() -> Void)?
        var cancelDeadlineHook: (() -> Void)?
        var drainHook: (() -> Void)?
        var deadlines: [@MainActor () -> Void] = []
        var writes: [Model.Completion] = []
        var drains: [Model.Completion] = []
        var drainContexts: [Model.ContextTicket] = []
        var cancelledDeadlines = 0
        var maximumActiveWrites = 16
        lazy var model = Model(canonical: canonical, actualUID: { [unowned self] in
            self.identityReads += 1
            self.identityHook?()
            return self.uid
        }, schedule: { [unowned self] action in
            self.deadlines.append(action)
            self.scheduleHook?()
            return { [unowned self] in
                self.cancelledDeadlines += 1
                self.cancelDeadlineHook?()
            }
        }, drainStart: { [unowned self] context, permitted, completion in
            self.drainHook?()
            guard permitted() else { completion(SDKFailure.rejected); return }
            self.drainContexts.append(context)
            self.drains.append(completion)
        }, maximumActiveWrites: maximumActiveWrites)
        init() { select("reader-A") }
        var context: Model.ContextTicket { canonical.contextTicket() }
        func select(_ uid: String?, forceNewGeneration: Bool = false) {
            self.uid = uid
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: "reader@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: forceNewGeneration)
        }
        func start(_ permitted: @escaping Model.Guard, _ completion: @escaping Model.Completion) {
            guard permitted() else { completion(SDKFailure.rejected); return }
            writes.append(completion)
        }
    }
    private func settle() async { for _ in 0..<40 { await Task.yield() } }
    private func write(_ f: Fixture, stillCurrent: @escaping Model.Guard = { true },
                       start: Model.Start? = nil) -> Pending<Void> {
        let pending = Pending<Void>(), original = f.context
        pending.task = Task { @MainActor in
            do {
                try await f.model.performWrite(context: original, stillCurrent: stillCurrent,
                                               start: start ?? { f.start($0, $1) })
                pending.result = .success(())
            } catch { pending.result = .failure(error) }
        }
        return pending
    }
    private func drain(_ f: Fixture, _ ticket: Model.StopTicket) -> Pending<Model.Receipt> {
        let pending = Pending<Model.Receipt>()
        pending.task = Task { @MainActor in
            do { pending.result = .success(try await f.model.drain(ticket)) }
            catch { pending.result = .failure(error) }
        }
        return pending
    }
    private func failure<T>(_ pending: Pending<T>, _ expected: Model.Failure,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = pending.result else {
            XCTFail("Expected resolved failure \(expected)", file: file, line: line); return
        }
        XCTAssertEqual(error as? Model.Failure, expected, file: file, line: line)
    }

    func testConstructionIsInertAndNormalWriteWaitsForRealCallback() async throws {
        let f = Fixture()
        XCTAssertFalse(f.model.isStopped); XCTAssertEqual(f.identityReads, 0)
        XCTAssertTrue(f.deadlines.isEmpty); XCTAssertTrue(f.drains.isEmpty)
        let work = write(f); await settle()
        XCTAssertNil(work.result); XCTAssertEqual(f.model.activeWriteCount, 1)
        try XCTUnwrap(f.writes.first)(nil); await settle()
        _ = try XCTUnwrap(work.result).get()
        XCTAssertEqual(f.model.activeWriteCount, 0); XCTAssertFalse(f.model.isStopped)
        XCTAssertTrue(f.deadlines.isEmpty); XCTAssertTrue(f.drains.isEmpty)
    }

    func testSynchronousAndDuplicateCallbacksResolveOnlyOnceAndPropagateSDKError() async throws {
        let f = Fixture()
        let work = write(f, start: { guardLast, callback in
            XCTAssertTrue(guardLast()); callback(nil); callback(SDKFailure.rejected)
        })
        await settle(); _ = try XCTUnwrap(work.result).get()
        XCTAssertEqual(f.model.activeWriteCount, 0)
        let error = write(f, start: { guardLast, callback in
            XCTAssertTrue(guardLast()); callback(SDKFailure.rejected); callback(nil)
        })
        await settle()
        guard case .failure(let received) = error.result else { return XCTFail("SDK error must propagate") }
        XCTAssertTrue(received is SDKFailure); XCTAssertEqual(f.model.activeWriteCount, 0)
    }

    func testBoundedAdmissionsRecoverOnlyAfterPhysicalReturn() async throws {
        let f = Fixture(); f.maximumActiveWrites = 1
        let first = write(f); await settle()
        let extra = write(f); await settle(); failure(extra, .limitExceeded)
        XCTAssertEqual(f.writes.count, 1)
        f.writes[0](nil); await settle(); _ = try XCTUnwrap(first.result).get()
        let next = write(f); await settle()
        XCTAssertEqual(f.writes.count, 2)
        f.writes[1](nil); await settle(); _ = try XCTUnwrap(next.result).get()
    }

    func testStopClosesAdmissionSynchronouslyThenDrainsAfterEveryPhysicalWrite() async throws {
        let f = Fixture(), first = write(f), second = write(f)
        await settle()
        let stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        XCTAssertTrue(f.model.isStopped)
        XCTAssertEqual(f.model.stopWrites(context: f.context), stop)
        let refused = write(f), flush = drain(f, stop); await settle()
        failure(refused, .stopped); XCTAssertTrue(f.drains.isEmpty)
        f.writes[0](nil); await settle(); XCTAssertTrue(f.drains.isEmpty)
        f.writes[1](nil); await settle()
        _ = try XCTUnwrap(first.result).get(); _ = try XCTUnwrap(second.result).get()
        XCTAssertEqual(f.drainContexts, [stop.context]); XCTAssertNil(flush.result)
        try XCTUnwrap(f.drains.first)(nil); await settle()
        let receipt = try XCTUnwrap(flush.result).get()
        XCTAssertTrue(f.model.isCurrent(receipt)); XCTAssertTrue(f.model.isStopped)
        let stillRefused = write(f); await settle(); failure(stillRefused, .stopped)
    }

    func testWriteCancellationDoesNotReleaseExistingCallerTransportSlot() async throws {
        let f = Fixture(), work = write(f); await settle()
        work.task?.cancel(); await settle()
        XCTAssertNil(work.result, "The existing writer must await its physical callback")
        XCTAssertEqual(f.model.activeWriteCount, 1)
        let flush = drain(f, try XCTUnwrap(f.model.stopWrites(context: f.context)))
        await settle(); XCTAssertTrue(f.drains.isEmpty)
        f.writes[0](nil); await settle(); failure(work, .cancelled)
        XCTAssertEqual(f.drains.count, 1)
        f.drains[0](nil); await settle(); XCTAssertTrue(f.model.isCurrent(try XCTUnwrap(flush.result).get()))
    }

    func testAccountSwitchAndSameUIDNewGenerationKeepWriteAwaitUntilCallback() async throws {
        for switchViaB in [false, true] {
            let f = Fixture(), work = write(f); await settle()
            let oldContext = f.context
            let oldStop = try XCTUnwrap(f.model.stopWrites(context: oldContext))
            if switchViaB { f.select("reader-B") }
            f.select("reader-A", forceNewGeneration: true)
            await settle()
            XCTAssertNil(work.result); XCTAssertEqual(f.model.activeWriteCount, 1)
            XCTAssertNil(f.model.stopWrites(context: f.context))
            let stale = drain(f, oldStop); await settle(); failure(stale, .stale)
            f.writes[0](nil); await settle(); failure(work, .stale)
            let newStop = try XCTUnwrap(f.model.stopWrites(context: f.context))
            XCTAssertNotEqual(newStop, oldStop)
            let flush = drain(f, newStop); await settle()
            f.drains[0](nil); await settle()
            XCTAssertTrue(f.model.isCurrent(try XCTUnwrap(flush.result).get()))
        }
    }

    func testTimeoutDuringPhysicalDrainRetainsSlotAndLateSuccessCannotIssueReceipt() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, stop); await settle()
        f.deadlines[0](); await settle(); failure(flush, .timedOut)
        XCTAssertTrue(f.model.isDrainInFlight); XCTAssertTrue(f.model.isStopped)
        let busy = drain(f, stop); await settle(); failure(busy, .busy)
        f.drains[0](nil); await settle()
        XCTAssertFalse(f.model.isDrainInFlight); failure(flush, .timedOut)
        let retry = drain(f, stop); await settle()
        XCTAssertEqual(f.drains.count, 2)
        f.drains[1](nil); await settle()
        XCTAssertTrue(f.model.isCurrent(try XCTUnwrap(retry.result).get()))
    }

    func testTimeoutWhileWaitingForWriteNeverStartsUnrequestedLateDrain() async throws {
        let f = Fixture(), work = write(f); await settle()
        let stop = try XCTUnwrap(f.model.stopWrites(context: f.context)), flush = drain(f, stop)
        await settle(); f.deadlines[0](); await settle(); failure(flush, .timedOut)
        XCTAssertTrue(f.model.isDrainInFlight); XCTAssertEqual(f.model.activeWriteCount, 1)
        f.writes[0](nil); await settle(); _ = try XCTUnwrap(work.result).get()
        XCTAssertTrue(f.drains.isEmpty); XCTAssertFalse(f.model.isDrainInFlight)
        let retry = drain(f, stop); await settle(); XCTAssertEqual(f.drains.count, 1)
        f.drains[0](nil); await settle(); _ = try XCTUnwrap(retry.result).get()
    }

    func testDrainCancellationAndLateFailureKeepStopClosedUntilFreshExplicitRetry() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, stop); await settle(); flush.task?.cancel(); await settle()
        failure(flush, .cancelled); XCTAssertTrue(f.model.isDrainInFlight)
        f.drains[0](SDKFailure.rejected); await settle()
        XCTAssertFalse(f.model.isDrainInFlight); XCTAssertTrue(f.model.isStopped)
        let retry = drain(f, stop); await settle(); f.drains[1](nil); await settle()
        XCTAssertTrue(f.model.isCurrent(try XCTUnwrap(retry.result).get()))
    }

    func testCancelWaitingDrainBeforeMainActorDeliveryCannotStartSDKFromQueuedWriteCallback() async throws {
        let f = Fixture(), work = write(f); await settle()
        let stop = try XCTUnwrap(f.model.stopWrites(context: f.context)), flush = drain(f, stop)
        await settle()
        // Both deliveries are queued; the cancellation signal must already be true.
        f.writes[0](nil); flush.task?.cancel(); await settle()
        _ = try XCTUnwrap(work.result).get(); failure(flush, .cancelled)
        XCTAssertTrue(f.drains.isEmpty); XCTAssertFalse(f.model.isDrainInFlight)
    }

    func testOldPhysicalDrainCannotBeReplacedAcrossAccountRoundTrip() async throws {
        let f = Fixture(), original = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, original); await settle()
        f.select("reader-B"); f.select("reader-A"); await settle()
        failure(flush, .stale); XCTAssertNil(f.model.stopWrites(context: f.context))
        XCTAssertTrue(f.model.isDrainInFlight)
        f.drains[0](nil); await settle()
        XCTAssertFalse(f.model.isDrainInFlight)
        XCTAssertNotEqual(try XCTUnwrap(f.model.stopWrites(context: f.context)), original)
        let stale = drain(f, original); await settle(); failure(stale, .stale)
    }

    func testReentrantAdmissionHooksCannotEnqueueAfterStopOrIdentityChange() async throws {
        let f = Fixture()
        f.identityHook = { [unowned f] in f.identityHook = nil; _ = f.model.stopWrites(context: f.context) }
        let stopped = write(f); await settle(); failure(stopped, .stopped)
        XCTAssertTrue(f.writes.isEmpty); XCTAssertEqual(f.model.activeWriteCount, 0)
        let other = Fixture()
        let stale = write(other, stillCurrent: { other.uid = "reader-B"; return true })
        await settle(); failure(stale, .stale)
        XCTAssertTrue(other.writes.isEmpty); XCTAssertEqual(other.model.activeWriteCount, 0)
    }

    func testFinalAdapterGuardAndCompletionRecheckArbitraryIntentGetter() async throws {
        let f = Fixture()
        let stopped = write(f, start: { permitted, completion in
            _ = f.model.stopWrites(context: f.context)
            XCTAssertFalse(permitted()); completion(SDKFailure.rejected)
        })
        await settle()
        // A cancelled enqueue is an SDK failure; it still completed physically.
        guard case .failure = stopped.result else { return XCTFail("Rejected start cannot succeed") }
        XCTAssertEqual(f.model.activeWriteCount, 0)
        let other = Fixture(); var invalidateOnCompletion = false
        let stale = write(other, stillCurrent: {
            if invalidateOnCompletion { other.uid = "reader-B" }
            return true
        })
        await settle(); invalidateOnCompletion = true
        other.writes[0](nil); await settle(); failure(stale, .stale)
    }

    func testSynchronousDeadlineAndDrainFactoryReentryNeverStartSDK() async throws {
        let f = Fixture()
        f.scheduleHook = { [unowned f] in f.deadlines.last?() }
        let timedOut = drain(f, try XCTUnwrap(f.model.stopWrites(context: f.context)))
        await settle(); failure(timedOut, .timedOut)
        XCTAssertTrue(f.drains.isEmpty); XCTAssertFalse(f.model.isDrainInFlight)
        let other = Fixture()
        other.drainHook = { [unowned other] in other.select("reader-B") }
        let stale = drain(other, try XCTUnwrap(other.model.stopWrites(context: other.context)))
        await settle(); failure(stale, .stale)
        XCTAssertTrue(other.drains.isEmpty); XCTAssertFalse(other.model.isDrainInFlight)
    }

    func testDeadlineCancellationHookCannotPublishReceiptForReenteredAccount() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        f.cancelDeadlineHook = { [unowned f] in f.select("reader-B") }
        let flush = drain(f, stop); await settle()
        f.drains[0](nil); await settle(); failure(flush, .stale)
        XCTAssertFalse(f.model.isDrainInFlight); XCTAssertTrue(f.model.isStopped)
    }

    func testReceiptIsInstanceAndGenerationBoundAndObservedMismatchCannotReviveIt() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, stop); await settle(); f.drains[0](nil); await settle()
        let receipt = try XCTUnwrap(flush.result).get()
        let restarted = Model(canonical: f.canonical, actualUID: { f.uid }, drainStart: { _, _, _ in
            XCTFail("Construction and receipt checks must not drain")
        })
        XCTAssertFalse(restarted.isCurrent(receipt)); XCTAssertFalse(restarted.isStopped)
        XCTAssertNil(f.model.stopWrites(context: Fixture().context))
        f.uid = "reader-B"; XCTAssertFalse(f.model.isCurrent(receipt))
        f.uid = "reader-A"; XCTAssertFalse(f.model.isCurrent(receipt), "An observed identity mismatch permanently revokes this proof")
        let retry = drain(f, stop); await settle(); f.drains[1](nil); await settle()
        let fresh = try XCTUnwrap(retry.result).get(); XCTAssertTrue(f.model.isCurrent(fresh))
        f.select("reader-A", forceNewGeneration: true)
        XCTAssertFalse(f.model.isCurrent(fresh))
    }

    func testFreshDrainSupersedesReceiptAndFailureDoesNotReopenBarrier() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let first = drain(f, stop); await settle(); f.drains[0](nil); await settle()
        let oldReceipt = try XCTUnwrap(first.result).get()
        let next = drain(f, stop); await settle()
        XCTAssertFalse(f.model.isCurrent(oldReceipt))
        f.drains[1](SDKFailure.rejected); await settle(); failure(next, .failed)
        XCTAssertTrue(f.model.isStopped); XCTAssertFalse(f.model.isCurrent(oldReceipt))
        XCTAssertFalse(f.model.isDrainInFlight)
    }

    func testExplicitAbortAllowsNormalWritesAndInvalidatesOriginalStopAndReceipt() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, stop); await settle(); f.drains[0](nil); await settle()
        let receipt = try XCTUnwrap(flush.result).get()
        XCTAssertTrue(f.model.isCurrent(receipt))
        XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertFalse(f.model.isStopped); XCTAssertFalse(f.model.isCurrent(receipt))
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        let stale = drain(f, stop); await settle(); failure(stale, .stale)
        let work = write(f); await settle(); XCTAssertEqual(f.writes.count, 1)
        f.writes[0](nil); await settle(); _ = try XCTUnwrap(work.result).get()
        let later = try XCTUnwrap(f.model.stopWrites(context: f.context))
        XCTAssertNotEqual(later, stop)
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(f.model.isStopped)
    }

    func testExplicitAbortNeedsNoDrainButRequiresUntouchedCallerPhase() throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { false }))
        XCTAssertTrue(f.model.isStopped); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertFalse(f.model.isStopped); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertTrue(f.deadlines.isEmpty)
    }

    func testAbortRefusesHeldWriteEvenWhenItsTaskWasCancelled() async throws {
        let f = Fixture(), work = write(f); await settle()
        let stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        work.task?.cancel(); await settle()
        var phaseReads = 0
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { phaseReads += 1; return true }))
        XCTAssertEqual(phaseReads, 0); XCTAssertNil(work.result)
        f.writes[0](nil); await settle(); failure(work, .cancelled)
        XCTAssertTrue(f.model.isStopped, "A late physical callback must not reopen writers")
        XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
    }

    func testTimedOutOrCancelledDrainCanOnlyBeAbortedAfterPhysicalReturn() async throws {
        for cancel in [false, true] {
            let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
            let flush = drain(f, stop); await settle()
            if cancel { flush.task?.cancel() } else { f.deadlines[0]() }
            await settle(); failure(flush, cancel ? .cancelled : .timedOut)
            XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
            XCTAssertTrue(f.model.isStopped); XCTAssertTrue(f.model.isDrainInFlight)
            f.drains[0](nil); await settle()
            XCTAssertTrue(f.model.isStopped, "Late success is not an abort request")
            XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
            XCTAssertFalse(f.model.isStopped)
            // A duplicate callback from the aborted generation cannot affect
            // a newly captured stop or reopen it.
            let next = try XCTUnwrap(f.model.stopWrites(context: f.context))
            f.drains[0](nil); await settle()
            XCTAssertTrue(f.model.isStopped)
            XCTAssertEqual(f.model.stopWrites(context: f.context), next)
        }
    }

    func testAbortCannotAdoptForeignInstanceOrAccountRoundTrip() throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let foreign = Fixture()
        XCTAssertFalse(foreign.model.abortStop(stop, stillBeforeTransition: { true }))
        f.select("reader-B")
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        f.select("reader-A")
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(f.model.isStopped)
        let current = try XCTUnwrap(f.model.stopWrites(context: f.context))
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(f.model.abortStop(current, stillBeforeTransition: { true }))
    }

    func testAbortRechecksPhaseAndOriginalStopAfterInjectedHooks() throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        var beforeTransition = true
        f.identityHook = { [unowned f] in f.identityHook = nil; beforeTransition = false }
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { beforeTransition }))
        XCTAssertTrue(f.model.isStopped)
        f.identityHook = { [unowned f] in
            f.identityHook = nil
            XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
            _ = f.model.stopWrites(context: f.context)
        }
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(f.model.isStopped, "The outer abort must not clear the nested newer stop")
        XCTAssertNotEqual(f.model.stopWrites(context: f.context), stop)
        let other = Fixture(), otherStop = try XCTUnwrap(other.model.stopWrites(context: other.context))
        XCTAssertFalse(other.model.abortStop(otherStop, stillBeforeTransition: {
            other.select("reader-B"); return true
        }))
        XCTAssertTrue(other.model.isStopped)
    }

    func testFailedAbortObservedIdentityMismatchPermanentlyRevokesOnlyOriginalReceipt() async throws {
        let f = Fixture(), stop = try XCTUnwrap(f.model.stopWrites(context: f.context))
        let flush = drain(f, stop); await settle(); f.drains[0](nil); await settle()
        let receipt = try XCTUnwrap(flush.result).get()
        f.uid = "reader-B"
        XCTAssertFalse(f.model.abortStop(stop, stillBeforeTransition: { true }))
        XCTAssertTrue(f.model.isStopped)
        f.uid = "reader-A"
        XCTAssertFalse(f.model.isCurrent(receipt))
        XCTAssertTrue(f.model.abortStop(stop, stillBeforeTransition: { true }))
    }
}
