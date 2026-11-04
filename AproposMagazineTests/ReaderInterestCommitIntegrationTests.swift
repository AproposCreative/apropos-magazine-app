import XCTest
@testable import Apropos

/// The same actions → load preparation → preference model → acknowledged write
/// used by the production intro. Only the read/write transports are local.
@MainActor
final class ReaderInterestCommitIntegrationTests: XCTestCase {
    @MainActor private final class Deadlines {
        struct Entry { let fire: @MainActor () -> Void; var cancelled = false }
        var entries: [Entry] = []
        var onSchedule: (() -> Void)?
        func schedule(_ fire: @escaping @MainActor () -> Void) -> () -> Void {
            let index = entries.count
            entries.append(Entry(fire: fire))
            onSchedule?()
            return { [weak self] in self?.entries[index].cancelled = true }
        }
        func fire(_ index: Int) { if !entries[index].cancelled { entries[index].fire() } }
    }

    @MainActor private final class Transport {
        var reads: [ReaderPreferencesModel.ContextTicket] = []
        var writes: [ReaderPreferencesModel.SaveRequest] = []
        var pendingReads: [Int: CheckedContinuation<ReaderPreferencesModel.ReadResult, Error>] = [:]
        var pendingWrites: [Int: CheckedContinuation<Void, Error>] = [:]
        func load(_ context: ReaderPreferencesModel.ContextTicket, current: ReaderPreferencesModel.Guard) async throws -> ReaderPreferencesModel.ReadResult {
            guard current() else { throw CancellationError() }
            let index = reads.count
            reads.append(context)
            return try await withCheckedThrowingContinuation { pendingReads[index] = $0 }
        }
        func save(_ request: ReaderPreferencesModel.SaveRequest, current: ReaderPreferencesModel.Guard) async throws {
            guard current() else { throw CancellationError() }
            let index = writes.count
            writes.append(request)
            try await withCheckedThrowingContinuation { pendingWrites[index] = $0 }
        }
        func read(_ index: Int, preferences: ReaderPreferences? = nil, fromCache: Bool = false) {
            pendingReads.removeValue(forKey: index)?.resume(returning: .init(preferences: preferences, isFromCache: fromCache))
        }
        func failRead(_ index: Int) {
            pendingReads.removeValue(forKey: index)?.resume(throwing: NSError(domain: "LocalReadFailure", code: 7))
        }
        func acknowledge(_ index: Int) { pendingWrites.removeValue(forKey: index)?.resume() }
        func failWrite(_ index: Int) { pendingWrites.removeValue(forKey: index)?.resume(throwing: URLError(.networkConnectionLost)) }
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let transport = Transport()
        let loadDeadlines = Deadlines()
        let writeDeadlines = Deadlines()
        var actualUID: String?
        lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [weak self] in
            .init(actualUID: self?.actualUID, canonicalUID: self?.canonical.snapshot.userID)
        }, load: { [transport] context, current in
            try await transport.load(context, current: current)
        }, save: { [transport] request, current in
            try await transport.save(request, current: current)
        }, schedule: { [writeDeadlines] in writeDeadlines.schedule($0) })
        lazy var actions = ReaderAccountActions(canonical: canonical, preferences: preferences,
            verify: { _ in XCTFail("Interest save must not send verification mail") },
            refresh: { _ in XCTFail("Interest save must not refresh authentication") })

        init(start: Bool = true) {
            select("reader-A")
            if start { preferences.start() }
        }
        func select(_ uid: String?) {
            actualUID = uid
            _ = preferences.changeContext(to: .confirmed(userID: uid))
            _ = canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: false) })
        }
        func commit(_ ids: [String] = ["music"], context: CanonicalSessionState.ContextTicket? = nil) async -> Bool {
            let original = context ?? canonical.contextTicket()
            return await actions.commitInterests(ids: ids, userID: original.userID ?? "reader-A", context: original,
                scheduleLoadDeadline: { [loadDeadlines] in loadDeadlines.schedule($0) })
        }
        func load() -> Task<Void, Never> {
            let context = preferences.contextTicket(), preferences = preferences
            return Task { await preferences.load(context) }
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local preference pipeline state was not reached", file: file, line: line)
    }

    func testUnloadedNewAccountAwaitsActualReadThenAcknowledgedWriteOfOriginalSelection() async {
        let f = Fixture()
        var selected = ["music", "culture"], result: Bool?
        let original = selected
        let commit = Task { let accepted = await f.commit(original); result = accepted; return accepted }
        await eventually { f.transport.reads.count == 1 }
        selected = ["film"]
        XCTAssertNil(result)
        XCTAssertTrue(f.transport.writes.isEmpty)
        f.transport.read(0) // An authoritative missing document is a valid new account.
        await eventually { f.transport.writes.count == 1 }
        XCTAssertNil(result, "A submitted write is not an acknowledgement")
        XCTAssertEqual(f.transport.writes[0].userID, "reader-A")
        XCTAssertEqual(f.transport.writes[0].preferences.interestTopicIDs, ["culture", "music"])
        XCTAssertTrue(f.transport.writes[0].preferences.onboardingCompleted)
        f.transport.acknowledge(0)
        let accepted = await commit.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, ["culture", "music"])
        XCTAssertEqual(selected, ["film"])
        XCTAssertTrue(f.loadDeadlines.entries[0].cancelled)
    }

    func testAlreadyRunningAuthLoadIsJoinedWithoutStartingOrSupersedingAnotherRead() async {
        let f = Fixture(), authLoad = f.load()
        await eventually { f.transport.reads.count == 1 }
        let originalLoadVersion = f.preferences.snapshot.revision
        let commit = Task { await f.commit() }
        await eventually { f.loadDeadlines.entries.count == 1 }
        XCTAssertEqual(f.transport.reads.count, 1)
        XCTAssertEqual(f.preferences.snapshot.revision, originalLoadVersion)
        XCTAssertTrue(f.transport.writes.isEmpty)
        f.transport.read(0, preferences: ReaderPreferences(interestTopicIDs: ["old"]))
        await authLoad.value
        await eventually { f.transport.writes.count == 1 }
        f.transport.acknowledge(0)
        let accepted = await commit.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.transport.reads.count, 1)
    }

    func testInitialLoadFailureIsActuallyRetriedBeforeSaving() async {
        let f = Fixture(), authLoad = f.load()
        await eventually { f.transport.reads.count == 1 }
        f.transport.failRead(0)
        await authLoad.value
        XCTAssertFalse(f.preferences.snapshot.loaded)
        XCTAssertNotNil(f.preferences.snapshot.errorMessage)
        let commit = Task { await f.commit(["film"]) }
        await eventually { f.transport.reads.count == 2 }
        XCTAssertTrue(f.transport.writes.isEmpty)
        f.transport.read(1)
        await eventually { f.transport.writes.count == 1 }
        f.transport.acknowledge(0)
        let accepted = await commit.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, ["film"])
    }

    func testFailedCommitReadReturnsFalseAndNextExplicitAttemptRetriesRealLoad() async {
        let f = Fixture()
        let first = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.transport.failRead(0)
        let firstAccepted = await first.value
        XCTAssertFalse(firstAccepted)
        XCTAssertTrue(f.transport.writes.isEmpty)
        let second = Task { await f.commit() }
        await eventually { f.transport.reads.count == 2 }
        f.transport.read(1)
        await eventually { f.transport.writes.count == 1 }
        f.transport.acknowledge(0)
        let secondAccepted = await second.value
        XCTAssertTrue(secondAccepted)
    }

    func testMissingCacheDocumentIsNotInventedAsLoadedOrSaved() async {
        let f = Fixture()
        let first = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.transport.read(0, fromCache: true)
        let firstAccepted = await first.value
        XCTAssertFalse(firstAccepted)
        XCTAssertFalse(f.preferences.snapshot.loaded)
        XCTAssertTrue(f.transport.writes.isEmpty)
        let retry = Task { await f.commit() }
        await eventually { f.transport.reads.count == 2 }
        f.transport.read(1, fromCache: false)
        await eventually { f.transport.writes.count == 1 }
        f.transport.acknowledge(0)
        let retried = await retry.value
        XCTAssertTrue(retried)
    }

    func testLoadTimeoutReturnsUnconfirmedAndRetryJoinsStillOccupiedRead() async {
        let f = Fixture()
        let first = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.loadDeadlines.fire(0)
        let firstAccepted = await first.value
        XCTAssertFalse(firstAccepted)
        XCTAssertEqual(f.preferences.activity.activeLoadCount, 1)
        XCTAssertTrue(f.transport.writes.isEmpty)
        let retry = Task { await f.commit(["culture"]) }
        await eventually { f.loadDeadlines.entries.count == 2 }
        XCTAssertEqual(f.transport.reads.count, 1, "A UI deadline cannot release or replace actual I/O")
        f.transport.read(0)
        await eventually { f.transport.writes.count == 1 }
        XCTAssertEqual(f.transport.writes[0].preferences.interestTopicIDs, ["culture"])
        f.transport.acknowledge(0)
        let retried = await retry.value
        XCTAssertTrue(retried)
    }

    func testWriteFailureUsesExistingSaveErrorAndRetryDoesNotReloadAcceptedPreferences() async {
        let f = Fixture()
        let first = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.transport.read(0)
        await eventually { f.transport.writes.count == 1 }
        f.transport.failWrite(0)
        let firstAccepted = await first.value
        XCTAssertFalse(firstAccepted)
        XCTAssertTrue(f.preferences.snapshot.loaded)
        XCTAssertNotNil(f.preferences.errorMessage)
        let retry = Task { await f.commit(["culture"]) }
        await eventually { f.transport.writes.count == 2 }
        XCTAssertEqual(f.transport.reads.count, 1)
        f.transport.acknowledge(1)
        let retried = await retry.value
        XCTAssertTrue(retried)
        XCTAssertNil(f.preferences.errorMessage)
    }

    func testExistingWriteDeadlineRemainsUnconfirmedUntilTransportDrains() async {
        let f = Fixture()
        let commit = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.transport.read(0)
        await eventually { f.transport.writes.count == 1 }
        f.writeDeadlines.fire(0)
        let accepted = await commit.value
        XCTAssertFalse(accepted)
        XCTAssertTrue(f.preferences.activity.activeSave)
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, [])
        f.transport.acknowledge(0)
        await eventually { !f.preferences.activity.activeSave }
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, [], "Late acknowledgement cannot change the timed-out receipt")
    }

    func testAccountBAndReturningARejectOriginalSelectionAfterSuspendedLoad() async {
        for returnToA in [false, true] {
            let f = Fixture()
            let original = f.canonical.contextTicket()
            let commit = Task { await f.commit(["old-A"], context: original) }
            await eventually { f.transport.reads.count == 1 }
            f.select(nil)
            f.select(returnToA ? "reader-A" : "reader-B")
            let accepted = await commit.value
            XCTAssertFalse(accepted)
            f.transport.read(0)
            await eventually { f.preferences.activity.activeLoadCount == 0 }
            XCTAssertTrue(f.transport.writes.isEmpty)
            XCTAssertFalse(f.preferences.snapshot.loaded)
        }
    }

    func testCanonicalOnlyGenerationChangeAlsoUnblocksWaitWithoutBorrowingPreferenceOwner() async {
        let f = Fixture()
        let commit = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        let original = f.canonical.snapshot.session
        _ = f.canonical.adopt(nil)
        _ = f.canonical.adopt(original)
        let accepted = await commit.value
        XCTAssertFalse(accepted)
        f.transport.read(0)
        await eventually { f.preferences.activity.activeLoadCount == 0 }
        XCTAssertTrue(f.transport.writes.isEmpty)
    }

    func testCancelledCommitDoesNotSaveWhenItsUncancelledModelReadReturns() async {
        let f = Fixture()
        let commit = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        commit.cancel()
        let accepted = await commit.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(f.preferences.activity.activeLoadCount, 1)
        f.transport.read(0)
        await eventually { f.preferences.activity.activeLoadCount == 0 }
        XCTAssertTrue(f.transport.writes.isEmpty)
    }

    func testStaleRenderedContextIsRejectedBeforeAnyReadOrWrite() async {
        let f = Fixture(), foreign = Fixture()
        let original = f.canonical.contextTicket()
        f.select(nil); f.select("reader-A")
        let stale = await f.commit(context: original)
        let wrongModel = await f.commit(context: foreign.canonical.contextTicket())
        XCTAssertFalse(stale)
        XCTAssertFalse(wrongModel)
        XCTAssertTrue(f.transport.reads.isEmpty)
        XCTAssertTrue(f.transport.writes.isEmpty)
        XCTAssertTrue(f.loadDeadlines.entries.isEmpty)
    }

    func testActualIdentityMismatchCannotBeRecoveredByBorrowingCanonicalUID() async {
        let f = Fixture()
        f.actualUID = "reader-B"
        let accepted = await f.commit()
        XCTAssertFalse(accepted)
        XCTAssertTrue(f.transport.reads.isEmpty)
        XCTAssertTrue(f.transport.writes.isEmpty)
    }

    func testModelNotStartedDoesNotHangOrSilentlyStartServices() async {
        let f = Fixture(start: false)
        let accepted = await f.commit()
        XCTAssertFalse(accepted)
        XCTAssertTrue(f.transport.reads.isEmpty)
        XCTAssertTrue(f.transport.writes.isEmpty)
        XCTAssertTrue(f.loadDeadlines.entries.isEmpty)
        XCTAssertTrue(f.writeDeadlines.entries.isEmpty)
    }

    func testSynchronousDeadlineAndAccountChangeBeforeReadCannotAdmitWork() async {
        for switchOwner in [false, true] {
            let f = Fixture()
            f.loadDeadlines.onSchedule = {
                if switchOwner { f.select("reader-B") } else { f.loadDeadlines.fire(0) }
            }
            let accepted = await f.commit()
            XCTAssertFalse(accepted)
            XCTAssertTrue(f.transport.reads.isEmpty)
            XCTAssertTrue(f.transport.writes.isEmpty)
            XCTAssertTrue(f.loadDeadlines.entries[0].cancelled)
        }
    }

    func testAccountChangeDuringActualWriteRejectsLateReceipt() async {
        let f = Fixture()
        let commit = Task { await f.commit() }
        await eventually { f.transport.reads.count == 1 }
        f.transport.read(0)
        await eventually { f.transport.writes.count == 1 }
        f.select("reader-B")
        let accepted = await commit.value
        XCTAssertFalse(accepted)
        f.transport.acknowledge(0)
        await eventually { !f.preferences.activity.activeSave }
        XCTAssertEqual(f.preferences.userID, "reader-B")
        XCTAssertEqual(f.preferences.preferences.interestTopicIDs, [])
    }
}
