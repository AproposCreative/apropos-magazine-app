import Combine
import Foundation

/// Installation recovery shared by startup and the existing SDK/source writers.
/// Construction performs no disk work. A local marker never grants account or
/// server authority; startup must explicitly read it before opening admission.
@MainActor
final class ReaderTransitionRecovery {
    typealias Marker = ReaderTransitionRecoveryStore.Marker
    typealias Binding = ReaderMembershipContract.Binding
    typealias DeletionCheckpoint = ReaderTransitionRecoveryStore.DeletionCheckpoint
    typealias DeletionPhase = ReaderTransitionRecoveryStore.DeletionPhase
    typealias PushCommitCheckpoint = ReaderTransitionRecoveryStore.PushCommitCheckpoint
    enum Status: Equatable { case unresolved, loading, legacy, sealed(Marker), unavailable }
    enum Failure: Error { case busy, unavailable, differentOriginal, missingSeal }
    /// Stable identity for the whole application composition. Resolving the
    /// standard path does not read or create the directory/marker.
    static let application = ReaderTransitionRecovery(store: ReaderTransitionRecoveryStore(
        rootDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AproposMagazine", isDirectory: true)
            .appendingPathComponent("reader-transition", isDirectory: true)))

    private let store: ReaderTransitionRecoveryStore
    let changes = PassthroughSubject<Void, Never>()
    /// UI-only notification after a complete physical read/write has settled.
    /// Admission changes retain their existing synchronous safety semantics.
    let presentationChanges = PassthroughSubject<Void, Never>()
    let admission = ReaderLegacyWriteAdmission()
    private(set) var status: Status = .unresolved { didSet { updateAdmission() } }
    private(set) var isBusy = false { didSet { updateAdmission() } }
    private var original: Marker?
    private(set) var deletionCheckpoint: DeletionCheckpoint?
    private(set) var pushCommitCheckpoint: PushCommitCheckpoint?
    // Retain a possibly written attempt even when its readback failed. This is
    // process evidence only until the exact sidecar is read back.
    private var originalPushCommit: PushCommitCheckpoint?
    private var permanentlyClosed = false { didSet { updateAdmission() } }

    init(store: ReaderTransitionRecoveryStore) { self.store = store }

    var legacyWritesPermitted: Bool { !permanentlyClosed && !isBusy && status == .legacy }
    var hasSealAttempt: Bool { permanentlyClosed }

    private func updateAdmission() {
        let permitted = legacyWritesPermitted
        guard admission.isAllowed != permitted else { return }
        // Store the pure last-reference guard before any subscriber can reenter.
        admission.setAllowed(permitted)
        changes.send()
    }

    func hasVerifiedSeal(binding: Binding) -> Bool {
        guard !isBusy, case .sealed(let marker) = status else { return false }
        return marker.binding == binding
    }

    /// A successful missing read is only local admission for untouched legacy
    /// storage. Any observed/attempted seal closes this process monotonically.
    /// Disk state cannot grant membership, restore a drain, or reopen writers.
    func bootstrap() async throws { _ = try await readResumption() }

    /// Reads both original records in one physical queue operation. A generic
    /// transition marker has no deletion intent; an orphaned checkpoint cannot
    /// make an absent marker look like an untouched legacy installation.
    func readResumption() async throws -> DeletionCheckpoint? {
        guard !isBusy else { throw Failure.busy }
        isBusy = true; status = .loading
        defer { isBusy = false; presentationChanges.send() }
        do {
            let value: ReaderTransitionRecoveryStore.Resumption = try await withCheckedThrowingContinuation { continuation in
                store.readResumption { continuation.resume(with: $0) }
            }
            if let marker = value.marker {
                permanentlyClosed = true
                if let original, original != marker { throw Failure.differentOriginal }
                original = marker
                status = .sealed(marker)
            } else {
                guard !permanentlyClosed else { throw Failure.missingSeal }
                status = .legacy
            }
            if let previous = deletionCheckpoint {
                guard let next = value.checkpoint else { throw ReaderTransitionRecoveryStore.Failure.missingCheckpoint }
                guard previous.isSameFamily(as: next), previous.phase != .ledger || next.phase == .ledger else {
                    throw ReaderTransitionRecoveryStore.Failure.conflictingCheckpoint
                }
            }
            if let previous = originalPushCommit ?? pushCommitCheckpoint {
                guard let next = value.pushCommit else { throw ReaderTransitionRecoveryStore.Failure.missingPushCheckpoint }
                guard previous == next else { throw ReaderTransitionRecoveryStore.Failure.conflictingPushCheckpoint }
            }
            deletionCheckpoint = value.checkpoint
            pushCommitCheckpoint = value.pushCommit
            if let child = value.pushCommit { originalPushCommit = child }
            try Task.checkCancellation()
            return value.checkpoint
        } catch { status = .unavailable; throw error }
    }

