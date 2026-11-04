import Foundation

/// One atomic owner record contains both membership and the latest outbox.
/// Registration is synchronous; bounded codec/file work runs on a private queue.
/// Atomic replacement is a commit boundary, not a power-loss/fsync guarantee.
@MainActor
final class FavoritesFileJournal {
    typealias LegacyRead = @Sendable (FavoritesNamespace) throws -> Data?
    typealias Replace = @Sendable (Data, URL) throws -> Void
    typealias LegacyDelete = @Sendable (FavoritesNamespace, Data) throws -> Void
    typealias Remove = @Sendable (URL) throws -> Void
    typealias CleanupFailure = FavoritesLocalCleanupRecord.Failure
    typealias CleanupPhase = FavoritesLocalCleanupRecord.Phase
    struct CleanupLease: Sendable {
        let namespace: FavoritesNamespace
        fileprivate let journalID: UUID
        fileprivate let record: FavoritesLocalCleanupRecord
        fileprivate let rawV1: Data?
        fileprivate let rawV2: Data?
    }
    struct CleanupReceipt: Equatable, Sendable {
        let namespace: FavoritesNamespace
        let requestID: String
        let transitionID: UUID
        let configurationDigest: String
        let phase: CleanupPhase
        var isComplete: Bool { phase == .complete }
    }
    static let maximumPendingJobs = 64
    static let maximumNamespaces = 64

    enum TransitionFailure: Error, Equatable { case frozen, invalidTicket, staleSnapshot }
    struct TransitionTicket: Equatable, Sendable {
        let namespace: FavoritesNamespace
        fileprivate let journalID: UUID
        fileprivate let id: UUID
    }
    struct SnapshotLease: Equatable, Sendable {
        let namespace: FavoritesNamespace
        let rawV1: Data?
        let rawV2: Data?
        fileprivate let ticket: TransitionTicket
        fileprivate let id: UUID
    }
    private struct Freeze {
        let ticket: TransitionTicket
        var snapshotID: UUID?
        var readySnapshotID: UUID?
    }

    private enum Work: Sendable {
        case read(FavoritesNamespace)
        case write(FavoritesNamespace, FavoritesRecord, UUID?)
        case snapshot(TransitionTicket, UUID)
        case cleanupPrepare(ReaderTransitionRecoveryStore.DeletionCheckpoint, FavoritesNamespace)
        case cleanupBegin(CleanupLease), cleanupCommit(CleanupLease)
        var namespace: FavoritesNamespace {
            switch self {
            case .read(let value), .write(let value, _, _): return value
            case .snapshot(let ticket, _): return ticket.namespace
            case .cleanupPrepare(_, let namespace): return namespace
            case .cleanupBegin(let lease), .cleanupCommit(let lease): return lease.namespace
            }
        }
    }
    private enum WorkResult: Sendable {
        case record(FavoritesRecord?)
        case snapshot(v1: Data?, v2: Data?)
        case cleanupPrepared(FavoritesLocalCleanupRecord, v1: Data?, v2: Data?)
        case cleanupReceipt(FavoritesLocalCleanupRecord)
    }
    private enum Completion {
        case read(@MainActor (Result<FavoritesRecord?, Error>) -> Void)
        case write(@MainActor (Result<Void, Error>) -> Void)
        case snapshot(@MainActor (Result<SnapshotLease, Error>) -> Void)
        case cleanupPrepare(@MainActor (Result<CleanupLease, Error>) -> Void)
        case cleanup(@MainActor (Result<CleanupReceipt, Error>) -> Void)
        @MainActor func call(_ result: Result<FavoritesRecord?, Error>) {
            switch self {
            case .read(let complete): complete(result)
            case .write(let complete): complete(result.map { _ in () })
            case .snapshot(let complete):
                if case .failure(let error) = result { complete(.failure(error)) }
                else { complete(.failure(TransitionFailure.staleSnapshot)) }
            case .cleanupPrepare(let complete):
                if case .failure(let error) = result { complete(.failure(error)) }
                else { complete(.failure(CleanupFailure.invalidLease)) }
            case .cleanup(let complete):
                if case .failure(let error) = result { complete(.failure(error)) }
                else { complete(.failure(CleanupFailure.invalidLease)) }
            }
        }
    }
    private struct Job {
        let id: UUID
        let work: Work
        let completion: Completion
        var admission: (@MainActor () -> Bool)? = nil
    }
    // A present Head with nil revision means this namespace was read as missing.
    private struct Head { let revision: UUID? }
    private let rootDirectory: URL
    private let legacyRead: LegacyRead
    private let replace: Replace
    private let legacyDelete: LegacyDelete
    private let remove: Remove
    private let legacyAdmission: ReaderLegacyWriteAdmission?
    private let ioQueue = DispatchQueue(label: "com.apropos.favorites-journal", qos: .utility)
    private var heads: [FavoritesNamespace: Head] = [:]
    private var pending: [Job] = []
    private var active: Job?
    private let journalID = UUID()
    private var freezes: [FavoritesNamespace: Freeze] = [:]
    private var cleanupClosed: Set<FavoritesNamespace> = []
    private var cleanupOperations: [FavoritesNamespace: UUID] = [:]

