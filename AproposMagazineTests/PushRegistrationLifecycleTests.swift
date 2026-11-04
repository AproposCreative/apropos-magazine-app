import Foundation
import XCTest
@testable import Apropos

/// Real local vault + registration model + lifecycle engine, with inert storage,
/// transport continuations and clocks. No provider or system keychain is initialized.
@MainActor
final class PushRegistrationLifecycleTests: XCTestCase {
    private let a = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
    private let b = PushAccountContext.authenticated(uid: "reader_B", epoch: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    private let preferences = PushRecipientPreferences(articles: .all, categoryIds: [], podcasts: true)
    private let token = String(repeating: "T", count: 80)

    private func snapshot(_ context: PushAccountContext, permission: Bool? = true,
                          preferences: PushRecipientPreferences? = .init(articles: .all, categoryIds: [], podcasts: true),
                          token: String? = String(repeating: "T", count: 80)) -> PushRegistrationLifecycle.Snapshot {
        .init(context: context, permission: permission, preferences: preferences,
              preferencesContext: preferences == nil ? nil : context, token: token)
    }

    private func start(_ fixture: LifecycleFixture, context: PushAccountContext? = nil,
                       snapshot value: PushRegistrationLifecycle.Snapshot? = nil) {
        let context = context ?? a
        fixture.engine.setAccountContext(context)
        fixture.engine.update(value ?? snapshot(context))
        fixture.engine.setForeground(true)
    }

    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected local lifecycle transition did not settle", file: file, line: line)
    }

    private func drain() async { for _ in 0..<30 { await Task.yield() } }

    func testUnknownInputsAndForeignPreferenceContextCannotStartOrInventGuest() async {
        let f = LifecycleFixture()
        f.engine.setForeground(true)
        XCTAssertFalse(f.engine.update(snapshot(a)))
        XCTAssertEqual(f.engine.status, .waitingForAccount)
        f.engine.setAccountContext(a)
        XCTAssertTrue(f.engine.update(snapshot(a, permission: nil)))
        XCTAssertEqual(f.engine.status, .waitingForPermission)
        XCTAssertTrue(f.engine.update(snapshot(a, preferences: nil)))
        XCTAssertEqual(f.engine.status, .waitingForPreferences)
        XCTAssertFalse(f.engine.update(.init(context: a, permission: true, preferences: preferences,
                                             preferencesContext: b, token: token)))
        XCTAssertFalse(f.engine.update(snapshot(b)))
        await drain()
        XCTAssertEqual(f.store.transactions, 0)
        XCTAssertTrue(f.transport.calls.isEmpty)
        XCTAssertEqual(f.wake.activeCount, 0)
        f.engine.update(snapshot(a))
        await settle { f.model.state == .pending }
        XCTAssertEqual(f.transport.calls.first?.ticket.context, a)
        f.engine.dispose()
    }

    func testBackgroundBuffersLatestSnapshotWithoutPreparingOrSchedulingUntilForeground() async throws {
        let f = LifecycleFixture()
        f.engine.setAccountContext(a)
        for index in 0..<100 {
            f.engine.update(snapshot(a, token: String(repeating: index == 99 ? "U" : "T", count: 80)))
        }
        await drain()
        XCTAssertEqual(f.engine.status, .background)
        XCTAssertEqual(f.store.transactions, 0)
        XCTAssertEqual(f.wake.activeCount, 0)
        XCTAssertTrue(f.transport.calls.isEmpty)
        f.engine.setForeground(true)
        await settle { f.model.state == .pending }
        XCTAssertEqual(f.transport.calls.count, 1)
        guard case .register(let request) = try XCTUnwrap(f.transport.calls.first).call else { return XCTFail("Expected register") }
        XCTAssertEqual(request.token, String(repeating: "U", count: 80))
        XCTAssertEqual(try f.store.record()?.revision, 1)
        XCTAssertLessThanOrEqual(f.wake.maximumActive, 1)
        f.engine.dispose()
    }

