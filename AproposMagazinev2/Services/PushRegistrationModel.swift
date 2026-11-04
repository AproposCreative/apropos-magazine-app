import Combine
import Foundation

/// Observation timeout, not a promise that an SDK/network operation was undone.
@MainActor
enum PushRegistrationDeadline {
    typealias Schedule = (@escaping () -> Void) -> (() -> Void)
    private final class Ticket<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var work: Task<Void, Never>?
        var cancelDeadline: (() -> Void)?
        var finished = false
        var beforeFailure: (@Sendable () -> Void)?
        func finish(_ result: Result<Value, Error>) {
            guard !finished else { return }
            finished = true
            if case .failure = result { beforeFailure?() }
            let continuation = self.continuation; self.continuation = nil
            cancelDeadline?(); cancelDeadline = nil
            work?.cancel(); work = nil
            continuation?.resume(with: result)
        }
    }
    static func perform<Value>(schedule: Schedule?, installCancellation: (@escaping () -> Void) -> Void,
                               beforeFailure: (@Sendable () -> Void)? = nil,
                               operation: @escaping () async throws -> Value) async throws -> Value {
        let ticket = Ticket<Value>()
        ticket.beforeFailure = beforeFailure
        let schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                action()
            }
            return { task.cancel() }
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ticket.continuation = continuation
                let cancel = schedule { ticket.finish(.failure(PushRegistrationFailure.transient(retryAfter: nil))) }
                ticket.cancelDeadline = cancel
                guard !ticket.finished else { cancel(); return }
                installCancellation { ticket.finish(.failure(PushRegistrationFailure.cancelled)) }
                guard !ticket.finished else { return }
                ticket.work = Task { @MainActor in
                    do { ticket.finish(.success(try await operation())) }
                    catch { ticket.finish(.failure(error)) }
                }
            }
        } onCancel: {
            beforeFailure?()
            Task { @MainActor in ticket.finish(.failure(PushRegistrationFailure.cancelled)) }
        }
    }
}

/// Inert until composed with a protected vault, explicit account context and transport.
/// Nonce/token/key stay private; published state never implies provider delivery.
@MainActor
final class PushRegistrationModel: ObservableObject {
    typealias Prepare = (String, Date, Bool) async throws -> PushInstallationRecord
    typealias RetainBinding = (PushAcknowledgedInstallationBinding, PushInstallationRecord, PushRegistrationBindingLease) async throws -> PushInstallationRecord
    typealias Send = (PushRegistrationCall, PushRegistrationTicket) async throws -> PushRegistrationReceipt
    struct DrivePlan: Equatable {
        let state: PushRegistrationState
        let generation: UUID
        let nextActionAt: Date?
        let proofExpiresAt: Date?
        let isPaused: Bool
        let isDisposed: Bool
    }
    @Published private(set) var drivePlan: DrivePlan
    @Published private(set) var state = PushRegistrationState.idle {
        didSet { publishDrivePlan() }
    }
    @Published private(set) var installationId: String?
    @Published private(set) var clientRevision: Int64?
    /// Available only after an original, negotiated receipt and actual vault readback.
    /// Recovery must still use readExisting and fresh server prepare/commit authority.
    private(set) var acknowledgedBinding: PushAcknowledgedInstallationBinding?
    private var bindingLease = PushRegistrationBindingLease()
    private let expectedAppID: String?
    private let retainBinding: RetainBinding?
    private let prepare: Prepare
    private let send: Send
    private let now: () -> Date
    private let schedule: PushRegistrationDeadline.Schedule?
    private let maximumAttempts: Int
    private let proofLifetime: TimeInterval
    private var desired: PushRegistrationIntent?
    private var record: PushInstallationRecord?
    private var persistedContext: PushAccountContext?
    private var generation = UUID()
    private var completedGeneration: UUID?
    private var registerAttempt: UUID?
    private var confirmAttempt: UUID?
    private var registerCount = 0
    private var confirmCount = 0
    private var registerRetryAt: Date?
    private var confirmRetryAt: Date?
    private var expectedChallengeId: String?
    private var challenge: (id: String, nonce: String)?
    private var awaitingToken = false
    private var cancellations: [UUID: () -> Void] = [:]
    private var isPaused = false
    private var isDisposed = false
    private struct Preparation {
        let id: UUID
        let fingerprint: String
        let context: PushAccountContext
        let awaitingToken: Bool
        let task: Task<PushInstallationRecord, Error>
    }
    private var preparation: Preparation?
    private let pendingReplayInterval: TimeInterval = 30

