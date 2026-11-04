import Combine
import Foundation

struct ReaderPreferences: Codable, Equatable, Sendable {
    var interestTopicIDs: [String] = []
    var onboardingCompleted = false

    init(interestTopicIDs: [String] = [], onboardingCompleted: Bool = false) {
        self.interestTopicIDs = Array(Set(interestTopicIDs.filter { !$0.isEmpty })).sorted().prefix(20).map { $0 }
        self.onboardingCompleted = onboardingCompleted
    }
}

/// Account-owned committed state and the actual injected I/O pipeline. Construction
/// is inert. UI deadlines never release a transport slot that is still occupied.
@MainActor
final class ReaderPreferencesModel: ObservableObject {
    enum Context: Equatable, Sendable {
        case unresolved, guest, account(String)
        var userID: String? { if case .account(let uid) = self { return uid }; return nil }
        static func confirmed(userID: String?) -> Self {
            guard let userID else { return .guest }
            return validUserID(userID) ? .account(userID) : .unresolved
        }
    }
    struct Snapshot: Equatable {
        var context: Context
        var generation: UUID
        var revision: UInt64
        var preferences: ReaderPreferences
        var isLoading: Bool
        var isSaving: Bool
        var errorMessage: String?
        var loaded: Bool
        var loadVersion: UUID?
        var userID: String? { context.userID }
    }
    struct ContextTicket: Equatable, Sendable {
        let context: Context
        let generation: UUID
        fileprivate let modelID: UUID
        var userID: String? { context.userID }
    }
    struct SaveRequest: Equatable, Sendable {
        let context: ContextTicket
        let preferences: ReaderPreferences
        fileprivate let loadVersion: UUID
        fileprivate let id: UUID
        var userID: String { context.userID! }
    }
    struct RefreshRequest: Equatable, Sendable {
        let context: ContextTicket
        fileprivate let id: UUID
        fileprivate let revision: UInt64
    }
    struct Identity { let actualUID: String?; let canonicalUID: String? }
    struct ReadResult { let preferences: ReaderPreferences?; let isFromCache: Bool }
    typealias Guard = @MainActor () -> Bool
    typealias Load = @MainActor (ContextTicket, @escaping Guard) async throws -> ReadResult
    typealias Save = @MainActor (SaveRequest, @escaping Guard) async throws -> Void
    typealias Schedule = (@escaping @MainActor () -> Void) -> (() -> Void)

