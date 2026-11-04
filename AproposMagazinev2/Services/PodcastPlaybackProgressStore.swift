import Combine
import Foundation

/// Local progress only. Construction is inert and every effect is injected.
/// Platform callbacks must carry the ticket captured when their item was adopted.
@MainActor
final class PodcastPlaybackProgressStore: ObservableObject {
    struct Storage {
        let read: @MainActor (PodcastProgressNamespace) throws -> Data?
        let write: @MainActor (PodcastProgressNamespace, Data) throws -> Void
    }
    typealias CleanupFailure = PodcastProgressLocalCleanupRecord.Failure
    typealias CleanupStorageProvider = @MainActor (ReaderTransitionRecoveryStore.DeletionCheckpoint,
        @escaping @MainActor () -> Bool) throws -> Storage
    struct CleanupLease: Sendable {
        fileprivate let modelID: UUID
        fileprivate let namespace: PodcastProgressNamespace
        fileprivate let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        fileprivate let raw: Data?
        fileprivate let record: PodcastProgressLocalCleanupRecord
        fileprivate let use: CleanupUse
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
    }
    struct CleanupReceipt: Equatable, Sendable {
        fileprivate let record: PodcastProgressLocalCleanupRecord
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
        var isComplete: Bool { record.phase == .complete }
        func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool { record.belongs(to: checkpoint) }
    }
    @MainActor fileprivate final class CleanupUse {
        private var used = false
        func consume() throws {
            guard !used else { throw CleanupFailure.invalidLease }
            used = true
        }
    }
    struct Ticket: Equatable, Sendable {
        fileprivate let modelID: UUID
        fileprivate let contextGeneration: UUID
        fileprivate let sessionID: UUID
        fileprivate let episodeID: String
        fileprivate let articleID: String?
    }
    struct Session: Equatable, Sendable {
        let ticket: Ticket
        let resumePosition: TimeInterval?
    }
    enum WriteOutcome: Equatable, Sendable { case written, unchanged, stale, unavailable }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var snapshot: PodcastProgressSnapshot
    private(set) var context = PodcastProgressContext.unresolved
    var onContextInvalidated: (@MainActor () -> Void)?

    private let storage: Storage
    private let legacyAdmission: ReaderLegacyWriteAdmission?
    private let cleanupStorageProvider: CleanupStorageProvider?
    private struct Confirmation { var record: PodcastProgressLocalCleanupRecord; var observed: Bool }
    private var confirmations: [PodcastProgressNamespace: Confirmation] = [:]
    private var observedClosedOwner: PodcastProgressNamespace?
    private static let maximumCleanupConfirmations = 64
    var isPhysicallyIdle: Bool { !storageInFlight }
    private var recoveryRevoked = false
    private let modelID = UUID()
    private var generation = UUID()
    private var operation = UUID()
    private var activeTicket: Ticket?
    private var completed = false
    private var transitioning = false
    private var loaded = false
    private var dirty = false
    private var record = PodcastProgressRecord.empty
    private var state = PodcastProgressStorageState.unresolved
    private var completionTombstones = Set<String>()
    private var storageInFlight = false
    private var deferredLoad: UUID?
    private var notifying = false

    init(storage: Storage, legacyAdmission: ReaderLegacyWriteAdmission? = nil,
         cleanupStorageProvider: CleanupStorageProvider? = nil) {
        self.storage = storage
        self.legacyAdmission = legacyAdmission
        self.cleanupStorageProvider = cleanupStorageProvider
        snapshot = PodcastProgressSnapshot(generation: generation, state: .unresolved)
    }

    func changeContext(to proposed: PodcastProgressContext) {
        let desired: PodcastProgressContext = proposed.namespace == nil ? .unresolved : proposed
        guard desired == .unresolved || permitsProgress else { return }
        guard desired != context else { return }
        transition(to: desired, recoveryInvalidation: false)
    }