    func testCanonicalSnapshotStormDoesNotCancelOutstandingRegistration() async throws {
        let f = LifecycleFixture()
        f.transport.holdPaths = ["register"]
        start(f, snapshot: snapshot(a, preferences: .init(articles: .categories, categoryIds: ["music", "film"], podcasts: true)))
        await settle { f.transport.calls.count == 1 }
        let ticket = try XCTUnwrap(f.transport.calls.first).ticket
        for index in 0..<200 {
            f.engine.update(snapshot(a, preferences: .init(articles: .categories,
                categoryIds: index.isMultiple(of: 2) ? ["film", "music", "film"] : ["music", "film"], podcasts: true)))
            f.engine.setForeground(true)
        }
        await drain()
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertTrue(f.model.isCurrent(ticket))
        XCTAssertEqual(try f.store.record()?.revision, 1)
        XCTAssertLessThanOrEqual(f.wake.maximumActive, 1)
        f.transport.finish(0, result: .success(f.transport.receipt(.pending, ticket: ticket)))
        await settle { f.model.state == .pending }
        f.engine.dispose()
    }

    func testEarlyChallengeConfirmsWhileRegisterHTTPStillHeldAndLateResponseCannotDowngrade() async throws {
        let f = LifecycleFixture()
        f.transport.holdPaths = ["register"]
        start(f)
        await settle { f.transport.calls.count == 1 }
        let old = try XCTUnwrap(f.transport.calls.first).ticket
        XCTAssertTrue(f.engine.receiveChallenge(f.payload(revision: old.clientRevision), context: a))
        await settle { f.model.state == .active }
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "confirm"])
        XCTAssertEqual(f.wake.activeCount, 0)
        f.transport.finish(0, result: .failure(PushRegistrationFailure.authentication))
        await drain()
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.count, 2)
        f.engine.dispose()
    }

    func testAccountChangeRejectsStaleSnapshotsAndTokenlessDisableUsesNewOwner() async throws {
        let f = LifecycleFixture()
        f.transport.holdPaths = ["register"]
        start(f)
        await settle { f.transport.calls.count == 1 }
        let old = try XCTUnwrap(f.transport.calls.first).ticket
        f.engine.setAccountContext(b)
        XCTAssertFalse(f.engine.update(snapshot(a)))
        XCTAssertFalse(f.engine.receiveChallenge(f.payload(revision: old.clientRevision), context: a))
        f.transport.holdPaths = []
        f.engine.update(snapshot(b, token: nil))
        await settle { f.model.state == .waitingForToken }
        XCTAssertEqual(f.transport.calls.count, 2)
        let current = f.transport.calls[1]
        XCTAssertEqual(current.ticket.context, b)
        guard case .register(let request) = current.call else { return XCTFail("Expected tokenless disable") }
        XCTAssertFalse(request.permission)
        XCTAssertNil(request.token)
        XCTAssertEqual(request.preferences, preferences)
        XCTAssertEqual(request.clientRevision, 2)
        XCTAssertFalse(f.model.isCurrent(old))
        f.transport.finish(0, result: .success(f.transport.receipt(.active, ticket: old)))
        await drain()
        XCTAssertEqual(f.model.state, .waitingForToken)
        f.engine.dispose()
    }

    func testBackgroundCancelsObservationAndResumeRetainsRevisionStartAndAttemptBudget() async throws {
        let f = LifecycleFixture(maximumAttempts: 2)
        f.transport.holdPaths = ["register"]
        start(f)
        await settle { f.transport.calls.count == 1 }
        let first = try XCTUnwrap(f.transport.calls.first).ticket
        let original = try XCTUnwrap(f.store.record())
        f.engine.setForeground(false)
        XCTAssertFalse(f.model.isCurrent(first))
        XCTAssertEqual(f.wake.activeCount, 0)
        XCTAssertEqual(f.observation.activeCount, 0)
        f.clock.date = f.clock.date.addingTimeInterval(3)
        f.transport.holdPaths = []
        f.engine.setForeground(true)
        await settle { if case .retryWaiting = f.model.state { return f.wake.nextDate != nil }; return false }
        XCTAssertEqual(f.transport.calls.count, 1, "The retained backoff has not elapsed at +3 seconds")
        f.clock.date = try XCTUnwrap(f.wake.nextDate)
        f.wake.fireNext()
        await settle { f.model.state == .pending }
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(try f.store.record()?.revision, original.revision)
        XCTAssertEqual(try f.store.record()?.revisionStartedAt, original.revisionStartedAt)
        f.engine.setForeground(false)
        f.engine.setForeground(true)
        await drain()
        XCTAssertEqual(f.transport.calls.count, 2, "Pause must not grant an extra register attempt")
        f.transport.finish(0, result: .success(f.transport.receipt(.active, ticket: first)))
        await drain()
        XCTAssertEqual(f.model.state, .pending)
        f.engine.dispose()
    }

    func testBackgroundReplacementCannotResumeRetainedOldOwnerPlan() async {
        let f = LifecycleFixture()
        start(f)
        await settle { f.model.state == .pending }
        f.engine.setForeground(false)
        f.engine.setAccountContext(b)
        f.engine.update(snapshot(b, permission: false))
        f.clock.date = f.clock.date.addingTimeInterval(100)
        f.engine.setForeground(true)
        await settle { f.model.state == .disabled }
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(f.transport.calls.last?.ticket.context, b)
        guard case .register(let request) = f.transport.calls.last?.call else { return XCTFail("Expected disabled B") }
        XCTAssertFalse(request.permission)
        XCTAssertEqual(request.clientRevision, 2)
        f.engine.dispose()
    }

    func testRateLimitAutomaticallyRetriesOnlyWhenDueWithoutChangingDurableBody() async throws {
        let f = LifecycleFixture()
        f.transport.reply = { _, _ in throw PushRegistrationFailure.transient(retryAfter: 40) }
        start(f)
        await settle { if case .retryWaiting = f.model.state { return true }; return false }
        let due = try XCTUnwrap(f.wake.nextDate)
        XCTAssertEqual(due.timeIntervalSince(f.clock.date), 40)
        f.clock.date = due.addingTimeInterval(-1)
        for _ in 0..<50 { f.engine.update(snapshot(a)); f.engine.setForeground(true) }
        await drain()
        XCTAssertEqual(f.transport.calls.count, 1)
        f.clock.date = due
        f.wake.fireNext()
        await settle { f.transport.calls.count == 2 }
        await settle { if case .retryWaiting = f.model.state { return true }; return false }
        XCTAssertEqual(f.transport.calls[0].call, f.transport.calls[1].call)
        XCTAssertEqual(try f.store.record()?.revision, 1)
        XCTAssertLessThanOrEqual(f.wake.maximumActive, 1)
        f.engine.dispose()
    }

    func testPendingWaitsUseBoundedRegisterAttemptsThenOnlyProofDeadline() async throws {
        let f = LifecycleFixture(maximumAttempts: 2)
        start(f)
        await settle { f.model.state == .pending && f.wake.nextDate != nil }
        let firstDue = try XCTUnwrap(f.wake.nextDate)
        XCTAssertEqual(firstDue.timeIntervalSince(f.clock.date), 30)
        f.clock.date = firstDue
        f.wake.fireNext()
        await settle { f.transport.calls.count == 2 && f.model.state == .pending }
        let proofDue = try XCTUnwrap(f.wake.nextDate)
        XCTAssertEqual(proofDue, try f.store.record()?.revisionStartedAt?.addingTimeInterval(240))
        f.engine.setForeground(false)
        f.engine.setForeground(true)
        await drain()
        XCTAssertEqual(f.transport.calls.count, 2)
        f.engine.dispose()
    }

    func testOneProofRenewalExpiresAtOriginalStartAndCannotRepeatThroughUnknownOrForeground() async throws {
        let f = LifecycleFixture(maximumAttempts: 1)
        start(f)
        await settle { f.model.state == .pending && f.wake.nextDate != nil }
        let original = try XCTUnwrap(f.store.record())
        f.clock.date = try XCTUnwrap(original.revisionStartedAt).addingTimeInterval(240)
        f.wake.fireNext()
        await settle { f.transport.calls.count == 2 && f.model.state == .pending }
        XCTAssertEqual(try f.store.record()?.revision, 2)
        // Permission and auth observations may temporarily be unknown without a
        // new session or a new requested intent. Neither grants a renewal budget.
        f.engine.update(snapshot(a, permission: nil))
        f.engine.update(snapshot(a))
        await drain()
        f.engine.setAccountContext(.unresolved)
        XCTAssertFalse(f.engine.update(snapshot(a)))
        f.engine.setAccountContext(a)
        f.engine.update(snapshot(a))
        f.engine.setForeground(false)
        f.engine.setForeground(true)
        await settle { !f.model.drivePlan.isPaused && f.model.state == .pending && f.wake.nextDate != nil }
        let second = try XCTUnwrap(f.store.record())
        f.clock.date = try XCTUnwrap(second.revisionStartedAt).addingTimeInterval(241)
        f.wake.fireNext()
        await settle { f.model.state == .proofExpired }
        for _ in 0..<50 { f.engine.update(snapshot(a)); f.engine.setForeground(true) }
        await drain()
        XCTAssertEqual(try f.store.record()?.revision, 2)
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(f.wake.activeCount, 0)
        f.engine.dispose()
    }

    func testFreshContextGetsItsOwnProofRenewalAndSameUIDNewEpochFencesOldProof() async throws {
        let f = LifecycleFixture(maximumAttempts: 1)
        start(f)
        await settle { f.model.state == .pending && f.wake.nextDate != nil }
        f.clock.date = try XCTUnwrap(f.wake.nextDate)
        f.wake.fireNext()
        await settle { f.model.clientRevision == 2 && f.model.state == .pending }
        let newSession = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID())
        f.engine.setAccountContext(newSession)
        f.engine.update(snapshot(newSession))
        await settle { f.model.clientRevision == 3 && f.model.state == .pending }
        XCTAssertFalse(f.engine.receiveChallenge(f.payload(revision: 2), context: a))
        f.clock.date = try XCTUnwrap(f.wake.nextDate)
        f.wake.fireNext()
        await settle { f.model.clientRevision == 4 && f.model.state == .pending }
        XCTAssertEqual(f.transport.calls.count, 4)
        XCTAssertEqual(f.transport.calls.last?.ticket.context, newSession)
        f.engine.dispose()
    }

    func testThirdPendingRegistrationCanStillConfirmWithoutExtraRegisterReplay() async throws {
        let f = LifecycleFixture(maximumAttempts: 3)
        start(f)
        await settle { f.model.state == .pending && f.wake.nextDate != nil }
        for expected in 2...3 {
            f.clock.date = try XCTUnwrap(f.wake.nextDate)
            f.wake.fireNext()
            await settle { f.transport.calls.count == expected && f.model.state == .pending }
        }
        for invalid in [snapshot(a, token: "invalid token"),
                        snapshot(a, preferences: .init(articles: .categories, categoryIds: [], podcasts: true))] {
            f.engine.update(invalid)
            XCTAssertEqual(f.engine.status, .invalidInput)
            XCTAssertTrue(f.model.drivePlan.isPaused)
            f.engine.update(snapshot(a))
            await settle { f.model.state == .pending && !f.model.drivePlan.isPaused }
            XCTAssertEqual(f.transport.calls.count, 3, "Invalid observations must not refund a revision's attempts")
        }
        let revision = try XCTUnwrap(f.store.record()?.revision)
        XCTAssertTrue(f.engine.receiveChallenge(f.payload(revision: revision), context: a))
        await settle { f.model.state == .active }
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "register", "register", "confirm"])
        XCTAssertEqual(try f.store.record()?.revision, 1)
        XCTAssertEqual(f.wake.activeCount, 0)
        f.engine.dispose()
    }

    func testInvalidTokenRoundTripCannotGrantAnotherRenewalForPreviousValidIntent() async throws {
        let f = LifecycleFixture(maximumAttempts: 1)
        start(f)
        await settle { f.model.state == .pending && f.wake.nextDate != nil }
        f.clock.date = try XCTUnwrap(f.wake.nextDate)
        f.wake.fireNext()
        await settle { f.model.clientRevision == 2 && f.model.state == .pending }
        f.engine.update(snapshot(a, token: "invalid token"))
        XCTAssertEqual(f.engine.status, .invalidInput)
        XCTAssertTrue(f.model.drivePlan.isPaused)
        f.engine.update(snapshot(a))
        await settle { !f.model.drivePlan.isPaused && f.model.state == .pending && f.wake.nextDate != nil }
        XCTAssertEqual(try f.store.record()?.revision, 2)
        f.clock.date = try XCTUnwrap(f.store.record()?.revisionStartedAt).addingTimeInterval(241)
        f.wake.fireNext()
        await settle { f.model.state == .proofExpired }
        await drain()
        XCTAssertEqual(try f.store.record()?.revision, 2)
        XCTAssertEqual(f.wake.activeCount, 0)
        f.engine.dispose()
    }

    func testAuthenticationForbiddenAndConflictNeverScheduleRenewalOrBecomeGuest() async throws {
        for failure in [PushRegistrationFailure.authentication, .forbidden, .conflict] {
            let f = LifecycleFixture()
            f.transport.reply = { _, _ in throw failure }
            start(f)
            await settle { if case .blocked = f.model.state { return true }; return false }
            f.clock.date = f.clock.date.addingTimeInterval(600)
            for _ in 0..<10 {
                f.engine.update(snapshot(a, permission: nil))
                f.engine.update(snapshot(a))
                f.engine.setForeground(false)
                f.engine.setForeground(true)
            }
            await drain()
            XCTAssertEqual(f.transport.calls.count, 1)
            XCTAssertEqual(try f.store.record()?.revision, 1)
            XCTAssertEqual(f.transport.calls.first?.ticket.context, a)
            XCTAssertEqual(f.wake.activeCount, 0)
            f.engine.dispose()
        }
    }

    func testTimerExpiryFencesHeldRegisterBeforeLateActiveReceipt() async throws {
        let f = LifecycleFixture(maximumAttempts: 1)
        f.transport.holdPaths = ["register"]
        start(f)
        await settle { f.transport.calls.count == 1 && f.wake.nextDate != nil }
        let old = try XCTUnwrap(f.transport.calls.first).ticket
        f.clock.date = try XCTUnwrap(f.wake.nextDate)
        f.wake.fireNext()
        XCTAssertFalse(f.model.isCurrent(old))
        f.transport.holdPaths = []
        await settle { f.transport.calls.count == 2 && f.model.state == .pending }
        f.transport.finish(0, result: .success(f.transport.receipt(.active, ticket: old)))
        await drain()
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.model.clientRevision, 2)
        f.engine.dispose()
    }

    func testDisposeCancelsBothTimersAndLateChallengeSnapshotOrTransportCannotRestart() async throws {
        let f = LifecycleFixture()
        f.transport.holdPaths = ["register"]
        start(f)
        await settle { f.transport.calls.count == 1 && f.wake.nextDate != nil }
        let old = try XCTUnwrap(f.transport.calls.first).ticket
        f.engine.dispose()
        XCTAssertEqual(f.engine.status, .disposed)
        XCTAssertEqual(f.wake.activeCount, 0)
        XCTAssertEqual(f.observation.activeCount, 0)
        XCTAssertFalse(f.model.isCurrent(old))
        f.engine.setForeground(true)
        f.engine.setAccountContext(b)
        XCTAssertFalse(f.engine.update(snapshot(b)))
        XCTAssertFalse(f.engine.receiveChallenge(f.payload(revision: 1), context: a))
        f.wake.fireCancelled()
        f.transport.finish(0, result: .success(f.transport.receipt(.active, ticket: old)))
        await drain()
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(try f.store.record()?.revision, 1)
    }

    func testHeldPreparationRetainsSingleDriverAcrossBackgroundAndNewLatestSnapshot() async throws {
        let f = LifecycleFixture(holdPreparation: true)
        start(f)
        await settle { f.preparation.heldCount == 1 }
        f.engine.setForeground(false)
        f.engine.setAccountContext(b)
        f.engine.update(snapshot(b, permission: false))
        f.engine.setForeground(true)
        await drain()
        XCTAssertEqual(f.preparation.calls, 1, "The old driver still owns a noncooperative preparation")
        XCTAssertTrue(f.transport.calls.isEmpty)
        f.preparation.release()
        await settle { f.model.state == .disabled }
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.transport.calls.first?.ticket.context, b)
        XCTAssertEqual(try f.store.record()?.revision, 2)
        f.engine.dispose()
    }
}