    init(prepare: @escaping Prepare, send: @escaping Send, expectedAppID: String? = nil,
         retainBinding: RetainBinding? = nil, now: @escaping () -> Date = Date.init,
         schedule: PushRegistrationDeadline.Schedule? = nil, maximumAttempts: Int = 3, proofLifetime: TimeInterval = 240) {
        precondition((1...10).contains(maximumAttempts) && proofLifetime > 0 && proofLifetime <= 300)
        self.prepare = prepare; self.send = send; self.now = now; self.schedule = schedule
        self.expectedAppID = expectedAppID; self.retainBinding = retainBinding
        self.maximumAttempts = maximumAttempts; self.proofLifetime = proofLifetime
        drivePlan = DrivePlan(state: .idle, generation: generation, nextActionAt: nil,
                              proofExpiresAt: nil, isPaused: false, isDisposed: false)
    }

    /// Existing model/vault composition, still inert until the lifecycle supplies intent.
    convenience init(vault: PushInstallationVault, expectedAppID: String, send: @escaping Send,
                     now: @escaping () -> Date = Date.init, schedule: PushRegistrationDeadline.Schedule? = nil) {
        self.init(prepare: { hash, date, force in
            try await vault.prepare(intentHash: hash, at: date, forceNewRevision: force)
        }, send: send, expectedAppID: expectedAppID, retainBinding: { binding, original, lease in
            try await vault.acknowledge(binding, original: original, lease: lease)
        }, now: now, schedule: schedule)
    }

    func update(_ input: PushRegistrationIntent) async {
        guard !isPaused, !isDisposed else { return }
        defer { publishDrivePlan() }
        guard input.context.isResolved else {
            invalidate(); desired = nil; record = nil; state = .waitingForAccount; return
        }
        let value: PushRegistrationIntent
        let tokenMissing = input.enabled && input.token == nil
        do {
            if tokenMissing {
                // Remove the previous owner's server eligibility even while FCM is unavailable.
                // This is a transport snapshot; the reader's requested preferences are retained.
                value = try PushRegistrationIntent(context: input.context, permission: false,
                    preferences: input.preferences, token: nil).normalized()
            } else { value = try input.normalized() }
        }
        catch { invalidate(); desired = nil; record = nil; state = .blocked(.invalidIntent); return }
        if value == desired, awaitingToken == tokenMissing, record != nil { await synchronize(); return }
        let force = persistedContext.map { $0 != value.context } ?? false
        await prepareDesired(value, force: force, awaitingToken: tokenMissing)
    }

    private func prepareDesired(_ value: PushRegistrationIntent, force: Bool, awaitingToken: Bool = false) async {
        guard !isPaused, !isDisposed else { return }
        let fingerprint: String
        do { fingerprint = try value.fingerprint() }
        catch { block(.invalidIntent); return }
        let pending: Preparation
        if let existing = preparation, existing.fingerprint == fingerprint,
           existing.context == value.context, existing.awaitingToken == awaitingToken {
            // A paused durable transaction may already have committed. Observe its
            // original result instead of performing the forced revision twice.
            pending = existing
        } else {
            invalidate(); desired = value; record = nil
            self.awaitingToken = awaitingToken
            let date = now()
            guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0 else { state = .blocked(.clock); return }
            let prepare = prepare
            pending = Preparation(id: UUID(), fingerprint: fingerprint, context: value.context,
                                  awaitingToken: awaitingToken,
                                  task: Task { try await prepare(fingerprint, date, force) })
            preparation = pending
        }
        state = .preparing
        let stamp = generation
        defer { publishDrivePlan() }
        do {
            let snapshot = try await pending.task.value
            guard generation == stamp, !isPaused, !isDisposed, preparation?.id == pending.id else { return }
            preparation = nil
            try snapshot.validate()
            guard snapshot.intentHash == fingerprint, snapshot.revision > 0 else { state = .blocked(.storage); return }
            record = snapshot; persistedContext = value.context
            installationId = snapshot.installationId; clientRevision = snapshot.revision
            await synchronize()
        } catch {
            guard generation == stamp, !isPaused, !isDisposed, preparation?.id == pending.id else { return }
            preparation = nil
            state = .blocked(.storage)
        }
    }

