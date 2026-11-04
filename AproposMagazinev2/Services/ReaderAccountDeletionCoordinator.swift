import Combine
import Foundation

/// Inert orchestration for the staged reader-only cloud slice. No implicit
/// confirmation, identity deletion, or complete-account success is provided.
@MainActor
final class ReaderAccountDeletionCoordinator: ObservableObject {
    typealias Contract = ReaderAccountDeletionContract
    typealias ContextTicket = CanonicalSessionState.ContextTicket

    enum Phase: Equatable, Sendable { case cloudSlice, mutationLedger, pushPreparation, pushRetirement }

    struct ActionTicket: Equatable, Sendable {
        let actionID: UUID
        let context: ContextTicket
        let request: Contract.Request
        let phase: Phase
        let ledgerRequest: Contract.LedgerRequest?
        let pushRequest: Contract.PushRequest?
        let startedAtMs: Int64
        fileprivate let coordinatorID: UUID
        init(actionID: UUID, context: ContextTicket, request: Contract.Request, phase: Phase,
             ledgerRequest: Contract.LedgerRequest?, pushRequest: Contract.PushRequest? = nil,
             startedAtMs: Int64, coordinatorID: UUID) {
            self.actionID = actionID; self.context = context; self.request = request; self.phase = phase
            self.ledgerRequest = ledgerRequest; self.pushRequest = pushRequest
            self.startedAtMs = startedAtMs; self.coordinatorID = coordinatorID
        }
    }