@MainActor
private final class LifecycleFixture {
    let clock = LifecycleClock()
    let store: LifecycleStore
    let preparation: LifecyclePreparation
    let transport = LifecycleTransport()
    let wake = LifecycleScheduler()
    let observation = LifecycleScheduler()
    let model: PushRegistrationModel
    let engine: PushRegistrationLifecycle

    init(maximumAttempts: Int = 3, holdPreparation: Bool = false) {
        let store = LifecycleStore()
        let vault = PushInstallationVault(store: store, makeIdentity: {
            ("11111111-1111-4111-8111-111111111111", String(repeating: "K", count: 64))
        })
        self.store = store
        let preparation = LifecyclePreparation(vault: vault, hold: holdPreparation)
        self.preparation = preparation
        let clock = self.clock, transport = self.transport, observation = self.observation
        let model = PushRegistrationModel(prepare: { hash, date, force in
            try await preparation.prepare(hash: hash, date: date, force: force)
        }, send: { call, ticket in try await transport.send(call, ticket: ticket) }, now: { clock.date },
            schedule: { observation.schedule(at: clock.date.addingTimeInterval(60), $0) }, maximumAttempts: maximumAttempts)
        self.model = model
        let wake = self.wake
        engine = PushRegistrationLifecycle(model: model, now: { clock.date }, schedule: { wake.schedule(at: $0, $1) })
    }

