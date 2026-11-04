import Foundation

/// Process-lifetime ownership and bounded provider work. Revocation drops pending
/// authority, but actual drain/transport slots survive until their work returns.
@MainActor
final class FavoritesCloudCoordinator {
    typealias Guard = @MainActor () -> Bool
    typealias CapturePermission = @MainActor () -> Guard?
    typealias GuardedWrite = @MainActor (FavoritesModel.Mutation, String, @escaping Guard) async throws -> Void
    typealias GuardedDispatch = @MainActor (FavoritesModel.DispatchTicket, String, @escaping Guard) async throws -> Void
    typealias GuardedDrain = @MainActor (String, @escaping Guard) async throws -> Void
    typealias Write = @MainActor (FavoritesModel.Mutation, String) async throws -> Void
    typealias Dispatch = @MainActor (FavoritesModel.DispatchTicket, String) async throws -> Void
    typealias Drain = @MainActor (String) async throws -> Void
    private struct Key: Hashable {
        let namespace: FavoritesNamespace
        let articleID: String
    }
    private struct Request {
        let mutation: FavoritesModel.Mutation
        let expectedUserID: String
    }
    private struct Slot {
        var activeID: UUID?
        var activeMutationID: UUID?
        var task: Task<Void, Never>?
        var pending: Request?
    }
    private struct Recovery {
        let id: UUID
        let ticket: FavoritesModel.RecoveryTicket
        let expectedUserID: String
        var task: Task<Void, Never>?
    }
    private let model: FavoritesModel
    private let maximumKeys: Int
    private let maximumConcurrentWrites: Int
    private let capturePermission: CapturePermission
    private let drain: GuardedDrain
    private let write: GuardedDispatch
    private var slots: [Key: Slot] = [:]
    private var order: [Key] = []
    private var recovery: Recovery?
    private var ownerUID: String?
    private var ownerGeneration: UUID?
    private var refreshing = false
    private var refreshRequested = false
    private var deniedRecovery: FavoritesModel.RecoveryTicket?
    private var deniedMutations: [Key: UUID] = [:]

    init(model: FavoritesModel, maximumKeys: Int = 256, maximumConcurrentWrites: Int = 4,
         capturePermission: @escaping CapturePermission,
         drainPendingWrites: @escaping GuardedDrain, write: @escaping GuardedDispatch) {
        precondition((1...256).contains(maximumKeys))
        precondition((1...4).contains(maximumConcurrentWrites))
        self.model = model
        self.maximumKeys = maximumKeys
        self.maximumConcurrentWrites = maximumConcurrentWrites
        self.capturePermission = capturePermission
        drain = drainPendingWrites
        self.write = write
    }

    /// Compatibility for existing, completely injected local pipelines. The live
    /// composition uses the required permission initializer above.
    convenience init(model: FavoritesModel, maximumKeys: Int = 256, maximumConcurrentWrites: Int = 4,
                     drainPendingWrites: @escaping Drain, write: @escaping Dispatch) {
        self.init(model: model, maximumKeys: maximumKeys, maximumConcurrentWrites: maximumConcurrentWrites,
            capturePermission: { { true } },
            drainPendingWrites: { uid, current in
                guard current() else { throw CancellationError() }
                try await drainPendingWrites(uid)
            }, write: { ticket, uid, current in
                guard current() else { throw CancellationError() }
                try await write(ticket, uid)
            })
    }

    /// Called by the canonical runtime after its model transition. A stale drain
    /// keeps its actual slot; its completion cannot approve a newer owner epoch.
    func setOwner(expectedUserID: String?, generation: UUID) {
        if ownerUID != expectedUserID || ownerGeneration != generation {
            deniedRecovery = nil
            deniedMutations.removeAll()
        }
        ownerUID = expectedUserID
        ownerGeneration = generation
        refresh()
    }

    /// Optimistic taps never grant transport authority. Only the model's queued,
    /// committed dispatchable set may enter beginDispatch below.
    func submit(_ mutation: FavoritesModel.Mutation, expectedUserID: String) {
        guard owns(mutation, expectedUserID: expectedUserID) else { return }
        deniedMutations.removeValue(forKey: Key(namespace: mutation.namespace, articleID: mutation.articleID))
        refresh()
    }

    func retryRecovery(generation: UUID) {
        guard ownerGeneration == generation, ownsCurrentOwner else { return }
        deniedRecovery = nil
        deniedMutations.removeAll()
        model.retryRecovery()
        refresh()
    }

    var activity: (activeWrites: Int, waiting: Int, draining: Bool) {
        (slots.values.filter { $0.activeID != nil }.count,
         slots.values.filter { $0.pending != nil }.count, recovery != nil)
    }

    func refresh() {
        if refreshing { refreshRequested = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshRequested = false
            reconcilePending()
            startRecoveryIfNeeded()
            if ownsCurrentOwner && model.snapshot.recoveryReady { pumpWrites() }
        } while refreshRequested
    }

