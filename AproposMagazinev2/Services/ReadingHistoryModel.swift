import Combine
import Foundation

/// Required injections keep construction, reading and tests free of cloud SDKs.
/// A scheduled write owns its accepted record, partition and epoch; it never
/// looks up a new account or consumes a newer article callback when it fires.
@MainActor
final class ReadingHistoryModel: ObservableObject {
    struct Storage {
        /// Explicit local-only capability. The live KVS transport deliberately
        /// leaves this nil: its ordinary writer may propagate to iCloud.
        struct Cleanup {
            let readSource: @MainActor (ReadingHistoryNamespace) throws -> Data?
            let writeSource: @MainActor (ReadingHistoryNamespace, Data) throws -> Void
            let readMetadata: @MainActor () throws -> Data?
            let writeMetadata: @MainActor (Data) throws -> Void
        }
        let cleanup: Cleanup?
        init(read: @escaping @MainActor (ReadingHistoryNamespace) throws -> Data?,
             write: @escaping @MainActor (ReadingHistoryNamespace, Data) throws -> Void,
             cleanup: Cleanup? = nil) {
            self.read = read; self.write = write; self.cleanup = cleanup
        }
        let read: @MainActor (ReadingHistoryNamespace) throws -> Data?
        let write: @MainActor (ReadingHistoryNamespace, Data) throws -> Void
    }
    typealias CleanupFailure = ReadingHistoryLocalCleanupRecord.Failure
    struct CleanupLease: Sendable {
        fileprivate let modelID: UUID
        fileprivate let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        fileprivate let source: Data?
        fileprivate let metadata: Data?
        fileprivate let target: Data?
        fileprivate let record: ReadingHistoryLocalCleanupRecord
        fileprivate let use: CleanupUse
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
    }
    struct CleanupReceipt: Equatable, Sendable {
        fileprivate let record: ReadingHistoryLocalCleanupRecord
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
        var isLocalReadbackConfirmed: Bool { record.phase == .complete }
        var cloudCleanupComplete: Bool { false }
        func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool { record.belongs(to: checkpoint) }
    }
    @MainActor fileprivate final class CleanupUse {
        private var used = false
        func consume() throws { guard !used else { throw CleanupFailure.invalidLease }; used = true }
    }
    typealias Cancel = @MainActor () -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel
    struct ArticleTicket: Equatable, Sendable {
        let articleID: String
        fileprivate let modelID: UUID
        fileprivate let generation: UUID
        fileprivate let sessionID: UUID
    }
    struct ExternalTicket: Equatable, Sendable {
        fileprivate let modelID: UUID
        fileprivate let generation: UUID
    }
    enum Outcome: Equatable, Sendable { case written, scheduled, unchanged, stale, unavailable, deferred }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var snapshot: ReadingHistorySnapshot
    private(set) var context = ReadingHistoryContext.unresolved
    var changes: AnyPublisher<ReadingHistorySnapshot, Never> { changeSubject.eraseToAnyPublisher() }

    private let storage: Storage
    private let schedule: Scheduler
    private let legacyAdmission: ReaderLegacyWriteAdmission?
    private let recovery: ReaderTransitionRecovery?
    private let cleanupModelID = UUID()
    private struct Confirmation { var record: ReadingHistoryLocalCleanupRecord; var observed: Bool }
    private var cleanupConfirmations: [String: Confirmation] = [:]
    var isPhysicallyIdle: Bool { !storageInFlight }
    var isLocalCleanupAvailable: Bool { storage.cleanup != nil }
    private var recoveryRevoked = false
    private let modelID = UUID()
    private let changeSubject = PassthroughSubject<ReadingHistorySnapshot, Never>()
    private var generation = UUID()
    private var revision: UInt64 = 0
    private var operation = UUID()
    private var record = ReadingHistoryRecord.empty
    private var state = ReadingHistoryStorageState.unresolved
    private var activeArticle: ArticleTicket?
    private var loaded = false
    private var dirty = false
    private var transitioning = false
    private var requiresRetry = false
    private var deferredExternal = false
    private var storageInFlight = false
    private var deferredLoad: UUID?
    private var notifying = false
    private var pending: PendingWrite?
    private var cancelPending: Cancel?

