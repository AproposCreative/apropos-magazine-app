import Foundation

/// Ownership of the actual player's effects, independent of AVPlayer and system
/// services. The manager uses these same gates for every delayed callback.
@MainActor
final class PodcastPlaybackSessionCoordinator {
    struct ContextTicket: Equatable, Sendable { fileprivate let id: UUID }
    struct Ticket: Equatable, Sendable {
        fileprivate let id: UUID
        fileprivate let progress: PodcastPlaybackProgressStore.Ticket
    }
    struct Session {
        let ticket: Ticket
        let resumePosition: TimeInterval?
    }
    struct PreparationTicket: Equatable, Sendable {
        let asset: PodcastAudioAsset
        fileprivate let id: UUID
        fileprivate let context: ContextTicket
        fileprivate let owner: Ticket?
    }
    private struct PendingPreparation {
        let ticket: PreparationTicket
        let routeIsCurrent: (@MainActor () -> Bool)?
        let accessIsCurrent: @MainActor () -> Bool
    }
    struct SeekTicket: Equatable, Sendable {
        fileprivate let owner: Ticket
        fileprivate let id: UUID
    }
    struct StartTicket: Equatable, Sendable {
        fileprivate let owner: Ticket
        fileprivate let id: UUID
    }
    private struct PendingStart {
        let ticket: StartTicket
        let routeIsCurrent: (@MainActor () -> Bool)?
    }
    struct SleepTicket: Equatable, Sendable {
        fileprivate let context: ContextTicket
        fileprivate let lifetime: UUID
        fileprivate let id: UUID
    }
    struct Effects {
        let cancelCallbacks: @MainActor () -> Void
        let stopPlayback: @MainActor () -> Void
        let clearPresentation: @MainActor () -> Void
        let clearNowPlaying: @MainActor () -> Void
        let deactivateAudio: @MainActor () -> Void
    }
    private struct Interruption {
        let owner: Ticket
        let intent: UUID
        let wantedPlayback: Bool
    }

    private let store: PodcastPlaybackProgressStore
    private let effects: Effects
    private(set) var contextTicket = ContextTicket(id: UUID())
    private(set) var currentTicket: Ticket?
    private var seek: SeekTicket?
    private var start: PendingStart?
    private var preparation: PendingPreparation?
    private var preparationResult: PendingPreparation?
    private var preparationRevision = UUID()
    private var sleep: SleepTicket?
    private var lifetime = UUID()
    private var intent = UUID()
    private var interruption: Interruption?
    private var isAdopting = false
    private var isClosing = false
    private var needsTeardown = false

    init(store: PodcastPlaybackProgressStore, effects: Effects) {
        self.store = store
        self.effects = effects
    }

    /// A saved position is only a suggestion for this newly observed asset.
    /// Unknown/shorter/invalid assets restart safely at zero; no completion or
    /// deletion of the owner's previous record is fabricated from that fact.
    static func safeResumePosition(_ saved: TimeInterval, currentDuration: TimeInterval?) -> TimeInterval {
        let maximum = PodcastProgressRecordCodec.maximumDurationSeconds
        guard saved.isFinite, saved >= 0, saved <= maximum,
              let currentDuration, currentDuration.isFinite,
              currentDuration > 0, currentDuration <= maximum,
              saved < currentDuration else { return 0 }
        return saved
    }

    func beginSession(episodeID: String, articleID: String?, expectedContext: ContextTicket? = nil) -> Session? {
        guard store.hasPlaybackAccess, !isAdopting, !isClosing,
              expectedContext.map({ $0 == contextTicket }) ?? true else { return nil }
        isAdopting = true
        defer { isAdopting = false }
        let origin = contextTicket
        currentTicket = nil
        seek = nil
        start = nil
        recordExplicitAction()
        guard let session = store.beginSession(episodeID: episodeID, articleID: articleID),
              origin == contextTicket, !isClosing, store.isCurrent(session.ticket) else {
            if origin == contextTicket { close() }
            return nil
        }
        let ticket = Ticket(id: UUID(), progress: session.ticket)
        currentTicket = ticket
        needsTeardown = true
        return Session(ticket: ticket, resumePosition: session.resumePosition)
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        !isClosing && currentTicket == ticket && store.isCurrent(ticket.progress)
    }

    @discardableResult
    func perform(ifCurrent ticket: Ticket, _ effect: @MainActor () -> Void) -> Bool {
        guard isCurrent(ticket) else { return false }
        effect()
        return isCurrent(ticket)
    }

    func canPublishProgress(_ ticket: Ticket) -> Bool { isCurrent(ticket) && seek == nil && start == nil }

    @discardableResult
    func save(_ ticket: Ticket, seconds: TimeInterval, duration: TimeInterval) -> Bool {
        guard canPublishProgress(ticket) else { return false }
        _ = store.save(ticket.progress, seconds: seconds, duration: duration)
        return isCurrent(ticket)
    }