    private var ownsCurrentOwner: Bool {
        guard let uid = ownerUID, ownerGeneration == model.snapshot.generation,
              model.context == .confirmed(userID: uid), model.context.namespace != .guest else { return false }
        return model.context.namespace != nil
    }

    private func owns(_ mutation: FavoritesModel.Mutation, expectedUserID: String) -> Bool {
        ownsCurrentOwner && ownerUID == expectedUserID && mutation.generation == ownerGeneration
            && mutation.namespace == model.context.namespace && model.isCurrent(mutation)
    }

    private func reconcilePending() {
        let eligible = ownsCurrentOwner && model.snapshot.recoveryReady ? model.dispatchableMutations : []
        let mutations = Dictionary(uniqueKeysWithValues: eligible.map { ($0.articleID, $0) })
        deniedMutations = deniedMutations.filter { key, mutationID in
            model.context.namespace == key.namespace && mutations[key.articleID]?.id == mutationID
        }
        for key in Array(slots.keys) {
            guard var slot = slots[key] else { continue }
            if let pending = slot.pending,
               !owns(pending.mutation, expectedUserID: pending.expectedUserID)
                || mutations[pending.mutation.articleID]?.id != pending.mutation.id { slot.pending = nil }
            if slot.activeID == nil && slot.pending == nil { slots.removeValue(forKey: key) }
            else { slots[key] = slot }
        }
        order.removeAll { slots[$0] == nil }
        guard let uid = ownerUID else { return }
        for mutation in eligible where owns(mutation, expectedUserID: uid) {
            let key = Key(namespace: mutation.namespace, articleID: mutation.articleID)
            guard deniedMutations[key] != mutation.id else { continue }
            guard slots[key] != nil || slots.count < maximumKeys else { continue }
            var slot = slots[key] ?? Slot()
            if slot.activeMutationID == mutation.id { continue }
            slot.pending = Request(mutation: mutation, expectedUserID: uid)
            slots[key] = slot
            if !order.contains(key) { order.append(key) }
        }
    }

    /// The ownership closure is pure; every injected capture/guard is followed
    /// by it again so synchronous reentry cannot admit an overwritten operation.
    private func permission(_ captured: @escaping Guard, owns: @escaping Guard) -> Guard {
        var denied = false
        return {
            guard !denied, owns() else { denied = true; return false }
            guard captured(), !denied, owns() else { denied = true; return false }
            return true
        }
    }
    private func ownsRecovery(_ id: UUID, ticket: FavoritesModel.RecoveryTicket, uid: String) -> Bool {
        recovery?.id == id && ownsCurrentOwner && ownerUID == uid
            && ownerGeneration == ticket.generation && model.isCurrent(ticket)
    }
    private func startRecoveryIfNeeded() {
        guard recovery == nil, model.recoveryIsRequired, ownsCurrentOwner, let uid = ownerUID,
              let ticket = model.recoveryTicket(), model.isCurrent(ticket), deniedRecovery != ticket else { return }
        let id = UUID()
        recovery = Recovery(id: id, ticket: ticket, expectedUserID: uid)
        let captured = capturePermission()
        guard let captured, ownsRecovery(id, ticket: ticket, uid: uid) else {
            if recovery?.id == id { deniedRecovery = ticket; recovery = nil }
            return
        }
        let current = permission(captured, owns: { [weak self] in
            self?.ownsRecovery(id, ticket: ticket, uid: uid) == true
        })
        guard current(), model.beginRecovery(ticket, stillCurrent: current), current() else {
            if recovery?.id == id { deniedRecovery = ticket; recovery = nil }
            return
        }
        let task = Task { @MainActor [self] in
            var success = false
            if current(), !Task.isCancelled {
                do { try await drain(uid, current); success = current() && !Task.isCancelled }
                catch { success = false }
            }
            // The same original permission also guards recovery publication
            // after its local receipt I/O. No fresh capture occurs on return.
            _ = await model.finishRecovery(ticket, success: success, stillCurrent: current)
            guard recovery?.id == id else { return }
            if !current(), model.isCurrent(ticket) { deniedRecovery = ticket }
            recovery = nil
            refresh()
        }
        if recovery?.id == id { recovery?.task = task }
    }

