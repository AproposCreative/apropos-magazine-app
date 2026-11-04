import Combine
import XCTest
@testable import Apropos

/// Exercises the registration state machine with local continuations only. No
/// Firebase, notification service, URLSession or keychain is created by this suite.
@MainActor
final class PushRegistrationModelTests: XCTestCase {
    private let installation = "11111111-1111-4111-8111-111111111111"
    private let key = String(repeating: "K", count: 64)
    private let token = String(repeating: "T", count: 80)
    private let challenge = String(repeating: "a", count: 64)
    private let nonce = String(repeating: "N", count: 64)
    private let epoch = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func intent(context: PushAccountContext? = nil, permission: Bool = true,
                        preferences: PushRecipientPreferences? = nil, token: String? = nil) -> PushRegistrationIntent {
        .init(context: context ?? .guest(epoch: epoch), permission: permission,
              preferences: preferences ?? .init(articles: .all, categoryIds: [], podcasts: false),
              token: token ?? self.token)
    }

    private func payload(revision: Int64 = 1, installation: String? = nil,
                         challenge: String? = nil, nonce: String? = nil) -> [String: String] {
        ["type": "verify_push_installation", "installation_id": installation ?? self.installation,
         "challenge_id": challenge ?? self.challenge, "client_revision": String(revision), "nonce": nonce ?? self.nonce]
    }

    private func receipt(_ status: PushRegistrationReceipt.Status = .pending, revision: Int64 = 1,
                         installation: String? = nil, challenge: String? = nil) -> PushRegistrationReceipt {
        .init(status: status, installationId: installation ?? self.installation, clientRevision: revision,
              revision: status == .pending ? nil : revision, challengeId: status == .pending ? challenge ?? self.challenge : nil)
    }

    private func fixture(maximumAttempts: Int = 3, proofLifetime: TimeInterval = 240) -> PushModelFixture {
        PushModelFixture(installation: installation, key: key, maximumAttempts: maximumAttempts, proofLifetime: proofLifetime)
    }

    func testFailedDurablePreparationNeverSendsOrClaimsRegistration() async {
        let f = fixture()
        f.preparation.failure = PushInstallationVaultError.keychainWrite(-1)
        await f.model.update(intent())
        XCTAssertEqual(f.model.state, .blocked(.storage))
        XCTAssertNil(f.model.clientRevision)
        XCTAssertTrue(f.transport.calls.isEmpty)
        XCTAssertNil(f.preparation.record)
    }

    func testTransportStartsOnlyAfterRevisionHasBeenDurablyPrepared() async throws {
        let f = fixture()
        f.preparation.holdNext = true
        f.transport.reply = { [self] _, _ in receipt() }
        let updating = Task { await f.model.update(intent()) }
        try await f.preparation.waitForHeldPreparation()
        XCTAssertEqual(f.model.state, .preparing)
        XCTAssertTrue(f.transport.calls.isEmpty)
        XCTAssertNil(f.preparation.record)
        f.preparation.finishHeldPreparation()
        await updating.value
        let prepared = try XCTUnwrap(f.preparation.record)
        guard case .register(let request) = try XCTUnwrap(f.transport.calls.first).call else {
            return XCTFail("The first transport operation must register the persisted identity")
        }
        XCTAssertEqual(request.installationId, prepared.installationId)
        XCTAssertEqual(request.clientRevision, prepared.revision)
        XCTAssertEqual(request.key, prepared.key)
        XCTAssertEqual(f.model.clientRevision, prepared.revision)
        XCTAssertEqual(f.model.state, .pending)
    }