    private struct PendingWrite {
        let id: UUID
        let generation: UUID
        let namespace: ReadingHistoryNamespace
        let payload: Data
    }

    init(storage: Storage, schedule: @escaping Scheduler, legacyAdmission: ReaderLegacyWriteAdmission? = nil,
         recovery: ReaderTransitionRecovery? = nil) {
        self.storage = storage
        self.schedule = schedule
        self.legacyAdmission = legacyAdmission ?? recovery?.admission
        self.recovery = recovery
        snapshot = ReadingHistorySnapshot(generation: generation, revision: revision, state: .unresolved)
    }

    func changeContext(to proposed: ReadingHistoryContext) {
        let desired: ReadingHistoryContext = proposed.namespace == nil ? .unresolved : proposed
        guard desired == .unresolved || permitsHistory else { return }
        guard desired != context else { return }
        transition(to: desired)
    }

    /// An Apple storage-account change is a new epoch even if Firebase is unchanged.
    func storageIdentityChanged() { guard permitsHistory else { return }; transition(to: context) }

    /// Synchronous recovery closure retires original reader/timer/observer
    /// tickets. Reopening a gate cannot lend those callbacks a new generation.
    func revokeForRecovery() {
        guard !recoveryRevoked else { return }
        recoveryRevoked = true
        transition(to: .unresolved)
    }

    private var permitsHistory: Bool {
        !recoveryRevoked && (legacyAdmission?.isAllowed ?? true) && (recovery?.admission.isAllowed ?? true)
    }

    func beginArticle(articleID: String) -> ArticleTicket? {
        guard permitsHistory, context.namespace != nil, !transitioning, !storageInFlight,
              ReadingHistoryRecordCodec.isValidID(articleID) else { return nil }
        let ticket = ArticleTicket(articleID: articleID, modelID: modelID, generation: generation, sessionID: UUID())
        activeArticle = ticket
        return ticket
    }

    func isCurrent(_ ticket: ArticleTicket) -> Bool {
        ticket.modelID == modelID && ticket.generation == generation && activeArticle == ticket
            && context.namespace != nil && !transitioning && permitsHistory
    }

    func endArticle(_ ticket: ArticleTicket) {
        guard isCurrent(ticket) else { return }
        activeArticle = nil
        // Already accepted edits may finish their owned write. No later callback
        // from the closed article can add another edit.
    }

    @discardableResult
    func markRead(_ ticket: ArticleTicket) -> Outcome {
        guard isCurrent(ticket) else { return .stale }
        guard loaded, !storageInFlight else { return .unavailable }
        let old = record.entries.first { $0.articleID == ticket.articleID }
        guard old?.read != true else { return .unchanged }
        let token = beginOperation()
        update(.init(articleID: ticket.articleID, read: true, progress: old?.progress))
        let cancel = takePendingCancellation()
        cancel?()
        guard operation == token, permitsHistory else { return .stale }
        if requiresRetry { state = .writeFailed;_ = publish(token);return .unavailable }
        return persist(token, payload: encodedRecord(), namespace: context.namespace)
    }

    @discardableResult
    func saveProgress(_ value: Double, ticket: ArticleTicket) -> Outcome {
        guard isCurrent(ticket) else { return .stale }
        guard value.isFinite, (0...1).contains(value) else { return .unchanged }
        guard loaded, !storageInFlight else { return .unavailable }
        let old = record.entries.first { $0.articleID == ticket.articleID }
        guard old?.progress != value else { return .unchanged }
        let token = beginOperation()
        update(.init(articleID: ticket.articleID, read: old?.read ?? false, progress: value))
        let cancel = takePendingCancellation()
        cancel?()
        guard operation == token, permitsHistory else { return .stale }
        if requiresRetry { state = .writeFailed;_ = publish(token);return .unavailable }
        state = .pending
        guard publish(token), let namespace = context.namespace, let data = encodedRecord() else { return .stale }
        let write = PendingWrite(id: UUID(), generation: generation, namespace: namespace, payload: data)
        pending = write
        let handle = schedule(0.4) { [weak self] in self?.fire(write) }
        guard pending?.id == write.id, generation == write.generation, permitsHistory else { handle();return .scheduled }
        cancelPending = handle
        return .scheduled
    }

