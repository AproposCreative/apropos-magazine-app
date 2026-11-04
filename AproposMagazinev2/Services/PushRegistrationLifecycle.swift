import Combine
import Foundation

/// Local lifecycle kernel only. Constructing it is not authority to enable the
/// recipient route; no app composition, provider, endpoint or live scheduler is supplied here.
@MainActor
final class PushRegistrationLifecycle {
    typealias Schedule = (Date, @escaping () -> Void) -> (() -> Void)

    /// Account authority is supplied separately by the canonical authentication
    /// source. A delayed callback cannot promote its own account/epoch to current.
    struct Snapshot: Equatable {
        let context: PushAccountContext
        let permission: Bool?
        let preferences: PushRecipientPreferences?
        let preferencesContext: PushAccountContext?
        let token: String?
    }

    enum Status: Equatable {
        case waitingForAccount, waitingForPermission, waitingForPreferences
        case invalidInput, background, running, disposed
    }

    private struct IntentIdentity: Equatable {
        let context: PushAccountContext
        let permission: Bool
        let preferences: PushRecipientPreferences
        let token: String?
    }

    private let model: PushRegistrationModel
    private let now: () -> Date
    private let schedule: Schedule
    private var observation: AnyCancellable?
    private var accountContext = PushAccountContext.unresolved
    private var latestSnapshot: Snapshot?
    private var foreground = false
    private var disposed = false
    private var plan: PushRegistrationModel.DrivePlan
    private var mustApply = true
    private var requested = false
    private var driver: Task<Void, Never>?
    private var cancelWake: (() -> Void)?
    private var wakeID = UUID()
    private var wakeDate: Date?
    private var renewalIdentity: IntentIdentity?
    private var renewalUsed = false

    var status: Status {
        if disposed { return .disposed }
        guard accountContext.isValid else { return .waitingForAccount }
        guard let snapshot = latestSnapshot, snapshot.permission != nil else { return .waitingForPermission }
        guard snapshot.preferences != nil, snapshot.preferencesContext == accountContext else { return .waitingForPreferences }
        guard identity(snapshot) != nil else { return .invalidInput }
        return foreground ? .running : .background
    }

    init(model: PushRegistrationModel, now: @escaping () -> Date, schedule: @escaping Schedule) {
        self.model = model
        self.now = now
        self.schedule = schedule
        self.plan = model.drivePlan
        model.pause()
        observation = model.$drivePlan.sink { [weak self] value in
            // @Published sends before mutation. Always use this delivered value.
            self?.receive(value)
        }
    }

    /// Call only from the canonical authentication state source. Unknown is an
    /// explicit fence, never a guest identity. Same UID with a new epoch is new ownership.
    func setAccountContext(_ context: PushAccountContext) {
        guard !disposed, accountContext != context else { return }
        accountContext = context
        latestSnapshot = nil
        mustApply = true
        requested = false
        model.pause()
        clearWake()
    }

    /// Full snapshots avoid merging permission/preferences from unrelated callbacks.
    /// Nil is unknown; permission=false and preferences=off are explicit known values.
    @discardableResult
    func update(_ snapshot: Snapshot) -> Bool {
        guard !disposed, accountContext.isValid, snapshot.context == accountContext else { return false }
        guard snapshot.preferences == nil || snapshot.preferencesContext == accountContext else { return false }
        guard latestSnapshot != snapshot else { return true }
        let previousIdentity = latestSnapshot.flatMap(identity)
        latestSnapshot = snapshot
        let nextIdentity = identity(snapshot)
        if let nextIdentity, nextIdentity != renewalIdentity {
            renewalIdentity = nextIdentity
            renewalUsed = false
        }
        // Canonically equivalent selections must not cancel or restart a request.
        if previousIdentity != nil, previousIdentity == nextIdentity { return true }
        mustApply = true
        model.pause()
        clearWake()
        requestDrive()
        return true
    }

    func setForeground(_ value: Bool) {
        guard !disposed, foreground != value else { return }
        foreground = value
        if !value {
            model.pause()
            clearWake()
        } else {
            mustApply = true
            requestDrive()
        }
    }