    func testEquivalentCategorySelectionsUseCanonicalRequestAndSameDurableRevision() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent(preferences: .init(articles: .categories, categoryIds: ["music", "film", "music"], podcasts: true)))
        let first = try XCTUnwrap(f.preparation.record)
        await f.model.update(intent(preferences: .init(articles: .categories, categoryIds: ["film", "music"], podcasts: true)))
        XCTAssertEqual(f.preparation.record?.revision, first.revision)
        XCTAssertEqual(f.preparation.record?.intentHash, first.intentHash)
        for call in f.transport.calls {
            guard case .register(let request) = call.call else { return XCTFail("No challenge was supplied") }
            XCTAssertEqual(request.preferences.categoryIds, ["film", "music"])
            XCTAssertEqual(request.clientRevision, first.revision)
        }
    }

    func testUnresolvedAccountWaitsButMissingTokenDisablesExplicitAccountBeforeWaiting() async throws {
        let f = fixture()
        await f.model.update(intent(context: .unresolved))
        XCTAssertEqual(f.model.state, .waitingForAccount)
        await f.model.synchronize()
        XCTAssertTrue(f.preparation.inputs.isEmpty)
        XCTAssertTrue(f.transport.calls.isEmpty)
        let context = PushAccountContext.authenticated(uid: "reader_B", epoch: epoch)
        let preferences = PushRecipientPreferences(articles: .categories, categoryIds: ["music"], podcasts: true)
        f.transport.holdPaths = ["register"]
        let updating = Task {
            await f.model.update(.init(context: context, permission: true, preferences: preferences, token: nil))
        }
        try await f.transport.waitForCalls(1)
        XCTAssertEqual(f.model.state, .registering)
        guard case .register(let request) = f.transport.calls[0].call else { return XCTFail("Expected tokenless disable") }
        XCTAssertFalse(request.permission)
        XCTAssertNil(request.token)
        XCTAssertEqual(request.preferences, preferences)
        XCTAssertEqual(f.transport.calls[0].ticket.context, context)
        XCTAssertEqual(f.preparation.record?.revision, 1)
        f.transport.finish(0, with: .success(receipt(.disabled)))
        await updating.value
        XCTAssertEqual(f.model.state, .waitingForToken)
        await f.model.synchronize()
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.transport.calls.count, 1)
    }

    func testAccountChangeWithoutTokenDisablesOldEligibilityBeforeFreshTokenRegisters() async throws {
        let nextContexts: [PushAccountContext] = [
            .authenticated(uid: "reader_B", epoch: UUID()),
            .authenticated(uid: "reader_A", epoch: UUID())
        ]
        for nextContext in nextContexts {
            let f = fixture()
            f.transport.reply = { [self, weak transport = f.transport] call, ticket in
                guard case .register(let request) = call else { throw PushRegistrationFailure.invalidResponse }
                if !request.permission { return receipt(.disabled, revision: ticket.clientRevision) }
                return receipt(transport?.calls.count == 1 ? .active : .pending, revision: ticket.clientRevision)
            }
            await f.model.update(intent(context: .authenticated(uid: "reader_A", epoch: epoch)))
            XCTAssertEqual(f.model.state, .active)
            let oldTicket = try XCTUnwrap(f.transport.calls.first).ticket
            let preferences = PushRecipientPreferences(articles: .all, categoryIds: [], podcasts: false)
            await f.model.update(.init(context: nextContext, permission: true, preferences: preferences, token: nil))
            XCTAssertEqual(f.model.state, .waitingForToken)
            XCTAssertEqual(f.model.clientRevision, 2)
            XCTAssertFalse(f.model.isCurrent(oldTicket))
            guard case .register(let disabled) = f.transport.calls[1].call else { return XCTFail("Expected tokenless disable") }
            XCTAssertFalse(disabled.permission)
            XCTAssertNil(disabled.token)
            XCTAssertEqual(disabled.clientRevision, 2)
            XCTAssertEqual(disabled.preferences, preferences)
            XCTAssertEqual(f.transport.calls[1].ticket.context, nextContext)
            let acceptedOldProof = await f.model.receiveChallenge(payload())
            XCTAssertFalse(acceptedOldProof)

            let freshToken = String(repeating: "U", count: 80)
            await f.model.update(intent(context: nextContext, token: freshToken))
            XCTAssertEqual(f.model.state, .pending)
            XCTAssertEqual(f.model.clientRevision, 3)
            guard case .register(let enabled) = f.transport.calls[2].call else { return XCTFail("Expected fresh-token registration") }
            XCTAssertTrue(enabled.permission)
            XCTAssertEqual(enabled.token, freshToken)
            XCTAssertEqual(enabled.clientRevision, 3)
            XCTAssertEqual(f.transport.calls[2].ticket.context, nextContext)
            XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "register", "register"])
        }
    }

    func testUnacknowledgedTokenlessDisableShowsRetryInsteadOfWaitingForToken() async throws {
        let f = fixture()
        f.transport.reply = { [self, weak transport = f.transport] _, ticket in
            if transport?.calls.count == 1 { throw PushRegistrationFailure.transient(retryAfter: 30) }
            return receipt(.disabled, revision: ticket.clientRevision)
        }
        await f.model.update(.init(context: .authenticated(uid: "reader_A", epoch: epoch), permission: true,
                                  preferences: .init(articles: .all, categoryIds: [], podcasts: false), token: nil))
        guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Unconfirmed disable must remain visibly retryable") }
        XCTAssertEqual(f.transport.calls.count, 1)
        f.clock.date = due
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .waitingForToken)
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(f.transport.calls[0].call, f.transport.calls[1].call)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testDisabledIntentCanRegisterWithoutTokenAndDoesNotRequestProof() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt(.disabled) }
        await f.model.update(intent(permission: false))
        guard case .register(let request) = try XCTUnwrap(f.transport.calls.first).call else { return XCTFail("Expected registration") }
        XCTAssertNil(request.token)
        XCTAssertFalse(request.permission)
        XCTAssertEqual(f.model.state, .disabled)
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertFalse(accepted)
        XCTAssertEqual(f.transport.calls.count, 1)
    }

    func testChallengeConfirmsOriginalInstallationAndPrivateNonceRemainsOutOfDurableState() async throws {
        let f = fixture()
        f.transport.reply = { [self] call, _ in receipt(call.path == "register" ? .pending : .active) }
        await f.model.update(intent())
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        guard case .confirm(let request) = try XCTUnwrap(f.transport.calls.last).call else { return XCTFail("Expected confirmation") }
        XCTAssertEqual(request.installationId, installation)
        XCTAssertEqual(request.key, key)
        XCTAssertEqual(request.challengeId, challenge)
        XCTAssertEqual(request.nonce, nonce)
        let storedRecord = try XCTUnwrap(f.preparation.record)
        let stored = String(decoding: try JSONEncoder().encode(storedRecord), as: UTF8.self)
        XCTAssertFalse(stored.contains(nonce))
        XCTAssertFalse(stored.contains(token))
        XCTAssertFalse(stored.contains(challenge))
        XCTAssertFalse(String(reflecting: f.model.state).contains(nonce))
        XCTAssertEqual(f.model.installationId, installation)
        XCTAssertEqual(f.model.clientRevision, 1)
    }

    func testChallengeArrivingBeforeRegistrationReceiptCannotBeDowngradedByLatePending() async throws {
        try await assertEarlyChallengeSurvivesRegistrationCompletion(.success(receipt()))
    }

    func testChallengeArrivingBeforeRegistrationReceiptCannotBeDowngradedByLateHTTPFailure() async throws {
        try await assertEarlyChallengeSurvivesRegistrationCompletion(.failure(PushRegistrationFailure.transient(retryAfter: 60)))
    }

    private func assertEarlyChallengeSurvivesRegistrationCompletion(_ result: Result<PushRegistrationReceipt, Error>) async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        f.transport.reply = { [self] _, _ in receipt(.active) }
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "confirm"])
        f.transport.finish(0, with: result)
        await updating.value
        XCTAssertEqual(f.model.state, .active)
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 2)
    }

    func testAccountAToBToNewASessionRejectsBothOldCompletionsAndTickets() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let a = PushAccountContext.authenticated(uid: "reader_A", epoch: epoch)
        let b = PushAccountContext.authenticated(uid: "reader_B", epoch: UUID())
        let newerA = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID())
        let first = Task { await f.model.update(intent(context: a)) }
        try await f.transport.waitForCalls(1)
        let second = Task { await f.model.update(intent(context: b)) }
        try await f.transport.waitForCalls(2)
        let third = Task { await f.model.update(intent(context: newerA)) }
        try await f.transport.waitForCalls(3)
        let calls = f.transport.calls
        XCTAssertFalse(f.model.isCurrent(calls[0].ticket))
        XCTAssertFalse(f.model.isCurrent(calls[1].ticket))
        XCTAssertTrue(f.model.isCurrent(calls[2].ticket))
        f.transport.finish(2, with: .success(receipt(.active, revision: calls[2].ticket.clientRevision)))
        await third.value
        f.transport.finish(0, with: .success(receipt(revision: calls[0].ticket.clientRevision)))
        f.transport.finish(1, with: .failure(PushRegistrationFailure.authentication))
        await first.value
        await second.value
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.model.clientRevision, calls[2].ticket.clientRevision)
        XCTAssertEqual(calls[2].ticket.context, newerA)
    }

    func testNewSessionWithSameUIDInvalidatesOldTransportGeneration() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let first = Task { await f.model.update(intent(context: .authenticated(uid: "reader_A", epoch: epoch))) }
        try await f.transport.waitForCalls(1)
        let nextContext = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID())
        let second = Task { await f.model.update(intent(context: nextContext)) }
        try await f.transport.waitForCalls(2)
        XCTAssertFalse(f.model.isCurrent(f.transport.calls[0].ticket))
        XCTAssertTrue(f.model.isCurrent(f.transport.calls[1].ticket))
        f.transport.finish(1, with: .success(receipt(.active, revision: f.transport.calls[1].ticket.clientRevision)))
        await second.value
        f.transport.finish(0, with: .failure(PushRegistrationFailure.forbidden))
        await first.value
        XCTAssertEqual(f.model.state, .active)
    }

    func testChangingTokenPreferencesOrPermissionMakesOldProofUnusable() async throws {
        let replacements = [
            intent(token: String(repeating: "U", count: 80)),
            intent(preferences: .init(articles: .categories, categoryIds: ["music"], podcasts: false)),
            intent(permission: false)
        ]
        for replacement in replacements {
            let f = fixture()
            f.transport.reply = { [self] call, ticket in
                if case .register(let request) = call {
                    return receipt(request.permission ? .pending : .disabled, revision: ticket.clientRevision,
                                   challenge: ticket.clientRevision == 1 ? challenge : String(repeating: "b", count: 64))
                }
                return receipt(.active, revision: ticket.clientRevision)
            }
            await f.model.update(intent())
            await f.model.update(replacement)
            XCTAssertEqual(f.model.clientRevision, 2)
            let accepted = await f.model.receiveChallenge(payload())
            XCTAssertFalse(accepted)
            XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "register"])
        }
    }

    func testDuplicateChallengeCoalescesInFlightConfirmationAndDoesNotReplayAfterSuccess() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        f.transport.holdPaths = ["confirm"]
        let first = Task { await f.model.receiveChallenge(payload()) }
        try await f.transport.waitForCalls(2)
        let second = Task { await f.model.receiveChallenge(payload()) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.transport.calls.count, 2)
        f.transport.finish(1, with: .success(receipt(.active)))
        let accepted = await first.value
        _ = await second.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        _ = await f.model.receiveChallenge(payload())
        XCTAssertEqual(f.transport.calls.count, 2)
    }

    func testMalformedAndStaleChallengesNeverReachConfirmationTransport() async {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        var invalid: [[String: String]] = [
            [:], payload(revision: 2), payload(installation: "33333333-3333-4333-8333-333333333333"),
            payload(challenge: "not-a-hash"), payload(nonce: "too-short")
        ]
        for (field, value) in [("type", "other"), ("client_revision", "01"), ("client_revision", "+1"),
                               ("client_revision", "1.0"), ("client_revision", "9007199254740992"),
                               ("nonce", String(repeating: "!", count: 64))] {
            var changed = payload(); changed[field] = value; invalid.append(changed)
        }
        for value in invalid {
            let accepted = await f.model.receiveChallenge(value)
            XCTAssertFalse(accepted, "Invalid local proof payload was accepted: \(value.keys.sorted())")
        }
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.transport.calls.count, 1)
    }

    func testConflictingChallengeDoesNotReplaceServerAcknowledgedProof() async {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        let accepted = await f.model.receiveChallenge(payload(challenge: String(repeating: "b", count: 64)))
        XCTAssertFalse(accepted)
        XCTAssertEqual(f.model.state, .blocked(.challengeMismatch))
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testRateLimitRetriesOnlyWhenDueWithIdenticalBodyAndStopsAtBound() async throws {
        let f = fixture(maximumAttempts: 3)
        f.transport.reply = { _, _ in throw PushRegistrationFailure.transient(retryAfter: 90) }
        await f.model.update(intent())
        for expected in 1...2 {
            guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Expected bounded retry deadline") }
            XCTAssertGreaterThanOrEqual(due.timeIntervalSince(f.clock.date), 90)
            f.clock.date = due.addingTimeInterval(-0.001)
            await f.model.synchronize()
            XCTAssertEqual(f.transport.calls.count, expected)
            f.clock.date = due
            await f.model.synchronize()
            XCTAssertEqual(f.transport.calls.count, expected + 1)
        }
        // A server may have accepted a request whose HTTP receipt was lost.
        // Exhausted replay allowance still admits its current private proof.
        XCTAssertEqual(f.model.state, .pending)
        f.clock.date = f.clock.date.addingTimeInterval(600)
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 3)
        XCTAssertEqual(f.preparation.record?.revision, 1)
        let first = try XCTUnwrap(f.transport.calls.first).call
        XCTAssertTrue(f.transport.calls.allSatisfy { $0.call == first })
        XCTAssertTrue(f.transport.calls.allSatisfy { $0.ticket.clientRevision == 1 })
        XCTAssertFalse(f.preparation.inputs.contains { $0.force })
    }

    func testConfirmationRetryRetainsNonceAndDoesNotRestartRegistration() async throws {
        let f = fixture()
        f.transport.reply = { [self, weak transport = f.transport] call, _ in
            if call.path == "register" { return receipt() }
            if transport?.calls.filter({ $0.call.path == "confirm" }).count == 1 {
                throw PushRegistrationFailure.transient(retryAfter: 30)
            }
            return receipt(.active)
        }
        await f.model.update(intent())
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Confirmation should wait for its retry deadline") }
        _ = await f.model.receiveChallenge(payload())
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 2)
        f.clock.date = due
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "confirm", "confirm"])
        XCTAssertEqual(f.transport.calls[1].call, f.transport.calls[2].call)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testObservationTimeoutEndsWaitAndLateSuccessCannotOverrideRetryState() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        f.deadline.fireNext()
        await updating.value
        guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Expired local observation should allow a bounded retry") }
        XCTAssertEqual(f.deadline.activeCount, 0)
        f.transport.finish(0, with: .success(receipt(.active)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.state, .retryWaiting(until: due))
        XCTAssertEqual(f.transport.calls.count, 1)
        f.transport.holdPaths = []
        f.transport.reply = { [self] _, _ in receipt() }
        f.clock.date = due
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(f.transport.calls[0].call, f.transport.calls[1].call)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testAuthenticationForbiddenAndConflictCannotBecomeGuestOrBumpRevision() async {
        let failures: [(PushRegistrationFailure, PushRegistrationBlock)] = [
            (.authentication, .authentication), (.forbidden, .forbidden), (.conflict, .conflict)
        ]
        for (failure, block) in failures {
            let f = fixture()
            f.transport.reply = { _, _ in throw failure }
            await f.model.update(intent(context: .authenticated(uid: "reader_A", epoch: epoch)))
            XCTAssertEqual(f.model.state, .blocked(block))
            f.clock.date = f.clock.date.addingTimeInterval(600)
            await f.model.synchronize()
            await f.model.renewExpiredProof()
            XCTAssertEqual(f.transport.calls.count, 1)
            XCTAssertEqual(f.preparation.record?.revision, 1)
            XCTAssertFalse(f.preparation.inputs.contains { $0.force })
            XCTAssertEqual(f.transport.calls.first?.ticket.context.ownerUID, "reader_A")
            if let ticket = f.transport.calls.first?.ticket { XCTAssertFalse(f.model.isCurrent(ticket)) }
        }
    }

    func testProofCanOnlyBeRenewedAfterOriginalLocalLifetimeExpires() async throws {
        let f = fixture(proofLifetime: 240)
        f.transport.reply = { [self] _, ticket in receipt(revision: ticket.clientRevision) }
        await f.model.update(intent())
        let started = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        f.clock.date = started.addingTimeInterval(239)
        await f.model.renewExpiredProof()
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.preparation.record?.revision, 1)
        f.clock.date = started.addingTimeInterval(241)
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .proofExpired)
        await f.model.renewExpiredProof()
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertEqual(f.preparation.record?.revision, 2)
        XCTAssertEqual(f.preparation.inputs.filter(\.force).count, 1)
        let accepted = await f.model.receiveChallenge(payload(revision: 1))
        XCTAssertFalse(accepted)
    }

    func testProofExpiryFencesOutstandingRegistrationAndLateReceiptCannotRestorePending() async throws {
        let f = fixture(proofLifetime: 240)
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        let started = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        f.clock.date = started.addingTimeInterval(241)
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .proofExpired)
        XCTAssertEqual(f.deadline.activeCount, 0)
        f.transport.finish(0, with: .success(receipt()))
        await updating.value
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.state, .proofExpired)
        XCTAssertEqual(f.preparation.record?.revision, 1)

        f.transport.holdPaths = []
        f.transport.reply = { [self] _, ticket in receipt(revision: ticket.clientRevision) }
        await f.model.renewExpiredProof()
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.model.clientRevision, 2)
        XCTAssertEqual(f.preparation.inputs.filter(\.force).count, 1)
        XCTAssertEqual(f.transport.calls.count, 2)
        let acceptedOldProof = await f.model.receiveChallenge(payload())
        XCTAssertFalse(acceptedOldProof)
    }

    func testClockMovingBeforeRevisionStartCannotRenewOrConfirmProof() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        f.clock.date = try XCTUnwrap(f.preparation.record?.revisionStartedAt).addingTimeInterval(-1)
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertFalse(accepted)
        XCTAssertEqual(f.model.state, .blocked(.clock))
        await f.model.renewExpiredProof()
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testDrivePlanDeliversOneAtomicValueAndFinalPendingWakeupAfterCleanup() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        var plans: [PushRegistrationModel.DrivePlan] = []
        let observer = f.model.$drivePlan.sink { plan in
            plans.append(plan)
            XCTAssertEqual(plan.state, f.model.state)
        }
        await f.model.update(intent())
        let start = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        let plan = try XCTUnwrap(plans.last)
        XCTAssertEqual(plan.state, .pending)
        XCTAssertEqual(plan.nextActionAt, start.addingTimeInterval(30))
        XCTAssertEqual(plan.proofExpiresAt, start.addingTimeInterval(240))
        XCTAssertFalse(plan.isPaused)
        XCTAssertFalse(plan.isDisposed)
        XCTAssertEqual(plan, f.model.drivePlan)
        let count = plans.count
        await f.model.synchronize()
        XCTAssertEqual(plans.count, count, "Unchanged plans must not feed back into the driver")
        XCTAssertFalse(String(reflecting: plan).contains(token))
        XCTAssertFalse(String(reflecting: plan).contains(key))
        observer.cancel()
    }

    func testPendingReplayWaitsThirtySecondsAndLastPendingStillAcceptsChallenge() async throws {
        let f = fixture()
        f.transport.reply = { [self] call, _ in receipt(call.path == "register" ? .pending : .active) }
        await f.model.update(intent())
        let started = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        for _ in 0..<10 { await f.model.update(intent()); await f.model.synchronize() }
        XCTAssertEqual(f.transport.calls.count, 1)
        f.clock.date = started.addingTimeInterval(29.999)
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 1)
        for seconds in [30.0, 60.0] {
            f.clock.date = started.addingTimeInterval(seconds)
            await f.model.synchronize()
        }
        XCTAssertEqual(f.transport.calls.count, 3)
        XCTAssertEqual(f.model.drivePlan.nextActionAt, started.addingTimeInterval(240))
        for _ in 0..<10 { await f.model.synchronize() }
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.transport.calls.count, 3)
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "register", "register", "confirm"])
    }

    func testExhaustedUnacknowledgedRegisterStillAdmitsCurrentPrivateProof() async throws {
        let f = fixture(maximumAttempts: 1)
        f.transport.reply = { [self] call, _ in
            if call.path == "register" { throw PushRegistrationFailure.transient(retryAfter: 30) }
            return receipt(.active)
        }
        await f.model.update(intent())
        XCTAssertEqual(f.model.state, .pending)
        let start = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        XCTAssertEqual(f.model.drivePlan.nextActionAt, start.addingTimeInterval(240))
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 1)
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.count, 2)
    }

    func testExhaustedDisabledRegistrationHasNoProofOrAutomaticRetry() async {
        let f = fixture(maximumAttempts: 1)
        f.transport.reply = { _, _ in throw PushRegistrationFailure.transient(retryAfter: nil) }
        await f.model.update(intent(permission: false))
        XCTAssertEqual(f.model.state, .blocked(.retryLimit))
        XCTAssertNil(f.model.drivePlan.nextActionAt)
        XCTAssertNil(f.model.drivePlan.proofExpiresAt)
        let accepted = f.model.stageChallenge(payload())
        XCTAssertFalse(accepted)
    }

    func testPauseLastInFlightRegisterFencesLateReceiptButKeepsProofAdmission() async throws {
        let f = fixture(maximumAttempts: 1)
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        let old = f.transport.calls[0]
        f.model.pause()
        XCTAssertFalse(f.model.isCurrent(old.ticket))
        XCTAssertTrue(f.model.drivePlan.isPaused)
        XCTAssertNil(f.model.drivePlan.nextActionAt)
        XCTAssertEqual(f.deadline.activeCount, 0)
        await updating.value
        f.transport.finish(0, with: .success(receipt(.active)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.state, .pending)
        f.model.resume()
        await f.model.update(intent())
        XCTAssertEqual(f.transport.calls.count, 1)
        f.transport.reply = { [self] _, _ in receipt(.active) }
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.preparation.inputs.count, 1)
    }

    func testPauseResumeRetainsRetryDeadlineBodyRevisionAndAttemptBudget() async throws {
        let f = fixture(maximumAttempts: 3)
        f.transport.reply = { _, _ in throw PushRegistrationFailure.transient(retryAfter: 30) }
        await f.model.update(intent())
        let started = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        for attempt in 1...2 {
            guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Expected retry") }
            for _ in 0..<5 {
                f.model.pause(); f.model.resume()
                await f.model.update(intent())
            }
            XCTAssertEqual(f.transport.calls.count, attempt)
            XCTAssertEqual(f.model.drivePlan.nextActionAt, due)
            f.clock.date = due
            await f.model.synchronize()
        }
        XCTAssertEqual(f.transport.calls.count, 3)
        XCTAssertEqual(f.model.state, .pending)
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.preparation.record?.revisionStartedAt, started)
        XCTAssertEqual(f.preparation.record?.revision, 1)
        XCTAssertTrue(f.transport.calls.allSatisfy { $0.call == f.transport.calls[0].call })
        f.model.pause(); f.model.resume()
        await f.model.update(intent())
        XCTAssertEqual(f.transport.calls.count, 3)
    }

    func testPauseResumeIsLocalAndObservesOriginalProofExpiryBeforeTransport() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        let started = try XCTUnwrap(f.preparation.record?.revisionStartedAt)
        f.model.pause()
        await f.model.update(intent(token: String(repeating: "U", count: 80)))
        await f.model.synchronize()
        await f.model.renewExpiredProof()
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.transport.calls.count, 1)
        f.clock.date = started.addingTimeInterval(241)
        f.model.resume()
        XCTAssertEqual(f.model.state, .proofExpired)
        XCTAssertNil(f.model.drivePlan.nextActionAt)
        XCTAssertNil(f.model.drivePlan.proofExpiresAt)
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testPauseRetainsInFlightForcedPreparationWithoutAdvancingRevisionTwice() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, ticket in receipt(revision: ticket.clientRevision) }
        await f.model.update(intent(context: .authenticated(uid: "reader_A", epoch: epoch)))
        let context = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID())
        f.preparation.holdNext = true
        let first = Task { await f.model.update(intent(context: context)) }
        try await f.preparation.waitForHeldPreparation()
        XCTAssertTrue(try XCTUnwrap(f.preparation.inputs.last).force)
        f.model.pause()
        f.preparation.finishHeldPreparation()
        await first.value
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertNil(f.model.clientRevision)
        f.model.resume()
        await f.model.update(intent(context: context))
        XCTAssertEqual(f.preparation.inputs.count, 2)
        XCTAssertEqual(f.preparation.inputs.filter(\.force).count, 1)
        XCTAssertEqual(f.preparation.record?.revision, 2)
        XCTAssertEqual(f.model.clientRevision, 2)
        XCTAssertEqual(f.transport.calls.count, 2)
    }

    func testChangedAccountOnResumeDoesNotAdoptPausedPreparationResult() async throws {
        let f = fixture()
        let a = PushAccountContext.authenticated(uid: "reader_A", epoch: epoch)
        let b = PushAccountContext.authenticated(uid: "reader_B", epoch: UUID())
        f.preparation.holdNext = true
        let updatingA = Task { await f.model.update(intent(context: a)) }
        try await f.preparation.waitForHeldPreparation()
        f.model.pause()
        f.preparation.finishHeldPreparation()
        await updatingA.value
        XCTAssertTrue(f.transport.calls.isEmpty)
        f.model.resume()
        f.transport.reply = { [self] _, ticket in receipt(revision: ticket.clientRevision) }
        await f.model.update(intent(context: b))
        XCTAssertEqual(f.preparation.inputs.count, 2)
        XCTAssertEqual(f.preparation.record?.revision, 2)
        XCTAssertEqual(f.model.clientRevision, 2)
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.transport.calls[0].ticket.context, b)
        XCTAssertEqual(f.preparation.record?.intentHash, try intent(context: b).fingerprint())
    }

    func testResumeCoalescesPreparationStillInFlight() async throws {
        let f = fixture()
        f.preparation.holdNext = true
        f.transport.reply = { [self] _, _ in receipt() }
        let first = Task { await f.model.update(intent()) }
        try await f.preparation.waitForHeldPreparation()
        f.model.pause(); f.model.resume()
        let resumed = Task { await f.model.update(intent()) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.preparation.inputs.count, 1)
        f.preparation.finishHeldPreparation()
        await first.value; await resumed.value
        XCTAssertEqual(f.transport.calls.count, 1)
        XCTAssertEqual(f.model.clientRevision, 1)
    }

    func testPausedConfirmationPreservesNonceAndDelayWhileIgnoringLateActive() async throws {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        f.transport.holdPaths = ["confirm"]
        let confirming = Task { await f.model.receiveChallenge(payload()) }
        try await f.transport.waitForCalls(2)
        let firstConfirm = f.transport.calls[1]
        f.model.pause()
        _ = await confirming.value
        f.transport.finish(1, with: .success(receipt(.active)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(f.model.isCurrent(firstConfirm.ticket))
        f.model.resume()
        guard case .retryWaiting(let due) = f.model.state else { return XCTFail("Canceled attempt consumes its retry budget") }
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.count, 2)
        f.clock.date = due
        f.transport.holdPaths = []
        f.transport.reply = { [self] _, _ in receipt(.active) }
        await f.model.synchronize()
        XCTAssertEqual(f.model.state, .active)
        XCTAssertEqual(f.transport.calls.count, 3)
        XCTAssertEqual(f.transport.calls[2].call, firstConfirm.call)
    }

    func testPausedLastConfirmationCannotRefundAttemptBudget() async throws {
        let f = fixture(maximumAttempts: 1)
        f.transport.reply = { [self] _, _ in receipt() }
        await f.model.update(intent())
        f.transport.holdPaths = ["confirm"]
        let confirming = Task { await f.model.receiveChallenge(payload()) }
        try await f.transport.waitForCalls(2)
        f.model.pause()
        _ = await confirming.value
        f.transport.finish(1, with: .success(receipt(.active)))
        f.model.resume()
        await f.model.update(intent())
        XCTAssertEqual(f.model.state, .blocked(.retryLimit))
        XCTAssertEqual(f.transport.calls.count, 2)
        XCTAssertNil(f.model.drivePlan.nextActionAt)
    }

    func testStagingEarlyChallengeCancelsRegisterObservationWithoutStartingConfirmation() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        XCTAssertTrue(f.model.stageChallenge(payload()))
        await updating.value
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register"])
        XCTAssertEqual(f.model.drivePlan.nextActionAt, f.clock.date)
        XCTAssertEqual(f.deadline.activeCount, 0)
        f.transport.reply = { [self] _, _ in receipt(.active) }
        await f.model.synchronize()
        XCTAssertEqual(f.transport.calls.map(\.call.path), ["register", "confirm"])
        XCTAssertEqual(f.model.state, .active)
        f.transport.finish(0, with: .success(receipt()))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.state, .active)
    }

    func testExplicitProofExpiryPerformsNoIOAndFencesLateActive() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        f.clock.date = try XCTUnwrap(f.preparation.record?.revisionStartedAt).addingTimeInterval(240)
        f.model.expireProofIfDue()
        XCTAssertFalse(f.model.isCurrent(f.transport.calls[0].ticket), "Expired proof must invalidate the exposed transport fence")
        await updating.value
        XCTAssertEqual(f.model.state, .proofExpired)
        XCTAssertNil(f.model.drivePlan.nextActionAt)
        XCTAssertNil(f.model.drivePlan.proofExpiresAt)
        f.transport.finish(0, with: .success(receipt(.active)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.state, .proofExpired)
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.transport.calls.count, 1)
    }

    func testDisposeDuringPreparationPermanentlyRejectsLateResultAndFutureInputs() async throws {
        let f = fixture()
        f.preparation.holdNext = true
        let updating = Task { await f.model.update(intent()) }
        try await f.preparation.waitForHeldPreparation()
        f.model.dispose()
        let disposed = f.model.drivePlan
        f.preparation.finishHeldPreparation()
        await updating.value
        f.model.resume(); f.model.pause(); f.model.expireProofIfDue()
        await f.model.update(intent()); await f.model.synchronize(); await f.model.renewExpiredProof()
        let accepted = await f.model.receiveChallenge(payload())
        XCTAssertFalse(accepted)
        XCTAssertEqual(f.model.drivePlan, disposed)
        XCTAssertTrue(disposed.isDisposed)
        XCTAssertNil(f.model.installationId)
        XCTAssertNil(f.model.clientRevision)
        XCTAssertNil(disposed.nextActionAt)
        XCTAssertNil(disposed.proofExpiresAt)
        XCTAssertEqual(f.preparation.record?.revision, 1, "Disposal cannot undo an already committing storage operation")
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertTrue(f.transport.calls.isEmpty)
    }

    func testDisposeDuringRegisterFencesLateReceiptWithoutDeletingIdentity() async throws {
        let f = fixture()
        f.transport.holdPaths = ["register"]
        let updating = Task { await f.model.update(intent()) }
        try await f.transport.waitForCalls(1)
        let oldTicket = f.transport.calls[0].ticket
        f.model.dispose()
        await updating.value
        let disposed = f.model.drivePlan
        f.transport.finish(0, with: .success(receipt(.active)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.drivePlan, disposed)
        XCTAssertFalse(f.model.isCurrent(oldTicket))
        XCTAssertEqual(f.deadline.activeCount, 0)
        XCTAssertEqual(f.preparation.record?.revision, 1)
    }

    func testPauseResumeOfConfirmedInstallationDoesNotRenewOrReplay() async {
        let f = fixture()
        f.transport.reply = { [self] _, _ in receipt(.active) }
        await f.model.update(intent())
        f.model.pause()
        f.clock.date = f.clock.date.addingTimeInterval(600)
        f.model.resume()
        await f.model.update(intent())
        XCTAssertEqual(f.model.state, .active)
        XCTAssertNil(f.model.drivePlan.nextActionAt)
        XCTAssertNil(f.model.drivePlan.proofExpiresAt)
        XCTAssertEqual(f.preparation.inputs.count, 1)
        XCTAssertEqual(f.transport.calls.count, 1)
    }

    func testMismatchedReceiptCannotClaimAnActiveInstallation() async {
        for incorrect in [receipt(.active, revision: 2), receipt(.active, installation: "33333333-3333-4333-8333-333333333333")] {
            let f = fixture()
            f.transport.reply = { _, _ in incorrect }
            await f.model.update(intent())
            XCTAssertEqual(f.model.state, .blocked(.invalidResponse))
            await f.model.synchronize()
            XCTAssertEqual(f.transport.calls.count, 1)
        }
    }
}