    /// Ordinary retries retain the durably committed body/revision and never reset a conflict.
    func synchronize() async {
        guard !isPaused, !isDisposed else { return }
        defer { publishDrivePlan() }
        guard let value = desired, let snapshot = record, completedGeneration != generation, !isBlocked else { return }
        if value.enabled, !proofIsValid(snapshot) { return }
        if challenge != nil { await confirmCurrent(); return }
        guard registerAttempt == nil, due(registerRetryAt) else { return }
        guard registerCount < maximumAttempts else {
            // An accepted pending request can still receive a valid proof. Exhausted
            // replay allowance is not evidence that its challenge was rejected.
            if value.enabled { state = .pending } else { block(.retryLimit) }
            return
        }
        registerCount += 1
        let id = UUID(), ticket = ticket(snapshot, context: value.context)
        registerAttempt = id; state = .registering
        let call = PushRegistrationCall.register(.init(installationId: snapshot.installationId, key: snapshot.key,
            clientRevision: snapshot.revision, permission: value.permission, preferences: value.preferences, token: value.token))
        defer { cancellations.removeValue(forKey: id); if registerAttempt == id { registerAttempt = nil }; publishDrivePlan() }
        do {
            let receipt = try await perform(call, ticket: ticket, id: id)
            guard isCurrent(ticket), registerAttempt == id, completedGeneration != generation else { return }
            guard valid(receipt, ticket: ticket) else { block(.invalidResponse); return }
            switch receipt.status {
            case .active, .disabled:
                guard (receipt.status == .active) == value.enabled else { block(.invalidResponse); return }
                guard await acknowledge(receipt, snapshot: snapshot, ticket: ticket, attempt: id),
                      isCurrent(ticket), registerAttempt == id, completedGeneration != generation else { return }
                complete(receipt.status == .active ? .active : awaitingToken ? .waitingForToken : .disabled, except: id)
            case .pending:
                guard value.enabled, let challengeId = receipt.challengeId else { block(.invalidResponse); return }
                if let expectedChallengeId, expectedChallengeId != challengeId { block(.challengeMismatch); return }
                guard await acknowledge(receipt, snapshot: snapshot, ticket: ticket, attempt: id),
                      isCurrent(ticket), registerAttempt == id, completedGeneration != generation else { return }
                let date = now()
                guard isCurrent(ticket), registerAttempt == id, completedGeneration != generation else { return }
                guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0 else { block(.clock); return }
                expectedChallengeId = challengeId
                registerRetryAt = date.addingTimeInterval(pendingReplayInterval)
                if challenge == nil { state = .pending }
            }
        } catch {
            guard isCurrent(ticket), registerAttempt == id, completedGeneration != generation, challenge == nil else { return }
            handle(error, attempts: registerCount, confirming: false)
        }
    }

    /// Stages a valid data challenge without starting transport. Cancelling the
    /// register observation lets a single lifecycle driver promptly confirm it.
    @discardableResult
    func stageChallenge(_ payload: [String: String]) -> Bool {
        guard !isPaused, !isDisposed else { return false }
        defer { publishDrivePlan() }
        guard let value = desired, value.enabled, let snapshot = record, completedGeneration != generation, !isBlocked,
              payload["type"] == "verify_push_installation", payload["installation_id"] == snapshot.installationId,
              payload["client_revision"] == String(snapshot.revision),
              let id = payload["challenge_id"], PushRegistrationValidation.validHash(id),
              let nonce = payload["nonce"], PushRegistrationValidation.validPrivateValue(nonce) else { return false }
        guard proofIsValid(snapshot) else { return false }
        if let existing = challenge {
            guard existing.id == id, existing.nonce == nonce else { block(.challengeMismatch); return false }
        } else {
            if let expectedChallengeId, expectedChallengeId != id { block(.challengeMismatch); return false }
            challenge = (id, nonce); expectedChallengeId = id
        }
        cancelRequests(except: confirmAttempt)
        if confirmAttempt == nil {
            state = confirmRetryAt.map { .retryWaiting(until: $0) } ?? .pending
        }
        return true
    }