    func externalTicket() -> ExternalTicket? {
        guard permitsHistory, context.namespace != nil, !transitioning else { return nil }
        return ExternalTicket(modelID: modelID, generation: generation)
    }

    @discardableResult
    func reloadExternal(ticket: ExternalTicket) -> Outcome {
        guard isCurrent(ticket) else { return .stale }
        if dirty || requiresRetry { deferredExternal = true;return .deferred }
        let token = beginOperation()
        load(token)
        return operation == token ? (loaded ? .unchanged : .unavailable) : .stale
    }

    /// A delayed quota notification is not a read or a cloud acknowledgement.
    /// Keep memory and require explicit retry; an old observer cannot block B.
    func reportQuotaViolation(ticket: ExternalTicket) {
        guard isCurrent(ticket) else { return }
        let token = beginOperation()
        dirty = true
        requiresRetry = true
        state = .writeFailed
        let cancel = takePendingCancellation()
        cancel?()
        guard operation == token else { return }
        _ = publish(token)
    }

    func retryStorage() {
        guard permitsHistory, context.namespace != nil, !transitioning, !storageInFlight, snapshot.canRetry else { return }
        let token = beginOperation()
        if loaded && dirty {
            requiresRetry = false
            _ = persist(token, payload: encodedRecord(), namespace: context.namespace)
        } else {
            requiresRetry = false
            load(token)
        }
    }

    /// Useful for an already prepared runtime at background entry. The payload
    /// remains the originally accepted owner record, even without an open article.
    func flushPending() {
        guard permitsHistory, let write = pending else { return }
        let token = beginOperation()
        let cancel = takePendingCancellation()
        cancel?()
        guard operation == token, generation == write.generation, !requiresRetry, permitsHistory else { return }
        _ = persist(token, payload: write.payload, namespace: write.namespace)
    }

    private func transition(to desired: ReadingHistoryContext) {
        let token = beginOperation()
        let cancel = takePendingCancellation()
        generation = UUID()
        context = desired
        activeArticle = nil
        loaded = false
        dirty = false
        requiresRetry = false
        deferredExternal = false
        deferredLoad = nil
        record = .empty
        transitioning = desired.namespace != nil
        state = desired.namespace == nil ? .unresolved : .loading
        _ = publish(token)
        cancel?()
        guard operation == token, desired.namespace != nil else { return }
        load(token)
    }

    private func isCurrent(_ ticket: ExternalTicket) -> Bool {
        ticket.modelID == modelID && ticket.generation == generation && context.namespace != nil && !transitioning && permitsHistory
    }

    private func update(_ entry: ReadingHistoryRecord.Entry) {
        record.entries.removeAll { $0.articleID == entry.articleID }
        record.entries.append(entry)
        record.entries = Array(record.entries.suffix(ReadingHistoryRecordCodec.maximumEntries))
        // Raw UTF-8 bounds do not include JSON escaping. Keep the largest newest
        // suffix that fits, rather than silently leaving a never-written record.
        if let namespace = context.namespace,
           (try? ReadingHistoryRecordCodec.encode(record, namespace: namespace)) == nil {
            var low = 1
            var high = record.entries.count
            while low < high {
                let count = (low + high + 1) / 2
                let candidate = ReadingHistoryRecord(entries: Array(record.entries.suffix(count)))
                if (try? ReadingHistoryRecordCodec.encode(candidate, namespace: namespace)) != nil { low = count }
                else { high = count - 1 }
            }
            record.entries = Array(record.entries.suffix(low))
        }
        dirty = true
    }

    private func encodedRecord() -> Data? {
        guard let namespace = context.namespace else { return nil }
        return try? ReadingHistoryRecordCodec.encode(record, namespace: namespace)
    }