    /// Only an explicitly confirmed existing deletion action calls this. It
    /// records desired work, never a server receipt or active membership. Parent
    /// reconciliation preserves a previously selected ledger phase on disk.
    func recordDeletion(request: ReaderAccountDeletionContract.Request, phase: DeletionPhase,
                        configurationDigest: String) async throws -> DeletionCheckpoint {
        guard !isBusy else { throw Failure.busy }
        guard let marker = original, permanentlyClosed else { throw Failure.missingSeal }
        let expected = deletionCheckpoint
        let retainedPhase: DeletionPhase = expected?.phase == .ledger ? .ledger : phase
        let candidate = try DeletionCheckpoint(marker: marker, request: request, phase: retainedPhase,
                                               configurationDigest: configurationDigest)
        if let expected, !expected.isSameFamily(as: candidate) { throw ReaderTransitionRecoveryStore.Failure.conflictingCheckpoint }
        try Task.checkCancellation()
        isBusy = true; status = .loading
        defer { isBusy = false; presentationChanges.send() }
        do {
            let verified: DeletionCheckpoint = try await withCheckedThrowingContinuation { continuation in
                store.saveDeletionCheckpoint(candidate, expected: expected) { continuation.resume(with: $0) }
            }
            guard verified == candidate else { throw ReaderTransitionRecoveryStore.Failure.unconfirmedCheckpoint }
            // Preserve physical success even if the waiting caller was cancelled.
            deletionCheckpoint = verified
            status = .sealed(marker)
            try Task.checkCancellation()
            return verified
        } catch { status = .unavailable; throw error }
    }

    /// Persist the already confirmed original commit before transport. Neither
    /// these bytes nor their fingerprint prove server authority or completion.
    func recordPushCommit(_ candidate: PushCommitCheckpoint) async throws -> PushCommitCheckpoint {
        guard !isBusy else { throw Failure.busy }
        guard let marker = original, permanentlyClosed else { throw Failure.missingSeal }
        guard marker == candidate.checkpoint.marker, deletionCheckpoint == candidate.checkpoint,
              candidate.checkpoint.phase == .ledger else { throw ReaderTransitionRecoveryStore.Failure.conflictingCheckpoint }
        if let pinned = originalPushCommit ?? pushCommitCheckpoint, pinned != candidate {
            throw ReaderTransitionRecoveryStore.Failure.conflictingPushCheckpoint
        }
        try Task.checkCancellation()
        let expected = pushCommitCheckpoint
        originalPushCommit = candidate
        isBusy = true; status = .loading
        defer { isBusy = false; presentationChanges.send() }
        do {
            let verified: PushCommitCheckpoint = try await withCheckedThrowingContinuation { continuation in
                store.savePushCommitCheckpoint(candidate, expected: expected) { continuation.resume(with: $0) }
            }
            guard verified == candidate else { throw ReaderTransitionRecoveryStore.Failure.unconfirmedPushCheckpoint }
            // Physical success remains owned even if its awaiting UI is cancelled.
            pushCommitCheckpoint = verified
            status = .sealed(marker)
            try Task.checkCancellation()
            return verified
        } catch {
            // Only a physically revalidated original family permits repair of
            // this same child. Parent/marker faults invalidate the shared seal.
            if (error as? ReaderTransitionRecoveryStore.Failure) == .unconfirmedPushCommit ||
                (error is CancellationError && pushCommitCheckpoint == candidate) {
                status = .sealed(marker)
            } else { status = .unavailable }
            throw error
        }
    }

    func canPrepare(binding: Binding) -> Bool {
        guard !isBusy else { return false }
        switch status {
        case .legacy: return !permanentlyClosed
        case .sealed(let marker): return marker.binding == binding
        case .unavailable: return original?.binding == binding
        case .unresolved, .loading: return false
        }
    }

    /// Close synchronously before the first physical marker attempt. Keep its
    /// original ID even on cancellation or unknown write outcome. Only exact
    /// disk readback permits the caller to proceed to target journal effects.
    func seal(binding: Binding) async throws -> Marker {
        guard !isBusy else { throw Failure.busy }
        guard canPrepare(binding: binding) else { throw Failure.unavailable }
        try Task.checkCancellation()
        let marker = original ?? Marker(binding: binding, transitionID: UUID())
        guard marker.binding == binding else { throw Failure.differentOriginal }
        original = marker; permanentlyClosed = true; isBusy = true; status = .loading
        defer { isBusy = false; presentationChanges.send() }
        do {
            let verified: Marker = try await withCheckedThrowingContinuation { continuation in
                store.seal(marker) { continuation.resume(with: $0) }
            }
            guard verified == marker else { throw Failure.differentOriginal }
            status = .sealed(verified)
            try Task.checkCancellation()
            return verified
        } catch { status = .unavailable; throw error }
    }
}