    @discardableResult
    func complete(_ ticket: Ticket) -> Bool {
        guard canPublishProgress(ticket) else { return false }
        _ = store.complete(ticket.progress)
        return isCurrent(ticket)
    }

    /// Explicit transport decisions cancel automatic interruption resume. An
    /// unresolved manual seek still blocks progress until its result or a new
    /// owner arrives; cancellation is not proof that its target was reached.
    func recordExplicitAction() {
        invalidatePreparation()
        intent = UUID()
        interruption = nil
    }

    func invalidatePreparation() {
        preparation = nil
        preparationResult = nil
        preparationRevision = UUID()
    }

    /// Local disk verification is asynchronous, but it does not adopt a player
    /// session. Original context, transport intent, asset and favorite access
    /// must all survive before its completion may start a new item.
    func beginPreparation(asset: PodcastAudioAsset, routeIsCurrent: (@MainActor () -> Bool)? = nil,
                          accessIsCurrent: @escaping @MainActor () -> Bool) -> PreparationTicket? {
        guard store.hasPlaybackAccess, !isClosing, !isAdopting else { return nil }
        recordExplicitAction()
        let revision = preparationRevision
        let context = contextTicket
        let owner = currentTicket
        guard store.hasPlaybackAccess, routeIsCurrent?() ?? true, store.hasPlaybackAccess, accessIsCurrent(), store.hasPlaybackAccess,
              !isClosing, !isAdopting, revision == preparationRevision, context == contextTicket, owner == currentTicket,
              owner.map(isCurrent) ?? true else { return nil }
        let ticket = PreparationTicket(asset: asset, id: UUID(), context: context, owner: owner)
        preparation = PendingPreparation(ticket: ticket, routeIsCurrent: routeIsCurrent, accessIsCurrent: accessIsCurrent)
        return ticket
    }

    func isCurrent(_ ticket: PreparationTicket) -> Bool {
        guard store.hasPlaybackAccess, !isClosing, !isAdopting, let pending = preparation, pending.ticket == ticket, ticket.context == contextTicket,
              ticket.owner == currentTicket, ticket.owner.map(isCurrent) ?? store.hasPlaybackAccess,
              pending.routeIsCurrent?() ?? true, store.hasPlaybackAccess, pending.accessIsCurrent() else { return false }
        return store.hasPlaybackAccess && !isClosing && !isAdopting && preparation?.ticket == ticket && ticket.context == contextTicket && ticket.owner == currentTicket
            && (ticket.owner.map(isCurrent) ?? store.hasPlaybackAccess)
    }

    /// The actual manager uses this boundary before beginning cache work and
    /// after its physical reply. Cancellation cannot endorse an old result.
    func prepare(_ ticket: PreparationTicket, using work: @MainActor () async -> Bool) async -> Bool? {
        guard !Task.isCancelled, isCurrent(ticket), !Task.isCancelled else { return nil }
        let prepared = await work()
        guard !Task.isCancelled, isCurrent(ticket), !Task.isCancelled else { return nil }
        return prepared
    }

    /// Original-bound publication checks before and after synchronous observers.
    /// Any closed presentation is cleared only while all playback access remains
    /// closed, never on replacement by a new owner. The manager's modal/error
    /// properties currently publish from didSet, after their values are assigned.
    @discardableResult
    func performPreparationPublication(_ ticket: PreparationTicket, isResult: Bool = false,
        publish: @MainActor () -> Void, clearClosedPresentation: @MainActor () -> Void) -> Bool {
        func admitted() -> Bool { isResult ? isCurrentPreparationResult(ticket) : isCurrent(ticket) }
        guard admitted() else { return false }
        publish()
        guard admitted() else {
            if !store.hasPlaybackAccess { clearClosedPresentation() }
            return false
        }
        return true
    }

    @discardableResult
    func discardPreparation(_ ticket: PreparationTicket) -> Bool {
        guard preparation?.ticket == ticket else { return false }
        invalidatePreparation()
        return true
    }

    func consumePreparation(_ ticket: PreparationTicket) -> Bool {
        guard isCurrent(ticket), let pending = preparation else { return false }
        preparation = nil
        preparationResult = pending
        preparationRevision = UUID()
        return isCurrentPreparationResult(ticket)
    }

    /// A consumed failure result retains its original authority only until a
    /// new explicit transport/request/context supersedes it. UI publications
    /// must recheck this fence before assigning an error or pausing the player.
    func isCurrentPreparationResult(_ ticket: PreparationTicket) -> Bool {
        guard store.hasPlaybackAccess, !isClosing, !isAdopting, let result = preparationResult, result.ticket == ticket,
              ticket.context == contextTicket, ticket.owner == currentTicket,
              ticket.owner.map(isCurrent) ?? store.hasPlaybackAccess,
              result.routeIsCurrent?() ?? true, store.hasPlaybackAccess, result.accessIsCurrent() else { return false }
        return store.hasPlaybackAccess && !isClosing && !isAdopting && preparationResult?.ticket == ticket
            && ticket.context == contextTicket && ticket.owner == currentTicket
            && (ticket.owner.map(isCurrent) ?? store.hasPlaybackAccess)
    }