    private func takePendingCancellation() -> Cancel? {
        let handle = cancelPending
        cancelPending = nil
        pending = nil
        return handle
    }

    private func fire(_ write: PendingWrite) {
        guard permitsHistory, pending?.id == write.id, generation == write.generation, !requiresRetry else { return }
        pending = nil
        cancelPending = nil
        let token = beginOperation()
        _ = persist(token, payload: write.payload, namespace: write.namespace)
    }

    private func load(_ token: UUID) {
        guard operation == token, permitsHistory, let namespace = context.namespace else { return }
        if storageInFlight { deferredLoad = token;return }
        let data: Data?
        do { data = try withStorage { try storage.read(namespace) } }
        catch {
            guard operation == token, permitsHistory else { return }
            loaded = false
            transitioning = false
            state = .readFailed
            _ = publish(token)
            return
        }
        guard operation == token, permitsHistory else { return }
        do {
            record = try data.map { try ReadingHistoryRecordCodec.decode($0, namespace: namespace) } ?? .empty
            loaded = true
            transitioning = false
            state = .ready
            _ = publish(token)
        } catch {
            loaded = false
            transitioning = false
            state = (error as? ReadingHistoryRecordCodec.Failure) == .unsupportedVersion ? .unsupportedVersion : .invalidRecord
            _ = publish(token)
        }
    }

    private func persist(_ token: UUID, payload: Data?, namespace: ReadingHistoryNamespace?) -> Outcome {
        guard operation == token, permitsHistory, loaded, !storageInFlight, let namespace, let payload else { return .unavailable }
        do { try withStorage { try storage.write(namespace, payload) } }
        catch {
            guard operation == token, permitsHistory else { return .stale }
            dirty = true
            requiresRetry = true
            state = .writeFailed
            _ = publish(token)
            return operation == token ? .unavailable : .stale
        }
        guard operation == token, permitsHistory else { return .stale }
        dirty = false
        requiresRetry = false
        state = .ready
        guard publish(token) else { return .stale }
        if deferredExternal {
            deferredExternal = false
            if let ticket = externalTicket() { _ = reloadExternal(ticket: ticket) }
        }
        return .written
    }

    private func beginOperation() -> UUID { operation = UUID();return operation }

    @discardableResult
    private func publish(_ token: UUID) -> Bool {
        guard operation == token, context == .unresolved || permitsHistory else { return false }
        if !notifying {
            notifying = true
            objectWillChange.send()
            notifying = false
        }
        guard operation == token, context == .unresolved || permitsHistory else { return false }
        revision &+= 1
        snapshot = ReadingHistorySnapshot(generation: generation, revision: revision, state: state, record: record)
        changeSubject.send(snapshot)
        return operation == token && (context == .unresolved || permitsHistory)
    }