    /// A valid data challenge may precede the register HTTP response.
    @discardableResult
    func receiveChallenge(_ payload: [String: String]) async -> Bool {
        guard stageChallenge(payload) else { return false }
        await confirmCurrent()
        return true
    }

    private func confirmCurrent() async {
        guard !isPaused, !isDisposed else { return }
        guard let value = desired, let snapshot = record, let challenge, confirmAttempt == nil,
              completedGeneration != generation, !isBlocked, due(confirmRetryAt), proofIsValid(snapshot) else { return }
        guard confirmCount < maximumAttempts else { block(.retryLimit); return }
        confirmCount += 1
        let id = UUID(), ticket = ticket(snapshot, context: value.context)
        confirmAttempt = id; state = .confirming
        let call = PushRegistrationCall.confirm(.init(installationId: snapshot.installationId, key: snapshot.key,
            challengeId: challenge.id, nonce: challenge.nonce))
        defer { cancellations.removeValue(forKey: id); if confirmAttempt == id { confirmAttempt = nil }; publishDrivePlan() }
        do {
            let receipt = try await perform(call, ticket: ticket, id: id)
            guard isCurrent(ticket), confirmAttempt == id, completedGeneration != generation else { return }
            guard valid(receipt, ticket: ticket), receipt.status == .active else { block(.invalidResponse); return }
            guard await acknowledge(receipt, snapshot: snapshot, ticket: ticket, attempt: id),
                  isCurrent(ticket), confirmAttempt == id, completedGeneration != generation else { return }
            complete(.active, except: id)
        } catch {
            guard isCurrent(ticket), confirmAttempt == id, completedGeneration != generation else { return }
            handle(error, attempts: confirmCount, confirming: true)
        }
    }

    /// Explicit local expiry recovery; a generic 409 is never authority to advance/reset a revision.
    func renewExpiredProof() async {
        guard !isPaused, !isDisposed else { return }
        defer { publishDrivePlan() }
        guard state == .proofExpired, let value = desired, let snapshot = record, let start = snapshot.revisionStartedAt,
              now().timeIntervalSince(start) >= proofLifetime else { return }
        await prepareDesired(value, force: true)
    }

    /// Stops observation immediately without refunding an already started attempt.
    /// A durable preparation may still commit; its result is retained for resume.
    func pause() {
        guard !isPaused, !isDisposed else { return }
        bindingLease.revoke(); acknowledgedBinding = nil
        let wasCompleted = completedGeneration == generation
        let registering = registerAttempt != nil, confirming = confirmAttempt != nil
        isPaused = true
        generation = UUID()
        completedGeneration = wasCompleted ? generation : nil
        cancelRequests()
        if confirming { pausedAttempt(attempts: confirmCount, confirming: true) }
        else if registering { pausedAttempt(attempts: registerCount, confirming: false) }
        publishDrivePlan()
    }

    /// Local only. The lifecycle owner supplies the latest complete intent before driving.
    func resume() {
        guard isPaused, !isDisposed else { return }
        bindingLease = PushRegistrationBindingLease()
        isPaused = false
        expireProofIfDue()
        publishDrivePlan()
    }