    init(rootDirectory: URL,
         legacyRead: @escaping LegacyRead = { _ in nil },
         replace: @escaping Replace = { data, url in try data.write(to: url, options: .atomic) },
         legacyAdmission: ReaderLegacyWriteAdmission? = nil,
         legacyDelete: @escaping LegacyDelete = { _, _ in throw CleanupFailure.legacyDeleteUnavailable },
         remove: @escaping Remove = { try FileManager.default.removeItem(at: $0) }) {
        self.rootDirectory = rootDirectory
        self.legacyRead = legacyRead
        self.replace = replace
        self.legacyAdmission = legacyAdmission
        self.legacyDelete = legacyDelete; self.remove = remove
    }

    /// The same queue covers accepted ordinary writes, snapshots and cleanup.
    /// Logical cancellation cannot make a physically active job disappear.
    var isPhysicallyIdle: Bool { active == nil && pending.isEmpty }

    func prepareLocalCleanup(checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint,
        stillCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Result<CleanupLease, Error>) -> Void) {
        guard checkpoint.phase == .ledger,
              let namespace = FavoritesContext.confirmed(userID: checkpoint.request.expectedUID).namespace,
              namespace != .guest else { completion(.failure(CleanupFailure.differentOriginal)); return }
        enqueueCleanup(.cleanupPrepare(checkpoint, namespace), stillCurrent: stillCurrent, completion: .cleanupPrepare(completion))
    }

    func beginLocalCleanup(_ lease: CleanupLease, stillCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Result<CleanupReceipt, Error>) -> Void) {
        guard lease.journalID == journalID else { completion(.failure(CleanupFailure.invalidLease)); return }
        enqueueCleanup(.cleanupBegin(lease), stillCurrent: stillCurrent, completion: .cleanup(completion))
    }

    func commitLocalCleanup(_ lease: CleanupLease, stillCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Result<CleanupReceipt, Error>) -> Void) {
        guard lease.journalID == journalID else { completion(.failure(CleanupFailure.invalidLease)); return }
        enqueueCleanup(.cleanupCommit(lease), stillCurrent: stillCurrent, completion: .cleanup(completion))
    }

    private func enqueueCleanup(_ work: Work, stillCurrent: @escaping @MainActor () -> Bool, completion: Completion) {
        let namespace = work.namespace, token = UUID()
        var namespaces = knownNamespaces(); namespaces.insert(namespace)
        guard namespaces.count <= Self.maximumNamespaces else {
            completion.call(.failure(FavoritesRecordCodec.Failure.limitExceeded)); return
        }
        cleanupOperations[namespace] = token
        var denied = false
        let original: @MainActor () -> Bool = { [weak self] in
            guard !denied, let self, self.cleanupOperations[namespace] == token else { return false }
            let current = stillCurrent()
            guard current, !denied, self.cleanupOperations[namespace] == token else { denied = true; return false }
            return true
        }
        guard original() else { completion.call(.failure(CleanupFailure.denied)); return }
        if case .cleanupBegin = work { cleanupClosed.insert(namespace) }
        if case .cleanupCommit = work { cleanupClosed.insert(namespace) }
        enqueue(work, completion: completion, admission: original)
    }

    var storage: FavoritesModel.Storage {
        .init(read: { [self] namespace, complete in
            guard self.admitsLegacy(namespace) else { complete(.failure(TransitionFailure.frozen)); return }
            enqueue(.read(namespace), completion: .read(complete))
        }, write: { [self] namespace, record, expected, complete in
            guard self.admitsLegacy(namespace) else { complete(.failure(TransitionFailure.frozen)); return }
            guard heads[namespace] != nil else { complete(.failure(FavoritesJournalFailure.readFailed)); return }
            do { try FavoritesRecordCodec.validate(record, namespace: namespace) }
            catch { complete(.failure(error)); return }
            enqueue(.write(namespace, record, expected), completion: .write(complete))
        })
    }

    /// Closes this instance's namespace synchronously, before any callback or
    /// queued I/O. Already accepted work keeps its queue order. Other instances
    /// and processes are not fenced by this source-local transition lease.
    /// A nonnil ticket remains the recovery handle even when snapshot I/O fails.
    @discardableResult
    func freezeForTransition(namespace: FavoritesNamespace,
        completion: @escaping @MainActor (Result<SnapshotLease, Error>) -> Void
    ) -> TransitionTicket? {
        guard namespace != .guest else { completion(.failure(TransitionFailure.invalidTicket)); return nil }
        if freezes[namespace] != nil, hasWork(namespace) {
            completion(.failure(TransitionFailure.frozen)); return nil
        }
        var namespaces = knownNamespaces()
        namespaces.insert(namespace)
        guard namespaces.count <= Self.maximumNamespaces else {
            completion(.failure(FavoritesRecordCodec.Failure.limitExceeded)); return nil
        }
        // An explicit fresh action may replace an idle older freeze. Its old
        // ticket/lease never becomes authority for the replacement action.
        let ticket = TransitionTicket(namespace: namespace, journalID: journalID, id: UUID())
        freezes[namespace] = Freeze(ticket: ticket)
        retryTransitionSnapshot(ticket, completion: completion)
        return ticket
    }

    func retryTransitionSnapshot(_ ticket: TransitionTicket,
        completion: @escaping @MainActor (Result<SnapshotLease, Error>) -> Void) {
        guard owns(ticket) else { completion(.failure(TransitionFailure.invalidTicket)); return }
        let snapshotID = UUID()
        freezes[ticket.namespace]?.snapshotID = snapshotID
        freezes[ticket.namespace]?.readySnapshotID = nil
        enqueue(.snapshot(ticket, snapshotID), completion: .snapshot(completion))
    }

    func isCurrent(_ lease: SnapshotLease) -> Bool {
        owns(lease.ticket) && lease.namespace == lease.ticket.namespace
            && freezes[lease.namespace]?.readySnapshotID == lease.id && !hasWork(lease.namespace)
    }

    /// The orchestration must additionally prove original account/membership
    /// and its pre-write phase. This pure check enables atomic paired SDK/source
    /// abort on MainActor. A failed snapshot alone never reopens the source.
    func canResumeAfterAbortedTransition(_ ticket: TransitionTicket) -> Bool {
        owns(ticket) && !cleanupClosed.contains(ticket.namespace) && !hasWork(ticket.namespace)
    }

    @discardableResult
    func resumeAfterAbortedTransition(_ ticket: TransitionTicket) -> Bool {
        guard canResumeAfterAbortedTransition(ticket) else { return false }
        freezes.removeValue(forKey: ticket.namespace)
        return true
    }

    private func owns(_ ticket: TransitionTicket) -> Bool {
        ticket.journalID == journalID && freezes[ticket.namespace]?.ticket == ticket
    }
    private func hasWork(_ namespace: FavoritesNamespace) -> Bool {
        active?.work.namespace == namespace || pending.contains { $0.work.namespace == namespace }
    }
    private func knownNamespaces() -> Set<FavoritesNamespace> {
        var namespaces = Set(heads.keys).union(freezes.keys).union(cleanupClosed).union(cleanupOperations.keys)
        if let active { namespaces.insert(active.work.namespace) }
        for job in pending { namespaces.insert(job.work.namespace) }
        return namespaces
    }

    private func admitsLegacy(_ namespace: FavoritesNamespace) -> Bool {
        freezes[namespace] == nil && !cleanupClosed.contains(namespace) && (legacyAdmission?.isAllowed ?? true)
    }

    private func enqueue(_ work: Work, completion: Completion, admission: (@MainActor () -> Bool)? = nil) {
        // Only the final consecutive write can be replaced. A read is an order
        // barrier; A -> guest -> A therefore observes every preceding A commit.
        if case .write(let namespace, let record, let expected) = work,
           let last = pending.last,
           case .write(let oldNamespace, let oldRecord, let originalExpected) = last.work,
           namespace == oldNamespace, expected == oldRecord.recordRevision {
            pending[pending.count - 1] = Job(id: UUID(), work: .write(namespace, record, originalExpected), completion: completion)
            // Replace metadata before this arbitrary/reentrant callback.
            last.completion.call(.failure(FavoritesJournalFailure.superseded))
            pump()
            return
        }
        var namespaces = knownNamespaces()
        namespaces.insert(work.namespace)
        guard pending.count < Self.maximumPendingJobs, namespaces.count <= Self.maximumNamespaces else {
            completion.call(.failure(FavoritesRecordCodec.Failure.limitExceeded)); return
        }
        pending.append(Job(id: UUID(), work: work, completion: completion, admission: admission))
        pump()
    }

    private func pump() {
        guard active == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        // Reserve queue ownership before denial callbacks. Reentrant enqueue
        // or freeze must retain the original physical queue order.
        active = job
        guard job.admission?() ?? true else {
            finish(id: job.id, result: .failure(CleanupFailure.denied)); return
        }
        switch job.work {
        case .read, .write:
            guard legacyAdmission?.isAllowed ?? true else {
                finish(id: job.id, result: .failure(TransitionFailure.frozen))
                return
            }
        case .snapshot, .cleanupPrepare, .cleanupBegin, .cleanupCommit:
            break // Explicit raw preservation is needed while legacy is closed.
        }
        if case .write = job.work, heads[job.work.namespace] == nil {
            // An earlier queued read can fail after this write's registration.
            // Its invalidation must reach already queued writes as well.
            finish(id: job.id, result: .failure(FavoritesJournalFailure.readFailed))
            return
        }
        let root = rootDirectory, legacy = legacyRead, replace = replace, work = job.work, id = job.id
        let legacyDelete = legacyDelete, remove = remove
        ioQueue.async { [self] in
            let result = Result { try Self.perform(work, root: root, legacy: legacy, replace: replace,
                                                 legacyDelete: legacyDelete, remove: remove) }
            Task { @MainActor [self] in self.finish(id: id, result: result) }
        }
    }

    private func finish(id: UUID, result: Result<WorkResult, Error>) {
        guard let job = active, job.id == id else { return }
        active = nil
        if case .success(.record(let record)) = result { heads[job.work.namespace] = Head(revision: record?.recordRevision) }
        else if case .read = job.work {
            // A failed re-read invalidates any former permission to replace.
            heads.removeValue(forKey: job.work.namespace)
        }
        if case .snapshot(let ticket, let snapshotID) = job.work,
           case .snapshot(let complete) = job.completion {
            guard owns(ticket), freezes[ticket.namespace]?.snapshotID == snapshotID else {
                complete(.failure(TransitionFailure.staleSnapshot)); pump(); return
            }
            switch result {
            case .success(.snapshot(let v1, let v2)):
                freezes[ticket.namespace]?.readySnapshotID = snapshotID
                complete(.success(SnapshotLease(namespace: ticket.namespace, rawV1: v1, rawV2: v2,
                                                ticket: ticket, id: snapshotID)))
            case .failure(let error): complete(.failure(error))
            case .success: complete(.failure(TransitionFailure.staleSnapshot))
            }
        } else if case .cleanupPrepare(let complete) = job.completion {
            complete(result.flatMap { value in
                guard case .cleanupPrepared(let record, let v1, let v2) = value else { return .failure(CleanupFailure.invalidLease) }
                return .success(CleanupLease(namespace: job.work.namespace, journalID: journalID, record: record, rawV1: v1, rawV2: v2))
            })
        } else if case .cleanup(let complete) = job.completion {
            complete(result.flatMap { value in
                guard case .cleanupReceipt(let record) = value else { return .failure(CleanupFailure.invalidLease) }
                return .success(CleanupReceipt(namespace: job.work.namespace, requestID: record.requestID,
                    transitionID: record.transitionID, configurationDigest: record.configurationDigest, phase: record.phase))
            })
        } else {
            job.completion.call(result.flatMap { value in
                guard case .record(let record) = value else { return .failure(TransitionFailure.staleSnapshot) }
                return .success(record)
            })
        }
        pump()
    }

    nonisolated private static func perform(_ work: Work, root: URL, legacy: LegacyRead, replace: Replace,
                                           legacyDelete: LegacyDelete, remove: Remove) throws -> WorkResult {
        let namespace = work.namespace
        let url = try location(root: root, namespace: namespace)
        let cleanupURL = root.appendingPathComponent(namespace.recordBinding + ".cleanup.json")
        switch work {
        case .read, .write, .snapshot:
            // Existence alone closes legacy paths. A corrupt, oversized or
            // symlink tombstone is never interpreted as a missing cleanup.
            guard try fileType(cleanupURL) == nil else { throw TransitionFailure.frozen }
        case .cleanupPrepare, .cleanupBegin, .cleanupCommit: break
        }
        switch work {
        case .read:
            if let record = try readRecord(url, namespace: namespace) { return .record(record) }
            let legacyData = try legacy(namespace)
            guard try fileType(cleanupURL) == nil else { throw TransitionFailure.frozen }
            guard let data = legacyData else { return .record(nil) }
            let migrated = try FavoritesRecordCodec.migrateLegacyV1(data, namespace: namespace)
            try createDirectory(root)
            try replace(FavoritesRecordCodec.encode(migrated, namespace: namespace), url)
            return .record(migrated)
        case .write(_, let record, let expected):
            let current = try readRecord(url, namespace: namespace)
            // A lost local callback may be retried, but never accept another
            // payload merely because its UUID was reused.
            if current == record { return .record(record) }
            guard current?.recordRevision == expected, record.recordRevision != expected else {
                throw FavoritesJournalFailure.staleRevision
            }
            let data = try FavoritesRecordCodec.encode(record, namespace: namespace)
            guard try fileType(cleanupURL) == nil else { throw TransitionFailure.frozen }
            try createDirectory(root)
            try replace(data, url)
            return .record(record)
        case .snapshot:
            // Both source formats are read independently. A valid v2 does not
            // hide a damaged v1, and a missing v2 never triggers migration.
            let v2 = try readRawRecord(url)
            if let v2 { _ = try FavoritesRecordCodec.decode(v2, namespace: namespace) }
            let v1 = try legacy(namespace)
            if let v1 { _ = try FavoritesRecordCodec.migrateLegacyV1(v1, namespace: namespace) }
            guard try fileType(cleanupURL) == nil else { throw TransitionFailure.frozen }
            return .snapshot(v1: v1, v2: v2)
        case .cleanupPrepare(let checkpoint, _):
            let existing = try readCleanup(cleanupURL)
            let v2 = try readRawRecord(url), v1 = try legacy(namespace)
            guard try readCleanup(cleanupURL) == existing else { throw CleanupFailure.differentOriginal }
            if let existing {
                guard existing.belongs(to: checkpoint) else { throw CleanupFailure.differentOriginal }
                try validateRemaining(existing, v1: v1, v2: v2)
                return .cleanupPrepared(existing, v1: v1, v2: v2)
            }
            let revision = try v2.map { try FavoritesRecordCodec.decode($0, namespace: namespace).recordRevision }
            if let v1 { _ = try FavoritesRecordCodec.migrateLegacyV1(v1, namespace: namespace) }
            let record = try FavoritesLocalCleanupRecord(checkpoint: checkpoint, v1: v1, v2: v2, revision: revision)
            return .cleanupPrepared(record, v1: v1, v2: v2)
        case .cleanupBegin(let lease):
            if let existing = try readCleanup(cleanupURL) {
                guard existing.sameOriginal(as: lease.record) else { throw CleanupFailure.differentOriginal }
                try validateRemaining(existing, v1: legacy(namespace), v2: readRawRecord(url))
                guard try readCleanup(cleanupURL) == existing else { throw CleanupFailure.differentOriginal }
                return .cleanupReceipt(existing)
            }
            guard lease.record.phase == .v2 else { throw CleanupFailure.missingBegin }
            let v1 = try legacy(namespace), v2 = try readRawRecord(url)
            guard lease.rawV1 == v1, lease.rawV2 == v2, lease.record.matchesV1(v1), lease.record.matchesV2(v2) else {
                throw CleanupFailure.changedSource
            }
            try persistCleanup(lease.record, expected: nil, url: cleanupURL, root: root, replace: replace)
            return .cleanupReceipt(lease.record)
        case .cleanupCommit(let lease):
            guard var current = try readCleanup(cleanupURL) else { throw CleanupFailure.missingBegin }
            guard current.sameOriginal(as: lease.record) else { throw CleanupFailure.differentOriginal }
            try validateRemaining(current, v1: legacy(namespace), v2: readRawRecord(url))
            guard try readCleanup(cleanupURL) == current else { throw CleanupFailure.differentOriginal }
            if current.phase == .v2 {
                if let original = try readRawRecord(url) {
                    guard current.matchesV2(original) else { throw CleanupFailure.changedSource }
                    guard try readCleanup(cleanupURL) == current else { throw CleanupFailure.differentOriginal }
                    try remove(url)
                }
                guard try readRawRecord(url) == nil else { throw CleanupFailure.unconfirmed }
                let previous = current
                current.phase = .v1
                try persistCleanup(current, expected: previous, url: cleanupURL, root: root, replace: replace)
            }
            if current.phase == .v1 {
                guard try readRawRecord(url) == nil else { throw CleanupFailure.changedSource }
                if let original = try legacy(namespace) {
                    guard current.matchesV1(original) else { throw CleanupFailure.changedSource }
                    guard try readCleanup(cleanupURL) == current else { throw CleanupFailure.differentOriginal }
                    try legacyDelete(namespace, original)
                }
                guard try legacy(namespace) == nil, try readRawRecord(url) == nil else { throw CleanupFailure.unconfirmed }
                let previous = current
                current.phase = .complete
                try persistCleanup(current, expected: previous, url: cleanupURL, root: root, replace: replace)
            }
            try validateRemaining(current, v1: legacy(namespace), v2: readRawRecord(url))
            guard try readCleanup(cleanupURL) == current else { throw CleanupFailure.differentOriginal }
            return .cleanupReceipt(current)
        }
    }

    nonisolated private static func validateRemaining(_ record: FavoritesLocalCleanupRecord, v1: Data?, v2: Data?) throws {
        // An interrupted original remove may already be absent. Present bytes
        // must still match the initial consent; a completed phase stays absent.
        guard v1 == nil || record.matchesV1(v1), v2 == nil || record.matchesV2(v2),
              record.phase == .v2 || v2 == nil,
              record.phase != .complete || v1 == nil else { throw CleanupFailure.changedSource }
    }
    nonisolated private static func readCleanup(_ url: URL) throws -> FavoritesLocalCleanupRecord? {
        guard let type = try fileType(url) else { return nil }
        guard type == .typeRegular else { throw CleanupFailure.invalidRecord }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: FavoritesLocalCleanupRecord.maximumBytes + 1) ?? Data()
        guard data.count <= FavoritesLocalCleanupRecord.maximumBytes,
              (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw CleanupFailure.invalidRecord }
        return try FavoritesLocalCleanupRecord.decode(data)
    }
    nonisolated private static func persistCleanup(_ record: FavoritesLocalCleanupRecord, expected: FavoritesLocalCleanupRecord?,
                                                 url: URL, root: URL, replace: Replace) throws {
        guard try readCleanup(url) == expected else { throw CleanupFailure.differentOriginal }
        try createDirectory(root)
        let data = try FavoritesLocalCleanupRecord.encode(record)
        try replace(data, url)
        guard let stored = try readCleanup(url), stored == record else { throw CleanupFailure.unconfirmed }
    }

    nonisolated private static func location(root: URL, namespace: FavoritesNamespace) throws -> URL {
        let binding = namespace.recordBinding
        guard binding == "guest" || (binding.hasPrefix("account_") && binding.count == 72
            && binding.dropFirst(8).allSatisfy({ "0123456789abcdef".contains($0) })) else {
            throw FavoritesJournalFailure.readFailed
        }
        if let type = try fileType(root), type != .typeDirectory { throw FavoritesJournalFailure.readFailed }
        return root.appendingPathComponent(binding + ".json", isDirectory: false)
    }

    nonisolated private static func createDirectory(_ root: URL) throws {
        if let type = try fileType(root) {
            guard type == .typeDirectory else { throw FavoritesJournalFailure.writeFailed }
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard try fileType(root) == .typeDirectory else { throw FavoritesJournalFailure.writeFailed }
        }
    }

    nonisolated private static func fileType(_ url: URL) throws -> FileAttributeType? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }

    nonisolated private static func readRecord(_ url: URL, namespace: FavoritesNamespace) throws -> FavoritesRecord? {
        try readRawRecord(url).map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
    }

    nonisolated private static func readRawRecord(_ url: URL) throws -> Data? {
        guard let type = try fileType(url) else { return nil }
        guard type == .typeRegular else { throw FavoritesJournalFailure.readFailed }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: FavoritesRecordCodec.maximumRecordBytes + 1) ?? Data()
        guard data.count <= FavoritesRecordCodec.maximumRecordBytes else { throw FavoritesRecordCodec.Failure.limitExceeded }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw FavoritesRecordCodec.Failure.limitExceeded }
        return data
    }
}