    /// Explicit recovery-only operations share the existing synchronous writer.
    /// Async signatures fit the coordinator; there is no artificial suspension,
    /// queue or timer preemption of an already-entered injected storage effect. No live KVS cleanup is configured.
    func prepareLocalCleanup(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                             finalAdmission: ReaderLegacyWriteAdmission,
                             stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupLease {
        guard !storageInFlight else { throw CleanupFailure.busy }
        return try withStorage {
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            guard let effects = storage.cleanup else { throw CleanupFailure.unavailable }
            let namespace = try cleanupNamespace(checkpoint)
            let source = try effects.readSource(namespace); try checkCleanup(checkpoint, finalAdmission)
            let metadata = try effects.readMetadata(); try checkCleanup(checkpoint, finalAdmission)
            let parsed = try cleanupSource(source, namespace: namespace)
            let records = try ReadingHistoryLocalCleanupRecord.decode(metadata)
            let owner = namespace.recordBinding
            let existing = records.records.first { $0.owner == owner }
            let record: ReadingHistoryLocalCleanupRecord
            let target: Data?
            if let existing {
                guard existing.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
                if let confirmed = cleanupConfirmations[owner], !confirmed.record.sameOriginal(as: existing) { throw CleanupFailure.changedSource }
                record = existing
                target = try retainedCleanupTarget(existing, source: source, namespace: namespace)
            } else if let confirmed = cleanupConfirmations[owner] {
                guard !confirmed.observed else { throw CleanupFailure.unconfirmed }
                guard confirmed.record.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
                record = confirmed.record
                target = try retainedCleanupTarget(record, source: source, namespace: namespace)
            } else {
                guard records.records.count < ReadingHistoryLocalCleanupRecord.maximumRecords,
                      cleanupConfirmations.count < ReadingHistoryLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
                target = try cleanupTarget(source: source, namespace: namespace)
                record = try .init(checkpoint: checkpoint, source: source, target: target,
                                   originalEntryCount: parsed?.entries.count ?? 0)
            }
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            try verifyCleanupPair(source: source, metadata: metadata, effects: effects, checkpoint: checkpoint, admission: finalAdmission)
            return .init(modelID: cleanupModelID, checkpoint: checkpoint, source: source, metadata: metadata,
                         target: target, record: record, use: CleanupUse())
        }
    }

    func commitLocalCleanup(_ lease: CleanupLease, finalAdmission: ReaderLegacyWriteAdmission,
                            stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupReceipt {
        guard lease.modelID == cleanupModelID else { throw CleanupFailure.invalidLease }
        guard !storageInFlight else { throw CleanupFailure.busy }
        try lease.use.consume()
        return try withStorage {
            let checkpoint = lease.checkpoint
            let namespace = try cleanupNamespace(checkpoint)
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            guard let effects = storage.cleanup else { throw CleanupFailure.unavailable }
            try verifyCleanupPair(source: lease.source, metadata: lease.metadata, effects: effects,
                                  checkpoint: checkpoint, admission: finalAdmission)
            if let confirmed = cleanupConfirmations[lease.owner] {
                guard confirmed.record.sameOriginal(as: lease.record) else { throw CleanupFailure.changedSource }
            } else {
                guard cleanupConfirmations.count < ReadingHistoryLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
                cleanupConfirmations[lease.owner] = .init(record: lease.record, observed: false)
            }
            var records = try ReadingHistoryLocalCleanupRecord.decode(lease.metadata)
            var metadata = lease.metadata
            if let existing = records.records.first(where: { $0.owner == lease.owner }) {
                guard existing == lease.record else { throw CleanupFailure.changedSource }
                cleanupConfirmations[lease.owner] = .init(record: existing, observed: true)
            } else {
                guard lease.record.phase == .pending,
                      records.records.count < ReadingHistoryLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
                records.records.append(lease.record)
                let pending = try ReadingHistoryLocalCleanupRecord.encode(records)
                try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
                try verifyCleanupPair(source: lease.source, metadata: metadata, effects: effects,
                                      checkpoint: checkpoint, admission: finalAdmission)
                try effects.writeMetadata(pending)
                let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
                guard try effects.readMetadata() == pending, try effects.readSource(namespace) == lease.source else { throw CleanupFailure.unconfirmed }
                cleanupConfirmations[lease.owner] = .init(record: lease.record, observed: true)
                metadata = pending
                try permitted.get(); try checkCleanup(checkpoint, finalAdmission)
            }
            if lease.source != lease.target {
                guard let target = lease.target else { throw CleanupFailure.invalidLease }
                try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
                try verifyCleanupPair(source: lease.source, metadata: metadata, effects: effects,
                                      checkpoint: checkpoint, admission: finalAdmission)
                try effects.writeSource(namespace, target)
                let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
                guard try effects.readSource(namespace) == target, try effects.readMetadata() == metadata else { throw CleanupFailure.unconfirmed }
                try permitted.get(); try checkCleanup(checkpoint, finalAdmission)
            }
            guard let index = records.records.firstIndex(where: { $0.owner == lease.owner }) else { throw CleanupFailure.unconfirmed }
            if records.records[index].phase != .complete {
                records.records[index].phase = .complete
                let completedMetadata = try ReadingHistoryLocalCleanupRecord.encode(records)
                try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
                try verifyCleanupPair(source: lease.target, metadata: metadata, effects: effects,
                                      checkpoint: checkpoint, admission: finalAdmission)
                try effects.writeMetadata(completedMetadata)
                let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
                guard try effects.readMetadata() == completedMetadata, try effects.readSource(namespace) == lease.target else { throw CleanupFailure.unconfirmed }
                metadata = completedMetadata
                cleanupConfirmations[lease.owner] = .init(record: records.records[index], observed: true)
                try permitted.get(); try checkCleanup(checkpoint, finalAdmission)
            }
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            try verifyCleanupPair(source: lease.target, metadata: metadata, effects: effects,
                                  checkpoint: checkpoint, admission: finalAdmission)
            var target = lease.record; target.phase = .complete
            guard records.records[index] == target else { throw CleanupFailure.unconfirmed }
            return .init(record: target)
        }
    }

    private func cleanupNamespace(_ checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) throws -> ReadingHistoryNamespace {
        guard let namespace = ReadingHistoryContext.confirmed(userID: checkpoint.request.expectedUID).namespace,
              namespace != .guest else { throw CleanupFailure.differentOriginal }
        return namespace
    }
    private func cleanupSource(_ data: Data?, namespace: ReadingHistoryNamespace) throws -> ReadingHistoryRecord? {
        guard let data else { return nil }
        let value = try ReadingHistoryRecordCodec.decode(data, namespace: namespace)
        // Canonical destructive preflight rejects unknown/repeated fields rather
        // than silently dropping an unrecognized payload during re-encoding.
        guard try ReadingHistoryRecordCodec.encode(value, namespace: namespace) == data else { throw CleanupFailure.invalidRecord }
        return value
    }
    private func cleanupTarget(source: Data?, namespace: ReadingHistoryNamespace) throws -> Data? {
        guard source != nil else { return nil }
        return try ReadingHistoryRecordCodec.encode(.empty, namespace: namespace)
    }
    private func retainedCleanupTarget(_ record: ReadingHistoryLocalCleanupRecord, source: Data?, namespace: ReadingHistoryNamespace) throws -> Data? {
        if record.matchesTarget(source) { return source }
        guard record.phase == .pending, record.matchesSource(source) else { throw CleanupFailure.changedSource }
        let target = try cleanupTarget(source: source, namespace: namespace)
        guard record.matchesTarget(target) else { throw CleanupFailure.changedSource }
        return target
    }
    private func checkCleanup(_ checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                              _ finalAdmission: ReaderLegacyWriteAdmission) throws {
        try Task.checkCancellation()
        guard finalAdmission.isAllowed, let recovery, !recovery.admission.isAllowed,
              checkpoint.phase == .ledger, recovery.hasVerifiedSeal(binding: checkpoint.marker.binding),
              recovery.deletionCheckpoint?.phase == .ledger,
              recovery.deletionCheckpoint?.isSameFamily(as: checkpoint) == true else { throw CleanupFailure.denied }
    }
    private func authorizeCleanup(_ checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                                  _ finalAdmission: ReaderLegacyWriteAdmission, _ stillCurrent: @MainActor () -> Bool) throws {
        try checkCleanup(checkpoint, finalAdmission)
        guard stillCurrent() else { finalAdmission.setAllowed(false); throw CleanupFailure.denied }
        try checkCleanup(checkpoint, finalAdmission)
    }
    private func verifyCleanupPair(source: Data?, metadata: Data?, effects: Storage.Cleanup,
                                   checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                                   admission: ReaderLegacyWriteAdmission) throws {
        let namespace = try cleanupNamespace(checkpoint)
        // Bounded sequential readbacks under the same physical owner. Recheck
        // the source after the metadata callback; this is not a two-key atomic
        // transaction, cross-process lock or filesystem durability promise.
        guard try effects.readSource(namespace) == source else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
        guard try effects.readMetadata() == metadata else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
        guard try effects.readSource(namespace) == source else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
    }

    private func withStorage<T>(_ effect: () throws -> T) rethrows -> T {
        storageInFlight = true
        defer {
            storageInFlight = false
            if let token = deferredLoad {
                deferredLoad = nil
                if operation == token { load(token) }
            }
        }
        return try effect()
    }
}