    func payload(revision: Int64) -> [String: String] {
        ["type": "verify_push_installation", "installation_id": "11111111-1111-4111-8111-111111111111",
         "client_revision": String(revision), "challenge_id": String(repeating: "a", count: 64), "nonce": String(repeating: "N", count: 64)]
    }
}

@MainActor
private final class LifecycleClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

private final class LifecycleStore: @unchecked Sendable, PushInstallationRecordStore {
    private let lock = NSLock()
    private var data: Data?
    private var count = 0
    var transactions: Int { lock.lock(); defer { lock.unlock() }; return count }
    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let next = try update(data)
        data = next
        return next
    }
    func record() throws -> PushInstallationRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let data else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(PushInstallationRecord.self, from: data)
    }
}

@MainActor
private final class LifecyclePreparation {
    let vault: PushInstallationVault
    var calls = 0
    var hold: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var heldCount: Int { continuation == nil ? 0 : 1 }
    init(vault: PushInstallationVault, hold: Bool) { self.vault = vault; self.hold = hold }
    func prepare(hash: String, date: Date, force: Bool) async throws -> PushInstallationRecord {
        calls += 1
        let record = try await vault.prepare(intentHash: hash, at: date, forceNewRevision: force)
        if hold {
            hold = false
            await withCheckedContinuation { continuation = $0 }
        }
        return record
    }
    func release() { let current = continuation; continuation = nil; current?.resume() }
}