@MainActor
private final class PushModelFixture {
    let clock: PushModelClock
    let preparation: PushModelPreparation
    let transport: PushModelTransport
    let deadline: PushModelDeadline
    let model: PushRegistrationModel

    init(installation: String, key: String, maximumAttempts: Int, proofLifetime: TimeInterval) {
        let clock = PushModelClock(), transport = PushModelTransport(), deadline = PushModelDeadline()
        let preparation = PushModelPreparation(installation: installation, key: key)
        self.clock = clock; self.transport = transport; self.preparation = preparation; self.deadline = deadline
        model = PushRegistrationModel(prepare: { hash, date, force in
            try await preparation.prepare(hash: hash, date: date, force: force)
        }, send: { call, ticket in try await transport.send(call, ticket: ticket) },
                                      now: { clock.date }, schedule: { deadline.schedule($0) },
                                      maximumAttempts: maximumAttempts, proofLifetime: proofLifetime)
    }
}

@MainActor
private final class PushModelClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
private final class PushModelDeadline {
    private var nextID = 0
    private var callbacks: [Int: () -> Void] = [:]
    var activeCount: Int { callbacks.count }

    func schedule(_ callback: @escaping () -> Void) -> () -> Void {
        let id = nextID; nextID += 1
        callbacks[id] = callback
        return { [weak self] in self?.callbacks.removeValue(forKey: id) }
    }