    /// A route or saved resume is a pending physical positioning operation.
    /// Neither periodic progress nor an old end callback can endorse its target.
    func beginPositioning(_ owner: Ticket, routeIsCurrent: (@MainActor () -> Bool)? = nil) -> StartTicket? {
        let previous = start?.ticket
        guard isCurrent(owner), routeIsCurrent?() ?? true, isCurrent(owner), start?.ticket == previous else { return nil }
        let ticket = StartTicket(owner: owner, id: UUID())
        start = PendingStart(ticket: ticket, routeIsCurrent: routeIsCurrent)
        return ticket
    }

    func isCurrent(_ ticket: StartTicket) -> Bool {
        guard start?.ticket == ticket, isCurrent(ticket.owner),
              start?.routeIsCurrent?() ?? true else { return false }
        return start?.ticket == ticket && isCurrent(ticket.owner)
    }

    func finishPositioning(_ ticket: StartTicket, observedPosition: TimeInterval) -> Bool {
        guard observedPosition.isFinite, observedPosition >= 0,
              observedPosition <= PodcastProgressRecordCodec.maximumDurationSeconds, isCurrent(ticket) else { return false }
        start = nil
        return isCurrent(ticket.owner)
    }

    /// Only unresolved incoming positioning is cancelled. Already-positioned
    /// playback and ordinary saved-position resume keep their lifetime.
    @discardableResult
    func cancelIncomingPositioning() -> Bool {
        let hasIncomingPreparation = preparation?.routeIsCurrent != nil
        if hasIncomingPreparation { invalidatePreparation() }
        guard start?.routeIsCurrent != nil else { return hasIncomingPreparation }
        close()
        return true
    }

    func beginManualSeek(_ ticket: Ticket) -> SeekTicket? {
        guard isCurrent(ticket) else { return nil }
        recordExplicitAction()
        let request = SeekTicket(owner: ticket, id: UUID())
        seek = request
        return request
    }

    func finishManualSeek(_ request: SeekTicket, observedPosition: TimeInterval?) -> Bool {
        guard isCurrent(request.owner), seek == request,
              let observedPosition, observedPosition.isFinite, observedPosition >= 0,
              observedPosition <= PodcastProgressRecordCodec.maximumDurationSeconds else { return false }
        seek = nil
        return true
    }

    func beginInterruption(_ ticket: Ticket, wantedPlayback: Bool) {
        guard isCurrent(ticket) else { return }
        if let interruption, interruption.owner == ticket, interruption.intent == intent { return }
        interruption = Interruption(owner: ticket, intent: intent, wantedPlayback: wantedPlayback)
    }

    func endInterruption(_ ticket: Ticket, shouldResume: Bool) -> Bool {
        guard isCurrent(ticket), let original = interruption, original.owner == ticket else { return false }
        interruption = nil
        return shouldResume && original.intent == intent && original.wantedPlayback
    }

    func invalidateSleepTimer() { sleep = nil }

    func beginSleepTimer() -> SleepTicket? {
        sleep = nil
        guard let currentTicket, isCurrent(currentTicket) else { return nil }
        let ticket = SleepTicket(context: contextTicket, lifetime: lifetime, id: UUID())
        sleep = ticket
        return ticket
    }

    func consumeSleepTimer(_ ticket: SleepTicket) -> Bool {
        guard let currentTicket, isCurrent(currentTicket), sleep == ticket,
              ticket.context == contextTicket, ticket.lifetime == lifetime else { return false }
        sleep = nil
        return true
    }

    /// Roll back a rejected adoption without affecting a newer session that
    /// may have been installed by a synchronous publication/effect callback.
    @discardableResult
    func abort(_ ticket: Ticket) -> Bool {
        guard isCurrent(ticket) else { return false }
        close()
        return true
    }

    func contextInvalidated() {
        contextTicket = ContextTicket(id: UUID())
        close()
    }

    /// No progress save or download is part of teardown. Reentrant adoption is
    /// denied until every old system resource has been detached and cleared.
    func close() {
        let hadPreparation = preparation != nil || preparationResult != nil
        let old = currentTicket
        currentTicket = nil
        recordExplicitAction()
        seek = nil
        start = nil
        sleep = nil
        lifetime = UUID()
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        if let old { store.endSession(old.progress) }
        let hadPlayback = needsTeardown
        guard hadPlayback || hadPreparation else { return }
        needsTeardown = false
        effects.cancelCallbacks()
        // An ownerless preparation still owns its task and visible loading
        // state, but has no audio/Now Playing session to deactivate.
        guard hadPlayback else { effects.clearPresentation(); return }
        effects.stopPlayback()
        effects.clearPresentation()
        effects.clearNowPlaying()
        effects.deactivateAudio()
    }
}