@MainActor
private final class LifecycleScheduler {
    private var callbacks: [Int: (Date, () -> Void)] = [:]
    private var cancelled: [() -> Void] = []
    private var sequence = 0
    private(set) var maximumActive = 0
    var activeCount: Int { callbacks.count }
    var nextDate: Date? { callbacks.values.map(\.0).min() }
    func schedule(at date: Date, _ action: @escaping () -> Void) -> () -> Void {
        let id = sequence; sequence += 1
        callbacks[id] = (date, action)
        maximumActive = max(maximumActive, callbacks.count)
        return { [weak self] in
            guard let self, let entry = self.callbacks.removeValue(forKey: id) else { return }
            self.cancelled.append(entry.1)
        }
    }
    func fireNext() {
        guard let entry = callbacks.min(by: { $0.value.0 < $1.value.0 }) else { return XCTFail("No local wake is pending") }
        callbacks.removeValue(forKey: entry.key)
        entry.value.1()
    }
    func fireCancelled() { let actions = cancelled; cancelled = []; actions.forEach { $0() } }
}

@MainActor
private final class LifecycleTransport {
    struct Call { let call: PushRegistrationCall; let ticket: PushRegistrationTicket }
    var calls: [Call] = []
    var holdPaths: Set<String> = []
    var reply: ((PushRegistrationCall, PushRegistrationTicket) throws -> PushRegistrationReceipt)?
    private var held: [Int: CheckedContinuation<PushRegistrationReceipt, Error>] = [:]
    func send(_ call: PushRegistrationCall, ticket: PushRegistrationTicket) async throws -> PushRegistrationReceipt {
        let index = calls.count
        calls.append(.init(call: call, ticket: ticket))
        if holdPaths.contains(call.path) { return try await withCheckedThrowingContinuation { held[index] = $0 } }
        if let reply { return try reply(call, ticket) }
        let status: PushRegistrationReceipt.Status
        if case .register(let request) = call { status = request.permission ? .pending : .disabled }
        else { status = .active }
        return receipt(status, ticket: ticket)
    }
    func receipt(_ status: PushRegistrationReceipt.Status, ticket: PushRegistrationTicket) -> PushRegistrationReceipt {
        .init(status: status, installationId: ticket.installationId, clientRevision: ticket.clientRevision,
              revision: status == .pending ? nil : ticket.clientRevision,
              challengeId: status == .pending ? String(repeating: "a", count: 64) : nil)
    }
    func finish(_ index: Int, result: Result<PushRegistrationReceipt, Error>) {
        guard let continuation = held.removeValue(forKey: index) else { return XCTFail("No local transport \(index) is held") }
        continuation.resume(with: result)
    }
}