    private func ownsSlot(_ key: Key, activeID: UUID, request: Request) -> Bool {
        slots[key]?.activeID == activeID && slots[key]?.activeMutationID == request.mutation.id
            && owns(request.mutation, expectedUserID: request.expectedUserID)
    }
    private func ownsSlotLifetime(_ key: Key, activeID: UUID, request: Request) -> Bool {
        slots[key]?.activeID == activeID && slots[key]?.activeMutationID == request.mutation.id
            && ownsCurrentOwner && ownerUID == request.expectedUserID
            && ownerGeneration == request.mutation.generation
            && model.context.namespace == request.mutation.namespace
    }
    private func pumpWrites() {
        while slots.values.filter({ $0.activeID != nil }).count < maximumConcurrentWrites,
              let index = order.firstIndex(where: { slots[$0]?.activeID == nil && slots[$0]?.pending != nil }) {
            let key = order.remove(at: index)
            guard var slot = slots[key], let request = slot.pending else { continue }
            guard owns(request.mutation, expectedUserID: request.expectedUserID) else {
                slots.removeValue(forKey: key); continue
            }
            let activeID = UUID()
            slot.activeID = activeID
            slot.activeMutationID = request.mutation.id
            slot.pending = nil
            slots[key] = slot
            order.append(key)
            let captured = capturePermission()
            guard let captured, ownsSlot(key, activeID: activeID, request: request) else {
                if slots[key]?.activeID == activeID {
                    deniedMutations[key] = request.mutation.id
                    finished(key, activeID: activeID, refreshAfter: false)
                }
                continue
            }
            var completingReceipt = false
            let current = permission(captured, owns: { [weak self] in
                guard let self else { return false }
                // Receipt publication may remove this exact intent itself. The
                // shared denial latch never revives, but successful retirement
                // must retain the original slot/context after that removal.
                return completingReceipt
                    ? self.ownsSlotLifetime(key, activeID: activeID, request: request)
                    : self.ownsSlot(key, activeID: activeID, request: request)
            })
            guard current() else {
                if slots[key]?.activeID == activeID {
                    deniedMutations[key] = request.mutation.id
                    finished(key, activeID: activeID, refreshAfter: false)
                }
                continue
            }
            let task = Task { @MainActor [self] in
                if current(), !Task.isCancelled, owns(request.mutation, expectedUserID: request.expectedUserID),
                   let ticket = await model.beginDispatch(request.mutation, stillCurrent: current) {
                    var result = FavoritesModel.Receipt.failed
                    if current(), !Task.isCancelled, model.isCurrent(ticket) {
                        do {
                            try await write(ticket, request.expectedUserID, current)
                            if current(), !Task.isCancelled { result = .acknowledged }
                        } catch { result = .failed }
                    }
                    // Both slots remain occupied through the physical provider
                    // callback and the actual original receipt write/readback.
                    completingReceipt = true
                    _ = await model.finishDispatch(ticket, result: result, stillCurrent: current)
                }
                if !current(), owns(request.mutation, expectedUserID: request.expectedUserID) {
                    deniedMutations[key] = request.mutation.id
                }
                finished(key, activeID: activeID)
            }
            if slots[key]?.activeID == activeID { slots[key]?.task = task }
        }
    }

    private func finished(_ key: Key, activeID: UUID, refreshAfter: Bool = true) {
        guard var slot = slots[key], slot.activeID == activeID else { return }
        slot.activeID = nil
        slot.activeMutationID = nil
        slot.task = nil
        slots[key] = slot
        order.removeAll { $0 == key }
        order.append(key)
        // The model is the latest-intent authority, including any mutation
        // synchronously created while finishDispatch published its receipt.
        if refreshAfter { refresh() }
    }
}

/// Pure ownership/provenance decisions shared by the actual listener adapter and
/// recommendation capture. Independent models' generation UUIDs never compare.
enum FavoritesCloudSelection {
    static func canObserve(context: FavoritesContext, snapshot: FavoritesSnapshot, expectedUserID: String) -> Bool {
        guard snapshot.recoveryReady, context == .confirmed(userID: expectedUserID), context.namespace != nil,
              context.namespace != .guest else { return false }
        switch snapshot.state {
        case .ready, .pending, .writeFailed, .cloudFailed, .limitExceeded: return true
        case .unresolved, .loading, .readFailed, .invalidRecord, .unsupportedVersion, .recovering, .recoveryFailed: return false
        }
    }

    static func ownsObservation(context: FavoritesContext, snapshot: FavoritesSnapshot, canonicalUserID: String?,
                                expectedUserID: String, expectedGeneration: UUID) -> Bool {
        canonicalUserID == expectedUserID && snapshot.generation == expectedGeneration
            && canObserve(context: context, snapshot: snapshot, expectedUserID: expectedUserID)
    }

    static func recommendationGeneration(favoritesContext: FavoritesContext, favoritesSnapshot: FavoritesSnapshot,
                                         historyContext: ReadingHistoryContext, historyGeneration: UUID,
                                         canonicalUserID: String?) -> UUID? {
        guard let canonicalUserID, favoritesSnapshot.serverConfirmed,
              canObserve(context: favoritesContext, snapshot: favoritesSnapshot, expectedUserID: canonicalUserID),
              historyContext == .confirmed(userID: canonicalUserID) else { return nil }
        return historyGeneration
    }

    static func permitsWrite(expectedUserID: String, actualUserID: String?, articleID: String) -> Bool {
        expectedUserID == actualUserID && safeDocumentID(expectedUserID) && safeDocumentID(articleID)
    }

    private static func safeDocumentID(_ value: String) -> Bool {
        FavoritesRecordCodec.isValidID(value) && !value.contains("/") && value != "." && value != ".."
            && !(value.hasPrefix("__") && value.hasSuffix("__"))
    }
}
