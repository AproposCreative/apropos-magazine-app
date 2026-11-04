import Combine
import CryptoKit
import Foundation

/// Independent device-local records. No provider, push preference or account
/// storage is read by these models; adapters explicitly start them after launch.
struct ReaderIntroductionStorage {
    struct Cleanup {
        let read: () throws -> Data?
        let write: (Data) throws -> Void
    }
    let read: () throws -> Data?
    let write: (Data) throws -> Void
    let cleanup: Cleanup?
    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void, cleanup: Cleanup? = nil) {
        self.read = read; self.write = write; self.cleanup = cleanup
    }
}

private enum ReaderIntroductionCodec {
    static let maximumBytes = 16_384
    enum Failure: Error { case invalid, unconfirmed }
    static func owner(_ context: CanonicalSessionState.Context) -> String? {
        switch context {
        case .unresolved: return nil
        case .guest: return "guest"
        case .account(let uid): return ReaderIntroductionLocalCleanupRecord.owner(uid)
        }
    }
    static func validOwner(_ value: String?) -> Bool {
        guard let value else { return true }
        if value == "guest" { return true }
        let hash = value.dropFirst("account:".count)
        return value.hasPrefix("account:") && hash.utf8.count == 64
            && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func normalized(_ ids: [String]) -> [String] {
        let valid = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && $0.utf8.count <= 128 && !$0.contains("/") && $0 != "." && $0 != ".."
                && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        return Array(Set(valid).sorted().prefix(20))
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.invalid }
        return try JSONDecoder().decode(type, from: data)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw Failure.invalid }
        return data
    }
}

