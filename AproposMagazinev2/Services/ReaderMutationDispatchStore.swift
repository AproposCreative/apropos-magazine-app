import Foundation

/// Inactive, SDK-free persistence for one original dispatch at a time. The
/// reservation belongs to this store instance, not an account's current UI.
/// No singleton, directory lookup, I/O or service is started by construction.
@MainActor
final class ReaderMutationDispatchStore {
    typealias Request = ReaderMutationContract.Request
    typealias Record = ReaderMutationJournalRecord
    static let maximumCASAttempts = 3

    enum Failure: Error, Equatable {
        case invalidLease, busy, missingMutation, changedMutation
        case conflictingReceipt, unconfirmedAcknowledgement, conflictLimitReached
    }
    struct Lease: Equatable, Sendable {
        let request: Request
        fileprivate let owner: UUID
        fileprivate let id: UUID
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner == rhs.owner && lhs.id == rhs.id }
    }
    struct Acknowledgement: Sendable {
        let receipt: ReaderMutationContract.Receipt
        let receiptData: Data
        let journalRevision: UUID
    }

    private let owner = UUID()
    private let journal: ReaderMutationFileJournal
    private var held: Lease?
    private var busy = false

    init(journal: ReaderMutationFileJournal) { self.journal = journal }

    /// Requests are already immutable/validated. Do not hash or encode a
    /// potentially large original payload on MainActor while reserving it.
    func reserve(request: Request) -> Lease? {
        guard held == nil else { return nil }
        let lease = Lease(request: request, owner: owner, id: UUID())
        held = lease
        return lease
    }
    func owns(_ lease: Lease) -> Bool { lease.owner == owner && held == lease }
    @discardableResult
    func release(_ lease: Lease) -> Bool {
        guard owns(lease), !busy else { return false }
        held = nil
        return true
    }

    func load(_ lease: Lease) async throws -> Record.Entry {
        try begin(lease)
        defer { busy = false }
        let record = try await read(ownerUID: lease.request.expectedUID)
        let request = lease.request
        return try await Task.detached(priority: .utility) {
            try Self.entry(in: record, matching: request)
        }.value
    }

    /// A receipt is historical evidence for the original request. Persist it
    /// even after cancellation/account change; the runner separately guards UI
    /// publication and future transport. Physical callbacks are always awaited.
    func acknowledge(_ lease: Lease, receiptData: Data) async throws -> Acknowledgement {
        try begin(lease)
        defer { busy = false }
        let request = lease.request
        let receipt = try await Task.detached(priority: .utility) {
            try ReaderMutationContract.decodeReceipt(data: receiptData, for: request)
        }.value
        var current = try await read(ownerUID: request.expectedUID)
        for attempt in 0..<Self.maximumCASAttempts {
            let original = current
            let prepared = try await Task.detached(priority: .utility) {
                let existing = try Self.acknowledgement(in: original, request: request, expected: receipt)
                if let existing { return Preparation.alreadyAcknowledged(existing) }
                guard let original else { throw Failure.missingMutation }
                let next = try original.acknowledging(requestID: request.requestID, receiptData: receiptData)
                return Preparation.write(next, expectedRevision: original.recordRevision)
            }.value
            switch prepared {
            case .alreadyAcknowledged(let result): return result
            case .write(let candidate, let expectedRevision):
                var writeFailure: Error?
                do { try await write(candidate, expectedRevision: expectedRevision) }
                catch { writeFailure = error }

                // A callback failure may follow a successful atomic replace.
                // A callback success alone is likewise insufficient evidence.
                let verified: Record?
                do { verified = try await read(ownerUID: request.expectedUID) }
                catch {
                    if let writeFailure { throw writeFailure }
                    throw error
                }
                let accepted = try await Task.detached(priority: .utility) {
                    try Self.acknowledgement(in: verified, request: request, expected: receipt)
                }.value
                if let accepted { return accepted }
                guard let writeFailure else { throw Failure.unconfirmedAcknowledgement }
                guard writeFailure as? ReaderMutationFileJournal.Failure == .staleRevision else { throw writeFailure }
                guard attempt + 1 < Self.maximumCASAttempts else { throw Failure.conflictLimitReached }
                // Rebase only the ACK over the freshly read durable prefix.
                // Never create/relabel an intent or retry its network mutation.
                current = verified
            }
        }
        throw Failure.conflictLimitReached
    }

    private enum Preparation: Sendable {
        case alreadyAcknowledged(Acknowledgement)
        case write(Record, expectedRevision: UUID)
    }
    private func begin(_ lease: Lease) throws {
        guard owns(lease) else { throw Failure.invalidLease }
        guard !busy else { throw Failure.busy }
        busy = true
    }
    nonisolated private static func entry(in record: Record?, matching request: Request) throws -> Record.Entry {
        guard let record else { throw Failure.missingMutation }
        guard record.ownerUID == request.expectedUID else { throw Failure.changedMutation }
        let id = request.requestID
        guard let entry = record.entries.first(where: { $0.requestID == id }) else { throw Failure.missingMutation }
        guard entry.request == request else { throw Failure.changedMutation }
        return entry
    }
    nonisolated private static func acknowledgement(in record: Record?, request: Request,
        expected: ReaderMutationContract.Receipt) throws -> Acknowledgement? {
        let original = try entry(in: record, matching: request)
        guard let data = original.receiptData else { return nil }
        let saved = try ReaderMutationContract.decodeReceipt(data: data, for: request)
        guard saved == expected, let record else { throw Failure.conflictingReceipt }
        return Acknowledgement(receipt: saved, receiptData: data, journalRevision: record.recordRevision)
    }
    private func read(ownerUID: String) async throws -> Record? {
        try await withCheckedThrowingContinuation { continuation in
            journal.read(ownerUID: ownerUID) { continuation.resume(with: $0) }
        }
    }
    private func write(_ record: Record, expectedRevision: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            journal.write(record, expectedRevision: expectedRevision) { continuation.resume(with: $0) }
        }
    }
}
