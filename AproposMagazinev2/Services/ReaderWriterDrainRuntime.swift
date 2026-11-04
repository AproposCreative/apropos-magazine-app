import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Shared admission for favorite, bookmark-mirror, preference, profile and
/// account notification-token SDK/HTTP writes. Construction performs no SDK lookup; stopping/draining is explicit
/// and has no production caller until the deletion boundary is integrated.
@MainActor
final class ReaderWriterDrainRuntime {
    typealias Guard = ReaderWriterDrainCoordinator.Guard
    typealias Completion = ReaderWriterDrainCoordinator.Completion
    typealias Start = ReaderWriterDrainCoordinator.Start

    @MainActor
    struct CapturedWrite {
        fileprivate let operation: @MainActor () async throws -> Void
        fileprivate let permission: Guard
        func callAsFunction() async throws { try await operation() }
        /// Original ownership for feedback. A stop blocks future starts, but
        /// does not invalidate a legitimately completed pre-stop write.
        func isCurrent() -> Bool { permission() }
    }

    struct PendingWriteDrain: Sendable {
        /// Retains the exact client captured by the factory through its callback.
        let wait: @MainActor @Sendable (@escaping Completion) -> Void
    }

    static let shared = ReaderWriterDrainRuntime(
        canonical: AuthService.shared.state,
        actualUID: {
            guard !disabled else { return nil }
            return Auth.auth().currentUser?.uid
        },
        makeDrain: {
            guard !disabled else { throw CancellationError() }
            let firestore = Firestore.firestore()
            return PendingWriteDrain(wait: { completion in
                firestore.waitForPendingWrites(completion: completion)
            })
        },
        // Service-free hosts keep their explicit legacy fixture composition.
        // Actual application startup always shares the nonoptional disk gate.
        legacyAdmission: disabled ? nil : ReaderTransitionRecovery.application.admission
    )