@MainActor
final class ReaderIntroductionModel: ObservableObject {
    typealias Storage = ReaderIntroductionStorage
    typealias CleanupFailure = ReaderIntroductionLocalCleanupRecord.Failure
    struct CleanupLease: Sendable {
        fileprivate let modelID: UUID
        fileprivate let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        fileprivate let source: Data?
        fileprivate let metadata: Data?
        fileprivate let target: Data?
        fileprivate let record: ReaderIntroductionLocalCleanupRecord
        fileprivate let use: CleanupUse
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
    }
    struct CleanupReceipt: Equatable, Sendable {
        fileprivate let record: ReaderIntroductionLocalCleanupRecord
        var owner: String { record.owner }
        var originalEntryCount: Int { record.originalEntryCount }
        var isComplete: Bool { record.phase == .complete }
        func belongs(to checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool { record.belongs(to: checkpoint) }
    }
    @MainActor fileprivate final class CleanupUse {
        private var used = false
        func consume() throws { guard !used else { throw CleanupFailure.invalidLease }; used = true }
    }
    enum Step: String, Codable, Equatable, Sendable { case welcome, interests, account }
    /// Captured synchronously for the provider action started by this welcome.
    /// A login elsewhere cannot advance this introduction merely by changing
    /// the canonical account.
    struct AccountEntryTicket: Equatable {
        let originalContext: CanonicalSessionState.ContextTicket
        let actionID: UUID
        fileprivate let id: UUID
    }
    struct Snapshot: Equatable {
        let step: Step
        let selectedTopicIDs: [String]
        let isCompleted: Bool
        let isPresented: Bool
        let hasLoaded: Bool
        let storageError: String?
        let revision: UUID
    }
    private struct Record: Codable, Equatable {
        var schemaVersion = 3
        var completed = false
        var replaying = false
        var step: Step = .welcome
        var selectedTopicIDs: [String] = []
        var draftOwner: String? = nil
        var isValid: Bool {
            (1...3).contains(schemaVersion) && (!replaying || completed) && ReaderIntroductionCodec.validOwner(draftOwner)
                && selectedTopicIDs.count <= 20 && selectedTopicIDs == ReaderIntroductionCodec.normalized(selectedTopicIDs)
        }
        var migrated: Record {
            guard schemaVersion < 3 else { return self }
            var value = self
            value.schemaVersion = 3
            // Older flows could persist an interests/newsletter entry before
            // the welcome account choice. Start that legacy draft at welcome;
            // completed introductions stay completed. A schema 2 replay was
            // explicitly started by the reader and still needs to finish.
            value.step = .welcome
            value.replaying = schemaVersion == 2 && replaying
            return value
        }
    }
    private struct AccountEntry {
        let ticket: AccountEntryTicket
        let selectedTopicIDs: [String]
        let isManualReplay: Bool
        var acceptedContext: CanonicalSessionState.ContextTicket?
    }
    private struct InterestSeed {
        let context: CanonicalSessionState.ContextTicket
        var revision: UUID?
        var localWritePending = false
        var sourceIsCurrent: (() -> Bool)?
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let subject = PassthroughSubject<Snapshot, Never>()
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] in self?.snapshot.revision == $0.revision }.eraseToAnyPublisher()
    }
    private(set) var snapshot = Snapshot(step: .welcome, selectedTopicIDs: [], isCompleted: false,
        isPresented: false, hasLoaded: false, storageError: nil, revision: UUID())
    var step: Step { snapshot.step }
    var selectedTopicIDs: [String] { snapshot.selectedTopicIDs }
    var isCompleted: Bool { snapshot.isCompleted }
    var isPresented: Bool { snapshot.isPresented }
    var hasLoaded: Bool { snapshot.hasLoaded }
    var storageError: String? { snapshot.storageError }
    var isSaving: Bool { writing }
    private let storage: Storage
    private let cleanupModelID = UUID()
    private struct Confirmation { var record: ReaderIntroductionLocalCleanupRecord; var observed: Bool }
    private var cleanupConfirmations: [String: Confirmation] = [:]
    var isPhysicallyIdle: Bool { !writing }
    private let recovery: ReaderTransitionRecovery?
    private var recoveryObservation: AnyCancellable?
    private var admittedOnce = false
    private var recoveryRevoked = false
    private var record = Record()
    private var storedRecord = Record()
    private var boundContext: CanonicalSessionState.ContextTicket?
    private var contextIsCurrent: ((CanonicalSessionState.ContextTicket) -> Bool)?
    private var accountEntry: AccountEntry?
    private var manualReplayContext: CanonicalSessionState.ContextTicket?
    private var manualReplayInterestSeedConsumed = false
    private var interestSeed: InterestSeed?
    var isAwaitingSavedInterests: Bool { interestSeed != nil && step == .interests }
    private var pending: Record?
    private var operation = UUID()
    private var notifying = false
    private var writing = false

    init(storage: Storage, recovery: ReaderTransitionRecovery? = nil) {
        self.storage = storage
        self.recovery = recovery
        recoveryObservation = recovery?.changes.sink { [weak self] in
            guard let self, self.admittedOnce, !self.permitsIntroduction else { return }
            self.revokeForRecovery()
        }
    }

    /// Pure last-effect gate. A cold unresolved bootstrap performs no I/O, but
    /// may still admit the first normal introduction after its missing read.
    var permitsIntroduction: Bool { !recoveryRevoked && (recovery?.admission.isAllowed ?? true) }

    private func admit() -> Bool {
        guard permitsIntroduction else {
            if admittedOnce { revokeForRecovery() }
            return false
        }
        admittedOnce = true
        return true
    }

    private func revokeForRecovery() {
        guard !recoveryRevoked else { return }
        recoveryRevoked = true
        let token = reserve()
        boundContext = nil
        contextIsCurrent = nil
        pending = nil
        accountEntry = nil
        manualReplayContext = nil; manualReplayInterestSeedConsumed = false; interestSeed = nil
        // In-flight synchronous writes may return their original bytes. This
        // retirement never writes a replacement or erases another draft owner.
        record = Record()
        notify()
        guard operation == token else { return }
        snapshot = Snapshot(step: .welcome, selectedTopicIDs: [], isCompleted: false,
            isPresented: false, hasLoaded: false, storageError: nil, revision: UUID())
        subject.send(snapshot)
    }

    /// Bind from the canonical account publisher before presenting the UI. A
    /// generation change invalidates pending actions even when the UID returns.
    @discardableResult func bindContext(_ context: CanonicalSessionState.ContextTicket,
        isCurrent: @escaping (CanonicalSessionState.ContextTicket) -> Bool) -> Bool {
        guard admit() else { return false }
        let token = reserve()
        let valid = isCurrent(context)
        guard admit(), valid, operation == token else { return false }
        if boundContext == context { return true }
        if var entry = accountEntry {
            if boundContext == entry.ticket.originalContext,
               entry.acceptedContext == nil, context.userID != nil {
                // The provider's canonical publication precedes its accepted
                // result callback. Permit this one transition, not a later ABA.
                entry.acceptedContext = context
                accountEntry = entry
                manualReplayContext = entry.isManualReplay ? context : nil
            } else {
                accountEntry = nil
                manualReplayContext = nil
                manualReplayInterestSeedConsumed = false
            }
        } else {
            manualReplayContext = nil
            manualReplayInterestSeedConsumed = false
        }
        interestSeed = nil
        boundContext = context; contextIsCurrent = isCurrent; pending = nil
        var projection = scoped(storedRecord)
        if accountEntry?.acceptedContext == context {
            // Keep a manually replayed welcome mounted until its own receipt
            // arrives; dismissing it here could cancel the provider callback.
            projection.replaying = projection.completed
        }
        return publish(projection, loaded: hasLoaded, error: nil, token: token)
    }
    private func scoped(_ value: Record) -> Record {
        let owner = boundContext.flatMap { ReaderIntroductionCodec.owner($0.context) }
        guard let owner, owner == value.draftOwner else {
            var clean = value
            clean.draftOwner = owner; clean.selectedTopicIDs = []; clean.step = .welcome; clean.replaying = false
            return clean
        }
        return value
    }
    private func current(_ context: CanonicalSessionState.ContextTicket?, token: UUID) -> Bool {
        guard admit(), let context, context.context != .unresolved, boundContext == context,
              let check = contextIsCurrent else { return false }
        let valid = check(context)
        return admit() && valid && operation == token && boundContext == context
    }

    @discardableResult func start() -> Bool {
        guard admit(), !writing else { return false }
        guard !hasLoaded else { return true }
        let token = reserve()
        do {
            let data = try { () throws -> Data? in
                writing = true; defer { writing = false }
                return try storage.read()
            }()
            guard admit(), operation == token else { return false }
            let loaded = try data.map { try ReaderIntroductionCodec.decode(Record.self, from: $0) } ?? Record()
            guard loaded.isValid else { throw ReaderIntroductionCodec.Failure.invalid }
            if let original = boundContext, original.context != .unresolved {
                guard current(original, token: token) else { return false }
            }
            let migrated = loaded.migrated
            storedRecord = migrated
            return publish(scoped(migrated), loaded: true, error: nil, token: token)
        } catch {
            guard admit(), operation == token else { return false }
            _ = publish(record, loaded: false, error: "Introduktionen kunne ikke indlæses. Prøv igen.", token: token)
            return false
        }
    }
    func beginAccountEntry(actionID: UUID, fromFeature: Bool = false) -> AccountEntryTicket? {
        guard admit(), hasLoaded, (fromFeature || (isPresented && step == .welcome)), !writing,
              let original = boundContext, original.context == .guest else { return nil }
        let token = reserve()
        guard current(original, token: token) else { return nil }
        let ticket = AccountEntryTicket(originalContext: original, actionID: actionID, id: UUID())
        accountEntry = AccountEntry(ticket: ticket, selectedTopicIDs: fromFeature ? [] : selectedTopicIDs,
            isManualReplay: !fromFeature && manualReplayContext == original)
        pending = nil
        return ticket
    }
    func cancelAccountEntry(_ ticket: AccountEntryTicket) {
        guard accountEntry?.ticket == ticket else { return }
        accountEntry = nil
        _ = reserve()
    }
    /// Consume an exact provider receipt once. New readers personalize after
    /// login; ordinary returning readers leave without overwriting preferences.
    /// An explicitly replayed presentation continues, independently of account age.
    @discardableResult func acceptLogin(_ result: ReaderLoginResult, ticket: AccountEntryTicket) -> Bool {
        guard admit(), let entry = accountEntry, entry.ticket == ticket,
              result.actionID == ticket.actionID,
              result.originalContext == ticket.originalContext,
              result.acceptedContext == entry.acceptedContext,
              result.acceptedContext.userID == result.session.uid else { return false }
        let token = reserve()
        guard current(result.acceptedContext, token: token), accountEntry?.ticket == ticket else { return false }
        accountEntry = nil
        var next = record
        next.draftOwner = ReaderIntroductionCodec.owner(result.acceptedContext.context)
        next.selectedTopicIDs = result.isNewUser ? entry.selectedTopicIDs : []
        if result.isNewUser || entry.isManualReplay {
            next.step = .interests
            next.replaying = next.completed
            if entry.isManualReplay, result.isNewUser { manualReplayInterestSeedConsumed = true }
            if !result.isNewUser {
                interestSeed = InterestSeed(context: result.acceptedContext)
            }
        } else {
            next.completed = true
            next.replaying = false
            manualReplayContext = nil
        }
        return persist(next)
    }
    @discardableResult func advance() -> Bool {
        interestSeed = nil
        var next = record
        switch next.step { case .welcome: next.step = .interests; case .interests: next.step = .account; case .account: return false }
        if next.step == .interests, let context = boundContext,
           context.userID != nil, manualReplayContext == context, !manualReplayInterestSeedConsumed {
            interestSeed = InterestSeed(context: context)
        }
        return persist(next)
    }
    @discardableResult func back() -> Bool {
        interestSeed = nil
        var next = record
        switch next.step { case .welcome: return false; case .interests: next.step = .welcome; case .account: next.step = .interests }
        if next.step == .interests, let context = boundContext,
           context.userID != nil, manualReplayContext == context, !manualReplayInterestSeedConsumed {
            interestSeed = InterestSeed(context: context)
        }
        return persist(next)
    }
    @discardableResult func toggleTopic(_ id: String) -> Bool {
        guard let normalized = ReaderIntroductionCodec.normalized([id]).first else { return false }
        var ids = selectedTopicIDs
        if ids.contains(normalized) { ids.removeAll { $0 == normalized } }
        else { guard ids.count < 20 else { return false }; ids.append(normalized) }
        return setSelectedTopicIDs(ids)
    }
    @discardableResult func setSelectedTopicIDs(_ ids: [String]) -> Bool {
        interestSeed = nil
        if step == .interests, let context = boundContext,
           context.userID != nil, manualReplayContext == context {
            // Even an explicit empty choice belongs to this presentation and
            // must survive Back/Continue without being replaced by a seed.
            manualReplayInterestSeedConsumed = true
        }
        var next = record; next.selectedTopicIDs = ReaderIntroductionCodec.normalized(ids)
        return persist(next)
    }
    /// One local draft seed, never an account-preferences write. The producer
    /// must still own the exact accepted source snapshot at every storage edge.
    @discardableResult func seedSavedInterests(_ ids: [String], context: CanonicalSessionState.ContextTicket,
        stillCurrent: @escaping () -> Bool) -> Bool {
        guard admit(), let seed = interestSeed, !seed.localWritePending,
              seed.context == context, boundContext == context, seed.revision == snapshot.revision,
              step == .interests, isPresented else { return false }
        let token = reserve()
        guard current(context, token: token), stillCurrent(), current(context, token: token),
              seed.revision == snapshot.revision, interestSeed?.context == context,
              interestSeed?.revision == seed.revision else { return false }
        interestSeed?.localWritePending = true
        interestSeed?.sourceIsCurrent = stillCurrent
        var next = record
        next.selectedTopicIDs = ReaderIntroductionCodec.normalized(ids)
        let accepted = persist(next, additionalAdmission: stillCurrent)
        if !accepted, storageError == nil, interestSeed?.context == context {
            interestSeed?.localWritePending = false
        }
        return accepted
    }
    @discardableResult func complete() -> Bool {
        manualReplayContext = nil; manualReplayInterestSeedConsumed = false; interestSeed = nil
        var next = record; next.completed = true; next.replaying = false
        return persist(next)
    }
    /// Skipping records only that the introduction was dismissed, never login,
    /// email consent, successful signup or a push authorization decision.
    @discardableResult func skip() -> Bool { complete() }
    @discardableResult func replay() -> Bool {
        guard admit(), hasLoaded, !writing, let context = boundContext,
              context.context != .unresolved, contextIsCurrent?(context) == true else { return false }
        manualReplayContext = context; manualReplayInterestSeedConsumed = false; interestSeed = nil
        var next = record
        // Explicit replay always shows the account choice first. A currently
        // signed-in reader can continue with that account from the welcome.
        next.step = .welcome
        next.replaying = next.completed
        return persist(next)
    }
    @discardableResult func retry() -> Bool {
        guard admit() else { return false }
        guard hasLoaded else { return start() }
        guard let pending else { return storageError == nil }
        if let seed = interestSeed, seed.localWritePending {
            let token = reserve(), original = boundContext
            guard seed.context == original, current(original, token: token) else { return false }
            let sourceIsCurrent = seed.sourceIsCurrent
            let sourceAccepted = sourceIsCurrent?() ?? false
            guard current(original, token: token), interestSeed?.context == seed.context,
                  interestSeed?.localWritePending == true else { return false }
            guard sourceAccepted, let sourceIsCurrent else {
                interestSeed?.localWritePending = false
                interestSeed?.sourceIsCurrent = nil
                interestSeed?.revision = nil
                self.pending = nil
                // A fresh source may have arrived while the failed local write
                // owned the seed. Publish its retirement so the existing view
                // revision observer can feed that already-current source once.
                _ = publish(record, loaded: hasLoaded, error: nil, token: token)
                return false
            }
            return persist(pending, additionalAdmission: sourceIsCurrent)
        }
        return persist(pending)
    }
    /// Explicit recovery-only operations share the existing synchronous writer.
    /// Async signatures fit the coordinator; there is no artificial suspension,
    /// queue or timer preemption of an already-entered Defaults effect.
    func prepareLocalCleanup(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
                             finalAdmission: ReaderLegacyWriteAdmission,
                             stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupLease {
        guard !writing else { throw CleanupFailure.busy }
        writing = true; defer { writing = false }
        try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
        guard let effects = storage.cleanup else { throw CleanupFailure.unavailable }
        let source = try storage.read(); try checkCleanup(checkpoint, finalAdmission)
        let metadata = try effects.read(); try checkCleanup(checkpoint, finalAdmission)
        let parsed = try cleanupSource(source)
        let records = try ReaderIntroductionLocalCleanupRecord.decode(metadata)
        let owner = ReaderIntroductionLocalCleanupRecord.owner(checkpoint.request.expectedUID)
        let existing = records.records.first { $0.owner == owner }
        let record: ReaderIntroductionLocalCleanupRecord
        let target: Data?
        if let existing {
            guard existing.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
            if let confirmed = cleanupConfirmations[owner], !confirmed.record.sameOriginal(as: existing) { throw CleanupFailure.changedSource }
            record = existing
            target = try retainedCleanupTarget(existing, source: source, parsed: parsed)
        } else if let confirmed = cleanupConfirmations[owner] {
            guard !confirmed.observed else { throw CleanupFailure.unconfirmed }
            guard confirmed.record.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
            record = confirmed.record
            target = try retainedCleanupTarget(record, source: source, parsed: parsed)
        } else {
            guard records.records.count < ReaderIntroductionLocalCleanupRecord.maximumRecords,
                  cleanupConfirmations.count < ReaderIntroductionLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
            let ownsDraft = parsed?.draftOwner == ReaderIntroductionCodec.owner(.account(checkpoint.request.expectedUID))
            target = try cleanupTarget(source: source, parsed: parsed, owned: ownsDraft)
            record = try .init(checkpoint: checkpoint, source: source, target: target, ownedDraft: ownsDraft,
                               originalEntryCount: ownsDraft ? parsed?.selectedTopicIDs.count ?? 0 : 0, completed: parsed?.completed)
        }
        try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
        try verifyCleanupPair(source: source, metadata: metadata, effects: effects, checkpoint: checkpoint, admission: finalAdmission)
        return .init(modelID: cleanupModelID, checkpoint: checkpoint, source: source, metadata: metadata,
                     target: target, record: record, use: CleanupUse())
    }

    func commitLocalCleanup(_ lease: CleanupLease, finalAdmission: ReaderLegacyWriteAdmission,
                            stillCurrent: @escaping @MainActor () -> Bool) async throws -> CleanupReceipt {
        guard lease.modelID == cleanupModelID else { throw CleanupFailure.invalidLease }
        guard !writing else { throw CleanupFailure.busy }
        try lease.use.consume()
        writing = true; defer { writing = false }
        let checkpoint = lease.checkpoint
        try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
        guard let effects = storage.cleanup else { throw CleanupFailure.unavailable }
        try verifyCleanupPair(source: lease.source, metadata: lease.metadata, effects: effects,
                              checkpoint: checkpoint, admission: finalAdmission)
        if let confirmed = cleanupConfirmations[lease.owner] {
            guard confirmed.record.sameOriginal(as: lease.record) else { throw CleanupFailure.changedSource }
        } else {
            guard cleanupConfirmations.count < ReaderIntroductionLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
            cleanupConfirmations[lease.owner] = .init(record: lease.record, observed: false)
        }
        var records = try ReaderIntroductionLocalCleanupRecord.decode(lease.metadata)
        var metadata = lease.metadata
        if let existing = records.records.first(where: { $0.owner == lease.owner }) {
            guard existing == lease.record else { throw CleanupFailure.changedSource }
            cleanupConfirmations[lease.owner] = .init(record: existing, observed: true)
        } else {
            guard lease.record.phase == .pending,
                  records.records.count < ReaderIntroductionLocalCleanupRecord.maximumRecords else { throw CleanupFailure.capacityExceeded }
            records.records.append(lease.record)
            let pending = try ReaderIntroductionLocalCleanupRecord.encode(records)
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            try verifyCleanupPair(source: lease.source, metadata: metadata, effects: effects,
                                  checkpoint: checkpoint, admission: finalAdmission)
            try effects.write(pending)
            let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
            guard try effects.read() == pending, try storage.read() == lease.source else { throw CleanupFailure.unconfirmed }
            cleanupConfirmations[lease.owner] = .init(record: lease.record, observed: true)
            metadata = pending
            try permitted.get(); try checkCleanup(checkpoint, finalAdmission)
        }
        if lease.source != lease.target {
            guard let target = lease.target, lease.record.ownedDraft else { throw CleanupFailure.invalidLease }
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            try verifyCleanupPair(source: lease.source, metadata: metadata, effects: effects,
                                  checkpoint: checkpoint, admission: finalAdmission)
            try storage.write(target)
            let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
            guard try storage.read() == target, try effects.read() == metadata else { throw CleanupFailure.unconfirmed }
            try permitted.get(); try checkCleanup(checkpoint, finalAdmission)
        }
        guard let index = records.records.firstIndex(where: { $0.owner == lease.owner }) else { throw CleanupFailure.unconfirmed }
        if records.records[index].phase != .complete {
            records.records[index].phase = .complete
            let completedMetadata = try ReaderIntroductionLocalCleanupRecord.encode(records)
            try authorizeCleanup(checkpoint, finalAdmission, stillCurrent)
            try verifyCleanupPair(source: lease.target, metadata: metadata, effects: effects,
                                  checkpoint: checkpoint, admission: finalAdmission)
            try effects.write(completedMetadata)
            let permitted = Result { try checkCleanup(checkpoint, finalAdmission) }
            guard try effects.read() == completedMetadata, try storage.read() == lease.target else { throw CleanupFailure.unconfirmed }
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

    private func cleanupSource(_ data: Data?) throws -> Record? {
        guard let data else { return nil }
        let value = try ReaderIntroductionCodec.decode(Record.self, from: data)
        guard value.isValid, try ReaderIntroductionCodec.encode(value) == data else { throw CleanupFailure.invalidRecord }
        return value
    }
    private func cleanupTarget(source: Data?, parsed: Record?, owned: Bool) throws -> Data? {
        guard owned, var parsed else { return source }
        // Device completion is deliberately independent of the account draft.
        // Clearing replay never turns a completed introduction back on.
        parsed.draftOwner = nil; parsed.selectedTopicIDs = []; parsed.step = .welcome; parsed.replaying = false
        return try ReaderIntroductionCodec.encode(parsed)
    }
    private func retainedCleanupTarget(_ record: ReaderIntroductionLocalCleanupRecord, source: Data?, parsed: Record?) throws -> Data? {
        guard parsed?.completed == record.completed else { throw CleanupFailure.changedSource }
        if record.matchesTarget(source) { return source }
        guard record.phase == .pending, record.matchesSource(source) else { throw CleanupFailure.changedSource }
        let target = try cleanupTarget(source: source, parsed: parsed, owned: record.ownedDraft)
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
        // Bounded sequential readbacks under the same physical owner. Recheck
        // the source after the metadata callback; this is not a two-key atomic
        // transaction, cross-process lock or filesystem durability promise.
        guard try storage.read() == source else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
        guard try effects.read() == metadata else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
        guard try storage.read() == source else { throw CleanupFailure.changedSource }
        try checkCleanup(checkpoint, admission)
    }

    private func reserve() -> UUID { let token = UUID(); operation = token; return token }
    private func notify() {
        guard !notifying else { return }
        notifying = true; objectWillChange.send(); notifying = false
    }
    private func persist(_ next: Record, additionalAdmission: (() -> Bool)? = nil) -> Bool {
        guard admit(), hasLoaded, !writing else { return false }
        accountEntry = nil
        let token = reserve(), original = boundContext
        func admitted() -> Bool {
            guard current(original, token: token), additionalAdmission?() ?? true else { return false }
            return current(original, token: token)
        }
        guard admitted() else { return false }
        // Observers may replace this proposal before any storage effect begins.
        notify()
        guard admitted() else { return false }
        pending = next
        writing = true
        do {
            let data = try ReaderIntroductionCodec.encode(next)
            guard admitted() else { writing = false; return false }
            try storage.write(data)
            guard admitted() else { writing = false; return false }
            guard try storage.read() == data else { throw ReaderIntroductionCodec.Failure.unconfirmed }
            writing = false
            guard admitted() else { return false }
            pending = nil; storedRecord = next
            return publish(next, loaded: true, error: nil, token: token, notifyObservers: false)
        } catch {
            writing = false
            guard current(original, token: token) else { return false }
            _ = publish(record, loaded: true, error: "Dit valg kunne ikke gemmes. Prøv igen.", token: token, notifyObservers: false)
            return false
        }
    }
    private func publish(_ value: Record, loaded: Bool, error: String?, token: UUID, notifyObservers: Bool = true) -> Bool {
        guard admit(), operation == token else { return false }
        if notifyObservers { notify() }
        guard admit(), operation == token else { return false }
        record = value
        snapshot = Snapshot(step: value.step, selectedTopicIDs: value.selectedTopicIDs, isCompleted: value.completed,
            isPresented: (loaded || error != nil) && boundContext?.context != nil && boundContext?.context != .unresolved
                && (!value.completed || value.replaying), hasLoaded: loaded, storageError: error, revision: UUID())
        if var seed = interestSeed, seed.context == boundContext, value.step == .interests {
            if seed.localWritePending, error == nil {
                interestSeed = nil
                manualReplayInterestSeedConsumed = true
            }
            else if seed.revision == nil { seed.revision = snapshot.revision; interestSeed = seed }
        }
        let committed = snapshot
        subject.send(committed)
        return admit() && operation == token && snapshot.revision == committed.revision
    }
}

@MainActor
final class GuestReaderInterestsModel: ObservableObject {
    typealias Storage = ReaderIntroductionStorage
    struct Snapshot: Equatable {
        let selectedTopicIDs: [String]
        let hasLoaded: Bool
        let storageError: String?
        let revision: UUID
    }
    private struct Record: Codable {
        let schemaVersion: Int
        let selectedTopicIDs: [String]
        var isValid: Bool {
            schemaVersion == 1 && selectedTopicIDs.count <= 20
                && selectedTopicIDs == ReaderIntroductionCodec.normalized(selectedTopicIDs)
        }
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let subject = PassthroughSubject<Snapshot, Never>()
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] in self?.snapshot.revision == $0.revision }.eraseToAnyPublisher()
    }
    private(set) var snapshot = Snapshot(selectedTopicIDs: [], hasLoaded: false, storageError: nil, revision: UUID())
    var selectedTopicIDs: [String] { snapshot.selectedTopicIDs }
    var hasLoaded: Bool { snapshot.hasLoaded }
    var storageError: String? { snapshot.storageError }
    private let storage: Storage
    private var operation = UUID()
    private var notifying = false
    private var writing = false
    init(storage: Storage) { self.storage = storage }

    @discardableResult func start() -> Bool {
        guard !writing else { return false }
        guard !hasLoaded else { return true }
        let token = reserve()
        do {
            let data = try storage.read()
            guard operation == token else { return false }
            let record = try data.map { try ReaderIntroductionCodec.decode(Record.self, from: $0) }
                ?? Record(schemaVersion: 1, selectedTopicIDs: [])
            guard record.isValid else { throw ReaderIntroductionCodec.Failure.invalid }
            return publish(ids: record.selectedTopicIDs, loaded: true, error: nil, token: token)
        } catch {
            guard operation == token else { return false }
            _ = publish(ids: [], loaded: false, error: "Dine interesser kunne ikke indlæses. Prøv igen.", token: token)
            return false
        }
    }

    /// This is device-only guest storage. Callers must capture the original
    /// canonical guest ticket before any deferred work; an account never owns it.
    @discardableResult func save(_ ids: [String], context: CanonicalSessionState.ContextTicket,
                                 isCurrent: (CanonicalSessionState.ContextTicket) -> Bool) -> Bool {
        guard hasLoaded, !writing, context.context == .guest else { return false }
        let token = reserve()
        func allowed() -> Bool {
            let valid = isCurrent(context)
            return valid && operation == token
        }
        guard allowed() else { return false }
        notify()
        guard allowed() else { return false }
        let normalized = ReaderIntroductionCodec.normalized(ids)
        writing = true
        do {
            let data = try ReaderIntroductionCodec.encode(Record(schemaVersion: 1, selectedTopicIDs: normalized))
            guard allowed() else { writing = false; return false }
            try storage.write(data)
            guard allowed() else { writing = false; return false }
            guard try storage.read() == data else { throw ReaderIntroductionCodec.Failure.unconfirmed }
            writing = false
            guard allowed() else { return false }
            return publish(ids: normalized, loaded: true, error: nil, token: token, notifyObservers: false)
        } catch {
            writing = false
            guard allowed() else { return false }
            _ = publish(ids: selectedTopicIDs, loaded: true, error: "Dine interesser kunne ikke gemmes. Prøv igen.", token: token, notifyObservers: false)
            return false
        }
    }
    private func reserve() -> UUID { let token = UUID(); operation = token; return token }
    private func notify() {
        guard !notifying else { return }
        notifying = true; objectWillChange.send(); notifying = false
    }
    private func publish(ids: [String], loaded: Bool, error: String?, token: UUID, notifyObservers: Bool = true) -> Bool {
        guard operation == token else { return false }
        if notifyObservers { notify() }
        guard operation == token else { return false }
        snapshot = Snapshot(selectedTopicIDs: ids, hasLoaded: loaded, storageError: error, revision: UUID())
        let committed = snapshot
        subject.send(committed)
        return operation == token && snapshot.revision == committed.revision
    }
}