    func fireNext() {
        guard let id = callbacks.keys.min(), let callback = callbacks.removeValue(forKey: id) else {
            return XCTFail("No registration observation deadline is pending")
        }
        callback()
    }
}

@MainActor
private final class PushModelPreparation {
    struct Input { let hash: String; let date: Date; let force: Bool }
    var inputs: [Input] = []
    var record: PushInstallationRecord?
    var failure: Error?
    var holdNext = false
    private let installation: String
    private let key: String
    private var held: (PushInstallationRecord, CheckedContinuation<PushInstallationRecord, Error>)?

    init(installation: String, key: String) { self.installation = installation; self.key = key }

    func prepare(hash: String, date: Date, force: Bool) async throws -> PushInstallationRecord {
        inputs.append(.init(hash: hash, date: date, force: force))
        if let failure { throw failure }
        var next = record ?? .init(installationId: installation, key: key)
        if force || next.intentHash != hash {
            next.revision += 1; next.intentHash = hash; next.revisionStartedAt = date
        }
        if holdNext {
            holdNext = false
            return try await withCheckedThrowingContinuation { held = (next, $0) }
        }
        record = next
        return next
    }

    func waitForHeldPreparation() async throws {
        for _ in 0..<1_000 {
            if held != nil { return }
            await Task.yield()
        }
        throw NSError(domain: "PushRegistrationModelTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected local durable preparation did not start"])
    }

    func finishHeldPreparation() {
        guard let (next, continuation) = held else { return XCTFail("No local preparation is waiting") }
        held = nil
        record = next
        continuation.resume(returning: next)
    }
}

