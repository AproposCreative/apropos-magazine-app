import Combine
import Foundation

/// One explicitly shared process state for the future startup composition.
/// This does not observe or stop a real Firestore client. Every path capable of
/// creating a reference must participate before this can be used in production.
@MainActor
final class ReaderSDKStartupState {
    /// A local marker only denies legacy startup; its absence is not proof of
    /// an empty SDK queue or deployed server protection. Service-free hosts
    /// keep their existing inert composition; tests inject real local recovery.
    static let application: ReaderSDKStartupState = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled {
            return ReaderSDKStartupState(legacyApplicationStartup: true)
        }
        return ReaderSDKStartupState(legacyRecovery: .application)
    }()
    let changes = PassthroughSubject<Void, Never>()
    let localRecovery: ReaderTransitionRecovery?
    private var localBootstrapReady = false
    private var localReaderPrepared = false
    private var didPublishLocalReadiness = false
    private var localPreparationAttempted = false
    private var hasReadLocalRecovery = false
    private var hasOpenedLocalServices = false
    private var localRecoveryObservation: AnyCancellable?
    enum Status: Equatable { case idle, preparing, attempted, started, uncertain }
    private(set) var status: Status
    private var owner: UUID?
    private let legacyApplicationStartup: Bool
    var requiresGuardedStartup: Bool { !legacyApplicationStartup }
    private var admittedContext: CanonicalSessionState.ContextTicket?
    init(alreadyInitialized: Bool = false) {
        legacyApplicationStartup = false
        localRecovery = nil
        status = alreadyInitialized ? .uncertain : .idle
    }
    private init(legacyApplicationStartup: Bool) {
        self.legacyApplicationStartup = legacyApplicationStartup
        localRecovery = nil
        status = .uncertain
    }
    init(legacyRecovery: ReaderTransitionRecovery) {
        legacyApplicationStartup = true
        localRecovery = legacyRecovery
        status = .uncertain
        localRecoveryObservation = legacyRecovery.changes.sink { [weak self] in
            guard let self, self.localBootstrapReady, self.localRecovery?.legacyWritesPermitted != true else { return }
            // Closing is immediate. Opening is published only after the actual
            // AppDelegate reader preparation and original Auth publication.
            self.localBootstrapReady = false
            self.changes.send()
        }
    }

    func prepareLocalRecovery() async throws {
        guard let localRecovery, !localPreparationAttempted else { throw ReaderTransitionRecoveryStore.Failure.readFailed }
        localPreparationAttempted = true // Reserve before the first disk hook.
        do {
            try await localRecovery.bootstrap()
            hasReadLocalRecovery = true
            try Task.checkCancellation()
            guard localRecovery.legacyWritesPermitted else { throw ReaderTransitionRecoveryStore.Failure.readFailed }
            hasOpenedLocalServices = true
            localBootstrapReady = true
        } catch {
            localBootstrapReady = false
            throw error
        }
    }

    /// Only a cold process that has read the sealed installation and never
    /// exposed reader work may use Auth-only recovery without starting/draining
    /// Firestore. This is local denial, never server or membership authority.
    func permitsAuthOnlyDeletionRecovery(_ recovery: ReaderTransitionRecovery) -> Bool {
        legacyApplicationStartup && localRecovery === recovery && hasReadLocalRecovery
            && !hasOpenedLocalServices && recovery.hasSealAttempt && !recovery.legacyWritesPermitted
    }

    func finishLocalPreparation() {
        guard localBootstrapReady, localRecovery?.legacyWritesPermitted == true else { return }
        localReaderPrepared = true
    }

    func permitsReaderPublication(identity: CanonicalSessionState) -> Bool {
        permitsReaderServices(identity: identity) && (localRecovery == nil || localReaderPrepared)
    }

    func publishLocalReadiness() {
        guard !didPublishLocalReadiness, localBootstrapReady, localReaderPrepared,
              localRecovery?.legacyWritesPermitted == true else { return }
        didPublishLocalReadiness = true // Reserve before observers can reenter.
        changes.send()
    }

    func closeLocalReadiness() {
        guard localRecovery != nil else { return }
        localBootstrapReady = false
        changes.send()
    }

    /// Startup readiness only, never current write/deletion authority. Guarded
    /// guest startup remains unsupported; the legacy guest path stays explicit.
    func permitsReaderServices(identity: CanonicalSessionState) -> Bool {
        if legacyApplicationStartup {
            guard let localRecovery else { return true }
            return localBootstrapReady && localRecovery.legacyWritesPermitted
        }
        guard status == .started, let admittedContext else { return false }
        return identity.isCurrent(admittedContext)
    }
    /// Captures before any Task/reference. A legacy unresolved start is an
    /// explicit compatibility decision, not a confirmed guest or fence proof.
    func captureReaderWork(identity: CanonicalSessionState, actualUserID: @escaping @MainActor () -> String?) -> (@MainActor () -> Bool)? {
        let original = identity.contextTicket()
        let uid = actualUserID() // May reenter; validate after the hook.
        guard identity.isCurrent(original), permitsReaderServices(identity: identity),
              original.context == .unresolved || original.userID == uid else { return nil }
        return { [self] in
            let currentUID = actualUserID()
            return identity.isCurrent(original) && currentUID == uid && permitsReaderServices(identity: identity)
        }
    }

    /// If the original Auth publication fails after physical startup, never
    /// leave its readiness usable. Physical initialization cannot be undone,
    /// so the process remains uncertain rather than retrying from idle.
    func revokeReaderContext(_ context: CanonicalSessionState.ContextTicket) {
        guard admittedContext == context else { return }
        admittedContext = nil
        status = .uncertain
    }

    fileprivate func reserve(_ id: UUID) -> Bool {
        guard status == .idle else { return false }
        owner = id; status = .preparing; return true
    }
    fileprivate func owns(_ id: UUID) -> Bool { owner == id }
    fileprivate func attempt(_ id: UUID) -> Bool {
        guard owns(id), status == .preparing else { return false }
        status = .attempted; return true
    }
    fileprivate func complete(_ id: UUID, success: Bool) {
        guard owns(id), status == .attempted else { return }
        status = success ? .started : .uncertain
    }
    fileprivate func acceptReaderContext(_ id: UUID, context: CanonicalSessionState.ContextTicket) -> Bool {
        guard owns(id), status == .started, admittedContext == nil else { return false }
        admittedContext = context
        return true
    }
    fileprivate func releasePreparation(_ id: UUID) {
        guard owns(id), status == .preparing else { return }
        owner = nil; status = .idle
    }
}