    private struct Authority {
        var snapshot = Snapshot(context: .unresolved, generation: UUID(), revision: 0,
                                preferences: ReaderPreferences(), isLoading: false, isSaving: false,
                                errorMessage: nil, loaded: false, loadVersion: nil)
        var loadID: UUID?
        var saveID: UUID?
        var savePermission: Permission?
    }
    @MainActor private final class Permission {
        private let original: Guard
        private let parent: Guard?
        private var denied = false
        init(original: @escaping Guard, parent: Guard?) { self.original = original; self.parent = parent }
        func revoke() { denied = true }
        func isCurrent() -> Bool {
            guard !denied else { return false }
            guard original(), !denied else { denied = true; return false }
            guard parent?() ?? true, !denied else { denied = true; return false }
            guard original(), !denied else { denied = true; return false }
            return true
        }
    }
    @MainActor private final class ReadOperation {
        let context: ContextTicket
        let id: UUID
        let permission: Permission
        let refresh: RefreshRequest?
        let cancellation: ReaderPreferencesRefreshCancellation?
        var continuation: CheckedContinuation<Void, Never>?
        init(context: ContextTicket, id: UUID, permission: Permission, continuation: CheckedContinuation<Void, Never>,
             refresh: RefreshRequest? = nil, cancellation: ReaderPreferencesRefreshCancellation? = nil) {
            self.context = context; self.id = id; self.permission = permission; self.continuation = continuation
            self.refresh = refresh; self.cancellation = cancellation
        }
        func finish() { let held = continuation; continuation = nil; held?.resume() }
    }
    @MainActor private final class WriteOperation {
        let request: SaveRequest
        let permission: Permission
        var continuation: CheckedContinuation<Bool, Never>?
        var cancelDeadline: (() -> Void)?
        var uiFinished = false
        init(request: SaveRequest, permission: Permission, continuation: CheckedContinuation<Bool, Never>) {
            self.request = request; self.permission = permission; self.continuation = continuation
        }
        func finish(_ success: Bool, confirmSuccess: Guard? = nil) {
            guard !uiFinished else { return }
            uiFinished = true
            let held = continuation, cancel = cancelDeadline
            continuation = nil; cancelDeadline = nil
            cancel?()
            // The injected cancellation hook can change accounts or revoke the
            // receipt. Only its post-hook original authority may return true.
            held?.resume(returning: success && confirmSuccess?() == true)
        }
    }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var snapshot: Snapshot { authority.snapshot }
    var userID: String? { snapshot.userID }
    var preferences: ReaderPreferences { snapshot.preferences }
    var isLoading: Bool { snapshot.isLoading }
    var isSaving: Bool { snapshot.isSaving }
    var errorMessage: String? { snapshot.errorMessage }
    var hasLoaded: Bool { snapshot.loaded }
    var acceptedLoadVersion: UUID? { snapshot.loadVersion }
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] value in
            self?.snapshot.generation == value.generation && self?.snapshot.revision == value.revision
        }.eraseToAnyPublisher()
    }
    var activity: (activeLoadCount: Int, pendingLoad: Bool, activeSave: Bool, pendingSave: Bool) {
        (activeReads.count, pendingRead != nil, activeWrite != nil, pendingWrite != nil)
    }

    private let modelID = UUID()
    private let capturePermission: @MainActor () -> Guard?
    private let identity: @MainActor () -> Identity
    private let read: Load
    private let write: Save
    private let schedule: Schedule
    private let subject = PassthroughSubject<Snapshot, Never>()
    private var authority = Authority()
    private var operation = UUID()
    private var notifying = false
    private var started = false
    private var activeReads: [UUID: ReadOperation] = [:]
    private var pendingRead: ReadOperation?
    private var activeWrite: WriteOperation?
    private var pendingWrite: WriteOperation?
    private var pendingCapture: (id: UUID, permission: Permission)?
    private var captureOperation = UUID()
    private var entryOperation = UUID()
    private var refreshID: UUID?
    private var capturedRefresh: (request: RefreshRequest, permission: Permission)?
    private var refreshCaptureOperation = UUID()

    init(capturePermission: @escaping @MainActor () -> Guard?,
         identity: @escaping @MainActor () -> Identity, load: @escaping Load, save: @escaping Save,
         schedule: Schedule? = nil) {
        self.capturePermission = capturePermission; self.identity = identity; read = load; write = save
        self.schedule = schedule ?? { action in
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                action()
            }
            return { task.cancel() }
        }
    }
    func start() { started = true; pumpRead(); pumpWrite() }

    func contextTicket() -> ContextTicket {
        ContextTicket(context: snapshot.context, generation: snapshot.generation, modelID: modelID)
    }
    func isCurrent(_ ticket: ContextTicket) -> Bool {
        ticket.modelID == modelID && ticket.context == snapshot.context && ticket.generation == snapshot.generation
    }
    /// Historical UI acknowledgement retains its original startup permission;
    /// this never captures a new permit after the provider has returned.
    func isCurrent(_ request: SaveRequest) -> Bool {
        guard isCurrentTicket(request), let permission = authority.savePermission else { return false }
        return owns(request, permission: permission)
    }
    private func isCurrentTicket(_ request: SaveRequest) -> Bool {
        canAdmit(request) && authority.saveID == request.id
    }

    /// This synchronous revocation runs before canonical/dependent publication.
    @discardableResult
    func changeContext(to proposed: Context) -> ContextTicket? {
        let context = proposed.userID.map { Context.confirmed(userID: $0) } ?? proposed
        if context == snapshot.context {
            if notifying { operation = UUID() }
            return contextTicket()
        }
        // Revoke prior button captures before notifying. A nested new-owner
        // capture made by a subscriber must not be cleared after publication.
        pendingCapture = nil; captureOperation = UUID(); entryOperation = UUID()
        invalidateRefresh()
        let accepted = mutate { value in
            value = Authority()
            value.snapshot.context = context
            value.snapshot.generation = UUID()
        }
        pruneWaiters()
        return accepted ? contextTicket() : nil
    }

    /// Capture in the original synchronous event, before starting a Task.
    /// The returned closure is owner-bound and latches a denial permanently.
    func capturePermissionForCurrentContext(_ original: ContextTicket) -> Guard? {
        let entry = UUID(); entryOperation = entry
        let revision = snapshot.revision
        guard started, original.userID != nil, isCurrent(original),
              let permission = makePermission(parent: nil), entryOperation == entry,
              owns(original, permission: permission), entryOperation == entry,
              snapshot.revision == revision else { return nil }
        return { [weak self] in self?.owns(original, permission: permission) ?? false }
    }

    /// Original ticket is required; a deferred task never selects today's UID.
    func load(_ original: ContextTicket, stillCurrent: Guard? = nil) async {
        let entry = UUID(); entryOperation = entry
        let revision = snapshot.revision
        guard !Task.isCancelled, started, original.userID != nil, isCurrent(original),
              let permission = makePermission(parent: stillCurrent), entryOperation == entry else { return }
        let admitted: Guard = { [weak self] in
            guard !Task.isCancelled, let self, self.entryOperation == entry else { return false }
            let current = self.owns(original, permission: permission)
            return current && self.entryOperation == entry && self.snapshot.revision == revision
        }
        guard admitted() else { return }
        let id = UUID()
        invalidateRefresh()
        pendingCapture = nil
        guard mutate({ value in
            value.loadID = id; value.saveID = nil; value.savePermission = nil
            value.snapshot.isLoading = true; value.snapshot.isSaving = false
            value.snapshot.loaded = false; value.snapshot.errorMessage = nil
        }, stillPermitted: admitted) else { return }
        guard ownsLoad(original, id: id, permission: permission), entryOperation == entry else {
            retireRead(original, id: id); return
        }
        pruneWaiters()
        guard ownsLoad(original, id: id, permission: permission), entryOperation == entry else {
            retireRead(original, id: id); return
        }
        await withCheckedContinuation { continuation in
            let request = ReadOperation(context: original, id: id, permission: permission, continuation: continuation)
            let superseded = pendingRead
            pendingRead = request
            superseded?.finish()
            pumpRead()
        }
    }
    func retry(_ original: ContextTicket, stillCurrent: Guard? = nil) async { await load(original, stillCurrent: stillCurrent) }

    /// Best-effort refresh is captured in the lifecycle event, before its Task.
    /// It never replaces a form capture, pending save, unconfirmed write or load.
    func captureRefresh(context: ContextTicket, stillCurrent: Guard? = nil) -> RefreshRequest? {
        guard started, !notifying, refreshID == nil, idleForRefresh,
              activeReads.isEmpty, pendingRead == nil, context.userID != nil, isCurrent(context) else { return nil }
        let entry = UUID(); refreshCaptureOperation = entry
        let revision = snapshot.revision
        guard let permission = makePermission(parent: stillCurrent), refreshCaptureOperation == entry,
              owns(context, permission: permission), refreshCaptureOperation == entry,
              snapshot.revision == revision, !notifying, refreshID == nil, idleForRefresh,
              activeReads.isEmpty, pendingRead == nil else { return nil }
        let request = RefreshRequest(context: context, id: UUID(), revision: revision)
        refreshID = request.id; capturedRefresh = (request, permission)
        return request
    }

    /// Refresh shares the bounded read pipeline, but leaves visible values and
    /// errors untouched until a fresh server result is accepted. Cancellation
    /// retires the waiter; the physical slot survives until the read returns.
    func refresh(_ request: RefreshRequest) async {
        guard let captured = capturedRefresh, captured.request == request else { return }
        capturedRefresh = nil
        let cancellation = ReaderPreferencesRefreshCancellation()
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { invalidateRefresh(request.id); return }
            await withCheckedContinuation { continuation in
                let job = ReadOperation(context: request.context, id: request.id, permission: captured.permission,
                                        continuation: continuation, refresh: request, cancellation: cancellation)
                guard ownsRead(job), activeReads.isEmpty, pendingRead == nil else {
                    invalidateRefresh(request.id); job.finish(); return
                }
                pendingRead = job
                pumpRead()
            }
        } onCancel: { [weak self] in
            cancellation.cancel()
            Task { @MainActor [weak self] in self?.invalidateRefresh(request.id) }
        }
    }

    /// Capture in the button event, before creating any Task. The request remains
    /// a Sendable value; its permission is retained privately by this model.
    func captureSave(ids: [String], context: ContextTicket, stillCurrent: Guard? = nil) -> SaveRequest? {
        let capture = UUID(); captureOperation = capture; entryOperation = capture
        let revision = snapshot.revision, version = snapshot.loadVersion
        guard started, context.userID != nil, isCurrent(context),
              let permission = makePermission(parent: stillCurrent), captureOperation == capture, entryOperation == capture,
              owns(context, permission: permission), captureOperation == capture, entryOperation == capture,
              snapshot.loaded, !snapshot.isLoading, snapshot.revision == revision,
              snapshot.loadVersion == version, let version else { return nil }
        let id = UUID()
        invalidateRefresh()
        pendingCapture = (id, permission)
        if notifying { operation = UUID() }
        return SaveRequest(context: context,
                           preferences: ReaderPreferences(interestTopicIDs: ids, onboardingCompleted: true),
                           loadVersion: version, id: id)
    }
    /// An event rejected before dispatch has no physical write to protect.
    /// Retire only that exact capture; an older caller cannot clear a newer tap.
    func abandonCapture(_ request: SaveRequest) {
        guard pendingCapture?.id == request.id else { return }
        pendingCapture = nil
    }
    @discardableResult
    func saveInterests(_ request: SaveRequest) async -> Bool {
        defer { abandonCapture(request) }
        let entry = UUID(); entryOperation = entry
        let revision = snapshot.revision
        guard !Task.isCancelled, started, let captured = pendingCapture, captured.id == request.id else { return false }
        let beforeCommit: Guard = { [weak self] in
            guard !Task.isCancelled, let self, self.entryOperation == entry else { return false }
            let current = self.owns(request.context, permission: captured.permission)
            return current && self.entryOperation == entry && self.canAdmit(request) && self.snapshot.revision == revision
        }
        guard beforeCommit(), pendingCapture?.id == request.id else { return false }
        // Consume the event before publication; replay cannot choose a new epoch.
        pendingCapture = nil
        guard mutate({ value in
            value.saveID = request.id; value.savePermission = captured.permission; value.loadID = nil
            value.snapshot.isSaving = true; value.snapshot.errorMessage = nil
        }, stillPermitted: beforeCommit) else { return false }
        guard owns(request, permission: captured.permission), entryOperation == entry else {
            retireWrite(request); return false
        }
        return await withCheckedContinuation { continuation in
            let job = WriteOperation(request: request, permission: captured.permission, continuation: continuation)
            let supersededPending = pendingWrite
            pendingWrite = job
            supersededPending?.finish(false)
            // Finishing superseded UI work calls an injected deadline cancel.
            // It can synchronously enqueue a newer save; never retire that job.
            guard pendingWrite === job, entryOperation == entry, owns(job), !job.uiFinished, entryOperation == entry else {
                discardPending(job); return
            }
            if let activeWrite, activeWrite.request.id != request.id { activeWrite.finish(false) }
            guard pendingWrite === job, entryOperation == entry, owns(job), !job.uiFinished, entryOperation == entry else {
                discardPending(job); return
            }
            let cancel = schedule { [weak self, weak job] in
                guard let self, let job, !job.uiFinished else { return }
                let admitted: Guard = { [weak self, weak job] in
                    guard let self, let job, !job.uiFinished else { return false }
                    return self.owns(job) && !job.uiFinished
                }
                if admitted() {
                    _ = self.mutate({ value in
                        value.snapshot.isSaving = false
                        value.snapshot.errorMessage = Self.unconfirmedSave
                    }, stillPermitted: admitted)
                }
                job.finish(false)
                self.retireWrite(job.request)
                self.pruneWaiters()
            }
            // Synchronous injected deadline/reentry must not resurrect a job.
            if job.uiFinished || pendingWrite !== job || entryOperation != entry || !owns(job) || entryOperation != entry {
                cancel(); discardPending(job)
            } else {
                job.cancelDeadline = cancel
                pumpWrite()
            }
        }
    }

    private func makePermission(parent: Guard?) -> Permission? {
        guard parent?() ?? true, let original = capturePermission() else { return nil }
        let permission = Permission(original: original, parent: parent)
        return permission.isCurrent() ? permission : nil
    }
    private func canAdmit(_ request: SaveRequest) -> Bool {
        isCurrent(request.context) && snapshot.loaded && !snapshot.isLoading
            && snapshot.loadVersion == request.loadVersion && request.context.userID != nil
    }
    private func owns(_ context: ContextTicket, permission: Permission) -> Bool {
        guard isCurrent(context), context.userID != nil, permission.isCurrent() else { return false }
        let observed = identity()
        guard permission.isCurrent(), isCurrent(context), observed.actualUID == context.userID,
              observed.canonicalUID == context.userID else { permission.revoke(); return false }
        return true
    }
    private func owns(_ request: SaveRequest, permission: Permission) -> Bool {
        guard isCurrentTicket(request), owns(request.context, permission: permission) else { return false }
        return isCurrentTicket(request)
    }
    private func owns(_ job: WriteOperation) -> Bool { owns(job.request, permission: job.permission) }
    private func ownsLoad(_ context: ContextTicket, id: UUID, permission: Permission) -> Bool {
        guard isCurrent(context), authority.loadID == id, owns(context, permission: permission) else { return false }
        return isCurrent(context) && authority.loadID == id
    }
    private var idleForRefresh: Bool {
        pendingCapture == nil && activeWrite == nil && pendingWrite == nil
            && !snapshot.isLoading && !snapshot.isSaving && snapshot.errorMessage != Self.unconfirmedSave
    }
    private func refreshMatches(_ request: RefreshRequest) -> Bool {
        refreshID == request.id && isCurrent(request.context)
            && snapshot.revision == request.revision && idleForRefresh
    }
    private func readMatches(_ job: ReadOperation) -> Bool {
        if let refresh = job.refresh {
            return job.cancellation?.isCancelled == false && refreshMatches(refresh)
        }
        return isCurrent(job.context) && authority.loadID == job.id
    }
    private func ownsRead(_ job: ReadOperation) -> Bool {
        guard readMatches(job), owns(job.context, permission: job.permission) else { return false }
        return readMatches(job)
    }
    private func invalidateRefresh(_ expectedID: UUID? = nil) {
        guard expectedID == nil || refreshID == expectedID else { return }
        let originalID = refreshID
        refreshID = nil; capturedRefresh = nil; refreshCaptureOperation = UUID()
        if let job = pendingRead, job.refresh != nil, job.id == originalID {
            pendingRead = nil; job.permission.revoke(); job.finish()
        }
        // Revocation ends only the waiter, never the physical read reservation.
        for job in activeReads.values where job.refresh != nil && job.id == originalID {
            job.permission.revoke(); job.finish()
        }
    }
    /// These retirement paths are pure ticket checks. They clear only an
    /// original spinner, never a provider error or another account's state.
    private func retireRead(_ context: ContextTicket, id: UUID) {
        let current: Guard = { [weak self] in
            guard let self else { return false }
            return self.isCurrent(context) && self.authority.loadID == id && self.snapshot.isLoading
        }
        guard current() else { return }
        _ = mutate({ value in value.snapshot.isLoading = false; value.loadID = nil }, stillPermitted: current)
    }
    private func retireWrite(_ request: SaveRequest) {
        let current: Guard = { [weak self] in
            guard let self else { return false }
            return self.isCurrentTicket(request) && self.snapshot.isSaving
        }
        guard current() else { return }
        _ = mutate({ value in value.snapshot.isSaving = false }, stillPermitted: current)
    }
    private func discardPending(_ job: WriteOperation) {
        if pendingWrite === job { pendingWrite = nil }
        job.finish(false); retireWrite(job.request)
    }
    private func pruneWaiters() {
        if let held = pendingRead, !readMatches(held) {
            pendingRead = nil; held.finish()
        }
        // Occupied actual slots remain until the provider returns.
        for held in Array(activeReads.values) where !readMatches(held) { held.finish() }
        if let held = pendingWrite, !isCurrentTicket(held.request) || held.uiFinished {
            pendingWrite = nil; held.finish(false)
        }
        if let held = activeWrite, !isCurrentTicket(held.request) { held.finish(false) }
    }
    private func pumpRead() {
        guard started, activeReads.count < 4, let job = pendingRead else { return }
        pendingRead = nil
        guard ownsRead(job), activeReads.count < 4 else {
            job.finish(); retireRead(job.context, id: job.id)
            if job.refresh != nil { invalidateRefresh(job.id) }
            return
        }
        activeReads[job.id] = job
        let admitted: Guard = { [weak self] in self?.ownsRead(job) ?? false }
        Task { @MainActor [self, job] in
            defer {
                activeReads.removeValue(forKey: job.id)
                if job.refresh != nil { invalidateRefresh(job.id) }
                retireRead(job.context, id: job.id); job.finish(); pumpRead()
            }
            do {
                guard admitted() else { return }
                let result = try await read(job.context, admitted)
                guard admitted() else { return }
                if job.refresh != nil {
                    guard !result.isFromCache else { return }
                    let preferences = result.preferences ?? ReaderPreferences()
                    // Repeated foregrounds with identical values must not reset
                    // a form's load version or publish an unnecessary revision.
                    guard !snapshot.loaded || snapshot.preferences != preferences else { return }
                    _ = mutate({ value in
                        value.snapshot.preferences = preferences
                        value.snapshot.loaded = true; value.snapshot.errorMessage = nil
                        value.snapshot.loadVersion = job.id
                    }, stillPermitted: admitted)
                    return
                }
                guard result.preferences != nil || !result.isFromCache else { throw URLError(.notConnectedToInternet) }
                let preferences = result.preferences ?? ReaderPreferences()
                _ = mutate({ value in
                    value.snapshot.preferences = preferences
                    value.snapshot.loaded = true; value.snapshot.isLoading = false
                    value.snapshot.errorMessage = nil; value.snapshot.loadVersion = job.id
                }, stillPermitted: admitted)
            } catch {
                guard job.refresh == nil else { return }
                guard admitted() else { return }
                _ = mutate({ value in
                    value.snapshot.isLoading = false; value.snapshot.loaded = false
                    value.snapshot.errorMessage = "Kunne ikke hente dine interesser. Prøv igen, når du er online."
                }, stillPermitted: admitted)
            }
        }
    }
    private func pumpWrite() {
        guard started, activeWrite == nil, let job = pendingWrite else { return }
        pendingWrite = nil
        guard !job.uiFinished, owns(job), !job.uiFinished, activeWrite == nil else {
            job.finish(false); retireWrite(job.request); return
        }
        activeWrite = job
        let admitted: Guard = { [weak self, weak job] in
            guard let self, let job, !job.uiFinished else { return false }
            return self.owns(job) && !job.uiFinished
        }
        Task { @MainActor [self, job] in
            defer {
                if activeWrite === job { activeWrite = nil }
                retireWrite(job.request); job.finish(false)
                pumpWrite()
            }
            do {
                guard admitted() else { return }
                try await write(job.request, admitted)
                guard admitted() else { return }
                let accepted = mutate({ value in
                    value.snapshot.preferences = job.request.preferences
                    value.snapshot.isSaving = false; value.snapshot.errorMessage = nil
                }, stillPermitted: admitted)
                job.finish(accepted, confirmSuccess: { [weak self] in
                    self?.owns(job.request, permission: job.permission) ?? false
                })
            } catch {
                guard admitted() else { return }
                _ = mutate({ value in
                    value.snapshot.isSaving = false; value.snapshot.errorMessage = Self.unconfirmedSave
                }, stillPermitted: admitted)
            }
        }
    }

    @discardableResult private func mutate(_ change: (inout Authority) -> Void, stillPermitted: Guard = { true }) -> Bool {
        let token = UUID(); operation = token
        var value = authority
        let revision = snapshot.revision
        guard revision < UInt64.max, stillPermitted(), operation == token else { return false }
        change(&value); value.snapshot.revision = revision + 1
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard operation == token, stillPermitted(), operation == token else { return false }
        authority = value
        subject.send(value.snapshot)
        return operation == token && snapshot.generation == value.snapshot.generation && snapshot.revision == value.snapshot.revision
    }
    private static let unconfirmedSave = "Gemning er ikke bekræftet. Dine valg kan blive synkroniseret, når forbindelsen vender tilbage. Prøv igen for at bekræfte dem."
    nonisolated private static func validUserID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.contains("/") && value != "." && value != ".."
            && !(value.hasPrefix("__") && value.hasSuffix("__"))
    }
}

/// Cancellation is visible before its MainActor delivery, so an already queued
/// provider completion cannot publish after the lifecycle task was cancelled.
private final class ReaderPreferencesRefreshCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