@MainActor
private final class PushModelTransport {
    struct Call { let call: PushRegistrationCall; let ticket: PushRegistrationTicket }
    var calls: [Call] = []
    var holdPaths: Set<String> = []
    var reply: (PushRegistrationCall, PushRegistrationTicket) throws -> PushRegistrationReceipt = { _, _ in
        throw PushRegistrationFailure.invalidResponse
    }
    private var held: [Int: CheckedContinuation<PushRegistrationReceipt, Error>] = [:]

    func send(_ call: PushRegistrationCall, ticket: PushRegistrationTicket) async throws -> PushRegistrationReceipt {
        let index = calls.count
        calls.append(.init(call: call, ticket: ticket))
        if holdPaths.contains(call.path) {
            return try await withCheckedThrowingContinuation { held[index] = $0 }
        }
        return try reply(call, ticket)
    }

    func waitForCalls(_ count: Int) async throws {
        for _ in 0..<1_000 {
            if calls.count >= count { return }
            await Task.yield()
        }
        throw NSError(domain: "PushRegistrationModelTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Expected \(count) local transport calls, received \(calls.count)"])
    }

    func finish(_ index: Int, with result: Result<PushRegistrationReceipt, Error>) {
        guard let continuation = held.removeValue(forKey: index) else { return XCTFail("No transport operation \(index) is waiting") }
        continuation.resume(with: result)
    }
}