    /// Only an injected provider reauthentication adapter may return this proof.
    /// A refreshed token/session is explicitly not evidence of reauthentication.
    struct ReauthenticationResult: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case reauthenticated, sessionRefresh }
        let action: ActionTicket
        let authenticatedUID: String
        let authTimeMs: Int64
        let kind: Kind
    }

    enum Status: Equatable {
        case idle, unavailable, reauthenticating, submitting
        case pending, paused, scopedCloudDataRemoved, ledgerDataRemoved, cancelled, timedOut
    }

    typealias EpochReader = @MainActor (ContextTicket) -> Int64?
    typealias Reauthenticator = @MainActor (ActionTicket) async throws -> ReauthenticationResult
    typealias Sender = @MainActor (Contract.Request, ReauthenticationResult) async throws -> Data
    typealias LedgerSender = @MainActor (Contract.LedgerRequest, ReauthenticationResult) async throws -> Data
    typealias PushSender = @MainActor (Contract.PushRequest, ReauthenticationResult) async throws -> Data
    typealias Clock = @MainActor () -> Int64
    typealias Cancellation = @MainActor () -> Void
    typealias TimeoutScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancellation

    /// The exact active legacy writer/journal instances, never a fresh empty
    /// replacement. A local stop is not a server fence or durable migration.
    struct WriteBarrier {
        let writers: ReaderWriterDrainRuntime
        let journal: FavoritesFileJournal
        let recovery: ReaderTransitionRecovery
        let resumeStore: ReaderResumeStore?
        let podcastStore: PodcastPlaybackProgressStore?

        init(writers: ReaderWriterDrainRuntime, journal: FavoritesFileJournal,
             recovery: ReaderTransitionRecovery, resumeStore: ReaderResumeStore? = nil,
             podcastStore: PodcastPlaybackProgressStore? = nil) {
            self.writers = writers; self.journal = journal; self.recovery = recovery
            self.resumeStore = resumeStore; self.podcastStore = podcastStore
        }
    }
    struct Resumption {
        let context: ContextTicket
        let recovery: ReaderTransitionRecovery
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        /// Captured from the same actual cold startup composition. No SDK drain
        /// or source journal is constructed to manufacture restart authority.
        let stillClosed: @MainActor () -> Bool
    }
    private final class HeldWriteBarrier {
        let context: ContextTicket
        let request: Contract.Request
        let reservation: UUID
        let stop: ReaderWriterDrainCoordinator.StopTicket
        let originalUserIsCurrent: @MainActor () -> Bool
        var sourceTicket: FavoritesFileJournal.TransitionTicket?
        var sealed = false
        init(action: ActionTicket, reservation: UUID, stop: ReaderWriterDrainCoordinator.StopTicket,
             originalUserIsCurrent: @escaping @MainActor () -> Bool) {
            context = action.context; request = action.request
            self.reservation = reservation; self.stop = stop
            self.originalUserIsCurrent = originalUserIsCurrent
        }
    }
    private let writeBarrier: WriteBarrier?
    private let resumption: Resumption?
    private let configurationDigest: String?
    private var heldWriteBarrier: HeldWriteBarrier?
    private var barrierAttempt: UUID?
    /// Remains true after logical cancellation and after a possible HTTP send.
    /// Replacing this coordinator would discard necessary recovery ownership.
    var hasWriteBarrier: Bool { heldWriteBarrier != nil || barrierAttempt != nil || resumption != nil }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var status: Status { presentation }
    var receipt: Contract.Receipt? { acceptedReceipt }
    var ledgerReceipt: Contract.LedgerReceipt? { acceptedLedgerReceipt }
    var requestID: String? { intent?.requestID }
    var accountDeletionComplete: Bool { false }
    var unresolved: [String] {
        intent?.phase == .mutationLedger ? (acceptedLedgerReceipt?.unresolved ?? Contract.ledgerUnresolved)
            : (acceptedReceipt?.unresolved ?? Contract.unresolved)
    }
    var isWorking: Bool { status == .reauthenticating || status == .submitting || localFlight != nil }
    /// Cancellation/deadline revokes delivery but cannot free an occupied SDK or
    /// transport slot. A subsequent explicit attempt waits for its actual return.
    var hasPhysicalFlight: Bool { flight != nil || localFlight != nil || !barrierPhysicallyIdle }
    var canRetry: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle, let candidate = intent, configured(for: candidate) else { return false }
        let token = publication, owned = owns(candidate)
        return owned && publication == token && flight == nil && intent == candidate
            && [.pending, .paused, .unavailable, .timedOut].contains(status)
    }
    var canBeginLedgerCleanup: Bool {
        guard configured, sendLedger != nil, localFlight == nil, flight == nil, status == .scopedCloudDataRemoved,
              let candidate = intent, candidate.phase == .cloudSlice, let parent = acceptedParent,
              parent.context == candidate.context, parent.request == candidate.request else { return false }
        let token = publication, owned = owns(candidate)
        return owned && publication == token && intent == candidate && acceptedParent == parent
            && flight == nil && status == .scopedCloudDataRemoved
    }
    var message: String? {
        switch status {
        case .idle: return nil
        case .unavailable: return "Anmodningen om læserdata kunne ikke bekræftes. Kontosletning er ikke gennemført."
        case .reauthenticating: return "Bekræft din identitet igen for at fortsætte."
        case .submitting: return "Kontrollerer anmodningen om læserdata…"
        case .pending: return "Oprydningen af de afgrænsede læserdata afventer. Kontosletning er ikke gennemført."
        case .paused: return "Oprydningen af de afgrænsede læserdata er sat på pause. Kontosletning er ikke gennemført."
        case .scopedCloudDataRemoved: return "De afgrænsede læserdata i skyen er fjernet. Andre data mangler fortsat; kontosletning er ikke gennemført."
        case .ledgerDataRemoved: return "De afgrænsede læseroplysninger i skyen er fjernet. Andre data mangler fortsat; kontosletning er ikke gennemført."
        case .cancelled: return "Anmodningen er lukket her. En allerede modtaget serveropgave kan stadig være aktiv."
        case .timedOut: return "Svaret kom ikke i tide. En allerede modtaget serveropgave kan stadig være aktiv."
        }
    }

    // Separate explicit device action. A cloud receipt is never consent to
    // remove local bytes, and this receipt never completes account deletion.
    enum LocalFavoritesStatus: Equatable { case idle, preparing, ready, removing, removed, failed, cancelled }
    struct LocalFavoritesConfirmation: Equatable {
        fileprivate let id: UUID
    }
    typealias LocalJournalFactory = @MainActor () -> FavoritesFileJournal?
    private struct LocalFavoritesPreparation {
        let confirmation: LocalFavoritesConfirmation
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let journal: FavoritesFileJournal
        let lease: FavoritesFileJournal.CleanupLease
    }
    private enum LocalCleanupKind { case favorites, resume, podcast, introduction, history, push }
    private struct LocalFavoritesFlight {
        let id: UUID
        let kind: LocalCleanupKind
        var task: Task<Void, Never>?
        var cancelDeadline: Cancellation?
        // Private, per-action stop bit. It grants no identity/server authority
        // and is never reopened; global recovery admission remains closed.
        let completionAdmission: ReaderLegacyWriteAdmission?
        @MainActor init(id: UUID, kind: LocalCleanupKind) {
            self.id = id; self.kind = kind
            completionAdmission = (kind == .podcast || kind == .introduction || kind == .history) ? ReaderLegacyWriteAdmission(isAllowed: true) : nil
        }
    }
    private let localJournalFactory: LocalJournalFactory?
    private var localJournal: FavoritesFileJournal?
    private var localPreparation: LocalFavoritesPreparation?
    private var localFlight: LocalFavoritesFlight?
    private var localGeneration = UUID()
    private(set) var localFavoritesStatus: LocalFavoritesStatus = .idle
    private(set) var localFavoritesReceipt: FavoritesFileJournal.CleanupReceipt?
    var localFavoritesConfirmation: LocalFavoritesConfirmation? { localPreparation?.confirmation }
    var localFavoritesMessage: String? {
        switch localFavoritesStatus {
        case .idle: return nil
        case .preparing: return "Kontrollerer denne kontos gemte artikelvalg…"
        case .ready: return "Kontrollen er klar. Bekræft, før de gemte artikelvalg fjernes fra enheden."
        case .removing: return "Fjerner denne kontos gemte artikelvalg fra enheden…"
        case .removed: return "Denne kontos gemte artikelvalg er fjernet fra enheden. Hele kontosletningen er ikke afsluttet."
        case .failed: return "Den lokale oprydning kunne ikke bekræftes. Prøv igen; en del kan allerede være fjernet."
        case .cancelled: return "Handlingen er lukket her. Allerede påbegyndt lokal oprydning kan være gennemført."
        }
    }
    var canPrepareLocalFavoritesCleanup: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle,
              localPreparation == nil, localFavoritesStatus != .removed,
              localJournal != nil || writeBarrier != nil || localJournalFactory != nil,
              let candidate = intent, let checkpoint = localCheckpoint else { return false }
        return localFamilyIsCurrent(candidate, checkpoint: checkpoint)
    }
    private var localRecovery: ReaderTransitionRecovery? { resumption?.recovery ?? writeBarrier?.recovery }
    private var localCheckpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint? {
        guard let recovery = localRecovery, let checkpoint = recovery.deletionCheckpoint,
              checkpoint.phase == .ledger, recovery.hasVerifiedSeal(binding: checkpoint.marker.binding),
              !recovery.admission.isAllowed else { return nil }
        return checkpoint
    }
    private func localFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        let generation = localGeneration, originalPublication = publication
        guard intent == candidate, candidate.phase == .mutationLedger,
              status == .ledgerDataRemoved, acceptedLedgerReceipt?.status == .ledgerDataRemoved,
              checkpoint.request == candidate.request, checkpoint.configurationDigest == configurationDigest,
              let current = localCheckpoint, current.isSameFamily(as: checkpoint),
              canonical?.isCurrent(candidate.context) == true else { return false }
        let owned = owns(candidate)
        return owned && localGeneration == generation && publication == originalPublication
            && intent == candidate && status == .ledgerDataRemoved
            && acceptedLedgerReceipt?.status == .ledgerDataRemoved
            && canonical?.isCurrent(candidate.context) == true
            && localCheckpoint?.isSameFamily(as: checkpoint) == true
    }
    private func localActionIsCurrent(_ id: UUID, candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard localGeneration == id, localFlight?.id == id,
              localFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localGeneration == id && localFlight?.id == id
    }
    /// Only an explicit UI tap prepares the exact bytes for the later alert.
    /// Rendering and cloud receipts never construct a journal or perform I/O.
    @discardableResult func prepareLocalFavoritesCleanup() -> Bool {
        guard canPrepareLocalFavoritesCleanup, let candidate = intent, let checkpoint = localCheckpoint else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .favorites)
        setLocalFavoritesStatus(.preparing)
        guard localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalFavorites(id, preparation: nil, receipt: nil); return false
        }
        let journal = localJournal ?? writeBarrier?.journal ?? localJournalFactory?()
        guard let journal, localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalFavorites(id, preparation: nil, receipt: nil); return false
        }
        localJournal = journal // Keep one physical queue across retries/reopenings.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    throw CancellationError()
                }
                let lease: FavoritesFileJournal.CleanupLease = try await withCheckedThrowingContinuation { continuation in
                    journal.prepareLocalCleanup(checkpoint: checkpoint, stillCurrent: { [weak self] in
                        self?.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) == true
                    }, completion: { continuation.resume(with: $0) })
                }
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    throw CancellationError()
                }
                let prepared = LocalFavoritesPreparation(confirmation: .init(id: UUID()), intent: candidate,
                    checkpoint: checkpoint, journal: journal, lease: lease)
                self.finishLocalFavorites(id, preparation: prepared, receipt: nil)
            } catch { self.finishLocalFavorites(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    @discardableResult func confirmLocalFavoritesCleanup(_ confirmation: LocalFavoritesConfirmation,
                                                         userConfirmed: Bool) -> Bool {
        guard userConfirmed, localFlight == nil, flight == nil,
              let prepared = localPreparation, prepared.confirmation == confirmation,
              localFavoritesStatus == .ready,
              localFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint),
              localPreparation?.confirmation == confirmation else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .favorites)
        localPreparation = nil
        setLocalFavoritesStatus(.removing)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func current() -> Bool {
                self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint)
            }
            do {
                guard !Task.isCancelled, current() else { throw CancellationError() }
                let pending: FavoritesFileJournal.CleanupReceipt = try await withCheckedThrowingContinuation { continuation in
                    prepared.journal.beginLocalCleanup(prepared.lease, stillCurrent: current,
                        completion: { continuation.resume(with: $0) })
                }
                guard !Task.isCancelled, current(), self.validLocalReceipt(pending, checkpoint: prepared.checkpoint) else {
                    throw CancellationError()
                }
                let receipt: FavoritesFileJournal.CleanupReceipt
                if pending.isComplete { receipt = pending }
                else {
                    receipt = try await withCheckedThrowingContinuation { continuation in
                        prepared.journal.commitLocalCleanup(prepared.lease, stillCurrent: current,
                            completion: { continuation.resume(with: $0) })
                    }
                }
                guard !Task.isCancelled, current(), receipt.isComplete,
                      self.validLocalReceipt(receipt, checkpoint: prepared.checkpoint) else { throw CancellationError() }
                self.finishLocalFavorites(id, preparation: nil, receipt: receipt)
            } catch { self.finishLocalFavorites(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    private func validLocalReceipt(_ receipt: FavoritesFileJournal.CleanupReceipt,
                                  checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        receipt.namespace == FavoritesContext.confirmed(userID: checkpoint.request.expectedUID).namespace
            && receipt.requestID == checkpoint.request.requestID
            && receipt.transitionID == checkpoint.marker.transitionID
            && receipt.configurationDigest == checkpoint.configurationDigest
    }
    private func installLocalTask(_ task: Task<Void, Never>, id: UUID) {
        guard localFlight?.id == id, localGeneration == id else { task.cancel(); return }
        localFlight?.task = task
        let cancelDeadline = scheduleTimeout(timeoutSeconds) { [weak self] in
            guard let self, self.localFlight?.id == id, self.localGeneration == id else { return }
            self.localFlight?.completionAdmission?.setAllowed(false)
            self.localGeneration = UUID(); self.localPreparation = nil; self.localResumePreparation = nil; self.localPodcastPreparation = nil; self.localIntroductionPreparation = nil; self.localHistoryPreparation = nil
            self.localFlight?.task?.cancel()
            if self.localFlight?.kind == .history { self.setLocalHistoryStatus(.failed) }
            else if self.localFlight?.kind == .introduction { self.setLocalIntroductionStatus(.failed) }
            else if self.localFlight?.kind == .podcast { self.setLocalPodcastStatus(.failed) }
            else if self.localFlight?.kind == .resume { self.setLocalResumeStatus(.failed) }
            else { self.setLocalFavoritesStatus(.failed) }
        }
        if localFlight?.id == id, localGeneration == id { localFlight?.cancelDeadline = cancelDeadline }
        else { cancelDeadline() }
    }
    func cancelLocalFavoritesCleanup() {
        guard localFlight?.kind == .favorites || localPreparation != nil else { return }
        localGeneration = UUID(); localPreparation = nil
        localFlight?.task?.cancel()
        let cancel = localFlight?.cancelDeadline; localFlight?.cancelDeadline = nil
        cancel?()
        setLocalFavoritesStatus(.cancelled)
    }
    private func finishLocalFavorites(_ id: UUID, preparation: LocalFavoritesPreparation?,
                                      receipt: FavoritesFileJournal.CleanupReceipt?) {
        guard let physical = localFlight, physical.id == id else { return }
        localFlight = nil
        physical.cancelDeadline?()
        guard localGeneration == id else { objectWillChange.send(); return }
        if let preparation, localFamilyIsCurrent(preparation.intent, checkpoint: preparation.checkpoint),
           localGeneration == id, localFlight == nil {
            localPreparation = preparation
            setLocalFavoritesStatus(.ready)
        } else if let receipt, let candidate = intent, let checkpoint = localCheckpoint,
                  localFamilyIsCurrent(candidate, checkpoint: checkpoint), validLocalReceipt(receipt, checkpoint: checkpoint),
                  localGeneration == id, localFlight == nil {
            localFavoritesReceipt = receipt
            setLocalFavoritesStatus(.removed)
        } else if localGeneration == id, localFlight == nil {
            setLocalFavoritesStatus(.failed)
        }
    }
    private func setLocalFavoritesStatus(_ value: LocalFavoritesStatus) {
        localFavoritesStatus = value
        objectWillChange.send()
    }

    typealias LocalResumeStatus = LocalFavoritesStatus
    struct LocalResumeConfirmation: Equatable { fileprivate let id: UUID }
    private struct LocalResumePreparation {
        let confirmation: LocalResumeConfirmation
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let store: ReaderResumeStore
        let lease: ReaderResumeStore.CleanupLease
    }
    private let localResumeStore: ReaderResumeStore?
    private var localResumePreparation: LocalResumePreparation?
    private(set) var localResumeStatus: LocalResumeStatus = .idle
    private(set) var localResumeReceipt: ReaderResumeStore.CleanupReceipt?
    var localResumeConfirmation: LocalResumeConfirmation? { localResumePreparation?.confirmation }
    var localResumeMessage: String? {
        switch localResumeStatus {
        case .idle: nil
        case .preparing: "Klargør kontoens læsepositioner på denne enhed…"
        case .ready: "Læsepositionerne er klargjort. Bekræft for at fjerne dem fra denne enhed."
        case .removing: "Fjerner kontoens læsepositioner på denne enhed…"
        case .removed: "Kontoens læsepositioner er fjernet fra denne enhed. Den samlede kontosletning er ikke færdig."
        case .failed: "Oprydningen kunne ikke bekræftes. Prøv igen med en ny bekræftelse."
        case .cancelled: "Oprydningen blev afbrudt. Et påbegyndt lagerarbejde kan stadig afslutte; prøv igen for at kontrollere resultatet."
        }
    }
    private func resumeFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard localFavoritesStatus == .removed, let receipt = localFavoritesReceipt,
              receipt.isComplete, validLocalReceipt(receipt, checkpoint: checkpoint),
              localFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localFavoritesStatus == .removed && localFavoritesReceipt == receipt
    }
    var canPrepareLocalResumeCleanup: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle, localResumeStore != nil,
              localResumePreparation == nil, localResumeStatus != .removed,
              let candidate = intent, let checkpoint = localCheckpoint,
              resumeFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localFlight == nil && localResumePreparation == nil && localResumeStatus != .removed
    }
    @discardableResult func prepareLocalResumeCleanup() -> Bool {
        guard canPrepareLocalResumeCleanup, let candidate = intent,
              let checkpoint = localCheckpoint, let store = localResumeStore,
              resumeFamilyIsCurrent(candidate, checkpoint: checkpoint), localFlight == nil else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .resume)
        setLocalResumeStatus(.preparing)
        guard localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalResume(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint)
                        && self.resumeFamilyIsCurrent(candidate, checkpoint: checkpoint)
                })
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    self.finishLocalResume(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalResume(id, preparation: .init(confirmation: .init(id: UUID()), intent: candidate,
                    checkpoint: checkpoint, store: store, lease: lease), receipt: nil)
            } catch { self.finishLocalResume(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    @discardableResult func confirmLocalResumeCleanup(_ confirmation: LocalResumeConfirmation,
        userConfirmed: Bool) -> Bool {
        guard userConfirmed, localFlight == nil, localResumeStatus == .ready,
              let prepared = localResumePreparation, prepared.confirmation == confirmation,
              resumeFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint),
              localResumePreparation?.confirmation == confirmation else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .resume)
        localResumePreparation = nil; setLocalResumeStatus(.removing)
        guard localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
            finishLocalResume(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await prepared.store.commitLocalCleanup(prepared.lease, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint)
                        && self.resumeFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint)
                })
                guard !Task.isCancelled, receipt.isComplete, receipt.belongs(to: prepared.checkpoint),
                      self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
                    self.finishLocalResume(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalResume(id, preparation: nil, receipt: receipt)
            } catch { self.finishLocalResume(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    func cancelLocalResumeCleanup() {
        guard localFlight?.kind == .resume || localResumePreparation != nil else { return }
        localGeneration = UUID(); localResumePreparation = nil
        localFlight?.task?.cancel()
        let cancel = localFlight?.cancelDeadline; localFlight?.cancelDeadline = nil
        cancel?(); setLocalResumeStatus(.cancelled)
    }
    private func finishLocalResume(_ id: UUID, preparation: LocalResumePreparation?, receipt: ReaderResumeStore.CleanupReceipt?) {
        guard let physical = localFlight, physical.id == id, physical.kind == .resume else { return }
        localFlight = nil; physical.cancelDeadline?()
        guard localGeneration == id else { objectWillChange.send(); return }
        if let preparation, resumeFamilyIsCurrent(preparation.intent, checkpoint: preparation.checkpoint),
           localGeneration == id, localFlight == nil {
            localResumePreparation = preparation; setLocalResumeStatus(.ready)
        } else if let receipt, let candidate = intent, let checkpoint = localCheckpoint,
                  receipt.isComplete, receipt.belongs(to: checkpoint), resumeFamilyIsCurrent(candidate, checkpoint: checkpoint),
                  localGeneration == id, localFlight == nil {
            localResumeReceipt = receipt; setLocalResumeStatus(.removed)
        } else if localGeneration == id, localFlight == nil { setLocalResumeStatus(.failed) }
    }
    private func setLocalResumeStatus(_ value: LocalResumeStatus) {
        localResumeStatus = value; objectWillChange.send()
    }

    typealias LocalPodcastStatus = LocalFavoritesStatus
    struct LocalPodcastConfirmation: Equatable { fileprivate let id: UUID }
    private struct LocalPodcastPreparation {
        let confirmation: LocalPodcastConfirmation
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let store: PodcastPlaybackProgressStore
        let lease: PodcastPlaybackProgressStore.CleanupLease
    }
    private let localPodcastStore: PodcastPlaybackProgressStore?
    private var localPodcastPreparation: LocalPodcastPreparation?
    private(set) var localPodcastStatus: LocalPodcastStatus = .idle
    private(set) var localPodcastReceipt: PodcastPlaybackProgressStore.CleanupReceipt?
    var localPodcastConfirmation: LocalPodcastConfirmation? { localPodcastPreparation?.confirmation }
    var localPodcastMessage: String? {
        switch localPodcastStatus {
        case .idle: nil
        case .preparing: "Klargør kontoens lyttepositioner på denne enhed…"
        case .ready: "Lyttepositionerne er klargjort. Bekræft for at fjerne dem fra denne enhed."
        case .removing: "Fjerner kontoens lyttepositioner på denne enhed…"
        case .removed: "Kontoens lyttepositioner er fjernet fra denne enhed. Den samlede kontosletning er ikke færdig."
        case .failed: "Oprydningen kunne ikke bekræftes. Prøv igen med en ny bekræftelse."
        case .cancelled: "Oprydningen blev afbrudt. Et påbegyndt lagerarbejde kan stadig afslutte; prøv igen for at kontrollere resultatet."
        }
    }
    private func podcastFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard localResumeStatus == .removed, let receipt = localResumeReceipt,
              receipt.isComplete, receipt.belongs(to: checkpoint),
              resumeFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localResumeStatus == .removed && localResumeReceipt == receipt
    }
    var canPrepareLocalPodcastCleanup: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle, localPodcastStore?.isPhysicallyIdle == true,
              localPodcastPreparation == nil, localPodcastStatus != .removed,
              let candidate = intent, let checkpoint = localCheckpoint,
              podcastFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localFlight == nil && localPodcastPreparation == nil && localPodcastStatus != .removed
    }
    @discardableResult func prepareLocalPodcastCleanup() -> Bool {
        guard canPrepareLocalPodcastCleanup, let candidate = intent,
              let checkpoint = localCheckpoint, let store = localPodcastStore,
              podcastFamilyIsCurrent(candidate, checkpoint: checkpoint), localFlight == nil else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .podcast)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        setLocalPodcastStatus(.preparing)
        guard localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalPodcast(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint)
                        && self.podcastFamilyIsCurrent(candidate, checkpoint: checkpoint)
                })
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    self.finishLocalPodcast(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalPodcast(id, preparation: .init(confirmation: .init(id: UUID()), intent: candidate,
                    checkpoint: checkpoint, store: store, lease: lease), receipt: nil)
            } catch { self.finishLocalPodcast(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    @discardableResult func confirmLocalPodcastCleanup(_ confirmation: LocalPodcastConfirmation,
        userConfirmed: Bool) -> Bool {
        guard userConfirmed, localFlight == nil, localPodcastStatus == .ready,
              let prepared = localPodcastPreparation, prepared.confirmation == confirmation,
              podcastFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint),
              localPodcastPreparation?.confirmation == confirmation else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .podcast)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        localPodcastPreparation = nil; setLocalPodcastStatus(.removing)
        guard localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
            finishLocalPodcast(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await prepared.store.commitLocalCleanup(prepared.lease, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint)
                        && self.podcastFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint)
                })
                guard !Task.isCancelled, receipt.isComplete, receipt.belongs(to: prepared.checkpoint),
                      self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
                    self.finishLocalPodcast(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalPodcast(id, preparation: nil, receipt: receipt)
            } catch { self.finishLocalPodcast(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    func cancelLocalPodcastCleanup() {
        guard localFlight?.kind == .podcast || localPodcastPreparation != nil else { return }
        localFlight?.completionAdmission?.setAllowed(false)
        localGeneration = UUID(); localPodcastPreparation = nil
        localFlight?.task?.cancel()
        let cancel = localFlight?.cancelDeadline; localFlight?.cancelDeadline = nil
        cancel?(); setLocalPodcastStatus(.cancelled)
    }
    private func finishLocalPodcast(_ id: UUID, preparation: LocalPodcastPreparation?, receipt: PodcastPlaybackProgressStore.CleanupReceipt?) {
        guard let physical = localFlight, physical.id == id, physical.kind == .podcast else { return }
        physical.completionAdmission?.setAllowed(false)
        localFlight = nil; physical.cancelDeadline?()
        guard localGeneration == id else { objectWillChange.send(); return }
        if let preparation, podcastFamilyIsCurrent(preparation.intent, checkpoint: preparation.checkpoint),
           localGeneration == id, localFlight == nil {
            localPodcastPreparation = preparation; setLocalPodcastStatus(.ready)
        } else if let receipt, let candidate = intent, let checkpoint = localCheckpoint,
                  receipt.isComplete, receipt.belongs(to: checkpoint), podcastFamilyIsCurrent(candidate, checkpoint: checkpoint),
                  localGeneration == id, localFlight == nil {
            localPodcastReceipt = receipt; setLocalPodcastStatus(.removed)
        } else if localGeneration == id, localFlight == nil { setLocalPodcastStatus(.failed) }
    }
    private func setLocalPodcastStatus(_ value: LocalPodcastStatus) {
        localPodcastStatus = value; objectWillChange.send()
    }

    typealias LocalIntroductionStatus = LocalFavoritesStatus
    struct LocalIntroductionConfirmation: Equatable { fileprivate let id: UUID }
    private struct LocalIntroductionPreparation {
        let confirmation: LocalIntroductionConfirmation
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let store: ReaderIntroductionModel
        let lease: ReaderIntroductionModel.CleanupLease
    }
    private let localIntroductionModel: ReaderIntroductionModel?
    private var localIntroductionPreparation: LocalIntroductionPreparation?
    private(set) var localIntroductionStatus: LocalIntroductionStatus = .idle
    private(set) var localIntroductionReceipt: ReaderIntroductionModel.CleanupReceipt?
    var localIntroductionConfirmation: LocalIntroductionConfirmation? { localIntroductionPreparation?.confirmation }
    var localIntroductionMessage: String? {
        switch localIntroductionStatus {
        case .idle: nil
        case .preparing: "Klargør kontoens introduktionsudkast på denne enhed…"
        case .ready: "Introduktionsudkastet er klargjort. Bekræft for at fjerne det fra denne enhed."
        case .removing: "Fjerner kontoens introduktionsudkast på denne enhed…"
        case .removed: "Kontoens introduktionsudkast er fjernet fra denne enhed. Den samlede kontosletning er ikke færdig."
        case .failed: "Oprydningen kunne ikke bekræftes. Prøv igen med en ny bekræftelse."
        case .cancelled: "Oprydningen blev afbrudt. Et påbegyndt lagerarbejde kan stadig afslutte; prøv igen for at kontrollere resultatet."
        }
    }
    private func introductionFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard localPodcastStatus == .removed, let receipt = localPodcastReceipt,
              receipt.isComplete, receipt.belongs(to: checkpoint),
              podcastFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localPodcastStatus == .removed && localPodcastReceipt == receipt
    }
    var canPrepareLocalIntroductionCleanup: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle, localIntroductionModel?.isPhysicallyIdle == true,
              localIntroductionPreparation == nil, localIntroductionStatus != .removed,
              let candidate = intent, let checkpoint = localCheckpoint,
              introductionFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localFlight == nil && localIntroductionPreparation == nil && localIntroductionStatus != .removed
    }
    @discardableResult func prepareLocalIntroductionCleanup() -> Bool {
        guard canPrepareLocalIntroductionCleanup, let candidate = intent,
              let checkpoint = localCheckpoint, let store = localIntroductionModel,
              introductionFamilyIsCurrent(candidate, checkpoint: checkpoint), localFlight == nil else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .introduction)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        setLocalIntroductionStatus(.preparing)
        guard localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalIntroduction(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint)
                        && self.introductionFamilyIsCurrent(candidate, checkpoint: checkpoint)
                })
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    self.finishLocalIntroduction(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalIntroduction(id, preparation: .init(confirmation: .init(id: UUID()), intent: candidate,
                    checkpoint: checkpoint, store: store, lease: lease), receipt: nil)
            } catch { self.finishLocalIntroduction(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    @discardableResult func confirmLocalIntroductionCleanup(_ confirmation: LocalIntroductionConfirmation,
        userConfirmed: Bool) -> Bool {
        guard userConfirmed, localFlight == nil, localIntroductionStatus == .ready,
              let prepared = localIntroductionPreparation, prepared.confirmation == confirmation,
              introductionFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint),
              localIntroductionPreparation?.confirmation == confirmation else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .introduction)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        localIntroductionPreparation = nil; setLocalIntroductionStatus(.removing)
        guard localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
            finishLocalIntroduction(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await prepared.store.commitLocalCleanup(prepared.lease, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint)
                        && self.introductionFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint)
                })
                guard !Task.isCancelled, receipt.isComplete, receipt.belongs(to: prepared.checkpoint),
                      self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
                    self.finishLocalIntroduction(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalIntroduction(id, preparation: nil, receipt: receipt)
            } catch { self.finishLocalIntroduction(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    func cancelLocalIntroductionCleanup() {
        guard localFlight?.kind == .introduction || localIntroductionPreparation != nil else { return }
        localFlight?.completionAdmission?.setAllowed(false)
        localGeneration = UUID(); localIntroductionPreparation = nil
        localFlight?.task?.cancel()
        let cancel = localFlight?.cancelDeadline; localFlight?.cancelDeadline = nil
        cancel?(); setLocalIntroductionStatus(.cancelled)
    }
    private func finishLocalIntroduction(_ id: UUID, preparation: LocalIntroductionPreparation?, receipt: ReaderIntroductionModel.CleanupReceipt?) {
        guard let physical = localFlight, physical.id == id, physical.kind == .introduction else { return }
        physical.completionAdmission?.setAllowed(false)
        localFlight = nil; physical.cancelDeadline?()
        guard localGeneration == id else { objectWillChange.send(); return }
        if let preparation, introductionFamilyIsCurrent(preparation.intent, checkpoint: preparation.checkpoint),
           localGeneration == id, localFlight == nil {
            localIntroductionPreparation = preparation; setLocalIntroductionStatus(.ready)
        } else if let receipt, let candidate = intent, let checkpoint = localCheckpoint,
                  receipt.isComplete, receipt.belongs(to: checkpoint), introductionFamilyIsCurrent(candidate, checkpoint: checkpoint),
                  localGeneration == id, localFlight == nil {
            localIntroductionReceipt = receipt; setLocalIntroductionStatus(.removed)
        } else if localGeneration == id, localFlight == nil { setLocalIntroductionStatus(.failed) }
    }
    private func setLocalIntroductionStatus(_ value: LocalIntroductionStatus) {
        localIntroductionStatus = value; objectWillChange.send()
    }

    typealias LocalHistoryStatus = LocalFavoritesStatus
    struct LocalHistoryConfirmation: Equatable { fileprivate let id: UUID }
    private struct LocalHistoryPreparation {
        let confirmation: LocalHistoryConfirmation
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let store: ReadingHistoryModel
        let lease: ReadingHistoryModel.CleanupLease
    }
    private let localHistoryModel: ReadingHistoryModel?
    private var localHistoryPreparation: LocalHistoryPreparation?
    private(set) var localHistoryStatus: LocalHistoryStatus = .idle
    private(set) var localHistoryReceipt: ReadingHistoryModel.CleanupReceipt?
    var localHistoryConfirmation: LocalHistoryConfirmation? { localHistoryPreparation?.confirmation }
    var localHistoryMessage: String? {
        switch localHistoryStatus {
        case .idle: nil
        case .preparing: "Klargør kontoens læsehistorik til lokal kontrol…"
        case .ready: "Læsehistorikken er klargjort. Bekræft den lokale oprydning; iCloud-oprydning er ikke bekræftet."
        case .removing: "Rydder kontoens lokale læsehistorik…"
        case .removed: "Den lokale oprydning er kontrolleret på denne enhed. iCloud-oprydning og den samlede kontosletning er ikke bekræftet."
        case .failed: "Oprydningen kunne ikke bekræftes. Prøv igen med en ny bekræftelse."
        case .cancelled: "Oprydningen blev afbrudt. Et påbegyndt lagerarbejde kan stadig afslutte; prøv igen for at kontrollere resultatet."
        }
    }
    private func historyFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard localIntroductionStatus == .removed, let receipt = localIntroductionReceipt,
              receipt.isComplete, receipt.belongs(to: checkpoint),
              introductionFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localIntroductionStatus == .removed && localIntroductionReceipt == receipt
    }
    var canPrepareLocalHistoryCleanup: Bool {
        guard localFlight == nil, flight == nil, barrierPhysicallyIdle, localHistoryModel?.isPhysicallyIdle == true,
              localHistoryModel?.isLocalCleanupAvailable == true,
              localHistoryPreparation == nil, localHistoryStatus != .removed,
              let candidate = intent, let checkpoint = localCheckpoint,
              historyFamilyIsCurrent(candidate, checkpoint: checkpoint) else { return false }
        return localFlight == nil && localHistoryPreparation == nil && localHistoryStatus != .removed
    }
    @discardableResult func prepareLocalHistoryCleanup() -> Bool {
        guard canPrepareLocalHistoryCleanup, let candidate = intent,
              let checkpoint = localCheckpoint, let store = localHistoryModel,
              historyFamilyIsCurrent(candidate, checkpoint: checkpoint), localFlight == nil else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .history)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        setLocalHistoryStatus(.preparing)
        guard localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
            finishLocalHistory(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let lease = try await store.prepareLocalCleanup(checkpoint: checkpoint, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint)
                        && self.historyFamilyIsCurrent(candidate, checkpoint: checkpoint)
                })
                guard !Task.isCancelled, self.localActionIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else {
                    self.finishLocalHistory(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalHistory(id, preparation: .init(confirmation: .init(id: UUID()), intent: candidate,
                    checkpoint: checkpoint, store: store, lease: lease), receipt: nil)
            } catch { self.finishLocalHistory(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    @discardableResult func confirmLocalHistoryCleanup(_ confirmation: LocalHistoryConfirmation,
        userConfirmed: Bool) -> Bool {
        guard userConfirmed, localFlight == nil, localHistoryStatus == .ready,
              let prepared = localHistoryPreparation, prepared.confirmation == confirmation,
              historyFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint),
              localHistoryPreparation?.confirmation == confirmation else { return false }
        let id = UUID(); localGeneration = id; localFlight = LocalFavoritesFlight(id: id, kind: .history)
        guard let finalAdmission = localFlight?.completionAdmission else { return false }
        localHistoryPreparation = nil; setLocalHistoryStatus(.removing)
        guard localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
            finishLocalHistory(id, preparation: nil, receipt: nil); return false
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await prepared.store.commitLocalCleanup(prepared.lease, finalAdmission: finalAdmission, stillCurrent: { [weak self] in
                    guard let self else { return false }
                    return self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint)
                        && self.historyFamilyIsCurrent(prepared.intent, checkpoint: prepared.checkpoint)
                })
                guard !Task.isCancelled, receipt.isLocalReadbackConfirmed, !receipt.cloudCleanupComplete, receipt.belongs(to: prepared.checkpoint),
                      self.localActionIsCurrent(id, candidate: prepared.intent, checkpoint: prepared.checkpoint) else {
                    self.finishLocalHistory(id, preparation: nil, receipt: nil); return
                }
                self.finishLocalHistory(id, preparation: nil, receipt: receipt)
            } catch { self.finishLocalHistory(id, preparation: nil, receipt: nil) }
        }
        installLocalTask(task, id: id)
        return localGeneration == id
    }
    func cancelLocalHistoryCleanup() {
        guard localFlight?.kind == .history || localHistoryPreparation != nil else { return }
        localFlight?.completionAdmission?.setAllowed(false)
        localGeneration = UUID(); localHistoryPreparation = nil
        localFlight?.task?.cancel()
        let cancel = localFlight?.cancelDeadline; localFlight?.cancelDeadline = nil
        cancel?(); setLocalHistoryStatus(.cancelled)
    }
    private func finishLocalHistory(_ id: UUID, preparation: LocalHistoryPreparation?, receipt: ReadingHistoryModel.CleanupReceipt?) {
        guard let physical = localFlight, physical.id == id, physical.kind == .history else { return }
        physical.completionAdmission?.setAllowed(false)
        localFlight = nil; physical.cancelDeadline?()
        guard localGeneration == id else { objectWillChange.send(); return }
        if let preparation, historyFamilyIsCurrent(preparation.intent, checkpoint: preparation.checkpoint),
           localGeneration == id, localFlight == nil {
            localHistoryPreparation = preparation; setLocalHistoryStatus(.ready)
        } else if let receipt, let candidate = intent, let checkpoint = localCheckpoint,
                  receipt.isLocalReadbackConfirmed, !receipt.cloudCleanupComplete, receipt.belongs(to: checkpoint), historyFamilyIsCurrent(candidate, checkpoint: checkpoint),
                  localGeneration == id, localFlight == nil {
            localHistoryReceipt = receipt; setLocalHistoryStatus(.removed)
        } else if localGeneration == id, localFlight == nil { setLocalHistoryStatus(.failed) }
    }
    private func setLocalHistoryStatus(_ value: LocalHistoryStatus) {
        localHistoryStatus = value; objectWillChange.send()
    }

    // One explicitly selected installation, inside the existing sealed recovery.
    // The key remains private. Only the secret-free, exact confirmed commit is
    // retained by the existing recovery store; disk never supplies authority.
    enum PushStatus: Equatable { case idle, readingInstallation, preparing, ready, awaitingRetry, retiring, retired, unavailable, cancelled, timedOut }
    private typealias PushCheckpoint = ReaderTransitionRecoveryStore.PushCommitCheckpoint
    private enum PushCompletion { case response(Data), restored }
    struct PushConfirmation: Equatable { fileprivate let id: UUID }
    private struct PushOriginal {
        let intent: Intent
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
        let record: PushInstallationRecord
        let preparationRequest: Contract.PushRequest
        var commitRequest: Contract.PushRequest?
        var pending: PushCheckpoint?
        func request(for phase: Phase) -> Contract.PushRequest? {
            phase == .pushPreparation ? preparationRequest : commitRequest
        }
    }
    private var pushOriginal: PushOriginal?
    private var pushGeneration = UUID()
    private var pushCommitAttempted = false
    private(set) var pushStatus: PushStatus = .idle
    private(set) var pushConfirmation: PushConfirmation?
    private(set) var pushReceipt: Contract.PushReceipt?
    var hasStoredPushCommit: Bool { localRecovery?.pushCommitCheckpoint != nil }
    var pushMessage: String? {
        switch pushStatus {
        case .idle: return nil
        case .readingInstallation: return "Kontrollerer denne installations kvitterede pushregistrering…"
        case .preparing: return "Klargør denne installations pushregistrering. Intet fjernes endnu."
        case .ready: return "Denne registrering er klar til særskilt bekræftelse. Intet er fjernet endnu."
        case .awaitingRetry: return "Den tidligere anmodning er fundet. Bekræft igen for at kontrollere resultatet for samme installation."
        case .retiring: return "Afslutter denne installations pushregistrering…"
        case .retired: return "Denne installations pushregistrering er afsluttet. Andre registreringer og data mangler fortsat; kontosletning er ikke gennemført."
        case .unavailable: return "Denne pushregistrering kunne ikke bekræftes. Manglende eller ændrede installationsoplysninger kan ikke erstattes her."
        case .cancelled: return "Handlingen er lukket her. En allerede modtaget anmodning kan være gennemført."
        case .timedOut: return "Svaret kom ikke i tide. Prøv samme anmodning igen, når den igangværende handling er afsluttet."
        }
    }
    private var pushConfigured: Bool {
        pushInstallationVault != nil && pushAppID != nil && sendPushPreparation != nil && sendPushRetirement != nil && configured
    }
    private var pushSlotsIdle: Bool {
        localFlight == nil && flight == nil && barrierPhysicallyIdle
            && localPreparation == nil && localResumePreparation == nil && localPodcastPreparation == nil
            && localIntroductionPreparation == nil && localHistoryPreparation == nil
    }
    var canPreparePushRetirement: Bool {
        guard pushConfigured, pushSlotsIdle, !pushCommitAttempted, pushConfirmation == nil,
              [.idle, .unavailable, .cancelled, .timedOut].contains(pushStatus),
              let candidate = intent, let checkpoint = localCheckpoint else { return false }
        let generation = pushGeneration
        return pushFamilyIsCurrent(candidate, checkpoint: checkpoint, generation: generation)
            && pushSlotsIdle && !pushCommitAttempted && pushConfirmation == nil
    }
    var canRetryPushRetirement: Bool {
        guard pushConfigured, pushSlotsIdle, pushCommitAttempted, let original = pushOriginal,
              original.commitRequest != nil, [.awaitingRetry, .unavailable, .timedOut, .cancelled].contains(pushStatus) else { return false }
        let generation = pushGeneration
        return pushFamilyIsCurrent(original.intent, checkpoint: original.checkpoint, generation: generation)
            && pushSlotsIdle && pushOriginal?.commitRequest == original.commitRequest
    }
    private func pushFamilyIsCurrent(_ candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint, generation: UUID) -> Bool {
        guard generation == pushGeneration else { return false }
        let valid = localFamilyIsCurrent(candidate, checkpoint: checkpoint)
        return valid && generation == pushGeneration && intent == candidate
            && canonical?.isCurrent(candidate.context) == true
            && localCheckpoint?.isSameFamily(as: checkpoint) == true
    }
    @discardableResult
    func preparePushRetirement() -> Bool {
        guard canPreparePushRetirement, let candidate = intent, let checkpoint = localCheckpoint else { return false }
        return runPush(phase: .pushPreparation, candidate: candidate, checkpoint: checkpoint)
    }
    @discardableResult
    func confirmPushRetirement(_ confirmation: PushConfirmation) -> Bool {
        guard pushSlotsIdle, pushStatus == .ready, pushConfirmation == confirmation,
              let original = pushOriginal, original.commitRequest != nil else { return false }
        let generation = pushGeneration
        guard pushFamilyIsCurrent(original.intent, checkpoint: original.checkpoint, generation: generation),
              pushConfirmation == confirmation, pushSlotsIdle else { return false }
        pushConfirmation = nil // Single use, before any clock/provider/publication hook.
        pushCommitAttempted = true
        return runPush(phase: .pushRetirement, candidate: original.intent, checkpoint: original.checkpoint)
    }
    @discardableResult
    func retryPushRetirement(userConfirmed: Bool) -> Bool {
        guard userConfirmed, canRetryPushRetirement, let original = pushOriginal else { return false }
        return runPush(phase: .pushRetirement, candidate: original.intent, checkpoint: original.checkpoint)
    }
    func cancelPushRetirement() { cancelPushRetirement(status: .cancelled) }
    private func cancelPushRetirement(status: PushStatus) {
        guard localFlight?.kind == .push || pushOriginal != nil || pushConfirmation != nil else { return }
        pushGeneration = UUID() // Revoke before cancellation/publication hooks.
        pushConfirmation = nil
        if !pushCommitAttempted { pushOriginal = nil }
        if flight?.action.phase == .pushPreparation || flight?.action.phase == .pushRetirement { activeAction = nil }
        let task = localFlight?.kind == .push ? localFlight?.task : nil
        let cancel = localFlight?.kind == .push ? localFlight?.cancelDeadline : nil
        if localFlight?.kind == .push { localFlight?.cancelDeadline = nil }
        task?.cancel(); cancel?()
        _ = publishPush(status, generation: pushGeneration)
    }
    @discardableResult
    private func publishPush(_ next: PushStatus, generation: UUID) -> Bool {
        guard generation == pushGeneration else { return false }
        let originalIntent = intent
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard generation == pushGeneration, intent == originalIntent else { return false }
        // Error/cancellation presentation grants no authority. It must still
        // replace a spinner if a read failure invalidated the recovery family.
        if ![.unavailable, .cancelled, .timedOut].contains(next) {
            guard let candidate = originalIntent, let checkpoint = localCheckpoint,
                  pushFamilyIsCurrent(candidate, checkpoint: checkpoint, generation: generation) else { return false }
        }
        pushStatus = next
        return true
    }
    private func pushFlightIsCurrent(_ id: UUID, candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        localFlight?.id == id && localFlight?.kind == .push && !Task.isCancelled
            && pushFamilyIsCurrent(candidate, checkpoint: checkpoint, generation: id)
            && localFlight?.id == id
    }
    /// Read-only checks of the same decoded installation record and durable recovery family.
    /// No identity creation, registration, new revision, checkpoint write or SDK reference.
    func validatePushStorage(action: ActionTicket) async throws {
        guard let original = pushOriginal, let vault = pushInstallationVault, isActive(action),
              let recovery = localRecovery else { throw CancellationError() }
        let record = try await vault.readExisting()
        guard isActive(action), record == original.record, !Task.isCancelled else { throw CancellationError() }
        let checkpoint = try await recovery.readResumption()
        guard isActive(action), checkpoint == original.checkpoint,
              !Task.isCancelled else { throw CancellationError() }
        if action.phase == .pushRetirement {
            guard let expected = original.pending, recovery.pushCommitCheckpoint == expected else { throw CancellationError() }
        } else {
            guard recovery.pushCommitCheckpoint == nil else { throw CancellationError() }
        }
        // The disk checkpoint read is another await: repeat the exact vault
        // observation after it. This is not a distributed/keychain+HTTP lock.
        let finalRecord = try await vault.readExisting()
        guard isActive(action), finalRecord == original.record, !Task.isCancelled else { throw CancellationError() }
    }

    /// Enter only after the separate commit/retry confirmation. This exact
    /// immutable save also repairs an unconfirmed earlier write. A generic
    /// resumption read must not run first: an attempted-but-missing child is
    /// deliberately denied by that read. The store verifies its parent family
    /// physically before writing and holds its slot through exact readback.
    private func retainPushCommit(action: ActionTicket) async throws {
        guard let original = pushOriginal, let vault = pushInstallationVault,
              let recovery = localRecovery, isActive(action),
              let request = original.commitRequest, let snapshot = request.installation.snapshot else { throw CancellationError() }
        let record = try await vault.readExisting()
        guard isActive(action), record == original.record, !Task.isCancelled else { throw CancellationError() }
        let pending = try PushCheckpoint(checkpoint: original.checkpoint, snapshot: snapshot,
            recordDigest: PushCheckpoint.recordDigest(for: original.record))
        if let previous = original.pending, previous != pending { throw CancellationError() }
        pushOriginal?.pending = pending // Never adopt a new request after uncertainty.
        let verified = try await recovery.recordPushCommit(pending)
        guard isActive(action), verified == pending, !Task.isCancelled else { throw CancellationError() }
    }
    private func runPush(phase: Phase, candidate: Intent,
        checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint) -> Bool {
        guard pushConfigured, pushSlotsIdle, let vault = pushInstallationVault,
              let appID = pushAppID, let reauthenticate else { return false }
        let id = UUID()
        pushGeneration = id
        localFlight = .init(id: id, kind: .push) // Reserve before all injected hooks.
        if phase == .pushPreparation { pushOriginal = nil; pushReceipt = nil }
        guard pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
              publishPush(phase == .pushPreparation ? .readingInstallation : .retiring, generation: id) else {
            finishPush(id: id, action: nil, result: .failure(CancellationError())); return false
        }
        let cancelDeadline = scheduleTimeout(timeoutSeconds) { [weak self] in
            guard let self, self.localFlight?.id == id, self.pushGeneration == id else { return }
            self.cancelPushRetirement(status: .timedOut)
        }
        guard localFlight?.id == id, pushGeneration == id else {
            cancelDeadline(); finishPush(id: id, action: nil, result: .failure(CancellationError())); return false
        }
        localFlight?.cancelDeadline = cancelDeadline
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var action: ActionTicket?
            do {
                guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint) else { throw CancellationError() }
                if phase == .pushPreparation {
                    guard let recovery = self.localRecovery else { throw CancellationError() }
                    let diskCheckpoint = try await recovery.readResumption()
                    guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
                          diskCheckpoint == checkpoint else { throw CancellationError() }
                    let retained = recovery.pushCommitCheckpoint
                    let record = try await vault.readExisting()
                    guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint), let record,
                          let binding = record.acknowledgedBinding,
                          binding.ownerUID == candidate.request.expectedUID, binding.appId == appID,
                          binding.installationId == record.installationId, binding.clientRevision == record.revision,
                          let ledger = candidate.ledgerRequest else { throw CancellationError() }
                    try record.validate(); try binding.validate()
                    if let retained {
                        guard retained.checkpoint == checkpoint, retained.snapshot.appId == appID,
                              retained.recordDigest == (try PushCheckpoint.recordDigest(for: record)) else { throw CancellationError() }
                        let commit = try retained.commitRequest(key: record.key)
                        guard commit.installation.installationId == binding.installationId,
                              commit.installation.expected.ownerEpoch == binding.ownerEpoch,
                              commit.installation.expected.revision == binding.revision,
                              commit.installation.expected.clientRevision == binding.clientRevision else { throw CancellationError() }
                        // This private prepare-shaped value is never sent. It
                        // only preserves the existing request representation.
                        let preparation = try Contract.PushRequest(expectedUID: commit.expectedUID,
                            membershipEpoch: commit.membershipEpoch, parentRequestID: commit.parentRequestID,
                            ledgerRequestID: commit.ledgerRequestID, installation: .init(
                                installationId: record.installationId, key: record.key,
                                requestId: retained.snapshot.requestId, expected: commit.installation.expected))
                        let finalCheckpoint = try await recovery.readResumption()
                        guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
                              finalCheckpoint == checkpoint, recovery.pushCommitCheckpoint == retained else { throw CancellationError() }
                        let finalRecord = try await vault.readExisting()
                        guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
                              finalRecord == record else { throw CancellationError() }
                        self.pushOriginal = .init(intent: candidate, checkpoint: checkpoint, record: record,
                            preparationRequest: preparation, commitRequest: commit, pending: retained)
                        self.pushCommitAttempted = true
                        self.finishPush(id: id, action: nil, result: .success(.restored))
                        return
                    }
                    let request = try Contract.PushRequest(expectedUID: candidate.request.expectedUID,
                        membershipEpoch: candidate.request.membershipEpoch, parentRequestID: candidate.request.requestID,
                        ledgerRequestID: ledger.requestID, installation: .init(installationId: record.installationId,
                            key: record.key, requestId: UUID().uuidString.lowercased(), expected: .init(
                                ownerEpoch: binding.ownerEpoch, revision: binding.revision, clientRevision: binding.clientRevision)))
                    self.pushOriginal = .init(intent: candidate, checkpoint: checkpoint, record: record,
                                              preparationRequest: request, commitRequest: nil, pending: nil)
                }
                guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
                      let request = self.pushOriginal?.request(for: phase) else { throw CancellationError() }
                let now = self.nowMilliseconds()
                guard self.pushFlightIsCurrent(id, candidate: candidate, checkpoint: checkpoint),
                      (1...Contract.maximumSafeInteger).contains(now) else { throw CancellationError() }
                let ticket = ActionTicket(actionID: UUID(), context: candidate.context, request: candidate.request,
                    phase: phase, ledgerRequest: candidate.ledgerRequest, pushRequest: request,
                    startedAtMs: now, coordinatorID: self.coordinatorID)
                action = ticket; self.activeAction = ticket; self.flight = Flight(action: ticket)
                if phase == .pushRetirement { try await self.retainPushCommit(action: ticket) }
                try await self.validatePushStorage(action: ticket)
                guard self.publishPush(phase == .pushPreparation ? .preparing : .retiring, generation: id),
                      self.isActive(ticket) else { throw CancellationError() }
                let proof = try await reauthenticate(ticket)
                guard self.accepts(proof, for: ticket), !Task.isCancelled else { throw CancellationError() }
                try await self.validatePushStorage(action: ticket)
                let send = phase == .pushPreparation ? self.sendPushPreparation : self.sendPushRetirement
                guard self.isActive(ticket), let send else { throw CancellationError() }
                let data = try await send(request, proof)
                guard self.isActive(ticket), !Task.isCancelled else { throw CancellationError() }
                try await self.validatePushStorage(action: ticket)
                self.finishPush(id: id, action: ticket, result: .success(.response(data)))
            } catch { self.finishPush(id: id, action: action, result: .failure(error)) }
        }
        if localFlight?.id == id { localFlight?.task = task } else { task.cancel() }
        return pushGeneration == id && localFlight?.id == id
    }
    private func finishPush(id: UUID, action: ActionTicket?, result: Result<PushCompletion, Error>) {
        guard localFlight?.id == id, localFlight?.kind == .push else { return }
        let cancel = localFlight?.cancelDeadline
        localFlight = nil
        if flight?.action == action { flight = nil }
        if activeAction == action { activeAction = nil }
        cancel?() // Physical return is the only slot release; hooks may now reenter.
        guard pushGeneration == id else {
            _ = publishPush(pushStatus, generation: pushGeneration); return
        }
        guard let original = pushOriginal else { _ = publishPush(.unavailable, generation: id); return }
        guard pushFamilyIsCurrent(original.intent, checkpoint: original.checkpoint, generation: id) else {
            _ = publishPush(.unavailable, generation: id); return
        }
        if case .success(.restored) = result {
            guard original.pending != nil, original.commitRequest != nil else { return }
            _ = publishPush(.awaitingRetry, generation: id)
            return
        }
        guard case .success(.response(let data)) = result, let action, let appID = pushAppID else {
            _ = publishPush(.unavailable, generation: id); return
        }
        do {
            if action.phase == .pushPreparation {
                let receipt = try Contract.decodePushPreparationReceipt(data: data, for: original.preparationRequest, appID: appID)
                let commit = try original.preparationRequest.committing(receipt.snapshot)
                guard pushGeneration == id else { return }
                // Do not expose the confirmation until original family survived UI hooks.
                guard publishPush(.ready, generation: id) else { return }
                pushOriginal?.commitRequest = commit
                pushConfirmation = PushConfirmation(id: UUID())
            } else {
                guard let request = original.commitRequest else { throw CancellationError() }
                let receipt = try Contract.decodePushReceipt(data: data, for: request, appID: appID)
                guard publishPush(.retired, generation: id) else { return }
                pushReceipt = receipt
            }
        } catch { _ = publishPush(.unavailable, generation: id) }
    }

    private struct Intent: Equatable {
        let context: ContextTicket
        let request: Contract.Request
        let ledgerRequest: Contract.LedgerRequest?
        var phase: Phase { ledgerRequest == nil ? .cloudSlice : .mutationLedger }
        var requestID: String { ledgerRequest?.requestID ?? request.requestID }
    }
    private struct AcceptedParent: Equatable {
        let context: ContextTicket
        let request: Contract.Request
        let receipt: Contract.Receipt
    }
    private struct Flight {
        let action: ActionTicket
        var task: Task<Void, Never>?
        var cancelDeadline: Cancellation?
    }
    private weak var canonical: CanonicalSessionState?
    private let currentMembershipEpoch: EpochReader?
    private let reauthenticate: Reauthenticator?
    private let send: Sender?
    private let sendLedger: LedgerSender?
    private let sendPushPreparation: PushSender?
    private let sendPushRetirement: PushSender?
    private let pushInstallationVault: PushInstallationVault?
    private let pushAppID: String?
    private let nowMilliseconds: Clock
    private let scheduleTimeout: TimeoutScheduler
    private let timeoutSeconds: TimeInterval
    private let coordinatorID = UUID()
    private var observation: AnyCancellable?
    private var intent: Intent?
    private var activeAction: ActionTicket?
    private var flight: Flight?
    private var acceptedReceipt: Contract.Receipt?
    private var acceptedLedgerReceipt: Contract.LedgerReceipt?
    private var acceptedParent: AcceptedParent?
    private var presentation: Status
    private var publication = UUID()
    private var notifying = false

    init(canonical: CanonicalSessionState,
         currentMembershipEpoch: EpochReader? = nil,
         reauthenticate: Reauthenticator? = nil,
         send: Sender? = nil,
         sendLedger: LedgerSender? = nil,
         sendPushPreparation: PushSender? = nil,
         sendPushRetirement: PushSender? = nil,
         pushInstallationVault: PushInstallationVault? = nil,
         pushAppID: String? = nil,
         writeBarrier: WriteBarrier? = nil,
         resumption: Resumption? = nil,
         configurationDigest: String? = nil,
         localJournalFactory: LocalJournalFactory? = nil,
         localResumeStore: ReaderResumeStore? = nil,
         localPodcastStore: PodcastPlaybackProgressStore? = nil,
         localIntroductionModel: ReaderIntroductionModel? = nil,
         localHistoryModel: ReadingHistoryModel? = nil,
         nowMilliseconds: @escaping Clock = { Int64(Date().timeIntervalSince1970 * 1_000) },
         timeoutSeconds: TimeInterval = 30,
         scheduleTimeout: @escaping TimeoutScheduler = ReaderAccountDeletionCoordinator.deadline) {
        self.canonical = canonical
        self.currentMembershipEpoch = currentMembershipEpoch
        self.reauthenticate = reauthenticate
        self.send = send
        self.sendLedger = sendLedger
        self.sendPushPreparation = sendPushPreparation; self.sendPushRetirement = sendPushRetirement
        self.pushInstallationVault = pushInstallationVault; self.pushAppID = pushAppID
        self.writeBarrier = writeBarrier
        self.resumption = resumption
        self.configurationDigest = configurationDigest
        self.localJournalFactory = localJournalFactory
        self.localResumeStore = writeBarrier?.resumeStore ?? localResumeStore
        self.localPodcastStore = writeBarrier?.podcastStore ?? localPodcastStore
        self.localIntroductionModel = localIntroductionModel
        self.localHistoryModel = localHistoryModel
        self.nowMilliseconds = nowMilliseconds
        self.timeoutSeconds = timeoutSeconds
        self.scheduleTimeout = scheduleTimeout
        presentation = (currentMembershipEpoch != nil || resumption != nil) && reauthenticate != nil && send != nil
            && timeoutSeconds.isFinite && timeoutSeconds > 0 && timeoutSeconds <= 120 ? .idle : .unavailable
        observation = canonical.changes.sink { [weak self] _ in self?.membershipDidChange() }
    }

    /// This is an explicit user action, never a login/listener side effect. The
    /// supplied epoch must be the current authoritative reader membership epoch.
    @discardableResult
    func begin(context: ContextTicket, membershipEpoch: Int64, userConfirmed: Bool) -> Bool {
        guard resumption == nil, userConfirmed, configured, flight == nil, let uid = context.userID,
              let request = try? Contract.Request(expectedUID: uid, membershipEpoch: membershipEpoch) else { return false }
        return start(Intent(context: context, request: request, ledgerRequest: nil))
    }

    /// Explicitly reconcile the original parent after restart, even if the
    /// disk records a prior ledger attempt. No historical receipt is accepted.
    @discardableResult
    func beginResumption(context: ContextTicket, userConfirmed: Bool) -> Bool {
        guard userConfirmed, let resumption, resumption.context == context,
              flight == nil, intent == nil, acceptedParent == nil else { return false }
        return start(Intent(context: context, request: resumption.checkpoint.request, ledgerRequest: nil))
    }

    /// The accepted parent is local history, not new authority. It selects the
    /// original request only; this separate action still obtains fresh reauth.
    @discardableResult
    func beginLedgerCleanup(userConfirmed: Bool) -> Bool {
        membershipDidChange()
        guard userConfirmed, let parent = acceptedParent else { return false }
        let token = publication, original = intent
        guard canBeginLedgerCleanup, publication == token, intent == original, acceptedParent == parent,
              let request = try? Contract.LedgerRequest(expectedUID: parent.request.expectedUID,
                membershipEpoch: parent.request.membershipEpoch, parentRequestID: parent.request.requestID) else { return false }
        return start(Intent(context: parent.context, request: parent.request, ledgerRequest: request))
    }

    /// Reuses only the original UID/epoch request. Every public retry requires a
    /// new confirmation and a new provider action; no previous proof is reused.
    @discardableResult
    func retry(userConfirmed: Bool) -> Bool {
        membershipDidChange()
        guard userConfirmed, canRetry, let intent else { return false }
        return start(intent)
    }

    func cancel() {
        cancelPushRetirement()
        pushOriginal = nil; pushConfirmation = nil; pushReceipt = nil; pushCommitAttempted = false
        if localFlight?.kind == .favorites || localPreparation != nil { cancelLocalFavoritesCleanup() }
        if localFlight?.kind == .resume || localResumePreparation != nil { cancelLocalResumeCleanup() }
        if localFlight?.kind == .podcast || localPodcastPreparation != nil { cancelLocalPodcastCleanup() }
        if localFlight?.kind == .history || localHistoryPreparation != nil { cancelLocalHistoryCleanup() }
        if localFlight?.kind == .introduction || localIntroductionPreparation != nil { cancelLocalIntroductionCleanup() }
        acceptedParent = nil
        acceptedLedgerReceipt = nil
        intent = nil
        activeAction = nil
        flight?.task?.cancel()
        let cancelDeadline = flight?.cancelDeadline
        flight?.cancelDeadline = nil
        cancelDeadline?()
        _ = publish(.cancelled)
    }

    /// The future membership adapter must call this when its epoch changes.
    /// Await boundaries and admission also independently recheck that epoch.
    func membershipDidChange() {
        guard let candidate = intent else { return }
        let token = publication, owned = owns(candidate)
        guard !owned, publication == token, intent == candidate else { return }
        cancel()
    }

    /// The composed transport retains the same original operation; this is a
    /// local cancellation/ownership check, never server authorization.
    func permitsTransport(action: ActionTicket) -> Bool { isActive(action) }

    /// Pure final check after an injected SDK identity getter. Calling the epoch
    /// provider again here could reenter after the last held-user comparison.
    func retainsTransport(action: ActionTicket) -> Bool {
        if action.phase == .pushPreparation || action.phase == .pushRetirement {
            guard let original = pushOriginal else { return false }
            return activeAction == action && flight?.action == action
                && localFlight?.id == pushGeneration && original.request(for: action.phase) == action.pushRequest
                && intent == original.intent && canonical?.isCurrent(action.context) == true
                && localCheckpoint?.isSameFamily(as: original.checkpoint) == true
        }
        return         activeAction == action && flight?.action == action && intent?.context == action.context
            && intent?.request == action.request && intent?.phase == action.phase
            && intent?.ledgerRequest == action.ledgerRequest && canonical?.isCurrent(action.context) == true
    }

    /// Called by the actual Auth sender with its original held SDK identity.
    /// A retry obtains a fresh snapshot/drain; historical receipts grant nothing.
    func prepareWritesForDeletion(action: ActionTicket,
        stillCurrent: @escaping @MainActor () -> Bool,
        originalUserIsCurrent: @escaping @MainActor () -> Bool) async throws {
        if action.phase == .pushPreparation || action.phase == .pushRetirement {
            guard stillCurrent(), originalUserIsCurrent(), retainsTransport(action: action) else { throw CancellationError() }
            try await validatePushStorage(action: action)
            guard stillCurrent(), originalUserIsCurrent(), retainsTransport(action: action) else { throw CancellationError() }
            return
        }
        if let resumption {
            try await prepareResumedDeletion(action: action, resumption: resumption,
                stillCurrent: stillCurrent, originalUserIsCurrent: originalUserIsCurrent)
            return
        }
        guard let barrier = writeBarrier, barrierAttempt == nil,
              let binding = try? ReaderMembershipContract.Binding(ownerUID: action.request.expectedUID,
                                                                  epoch: action.request.membershipEpoch),
              barrier.recovery.canPrepare(binding: binding) else { throw CancellationError() }
        let attempt = UUID()
        barrierAttempt = attempt // Before any injected epoch/identity getter.
        defer { if barrierAttempt == attempt { barrierAttempt = nil } }
        do {
            func admitted() -> Bool {
                guard barrierAttempt == attempt, !Task.isCancelled, isActive(action) else { return false }
                guard stillCurrent(), barrierAttempt == attempt, !Task.isCancelled,
                      retainsTransport(action: action) else { return false }
                return true
            }
            guard admitted(), originalUserIsCurrent(), admitted() else { throw CancellationError() }
            let held: HeldWriteBarrier
            if let existing = heldWriteBarrier {
                guard existing.context == action.context, existing.request == action.request,
                      barrier.writers.ownsTransition(existing.reservation),
                      existing.originalUserIsCurrent(), admitted() else { throw CancellationError() }
                held = existing
            } else {
                guard let reservation = barrier.writers.reserveTransition(context: action.context) else { throw CancellationError() }
                guard let stop = barrier.writers.stopWrites(context: action.context) else {
                    _ = barrier.writers.releaseTransition(owner: reservation, stillIdle: { true })
                    throw CancellationError()
                }
                held = HeldWriteBarrier(action: action, reservation: reservation, stop: stop,
                                        originalUserIsCurrent: originalUserIsCurrent)
                heldWriteBarrier = held
            }
            func check() throws {
                guard heldWriteBarrier === held, barrier.writers.ownsTransition(held.reservation),
                      held.originalUserIsCurrent(), admitted(), heldWriteBarrier === held,
                      barrier.writers.ownsTransition(held.reservation) else { throw CancellationError() }
            }
            try check()
            let snapshot: FavoritesFileJournal.SnapshotLease = try await withCheckedThrowingContinuation { continuation in
                if let ticket = held.sourceTicket {
                    barrier.journal.retryTransitionSnapshot(ticket) { continuation.resume(with: $0) }
                } else {
                    guard let namespace = FavoritesContext.confirmed(userID: held.request.expectedUID).namespace else {
                        continuation.resume(throwing: CancellationError()); return
                    }
                    // Keep even a ticket whose asynchronous snapshot fails. A nil
                    // ticket means no journal gate was acquired, not an SDK reopen.
                    held.sourceTicket = barrier.journal.freezeForTransition(namespace: namespace) {
                        continuation.resume(with: $0)
                    }
                }
            }
            try check()
            guard barrier.journal.isCurrent(snapshot) else { throw CancellationError() }
            let receipt = try await barrier.writers.drain(held.stop)
            try check()
            guard barrier.journal.isCurrent(snapshot), barrier.writers.isCurrent(receipt) else { throw CancellationError() }
            try check()
            guard barrier.recovery.canPrepare(binding: binding) else { throw CancellationError() }
            // Monotonic before the first marker attempt, which can commit even
            // if its caller is cancelled or does not receive a successful return.
            // Neither that unknown outcome nor a later HTTP failure permits abort.
            held.sealed = true
            guard barrier.writers.sealStop(held.stop) else { throw CancellationError() }
            guard barrier.journal.isCurrent(snapshot), barrier.writers.isCurrent(receipt) else { throw CancellationError() }
            try check()
            let marker = try await barrier.recovery.seal(binding: binding)
            // The same recovery admission now refuses new history/capture work.
            // Already accepted resume writes keep their original owner and must
            // finish on the actual store queue before checkpoint/HTTP proceeds.
            // This waits for local write/readback, not fsync or cloud delivery.
            await barrier.resumeStore?.waitForPhysicalIdle()
            try check()
            guard marker.binding == binding, barrier.recovery.hasVerifiedSeal(binding: binding),
                  barrier.journal.isCurrent(snapshot), barrier.writers.isCurrent(receipt) else { throw CancellationError() }
            try check()
            guard let configurationDigest else { throw CancellationError() }
            _ = try await barrier.recovery.recordDeletion(request: action.request,
                phase: action.phase == .cloudSlice ? .parent : .ledger, configurationDigest: configurationDigest)
            try check()
            guard barrier.recovery.hasVerifiedSeal(binding: binding), barrier.journal.isCurrent(snapshot),
                  barrier.writers.isCurrent(receipt) else { throw CancellationError() }
        } catch {
            // seal can commit and then throw for cancellation, or fail after
            // closing admission. Neither outcome releases accepted local I/O.
            if heldWriteBarrier?.sealed == true {
                await barrier.resumeStore?.waitForPhysicalIdle()
            }
            // Snapshot/identity failure may also precede a pre-stop SDK write's
            // callback. Retain the sender flight until every physical write and
            // drain returns, then let finish publish actual retry availability.
            if heldWriteBarrier != nil { try await barrier.writers.waitForPhysicalIdle() }
            throw error
        }
    }

    private func prepareResumedDeletion(action: ActionTicket, resumption: Resumption,
        stillCurrent: @escaping @MainActor () -> Bool,
        originalUserIsCurrent: @escaping @MainActor () -> Bool) async throws {
        guard barrierAttempt == nil, writeBarrier == nil, let configurationDigest else { throw CancellationError() }
        let attempt = UUID(); barrierAttempt = attempt
        defer { if barrierAttempt == attempt { barrierAttempt = nil } }
        func check() throws {
            guard !Task.isCancelled, barrierAttempt == attempt, isActive(action),
                  originalUserIsCurrent(), stillCurrent(), barrierAttempt == attempt,
                  retainsTransport(action: action) else { throw CancellationError() }
        }
        try check()
        let verified = try await resumption.recovery.readResumption()
        try check()
        guard let verified, verified.isSameFamily(as: resumption.checkpoint),
              resumption.recovery.hasVerifiedSeal(binding: resumption.checkpoint.marker.binding) else { throw CancellationError() }
        // Original request/phase persistence, never a fresh journal/SDK client.
        _ = try await resumption.recovery.recordDeletion(request: action.request,
            phase: action.phase == .cloudSlice ? .parent : .ledger, configurationDigest: configurationDigest)
        try check()
        guard resumption.recovery.hasVerifiedSeal(binding: resumption.checkpoint.marker.binding) else { throw CancellationError() }
    }

    /// Explicit rollback only before any possible HTTP submission. Neither
    /// timeout nor cancel invokes this. Logical drain failure is not physical
    /// completion, and cancel may have erased intent, so use the original hold.
    @discardableResult
    func abortBeforeSubmission() -> Bool {
        guard flight == nil, barrierAttempt == nil, let barrier = writeBarrier,
              let held = heldWriteBarrier, !held.sealed,
              !barrier.recovery.hasSealAttempt, barrier.recovery.legacyWritesPermitted,
              canonical?.isCurrent(held.context) == true else { return false }
        let epoch = currentMembershipEpoch?(held.context)
        guard epoch == held.request.membershipEpoch, held.originalUserIsCurrent(),
              heldWriteBarrier === held, barrierAttempt == nil, flight == nil,
              canonical?.isCurrent(held.context) == true else { return false }
        let pure: @MainActor () -> Bool = { [self] in
            heldWriteBarrier === held && !held.sealed && barrierAttempt == nil && flight == nil
                && !barrier.recovery.hasSealAttempt && barrier.recovery.legacyWritesPermitted
                && canonical?.isCurrent(held.context) == true
                && barrier.writers.ownsTransition(held.reservation) && barrier.writers.isPhysicallyIdle
                && (held.sourceTicket.map(barrier.journal.canResumeAfterAbortedTransition) ?? true)
        }
        let admission: @MainActor () -> Bool = { [self] in
            guard pure(), held.originalUserIsCurrent(), pure() else { return false }
            // abortStop invokes this again after its SDK UID getter. Observe
            // an epoch change caused by that hook before reopening either gate.
            let latestEpoch = currentMembershipEpoch?(held.context)
            return latestEpoch == held.request.membershipEpoch && pure()
        }
        guard admission(), barrier.writers.abortStop(held.stop, stillBeforeTransition: admission) else { return false }
        if let ticket = held.sourceTicket {
            guard barrier.journal.resumeAfterAbortedTransition(ticket) else { return false }
        }
        // The source ticket has intentionally been retired by resume above.
        // No external hook runs between paired resume and reservation release.
        guard barrier.writers.releaseTransition(owner: held.reservation, stillIdle: { [self] in
            heldWriteBarrier === held && !held.sealed && barrierAttempt == nil && flight == nil
                && !barrier.recovery.hasSealAttempt && barrier.recovery.legacyWritesPermitted
                && canonical?.isCurrent(held.context) == true && barrier.writers.isPhysicallyIdle
        }) else { return false }
        heldWriteBarrier = nil
        return true
    }

    private var barrierPhysicallyIdle: Bool {
        guard barrierAttempt == nil else { return false }
        guard let held = heldWriteBarrier, let barrier = writeBarrier else { return true }
        return barrier.writers.isPhysicallyIdle
            && (held.sealed && localJournal === barrier.journal ? barrier.journal.isPhysicallyIdle
                : (held.sourceTicket.map(barrier.journal.canResumeAfterAbortedTransition) ?? true))
    }

    private var configured: Bool {
        (currentMembershipEpoch != nil || resumption != nil) && reauthenticate != nil && send != nil
            && timeoutSeconds.isFinite && timeoutSeconds > 0 && timeoutSeconds <= 120
    }

    private func configured(for candidate: Intent) -> Bool {
        configured && (candidate.phase == .cloudSlice || sendLedger != nil)
    }

    private func owns(_ candidate: Intent) -> Bool {
        let parent = acceptedParent
        if let ledger = candidate.ledgerRequest {
            guard let parent, parent.context == candidate.context, parent.request == candidate.request,
                  parent.receipt.status == .scopedCloudDataRemoved,
                  ledger.expectedUID == candidate.request.expectedUID,
                  ledger.membershipEpoch == candidate.request.membershipEpoch,
                  ledger.parentRequestID == candidate.request.requestID else { return false }
        }
        guard let canonical, canonical.isCurrent(candidate.context),
              canonical.snapshot.session?.uid == candidate.request.expectedUID else { return false }
        if let resumption {
            guard resumption.context == candidate.context, candidate.request == resumption.checkpoint.request,
                  configurationDigest == resumption.checkpoint.configurationDigest,
                  resumption.stillClosed(), canonical.isCurrent(candidate.context),
                  let current = resumption.recovery.deletionCheckpoint else { return false }
            // Phase can monotonically advance; the marker, destination and
            // original family cannot change. A disk receipt grants nothing.
            return current.marker == resumption.checkpoint.marker && current.request == candidate.request
                && current.configurationDigest == configurationDigest
                && (candidate.phase == .cloudSlice || acceptedParent == parent)
        }
        let epoch = currentMembershipEpoch?(candidate.context)
        return epoch == candidate.request.membershipEpoch && canonical.isCurrent(candidate.context)
            && canonical.snapshot.session?.uid == candidate.request.expectedUID
            && (candidate.phase == .cloudSlice || acceptedParent == parent)
    }

    private func isActive(_ action: ActionTicket) -> Bool {
        if action.phase == .pushPreparation || action.phase == .pushRetirement {
            guard let original = pushOriginal, retainsTransport(action: action) else { return false }
            return pushFamilyIsCurrent(original.intent, checkpoint: original.checkpoint, generation: pushGeneration)
                && retainsTransport(action: action)
        }
        guard activeAction == action, flight?.action == action, let intent,
              intent.context == action.context, intent.request == action.request,
              intent.phase == action.phase, intent.ledgerRequest == action.ledgerRequest else { return false }
        let owned = owns(intent)
        return owned && activeAction == action && flight?.action == action && self.intent == intent
    }

    private func start(_ candidate: Intent) -> Bool {
        let admission = UUID()
        publication = admission
        guard localFlight == nil, localPreparation == nil, localResumePreparation == nil, localPodcastPreparation == nil, localIntroductionPreparation == nil, localHistoryPreparation == nil, flight == nil, barrierPhysicallyIdle, let reauthenticate, configured(for: candidate) else { return false }
        if let held = heldWriteBarrier {
            guard held.context == candidate.context, held.request == candidate.request else { return false }
        }
        let send = self.send, sendLedger = self.sendLedger
        let initiallyOwned = owns(candidate)
        guard initiallyOwned, publication == admission, flight == nil else { return false }
        let now = nowMilliseconds()
        let stillOwned = owns(candidate)
        guard stillOwned, publication == admission, flight == nil,
              (1...Contract.maximumSafeInteger).contains(now) else { return false }
        let action = ActionTicket(actionID: UUID(), context: candidate.context, request: candidate.request,
                                  phase: candidate.phase, ledgerRequest: candidate.ledgerRequest, startedAtMs: now, coordinatorID: coordinatorID)
        intent = candidate
        activeAction = action
        flight = Flight(action: action)
        guard publish(.reauthenticating), isActive(action) else {
            finish(action, result: .failure(CancellationError()))
            return false
        }
        let cancelDeadline = scheduleTimeout(timeoutSeconds) { [weak self] in self?.expire(action) }
        guard flight?.action == action else { cancelDeadline(); return false }
        flight?.cancelDeadline = cancelDeadline
        guard isActive(action) else {
            finish(action, result: .failure(CancellationError()))
            return false
        }
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isActive(action) == true else {
                self?.finish(action, result: .failure(CancellationError()))
                return
            }
            do {
                let proof = try await reauthenticate(action)
                guard !Task.isCancelled, self?.accepts(proof, for: action) == true else {
                    self?.finish(action, result: .failure(InvalidReauthentication()))
                    return
                }
                guard self?.publish(.submitting) == true, !Task.isCancelled,
                      self?.isActive(action) == true else {
                    self?.finish(action, result: .failure(CancellationError()))
                    return
                }
                let data: Data
                switch action.phase {
                case .cloudSlice:
                    guard let send else { throw CancellationError() }
                    data = try await send(action.request, proof)
                case .mutationLedger:
                    guard let sendLedger, let request = action.ledgerRequest else { throw CancellationError() }
                    data = try await sendLedger(request, proof)
                case .pushPreparation, .pushRetirement: throw CancellationError()
                }
                self?.finish(action, result: .success(data))
            } catch { self?.finish(action, result: .failure(error)) }
        }
        if flight?.action == action { flight?.task = task } else { task.cancel() }
        return isActive(action)
    }

    private struct InvalidReauthentication: Error {}

    private func accepts(_ proof: ReauthenticationResult, for action: ActionTicket) -> Bool {
        guard isActive(action), proof.action == action, proof.authenticatedUID == action.request.expectedUID,
              proof.kind == .reauthenticated else { return false }
        let now = nowMilliseconds()
        // Firebase auth_time is second-grained. Permit that rounding only; an
        // earlier public attempt cannot supply the action ticket for this one.
        let earliest = (action.startedAtMs / 1_000) * 1_000
        return (1...Contract.maximumSafeInteger).contains(now)
            && (1...Contract.maximumSafeInteger).contains(proof.authTimeMs)
            && now >= action.startedAtMs && now - action.startedAtMs < 300_000
            && proof.authTimeMs >= earliest && proof.authTimeMs <= now
            && now - proof.authTimeMs < 300_000 && isActive(action)
    }

    private func expire(_ action: ActionTicket) {
        guard isActive(action) else { membershipDidChange(); return }
        activeAction = nil
        flight?.task?.cancel()
        _ = publish(.timedOut)
    }

    private func finish(_ action: ActionTicket, result: Result<Data, Error>) {
        guard let completed = flight, completed.action == action else { return }
        flight = nil
        completed.cancelDeadline?()
        membershipDidChange()
        let candidate = intent
        let token = publication
        let owned = candidate.map(owns) ?? false
        guard owned, publication == token, activeAction == action, intent == candidate, flight == nil else {
            // Publish slot release for retry availability, retaining the timeout
            // or cancellation instead of delivering this late result.
            _ = publish(status, receipt: acceptedReceipt, ledgerReceipt: acceptedLedgerReceipt)
            return
        }
        activeAction = nil
        guard case .success(let data) = result else {
            _ = publish(.unavailable)
            return
        }
        switch action.phase {
        case .cloudSlice:
            guard let receipt = try? Contract.decodeReceipt(data: data, for: action.request) else {
                _ = publish(.unavailable); return
            }
            let next: Status
            switch receipt.status {
            case .pending: next = .pending
            case .paused: next = .paused
            case .scopedCloudDataRemoved: next = .scopedCloudDataRemoved
            }
            _ = publish(next, receipt: receipt)
        case .mutationLedger:
            guard let request = action.ledgerRequest,
                  let receipt = try? Contract.decodeLedgerReceipt(data: data, for: request) else {
                _ = publish(.unavailable); return
            }
            let next: Status
            switch receipt.status {
            case .pending: next = .pending
            case .paused: next = .paused
            case .ledgerDataRemoved: next = .ledgerDataRemoved
            }
            _ = publish(next, ledgerReceipt: receipt)
        case .pushPreparation, .pushRetirement: break // separate, same physical flight below
        }
    }

    @discardableResult
    private func publish(_ next: Status, receipt: Contract.Receipt? = nil,
                         ledgerReceipt: Contract.LedgerReceipt? = nil) -> Bool {
        let token = UUID(), expectedIntent = intent, expectedAction = activeAction
        publication = token
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard publication == token, intent == expectedIntent, activeAction == expectedAction else { return false }
        let owned = expectedIntent.map(owns) ?? true
        guard publication == token, intent == expectedIntent, activeAction == expectedAction else { return false }
        if !owned { cancel(); return false }
        if let expectedIntent, expectedIntent.phase == .mutationLedger {
            acceptedReceipt = acceptedParent?.receipt
            acceptedLedgerReceipt = ledgerReceipt
        } else {
            acceptedReceipt = receipt
            acceptedLedgerReceipt = nil
            if let receipt, receipt.status == .scopedCloudDataRemoved, let expectedIntent {
                acceptedParent = AcceptedParent(context: expectedIntent.context, request: expectedIntent.request, receipt: receipt)
            } else { acceptedParent = nil }
        }
        presentation = next
        return true
    }

    static func deadline(after seconds: TimeInterval, fire: @escaping @MainActor () -> Void) -> Cancellation {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            fire()
        }
        return { task.cancel() }
    }
}