    /// Staging releases an outstanding register observation so the one driver can
    /// confirm an early data challenge before a delayed HTTP response arrives.
    @discardableResult
    func receiveChallenge(_ payload: [String: String], context: PushAccountContext) -> Bool {
        guard !disposed, foreground, completeIntent != nil, !mustApply,
              context == accountContext, model.stageChallenge(payload) else { return false }
        requestDrive()
        return true
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        requested = false
        latestSnapshot = nil
        accountContext = .unresolved
        clearWake()
        observation?.cancel()
        observation = nil
        model.dispose()
        // Retain ownership until the task actually returns, including a local
        // durable preparation that ignores Task cancellation.
        driver?.cancel()
    }

    private var completeIntent: PushRegistrationIntent? {
        guard !disposed, accountContext.isValid, let snapshot = latestSnapshot,
              snapshot.context == accountContext, let permission = snapshot.permission,
              let preferences = snapshot.preferences, snapshot.preferencesContext == accountContext,
              identity(snapshot) != nil else { return nil }
        return .init(context: accountContext, permission: permission, preferences: preferences, token: snapshot.token)
    }

    private func identity(_ snapshot: Snapshot) -> IntentIdentity? {
        guard snapshot.context.isValid, let permission = snapshot.permission,
              let preferences = snapshot.preferences, snapshot.preferencesContext == snapshot.context,
              let normalized = try? preferences.normalized() else { return nil }
        let enabled = permission && (normalized.articles != .off || normalized.podcasts)
        if enabled, let token = snapshot.token {
            guard token.count >= 20, token.count <= 4096,
                  token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        }
        return .init(context: snapshot.context, permission: permission, preferences: normalized,
                     token: enabled ? snapshot.token : nil)
    }

    private var canDrive: Bool { !disposed && foreground && completeIntent != nil }

    private func requestDrive() {
        requested = true
        guard canDrive, driver == nil else { return }
        driver = Task { @MainActor [weak self] in await self?.runDriver() }
    }

    private func runDriver() async {
        defer {
            driver = nil
            if requested && canDrive { requestDrive() }
        }
        while requested && canDrive && !Task.isCancelled {
            requested = false
            if mustApply, let intent = completeIntent {
                // Resume may publish the retained old plan. mustApply remains
                // true until after resume, so it cannot drive old ownership.
                model.resume()
                mustApply = false
                await model.update(intent)
            } else {
                model.expireProofIfDue()
                if plan.state == .proofExpired, !renewalUsed, renewalIdentity != nil {
                    renewalUsed = true
                    await model.renewExpiredProof()
                } else if isDue(plan.nextActionAt) {
                    await model.synchronize()
                }
            }
            reconcile()
        }
    }

    private func receive(_ value: PushRegistrationModel.DrivePlan) {
        plan = value
        reconcile()
    }

    private func isDue(_ date: Date?) -> Bool {
        guard let date else { return false }
        let current = now()
        return current.timeIntervalSince1970.isFinite && current.timeIntervalSince1970 > 0 && date <= current
    }

    private func reconcile() {
        guard canDrive, !mustApply, !plan.isPaused, !plan.isDisposed else { clearWake(); return }
        let actionDue = isDue(plan.nextActionAt)
        let proofDate: Date?
        switch plan.state {
        case .registering, .pending, .confirming, .retryWaiting: proofDate = plan.proofExpiresAt
        default: proofDate = nil
        }
        let proofDue = isDue(proofDate)
        let renewalDue = plan.state == .proofExpired && !renewalUsed && renewalIdentity != nil
        if actionDue || proofDue || renewalDue {
            clearWake()
            requestDrive()
            return
        }
        let current = now()
        guard current.timeIntervalSince1970.isFinite, current.timeIntervalSince1970 > 0 else { clearWake(); return }
        let next = [plan.nextActionAt, proofDate].compactMap { $0 }.filter { $0 > current }.min()
        guard let next else { clearWake(); return }
        guard wakeDate != next else { return }
        clearWake()
        let id = UUID()
        wakeID = id
        wakeDate = next
        let cancel = schedule(next) { [weak self] in
            guard let self, self.wakeID == id, !self.disposed else { return }
            self.cancelWake = nil
            self.wakeDate = nil
            self.wakeID = UUID()
            guard self.canDrive, !self.mustApply else { return }
            // Expiry is synchronous: cancel the current observation before any
            // late transport completion can restore a pending proof.
            self.model.expireProofIfDue()
            self.requestDrive()
        }
        if wakeID == id, wakeDate == next { cancelWake = cancel } else { cancel() }
    }

    private func clearWake() {
        wakeID = UUID()
        wakeDate = nil
        let cancel = cancelWake
        cancelWake = nil
        cancel?()
    }
}