    private static var disabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
    }

    private let canonical: CanonicalSessionState
    private let actualUID: @MainActor () -> String?
    private let coordinator: ReaderWriterDrainCoordinator
    private let legacyAdmission: ReaderLegacyWriteAdmission?
    private var transitionOwner: UUID?

    init(canonical: CanonicalSessionState,
         actualUID: @escaping @MainActor () -> String?,
         schedule: ReaderWriterDrainCoordinator.Schedule? = nil,
         makeDrain: @escaping @MainActor () throws -> PendingWriteDrain,
         maximumActiveWrites: Int = 16,
         legacyAdmission: ReaderLegacyWriteAdmission? = nil) {
        self.canonical = canonical
        self.actualUID = actualUID
        self.legacyAdmission = legacyAdmission
        coordinator = ReaderWriterDrainCoordinator(canonical: canonical, actualUID: actualUID,
            schedule: schedule, drainStart: { _, stillAdmitted, completion in
                do {
                    // Factory lookup can reenter/change the account. No SDK wait
                    // is enqueued without the final original-context guard.
                    let held = try makeDrain()
                    guard stillAdmitted() else { completion(CancellationError()); return }
                    held.wait { error in
                        // Keep the captured client alive even if the factory
                        // returned its only strong owner and the UI timed out.
                        withExtendedLifetime(held) { completion(error) }
                    }
                } catch { completion(error) }
            }, maximumActiveWrites: maximumActiveWrites)
    }

    /// The synchronous actor entry captures the original canonical generation.
    /// The caller's separate intent guard must retain its original model ticket,
    /// so a delayed invocation cannot adopt a new A -> guest -> A generation.
    func performWrite(expectedUserID: String, stillCurrent: @escaping Guard,
                      start: Start) async throws {
        let original = canonical.contextTicket()
        guard original.userID == expectedUserID else { throw CancellationError() }
        try await performWrite(original: original, stillCurrent: stillCurrent, start: start)
    }

    /// Callback entry points capture the canonical generation synchronously,
    /// before creating a Task. The resulting action is single-use and cannot
    /// adopt a later same-UID session. Capturing never starts an SDK operation.
    func captureWrite(expectedUserID: String, stillCurrent: @escaping Guard,
                      start: @escaping Start) -> CapturedWrite? {
        let original = canonical.contextTicket()
        guard original.userID == expectedUserID, !expectedUserID.isEmpty,
              !coordinator.isStopped, legacyAdmission?.isAllowed ?? true else { return nil }
        var denied = false
        let bound: Guard = { [self] in
            guard !denied, self.canonical.isCurrent(original) else { denied = true; return false }
            guard stillCurrent(), !denied, self.canonical.isCurrent(original),
                  self.legacyAdmission?.isAllowed ?? true else { denied = true; return false }
            return true
        }
        guard bound(), canonical.isCurrent(original), !coordinator.isStopped else { return nil }
        let feedback: Guard = { [self] in
            guard bound() else { return false }
            let uid = self.actualUID()
            // As in coordinator admission/completion, the provider getter is
            // the last external hook. Finish with pure original-owner checks;
            // invoking the caller again could mutate the UID just observed.
            guard uid == original.userID, !denied, self.canonical.isCurrent(original),
                  self.legacyAdmission?.isAllowed ?? true else { denied = true; return false }
            return true
        }
        var consumed = false
        return CapturedWrite(operation: { [self] in
            guard !consumed else { throw CancellationError() }
            consumed = true
            guard bound() else { throw CancellationError() }
            try await self.performWrite(original: original, stillCurrent: bound, start: start)
        }, permission: feedback)
    }

    private func performWrite(original: CanonicalSessionState.ContextTicket,
                              stillCurrent: @escaping Guard, start: Start) async throws {
        guard legacyAdmission?.isAllowed ?? true else { throw ReaderWriterDrainCoordinator.Failure.stopped }
        guard canonical.isCurrent(original) else { throw CancellationError() }
        // A configured recovery gate is checked throughout the original write,
        // including after the coordinator's arbitrary identity getter. Once an
        // attempt observes a closed gate it cannot revive when recovery changes.
        var admissionRevoked = false
        let permitted: Guard = { [self] in
            guard !admissionRevoked else { return false }
            guard stillCurrent(), self.legacyAdmission?.isAllowed ?? true else {
                admissionRevoked = true
                return false
            }
            return true
        }
        try await coordinator.performWrite(context: original, stillCurrent: permitted, start: { [self] lastGuard, completion in
            start({ [self] in
                guard !admissionRevoked, lastGuard() else { return false }
                guard self.legacyAdmission?.isAllowed ?? true else { admissionRevoked = true; return false }
                // Admission is stored actor state, not another arbitrary hook.
                // Finish with pure checks after the SDK identity/caller guards.
                return self.canonical.isCurrent(original) && !self.coordinator.isStopped && !Task.isCancelled
            }, completion)
        })
    }

    func stopWrites(context: CanonicalSessionState.ContextTicket) -> ReaderWriterDrainCoordinator.StopTicket? {
        coordinator.stopWrites(context: context)
    }

    /// Process-local exclusive owner, shared by every transition using this
    /// runtime. It survives logical cancellation/account changes until the
    /// original holder explicitly confirms that its physical work has ended.
    func reserveTransition(context: CanonicalSessionState.ContextTicket) -> UUID? {
        guard transitionOwner == nil, canonical.isCurrent(context), context.userID != nil else { return nil }
        let owner = UUID()
        transitionOwner = owner
        return owner
    }

    func ownsTransition(_ owner: UUID) -> Bool { transitionOwner == owner }

    /// Pure physical state; logical cancellation does not release SDK slots.
    var isPhysicallyIdle: Bool {
        coordinator.activeWriteCount == 0 && !coordinator.isDrainInFlight
    }

    @discardableResult
    func releaseTransition(owner: UUID, stillIdle: Guard) -> Bool {
        guard transitionOwner == owner else { return false }
        let idle = stillIdle()
        guard idle, transitionOwner == owner else { return false }
        // Releasing orchestration ownership never reopens or unseals writers.
        transitionOwner = nil
        return true
    }

    @discardableResult
    func sealStop(_ original: ReaderWriterDrainCoordinator.StopTicket) -> Bool {
        coordinator.sealStop(original)
    }

    /// Only the original transition owner may explicitly abandon a stop before
    /// side effects. The required predicate is a pure action/phase check.
    @discardableResult
    func abortStop(_ original: ReaderWriterDrainCoordinator.StopTicket, stillBeforeTransition: Guard) -> Bool {
        coordinator.abortStop(original, stillBeforeTransition: stillBeforeTransition)
    }

    func drain(_ ticket: ReaderWriterDrainCoordinator.StopTicket) async throws -> ReaderWriterDrainCoordinator.Receipt {
        try await coordinator.drain(ticket)
    }

    func waitForPhysicalIdle() async throws {
        try await coordinator.waitForPhysicalIdle()
    }

    func isCurrent(_ receipt: ReaderWriterDrainCoordinator.Receipt) -> Bool {
        coordinator.isCurrent(receipt)
    }
}