/// Inactive ordering seam. No default verifier, SDK adapter, singleton or live
/// caller exists. A member/resource snapshot alone can never start the SDK.
@MainActor
final class ReaderStartupCoordinator {
    typealias Context = CanonicalSessionState.ContextTicket
    typealias Marker = ReaderTransitionRecoveryStore.Marker
    typealias MembershipRequest = ReaderAuthoritativeReadContract.MembershipRequest
    typealias MembershipSnapshot = ReaderAuthoritativeReadContract.MembershipSnapshot
    typealias Schedule = @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void)
    typealias Verifier = @MainActor (Challenge) async throws -> Permit
    typealias StartAdmission = @MainActor () throws -> Void
    enum Failure: Error, Equatable {
        case unavailable, busy, stale, timedOut, cancelled, markerMismatch, invalidPermit, expired, sdkAlreadyStarted
    }

    struct Configuration: Equatable, Sendable {
        let projectID: String
        let appID: String
        let installationID: UUID
        let writerFenceRevision: String
        let migrationRevision: String
        init(projectID: String, appID: String, installationID: UUID,
             writerFenceRevision: String, migrationRevision: String) throws {
            guard Self.validID(projectID), Self.validID(appID),
                  Self.validHash(writerFenceRevision), Self.validHash(migrationRevision) else { throw Failure.invalidPermit }
            self.projectID = projectID; self.appID = appID; self.installationID = installationID
            self.writerFenceRevision = writerFenceRevision; self.migrationRevision = migrationRevision
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            Data(lhs.projectID.utf8) == Data(rhs.projectID.utf8) && Data(lhs.appID.utf8) == Data(rhs.appID.utf8)
                && lhs.installationID == rhs.installationID && lhs.writerFenceRevision == rhs.writerFenceRevision
                && lhs.migrationRevision == rhs.migrationRevision
        }
        private static func validID(_ value: String) -> Bool {
            (1...256).contains(value.utf8.count) && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        fileprivate static func validHash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
    struct Challenge: Equatable, Sendable {
        let configuration: Configuration
        let context: Context
        let binding: ReaderMembershipContract.Binding
        let marker: Marker?
        let readID: String
    }
    enum Coverage: Equatable, Sendable { case allPersistedWritersIncludingPreviousAccounts, currentReaderOnly }
    /// A trusted verifier must attest the installation-wide deployed boundary,
    /// including old-account/legacy SDK backlog. These fields are not a wire
    /// decoder or a deployment check. No production producer is supplied.
    struct Permit: Equatable, Sendable {
        let challenge: Challenge
        let coverage: Coverage
        let writerFenceRevision: String
        let migrationRevision: String
        let validUntilMs: Int64
    }
    /// Opaque, one-attempt context passed to the injected starter and returned
    /// only after it completes. Never current read/write or deletion authority.
    struct Receipt: Equatable, Sendable {
        let challenge: Challenge
        fileprivate let validUntilMs: Int64
        fileprivate init(challenge: Challenge, validUntilMs: Int64) {
            self.challenge = challenge; self.validUntilMs = validUntilMs
        }
    }

    private final class Flight {
        let id: UUID
        let context: Context
        let cancellation: ReaderStartupCancellationFlag
        var continuation: CheckedContinuation<Receipt, Error>?
        var cancelDeadline: (@MainActor () -> Void)?
        var revoked: Failure?
        var admitted = false
        var successValidUntilMs: Int64?
        init(id: UUID, context: Context, cancellation: ReaderStartupCancellationFlag,
             continuation: CheckedContinuation<Receipt, Error>) {
            self.id = id; self.context = context; self.cancellation = cancellation; self.continuation = continuation
        }
    }
    private let canonical: CanonicalSessionState
    private let sdkState: ReaderSDKStartupState
    private let configuration: Configuration
    private let readMarker: @MainActor () async throws -> Marker?
    private let readMembership: @MainActor (MembershipRequest) async throws -> MembershipSnapshot
    private let verify: Verifier?
    private let startSDK: @MainActor (Receipt, @escaping StartAdmission) async throws -> Void
    private let now: @MainActor () -> Int64
    private let schedule: Schedule
    private var flight: Flight?
    private var observation: AnyCancellable?
    var isBusy: Bool { flight != nil }

    /// A suspended credential/HTTP adapter must consult the original flight,
    /// not only account equality, before starting its next physical operation.
    /// This is local request admission, never a server or SDK-start permit.
    func permitsAuthorityTransport(context: Context) -> Bool {
        guard let held = flight, held.context == context, held.revoked == nil,
              !held.cancellation.isCancelled, sdkState.owns(held.id), sdkState.status == .preparing,
              canonical.isCurrent(context) else { return false }
        return true
    }

    init(canonical: CanonicalSessionState, sdkState: ReaderSDKStartupState, configuration: Configuration,
         readMarker: @escaping @MainActor () async throws -> Marker?,
         readMembership: @escaping @MainActor (MembershipRequest) async throws -> MembershipSnapshot,
         verify: Verifier? = nil, startSDK: @escaping @MainActor (Receipt, @escaping StartAdmission) async throws -> Void,
         now: @escaping @MainActor () -> Int64, schedule: Schedule? = nil) {
        self.canonical = canonical; self.sdkState = sdkState; self.configuration = configuration
        self.readMarker = readMarker; self.readMembership = readMembership; self.verify = verify
        self.startSDK = startSDK; self.now = now
        self.schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                action()
            }
            return { task.cancel() }
        }
        observation = canonical.changes.sink { [weak self] _ in
            guard let self, let held = self.flight, !self.canonical.isCurrent(held.context) else { return }
            self.revoke(held, reason: .stale)
        }
    }

    func start(context: Context) async throws -> Receipt {
        let id = UUID(), cancellation = ReaderStartupCancellationFlag()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Receipt, Error>) in
                guard !cancellation.isCancelled, !Task.isCancelled else { continuation.resume(throwing: Failure.cancelled); return }
                guard flight == nil, sdkState.status != .preparing else { continuation.resume(throwing: Failure.busy); return }
                guard sdkState.status == .idle else { continuation.resume(throwing: Failure.sdkAlreadyStarted); return }
                guard canonical.isCurrent(context), context.userID != nil else { continuation.resume(throwing: Failure.unavailable); return }
                guard sdkState.reserve(id) else { continuation.resume(throwing: Failure.busy); return }
                let held = Flight(id: id, context: context, cancellation: cancellation, continuation: continuation)
                flight = held // Reserve before every injected hook, including scheduler/clock/disk.
                let cancel = schedule { [weak self, weak held] in
                    guard let self, let held else { return }; self.revoke(held, reason: .timedOut)
                }
                if held.revoked != nil || cancellation.isCancelled { cancel() } else { held.cancelDeadline = cancel }
                // Never cancel the physical operation because the UI stopped waiting.
                Task { @MainActor [self] in await perform(held) }
            }
        } onCancel: { [self] in
            cancellation.cancel()
            Task { @MainActor in
                if let held = self.flight, held.id == id { self.revoke(held, reason: .cancelled) }
            }
        }
        // Physical completion is historical. Only the caller's final accepted
        // return opens reader work; a late SDK callback after timeout never can.
        let time = now() // Last injected hook; recheck identity/cancellation after it.
        guard !cancellation.isCancelled, !Task.isCancelled else { throw Failure.cancelled }
        guard canonical.isCurrent(context) else { throw Failure.stale }
        guard time >= 0, time < result.validUntilMs else { throw Failure.expired }
        guard sdkState.acceptReaderContext(id, context: context) else { throw Failure.stale }
        return result
    }

    private func perform(_ held: Flight) async {
        defer {
            sdkState.releasePreparation(held.id)
            if flight === held { flight = nil }
        }
        do {
            try check(held)
            let marker = try await readMarker()
            try check(held)
            guard let uid = held.context.userID else { throw Failure.unavailable }
            let request = try MembershipRequest(expectedUID: uid, readID: held.id.uuidString.lowercased())
            let snapshot = try await readMembership(request)
            try check(held)
            guard snapshot.request == request, let member = snapshot.membership,
                  member.state == .active, Data(member.binding.ownerUID.utf8) == Data(uid.utf8) else { throw Failure.unavailable }
            if let marker, marker.binding != member.binding { throw Failure.markerMismatch }
            try fresh(held, until: snapshot.validUntilMs)
            guard let verify else { throw Failure.unavailable }
            let challenge = Challenge(configuration: configuration, context: held.context, binding: member.binding,
                                      marker: marker, readID: request.readID)
            let permit = try await verify(challenge)
            try check(held)
            guard permit.challenge == challenge, permit.coverage == .allPersistedWritersIncludingPreviousAccounts,
                  permit.writerFenceRevision == configuration.writerFenceRevision,
                  permit.migrationRevision == configuration.migrationRevision,
                  permit.validUntilMs <= snapshot.validUntilMs else { throw Failure.invalidPermit }
            try fresh(held, until: permit.validUntilMs)
            let currentMarker = try await readMarker()
            try check(held)
            guard currentMarker == marker else { throw Failure.markerMismatch }
            // Keep the deadline alive through a non-cooperative starter. The
            // final external hook is the clock; all pure checks follow it.
            try fresh(held, until: permit.validUntilMs)
            guard sdkState.attempt(held.id) else { throw Failure.sdkAlreadyStarted }
            let receipt = Receipt(challenge: challenge, validUntilMs: permit.validUntilMs)
            held.successValidUntilMs = permit.validUntilMs
            do {
                // The future adapter must call admission immediately before its
                // first synchronous SDK reference, with no intervening await.
                // It may have suspended before that boundary; recheck here.
                try await startSDK(receipt) { [self] in
                    try fresh(held, until: permit.validUntilMs)
                    guard !held.admitted, sdkState.status == .attempted else { throw Failure.sdkAlreadyStarted }
                    held.admitted = true
                }
                guard held.admitted else { throw Failure.invalidPermit }
                sdkState.complete(held.id, success: true)
            } catch {
                sdkState.complete(held.id, success: false)
                throw error // It may already have initialized the SDK. Never retry.
            }
            try fresh(held, until: permit.validUntilMs)
            finishUI(held, result: .success(receipt))
        } catch { finishUI(held, result: .failure(error)) }
    }

    private func check(_ held: Flight) throws {
        if held.cancellation.isCancelled { throw Failure.cancelled }
        if let reason = held.revoked { throw reason }
        guard flight === held, sdkState.owns(held.id), canonical.isCurrent(held.context) else { throw Failure.stale }
    }
    private func fresh(_ held: Flight, until: Int64) throws {
        let time = now() // May reenter; pure checks must follow it.
        try check(held)
        guard time >= 0, time < until, until <= ReaderAuthoritativeReadContract.maximumSafeInteger else { throw Failure.expired }
    }
    private func cancelDeadline(_ held: Flight) {
        let cancel = held.cancelDeadline; held.cancelDeadline = nil
        cancel?()
    }
    private func finishUI(_ held: Flight, result: Result<Receipt, Error>) {
        guard let continuation = held.continuation else { return }
        held.continuation = nil
        cancelDeadline(held)
        do {
            if case .success = result, let until = held.successValidUntilMs { try fresh(held, until: until) }
            else { try check(held) }
            continuation.resume(with: result)
        }
        catch { continuation.resume(throwing: error) }
    }
    private func revoke(_ held: Flight, reason: Failure) {
        guard flight === held else { return }
        if held.revoked == nil { held.revoked = reason }
        finishUI(held, result: .failure(reason))
    }
}

private final class ReaderStartupCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