    /// No storage deletion or replacement. Every later callback/input is inert.
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true; isPaused = true
        invalidate()
        desired = nil; record = nil; persistedContext = nil
        state = .idle
        publishDrivePlan()
    }

    /// Observes the original durable proof deadline without transport or storage.
    func expireProofIfDue() {
        guard !isDisposed, let desired, desired.enabled, let record,
              completedGeneration != generation, !isBlocked else { return }
        _ = proofIsValid(record)
        publishDrivePlan()
    }

    private func pausedAttempt(attempts: Int, confirming: Bool) {
        if attempts >= maximumAttempts {
            if !confirming, desired?.enabled == true { state = .pending }
            else { block(.retryLimit) }
            return
        }
        let date = now()
        guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0 else { block(.clock); return }
        let earliest = date.addingTimeInterval(5 * pow(2, Double(max(0, attempts - 1))))
        let prior = confirming ? confirmRetryAt : registerRetryAt
        let due = max(prior ?? earliest, earliest)
        if confirming { confirmRetryAt = due } else { registerRetryAt = due }
        state = .retryWaiting(until: due)
    }

    private func publishDrivePlan() {
        let expiry = desired?.enabled == true && completedGeneration != generation && !isBlocked
            ? record?.revisionStartedAt?.addingTimeInterval(proofLifetime) : nil
        var next: Date?
        if !isPaused, !isDisposed, !isBlocked, completedGeneration != generation,
           desired != nil, record != nil {
            next = expiry
            let retry: Date?
            if challenge != nil {
                retry = confirmAttempt == nil && confirmCount < maximumAttempts ? confirmRetryAt ?? now() : nil
            } else {
                retry = registerAttempt == nil && registerCount < maximumAttempts ? registerRetryAt ?? now() : nil
            }
            if let retry { next = next.map { min($0, retry) } ?? retry }
        }
        let value = DrivePlan(state: state, generation: generation, nextActionAt: next,
                              proofExpiresAt: expiry, isPaused: isPaused, isDisposed: isDisposed)
        if value != drivePlan { drivePlan = value }
    }

    func isCurrent(_ ticket: PushRegistrationTicket) -> Bool {
        !isPaused && !isDisposed && !isBlocked && ticket.generation == generation && ticket.context == desired?.context && ticket.installationId == record?.installationId && ticket.clientRevision == record?.revision
    }
    private func ticket(_ snapshot: PushInstallationRecord, context: PushAccountContext) -> PushRegistrationTicket {
        .init(generation: generation, context: context, installationId: snapshot.installationId, clientRevision: snapshot.revision)
    }
    private func perform(_ call: PushRegistrationCall, ticket: PushRegistrationTicket, id: UUID) async throws -> PushRegistrationReceipt {
        let send = send
        return try await PushRegistrationDeadline.perform(schedule: schedule, installCancellation: { [weak self] cancel in
            self?.cancellations[id] = cancel
        }, operation: { try await send(call, ticket) })
    }
    private var isBlocked: Bool {
        if case .blocked = state { return true }
        return state == .proofExpired
    }
    private func due(_ date: Date?) -> Bool { date.map { now() >= $0 } ?? true }
    private func proofIsValid(_ snapshot: PushInstallationRecord) -> Bool {
        guard let start = snapshot.revisionStartedAt else { block(.storage); return false }
        let age = now().timeIntervalSince(start)
        guard age.isFinite, age >= 0 else { block(.clock); return false }
        guard age < proofLifetime else {
            bindingLease.revoke(); acknowledgedBinding = nil
            challenge = nil; expectedChallengeId = nil; cancelRequests(); state = .proofExpired; return false
        }
        return true
    }
    private func valid(_ receipt: PushRegistrationReceipt, ticket: PushRegistrationTicket) -> Bool {
        if let expectedAppID {
            guard let binding = receipt.binding, binding.matches(receipt, ticket: ticket, expectedAppID: expectedAppID),
                  retainBinding != nil else { return false }
        } else if receipt.binding != nil { return false }
        guard receipt.installationId == ticket.installationId, receipt.clientRevision == ticket.clientRevision else { return false }
        if receipt.status == .pending { return receipt.challengeId.map(PushRegistrationValidation.validHash) == true }
        return receipt.challengeId == nil && receipt.revision.map { $0 > 0 && $0 <= PushRegistrationValidation.maximumRevision } == true
    }
    private func acknowledge(_ receipt: PushRegistrationReceipt, snapshot: PushInstallationRecord,
                             ticket: PushRegistrationTicket, attempt: UUID) async -> Bool {
        guard expectedAppID != nil else { return true } // Legacy mode never invents binding evidence.
        guard let binding = receipt.binding, let retainBinding, currentAcknowledgement(ticket, attempt: attempt) else { return false }
        let lease = PushRegistrationBindingLease(parent: bindingLease)
        defer { lease.revoke() }
        do {
            let stored = try await PushRegistrationDeadline.perform(schedule: schedule, installCancellation: { [weak self] cancel in
                self?.cancellations[attempt] = cancel
            }, beforeFailure: { lease.revoke() }, operation: {
                guard !Task.isCancelled, lease.isValid else { throw PushRegistrationFailure.cancelled }
                return try await retainBinding(binding, snapshot, lease)
            })
            guard !Task.isCancelled, lease.isValid, currentAcknowledgement(ticket, attempt: attempt) else { return false }
            try stored.validate()
            guard stored.installationId == snapshot.installationId, stored.key == snapshot.key,
                  stored.revision == snapshot.revision, stored.intentHash == snapshot.intentHash,
                  stored.revisionStartedAt == snapshot.revisionStartedAt,
                  stored.acknowledgedBinding == binding else { throw PushInstallationVaultError.invalidRecord }
            record = stored
            acknowledgedBinding = binding
            return true
        } catch {
            // Revocation never refunds a physical transaction that already entered.
            lease.revoke()
            guard currentAcknowledgement(ticket, attempt: attempt) else { return false }
            block(.storage)
            return false
        }
    }

    private func currentAcknowledgement(_ ticket: PushRegistrationTicket, attempt: UUID) -> Bool {
        isCurrent(ticket) && completedGeneration != generation &&
            (registerAttempt == attempt || confirmAttempt == attempt)
    }

    private func handle(_ error: Error, attempts: Int, confirming: Bool) {
        switch error as? PushRegistrationFailure {
        case .authentication: block(.authentication)
        case .forbidden: block(.forbidden)
        case .conflict: block(.conflict)
        case .invalidResponse: block(.invalidResponse)
        case .transient(let supplied):
            retry(attempts: attempts, confirming: confirming, supplied: supplied)
        default: retry(attempts: attempts, confirming: confirming, supplied: nil)
        }
    }
    private func retry(attempts: Int, confirming: Bool, supplied: TimeInterval?) {
        guard attempts < maximumAttempts else {
            if !confirming, desired?.enabled == true { state = .pending; registerRetryAt = nil }
            else { block(.retryLimit) }
            return
        }
        if let supplied, !supplied.isFinite || supplied < 0 { block(.invalidResponse); return }
        let date = now()
        guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0 else { block(.clock); return }
        let until = date.addingTimeInterval(max(5 * pow(2, Double(attempts - 1)), supplied ?? 0))
        guard until.timeIntervalSince1970.isFinite else { block(.invalidResponse); return }
        if confirming { confirmRetryAt = until } else { registerRetryAt = until }
        state = .retryWaiting(until: until)
    }
    private func complete(_ value: PushRegistrationState, except id: UUID) {
        completedGeneration = generation; state = value; challenge = nil; expectedChallengeId = nil
        cancelRequests(except: id)
    }
    private func block(_ reason: PushRegistrationBlock) {
        bindingLease.revoke(); acknowledgedBinding = nil
        state = .blocked(reason); challenge = nil; cancelRequests()
    }
    private func cancelRequests(except retained: UUID? = nil) {
        let cancel = cancellations.filter { $0.key != retained }
        for (id, action) in cancel { cancellations.removeValue(forKey: id); action() }
        if registerAttempt != retained { registerAttempt = nil }
        if confirmAttempt != retained { confirmAttempt = nil }
    }
    private func invalidate() {
        bindingLease.revoke(); bindingLease = PushRegistrationBindingLease(); acknowledgedBinding = nil
        generation = UUID(); completedGeneration = nil; cancelRequests()
        registerCount = 0; confirmCount = 0; registerRetryAt = nil; confirmRetryAt = nil
        expectedChallengeId = nil; challenge = nil
        preparation?.task.cancel(); preparation = nil
        awaitingToken = false
        installationId = nil; clientRevision = nil
    }
}