    /// Existing playback hooks must run after original tickets are retired,
    /// including when an observer reenters during the closing publication.
    func revokeForRecovery() {
        guard !recoveryRevoked else { return }
        recoveryRevoked = true
        transition(to: .unresolved, recoveryInvalidation: true)
    }

    private var permitsProgress: Bool { !recoveryRevoked && (legacyAdmission?.isAllowed ?? true) }

    /// Pure admission shared with the actual session/preparation pipeline.
    /// Storage in flight does not revoke already accepted playback ownership.
    var hasPlaybackAccess: Bool {
        context.namespace.map { !isOwnerClosed($0) } == true && !transitioning && permitsProgress
    }

    private func transition(to desired: PodcastProgressContext, recoveryInvalidation: Bool) {
        let originalInvalidation: (@MainActor () -> Void)?
        if recoveryInvalidation { originalInvalidation = onContextInvalidated }
        else { originalInvalidation = nil }
        let token = beginOperation()
        generation = UUID()
        context = desired
        activeTicket = nil
        completed = false
        transitioning = true
        loaded = false
        dirty = false
        record = .empty
        completionTombstones = []
        deferredLoad = nil
        state = desired.namespace == nil ? .unresolved : .loading
        let published = publish(token)
        if recoveryInvalidation {
            // Captured before publication: a newer hook cannot receive the
            // original player's cleanup, and a failed publication cannot skip it.
            originalInvalidation?()
        } else {
            guard published else { return }
            onContextInvalidated?()
        }
        guard operation == token else { return }
        guard desired.namespace != nil else { transitioning = false;return }
        load(token)
    }

    func retryStorage() {
        guard hasPlaybackAccess, !storageInFlight,
              snapshot.canRetry else { return }
        let token = beginOperation()
        if loaded && dirty { _ = persist(token);return }
        if !loaded { load(token) }
    }

    func beginSession(episodeID: String, articleID: String?) -> Session? {
        guard hasPlaybackAccess, !storageInFlight,
              PodcastProgressRecordCodec.isValidID(episodeID),
              articleID.map(PodcastProgressRecordCodec.isValidID) ?? true else { return nil }
        let token = beginOperation()
        let ticket = Ticket(modelID: modelID, contextGeneration: generation, sessionID: UUID(),
                            episodeID: episodeID, articleID: articleID)
        activeTicket = ticket
        completed = false
        completionTombstones.remove(episodeID)
        if notifying { _ = publish(token) }
        guard operation == token, isCurrent(ticket) else { return nil }
        return Session(ticket: ticket, resumePosition: snapshot.position(for: episodeID))
    }

