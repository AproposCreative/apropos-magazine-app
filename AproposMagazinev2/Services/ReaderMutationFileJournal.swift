import CryptoKit
import Foundation

/// Inactive, explicit-owner journal. Construction performs no I/O and no active
/// app caller uses it. The supplied directory must be separate from legacy data.
/// One shared queue makes read/CAS/replace indivisible among these instances in
/// this process. Atomic replacement is not fsync or a cross-process file lock.
@MainActor
final class ReaderMutationFileJournal {
    enum Failure: Error, Equatable, Sendable {
        case readRequired, readFailed, writeFailed, staleRevision, limitExceeded
    }
    typealias Record = ReaderMutationJournalRecord
    typealias Replace = @Sendable (Data, URL) throws -> Void
    static let maximumPendingJobs = 64
    static let maximumOwners = 64

    private enum Work: Sendable {
        case read(String)
        case write(Record, UUID?)
        var ownerUID: String {
            switch self { case .read(let uid): return uid; case .write(let record, _): return record.ownerUID }
        }
    }
    private enum Completion {
        case read(@MainActor (Result<Record?, Error>) -> Void)
        case write(@MainActor (Result<Void, Error>) -> Void)
        @MainActor func call(_ result: Result<Record?, Error>) {
            switch self {
            case .read(let callback): callback(result)
            case .write(let callback): callback(result.map { _ in () })
            }
        }
    }
    private struct Job {
        let id = UUID()
        let work: Work
        let completion: Completion
    }
    private struct Head { let revision: UUID? }
    nonisolated private static let ioQueue = DispatchQueue(label: "com.apropos.reader-mutation-journal", qos: .utility)
    private let rootDirectory: URL
    private let replace: Replace
    // These bounds are per instance; physical disk work is shared across instances.
    private var heads: [String: Head] = [:]
    private var pending: [Job] = []
    private var active: Job?

    init(rootDirectory: URL, replace: @escaping Replace = { data, url in try data.write(to: url, options: .atomic) }) {
        self.rootDirectory = rootDirectory
        self.replace = replace
    }

    func read(ownerUID: String, completion: @escaping @MainActor (Result<Record?, Error>) -> Void) {
        do { try Self.validateOwner(ownerUID) }
        catch { completion(.failure(error)); return }
        enqueue(.read(ownerUID), completion: .read(completion))
    }

    func write(_ record: Record, expectedRevision: UUID?, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        guard heads[record.ownerUID] != nil else { completion(.failure(Failure.readRequired)); return }
        // Record is immutable and validated at construction. Expensive encoding
        // and strict byte validation occur on the I/O queue before any replace.
        enqueue(.write(record, expectedRevision), completion: .write(completion))
    }

    private func enqueue(_ work: Work, completion: Completion) {
        var owners = Set(heads.keys)
        owners.insert(work.ownerUID)
        if let active { owners.insert(active.work.ownerUID) }
        for job in pending { owners.insert(job.work.ownerUID) }
        guard pending.count < Self.maximumPendingJobs, owners.count <= Self.maximumOwners else {
            completion.call(.failure(Failure.limitExceeded)); return
        }
        // No coalescing: an accepted request or receipt is not discarded merely
        // because a newer local snapshot was registered before physical I/O.
        pending.append(Job(work: work, completion: completion))
        pump()
    }

    private func pump() {
        guard active == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        if case .write = job.work, heads[job.work.ownerUID] == nil {
            job.completion.call(.failure(Failure.readRequired))
            pump()
            return
        }
        active = job
        let root = rootDirectory, replace = replace, work = job.work, id = job.id
        let observedRevision = heads[job.work.ownerUID]?.revision
        Self.ioQueue.async { [self] in
            let result = Result { try Self.perform(work, root: root, observedRevision: observedRevision, replace: replace) }
            Task { @MainActor [self] in self.finish(id: id, result: result) }
        }
    }

    private func finish(id: UUID, result: Result<Record?, Error>) {
        guard let job = active, job.id == id else { return }
        active = nil
        if case .success(let record) = result { heads[job.work.ownerUID] = Head(revision: record?.recordRevision) }
        else if case .read = job.work { heads.removeValue(forKey: job.work.ownerUID) }
        // Admission state changes before callbacks, which may synchronously
        // reenter with another read/write. A failed read revokes queued writes.
        job.completion.call(result)
        pump()
    }

    nonisolated private static func perform(_ work: Work, root: URL, observedRevision: UUID?, replace: Replace) throws -> Record? {
        let uid = work.ownerUID, url = try location(root: root, ownerUID: uid)
        switch work {
        case .read:
            // No legacy fallback, import, epoch inference, or automatic migration.
            return try readRecord(url, ownerUID: uid)
        case .write(let record, let expectedRevision):
            let candidate = try ReaderMutationJournalCodec.encode(record)
            let current = try readRecord(url, ownerUID: uid)
            if let current, try ReaderMutationJournalCodec.encode(current) == candidate { return record }
            // A vanished previously observed file is not a new empty journal.
            // A new process or explicit successful missing re-read cannot prove
            // such historical loss; this is bounded local knowledge only.
            guard current != nil || observedRevision == nil else { throw Failure.staleRevision }
            guard current?.recordRevision == expectedRevision, record.recordRevision != expectedRevision else { throw Failure.staleRevision }
            if let current { try ReaderMutationJournalCodec.validateReplacement(current: current, next: record) }
            try createDirectory(root)
            try replace(candidate, url)
            return record
        }
    }

    nonisolated private static func validateOwner(_ ownerUID: String) throws {
        guard (try? ReaderMembershipContract.Binding(ownerUID: ownerUID, epoch: 1)) != nil else { throw Failure.readFailed }
    }
    nonisolated private static func location(root: URL, ownerUID: String) throws -> URL {
        try validateOwner(ownerUID)
        guard root.isFileURL, root.path.hasPrefix("/") else { throw Failure.readFailed }
        if let type = try fileType(root), type != .typeDirectory { throw Failure.readFailed }
        let digest = SHA256.hash(data: Data(("apropos/reader-mutation-journal/v1\u{0}" + ownerUID).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("account_" + digest + ".json", isDirectory: false)
    }
    nonisolated private static func createDirectory(_ root: URL) throws {
        if let type = try fileType(root) {
            guard type == .typeDirectory else { throw Failure.writeFailed }
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard try fileType(root) == .typeDirectory else { throw Failure.writeFailed }
        }
    }
    nonisolated private static func fileType(_ url: URL) throws -> FileAttributeType? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
    nonisolated private static func readRecord(_ url: URL, ownerUID: String) throws -> Record? {
        guard let type = try fileType(url) else { return nil }
        guard type == .typeRegular else { throw Failure.readFailed }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: ReaderMutationJournalCodec.maximumRecordBytes + 1) ?? Data()
        guard data.count <= ReaderMutationJournalCodec.maximumRecordBytes,
              (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.limitExceeded }
        return try ReaderMutationJournalCodec.decode(data, ownerUID: ownerUID)
    }
}