    /// Completion retains playback ownership so existing UI/queue logic can
    /// finish, while the separate completed barrier rejects every late save.
    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.modelID == modelID && ticket.contextGeneration == generation && activeTicket == ticket
            && hasPlaybackAccess
    }

    @discardableResult
    func save(_ ticket: Ticket, seconds: TimeInterval, duration: TimeInterval?) -> WriteOutcome {
        guard isCurrent(ticket), !completed else { return .stale }
        guard !storageInFlight else { return .unavailable }
        guard seconds.isFinite, seconds <= PodcastProgressRecordCodec.maximumDurationSeconds,
              let duration, duration.isFinite, duration > 0,
              duration <= PodcastProgressRecordCodec.maximumDurationSeconds else { return .unchanged }
        let bounded = max(0, seconds)
        if bounded >= PodcastProgressRecordCodec.completionPosition(duration: duration) { return complete(ticket) }
        guard bounded >= PodcastProgressRecordCodec.minimumSavedPosition else { return .unchanged }
        guard loaded else { return .unavailable }
        let entry = PodcastProgressRecord.Entry(episodeID: ticket.episodeID, articleID: ticket.articleID,
                                               positionSeconds: bounded, durationSeconds: duration)
        if record.entries.last == entry && record.lastEpisodeID == ticket.episodeID && !dirty { return .unchanged }
        let token = beginOperation()
        record.entries.removeAll { $0.episodeID == ticket.episodeID }
        record.entries.append(entry)
        record.entries = Array(record.entries.suffix(PodcastProgressRecordCodec.maximumEntries))
        record.lastEpisodeID = ticket.episodeID
        dirty = true
        return persist(token)
    }

    @discardableResult
    func complete(_ ticket: Ticket) -> WriteOutcome {
        guard isCurrent(ticket), !completed else { return .stale }
        let token = beginOperation()
        completed = true
        if !loaded {
            if !completionTombstones.contains(ticket.episodeID),
               completionTombstones.count >= PodcastProgressRecordCodec.maximumEntries {
                // We cannot identify which unknown disk entries were completed.
                // Keep the record untouched instead of forgetting a completion or
                // silently deleting other history. A new context starts a fresh read.
                state = .recoveryLimited
            } else if state != .recoveryLimited {
                completionTombstones.insert(ticket.episodeID)
            }
        }
        record.entries.removeAll { $0.episodeID == ticket.episodeID }
        if record.lastEpisodeID == ticket.episodeID { record.lastEpisodeID = nil }
        dirty = true
        if storageInFlight {
            state = loaded ? .writeFailed : state
            _ = publish(token)
            return .unavailable
        }
        guard loaded else { _ = publish(token);return .unavailable }
        return persist(token)
    }

    func endSession(_ ticket: Ticket) {
        guard isCurrent(ticket) else { return }
        // An already-started write still belongs to this partition and must
        // report its success/failure, even if the player closes inside an effect.
        activeTicket = nil
        completed = false
    }

    private func beginOperation() -> UUID {
        operation = UUID()
        return operation
    }

    private func load(_ token: UUID) {
        guard operation == token, permitsProgress, let namespace = context.namespace else { return }
        if storageInFlight { deferredLoad = token;return }
        let data: Data?
        do { data = try withStorage { try storage.read(namespace) } }
        catch {
            guard operation == token, permitsProgress else { return }
            transitioning = false
            state = .readFailed
            _ = publish(token)
            return
        }
        guard operation == token, permitsProgress else { return }
        do {
            let decoded = try data.map { try PodcastProgressRecordCodec.decode($0, namespace: namespace) } ?? .empty
            if decoded.cleanup != nil {
                observedClosedOwner = namespace
                record = .empty; loaded = false; transitioning = false; state = .recoveryLimited
                _ = publish(token)
                return
            }
            observedClosedOwner = nil
            record = decoded
            let original = record
            record.entries.removeAll { completionTombstones.contains($0.episodeID) }
            if let last = record.lastEpisodeID, completionTombstones.contains(last) { record.lastEpisodeID = nil }
            dirty = original != record
            loaded = true
            transitioning = false
            state = .ready
            if dirty { _ = persist(token) }
            else { _ = publish(token) }
        } catch {
            transitioning = false
            state = (error as? PodcastProgressRecordCodec.Failure) == .unsupportedVersion ? .unsupportedVersion : .invalidRecord
            _ = publish(token)
        }
    }

    private func persist(_ token: UUID) -> WriteOutcome {
        guard operation == token, permitsProgress, loaded, let namespace = context.namespace,
              !isOwnerClosed(namespace) else { return .unavailable }
        do {
            let data = try PodcastProgressRecordCodec.encode(record, namespace: namespace)
            try withStorage { try storage.write(namespace, data) }
        } catch {
            guard operation == token, permitsProgress else { return .stale }
            state = .writeFailed
            _ = publish(token)
            return operation == token ? .unavailable : .stale
        }
        guard operation == token, permitsProgress else { return .stale }
        dirty = false
        completionTombstones = []
        state = .ready
        return publish(token) ? .written : .stale
    }

    /// @Published's willSet can overwrite a newer snapshot if a subscriber
    /// changes context synchronously. Publish explicitly and recheck ownership.
    @discardableResult
    private func publish(_ token: UUID) -> Bool {
        guard operation == token, context == .unresolved || permitsProgress else { return false }
        if !notifying {
            notifying = true
            objectWillChange.send()
            notifying = false
        }
        guard operation == token, context == .unresolved || permitsProgress else { return false }
        snapshot = PodcastProgressSnapshot(generation: generation, state: state, record: record)
        return true
    }

    /// Explicit recovery only. These async signatures fit the existing task
    /// owner, but the injected storage effects and bodies remain synchronous on
    /// MainActor. A timer cannot preempt an already-entered Defaults callback.
    func prepareLocalCleanup(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                             finalAdmission: ReaderLegacyWriteAdmission,
                             stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupLease {
        guard !storageInFlight else { throw CleanupFailure.busy }
        storageInFlight = true; defer { finishStorage() }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        let namespace = try cleanupNamespace(checkpoint)
        let effects = try cleanupStorageProvider?(checkpoint, stillCurrent) ?? storage
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        let raw = try effects.read(namespace)
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        let source = try cleanupSnapshot(raw, namespace: namespace)
        let record: PodcastProgressLocalCleanupRecord
        if let existing = source.cleanup {
            guard existing.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
            if let confirmed = confirmations[namespace], !confirmed.record.sameOriginal(as: existing) { throw CleanupFailure.changedSource }
            record = existing
        } else if let confirmed = confirmations[namespace] {
            guard !confirmed.observed else { throw CleanupFailure.unconfirmed }
            guard confirmed.record.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
            try confirmed.record.validateRemaining(source, namespace: namespace)
            record = confirmed.record
        } else {
            guard confirmations.count < Self.maximumCleanupConfirmations else { throw CleanupFailure.capacityExceeded }
            record = try .init(checkpoint: checkpoint, namespace: namespace, raw: raw, record: source)
        }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        guard try effects.read(namespace) == raw else { throw CleanupFailure.changedSource }
        try checkCleanupAdmission(finalAdmission)
        return CleanupLease(modelID: modelID, namespace: namespace, checkpoint: checkpoint,
                            raw: raw, record: record, use: CleanupUse())
    }

    func commitLocalCleanup(_ lease: CleanupLease,
                            finalAdmission: ReaderLegacyWriteAdmission,
                            stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupReceipt {
        guard lease.modelID == modelID else { throw CleanupFailure.invalidLease }
        guard !storageInFlight else { throw CleanupFailure.busy }
        try lease.use.consume()
        storageInFlight = true; defer { finishStorage() }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        let namespace = try cleanupNamespace(lease.checkpoint)
        guard namespace == lease.namespace else { throw CleanupFailure.differentOriginal }
        let effects = try cleanupStorageProvider?(lease.checkpoint, stillCurrent) ?? storage
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        guard try effects.read(namespace) == lease.raw else { throw CleanupFailure.changedSource }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        var source = try cleanupSnapshot(lease.raw, namespace: namespace)
        if let confirmed = confirmations[namespace] {
            guard confirmed.record.sameOriginal(as: lease.record) else { throw CleanupFailure.changedSource }
        } else {
            guard confirmations.count < Self.maximumCleanupConfirmations else { throw CleanupFailure.capacityExceeded }
            confirmations[namespace] = Confirmation(record: lease.record, observed: false)
        }
        observedClosedOwner = namespace
        var expected = lease.raw
        if let existing = source.cleanup {
            guard existing == lease.record else { throw CleanupFailure.changedSource }
            confirmations[namespace] = Confirmation(record: existing, observed: true)
        } else {
            try lease.record.validateRemaining(source, namespace: namespace)
            source.cleanup = lease.record
            let pending = try PodcastProgressRecordCodec.encode(source, namespace: namespace)
            try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
            guard try effects.read(namespace) == expected else { throw CleanupFailure.changedSource }
            try checkCleanupAdmission(finalAdmission)
            try effects.write(namespace, pending)
            let writeAdmission = Result { try checkCleanupAdmission(finalAdmission) }
            // Always finish the original physical readback, even if a write
            // callback cancelled its task or revoked the confirmation.
            guard try effects.read(namespace) == pending else { throw CleanupFailure.unconfirmed }
            confirmations[namespace] = Confirmation(record: lease.record, observed: true)
            expected = pending
            try writeAdmission.get()
        }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        if source.cleanup?.phase != .complete {
            source.entries = []; source.lastEpisodeID = nil; source.cleanup?.phase = .complete
            let complete = try PodcastProgressRecordCodec.encode(source, namespace: namespace)
            try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
            guard try effects.read(namespace) == expected else { throw CleanupFailure.changedSource }
            try checkCleanupAdmission(finalAdmission)
            try effects.write(namespace, complete)
            let writeAdmission = Result { try checkCleanupAdmission(finalAdmission) }
            guard try effects.read(namespace) == complete else { throw CleanupFailure.unconfirmed }
            confirmations[namespace] = Confirmation(record: source.cleanup!, observed: true)
            expected = complete
            try writeAdmission.get()
        }
        try authorizeCleanup(stillCurrent, finalAdmission: finalAdmission)
        // No permission hook after this final exact readback. The coordinator
        // separately guards publication using the original action/context.
        guard try effects.read(namespace) == expected else { throw CleanupFailure.unconfirmed }
        try checkCleanupAdmission(finalAdmission)
        let final = try cleanupSnapshot(expected, namespace: namespace)
        var target = lease.record; target.phase = .complete
        guard final.cleanup == target, final.entries.isEmpty, final.lastEpisodeID == nil else { throw CleanupFailure.unconfirmed }
        return CleanupReceipt(record: target)
    }

    private func isOwnerClosed(_ namespace: PodcastProgressNamespace) -> Bool {
        observedClosedOwner == namespace || confirmations[namespace] != nil
    }

    private func cleanupNamespace(_ checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) throws -> PodcastProgressNamespace {
        guard let namespace = PodcastProgressContext.confirmed(userID: checkpoint.request.expectedUID).namespace else {
            throw CleanupFailure.differentOriginal
        }
        _ = try PodcastProgressLocalCleanupRecord(checkpoint: checkpoint, namespace: namespace, raw: nil, record: .empty)
        return namespace
    }
    private func checkCleanupAdmission(_ finalAdmission: ReaderLegacyWriteAdmission) throws {
        try Task.checkCancellation()
        guard finalAdmission.isAllowed, recoveryRevoked || legacyAdmission?.isAllowed == false else {
            throw CleanupFailure.denied
        }
    }
    private func authorizeCleanup(_ stillCurrent: @MainActor () -> Bool,
                                  finalAdmission: ReaderLegacyWriteAdmission) throws {
        try checkCleanupAdmission(finalAdmission)
        guard stillCurrent() else {
            finalAdmission.setAllowed(false)
            throw CleanupFailure.denied
        }
        try checkCleanupAdmission(finalAdmission)
    }
    private func cleanupSnapshot(_ raw: Data?, namespace: PodcastProgressNamespace) throws -> PodcastProgressRecord {
        guard let raw else { return .empty }
        let record = try PodcastProgressRecordCodec.decode(raw, namespace: namespace)
        guard try PodcastProgressRecordCodec.encode(record, namespace: namespace) == raw else { throw CleanupFailure.invalidRecord }
        return record
    }

    /// A synchronous injected effect may change account. Finish that original
    /// effect before reading the new partition; never overlap same-owner writes.
    private func withStorage<T>(_ body: () throws -> T) rethrows -> T {
        storageInFlight = true
        defer { finishStorage() }
        return try body()
    }
    private func finishStorage() {
        storageInFlight = false
        if let token = deferredLoad {
            deferredLoad = nil
            if operation == token { load(token) }
        }
    }
}
