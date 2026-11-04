import Combine
import Foundation

/// Publication state is global editorial state, independent of the reader account.
/// Persistence and observation are injected: this model never starts an SDK.
@MainActor
final class ArticleAvailabilityModel: ObservableObject {
    struct Update {
        let withdrawn: Bool
        let isFromCache: Bool
        var revision: String? = nil
    }
    struct Snapshot: Codable, Equatable {
        var withdrawnIDs: Set<String> = []
        var invalidatedIDs: Set<String> = []
        var approvedRevisions: [String: String] = [:]
    }
    struct ReadTicket { fileprivate let revisions: [String: Int] }
    struct Change {
        let withdrawnIDs: Set<String>
        let invalidatedBodyIDs: Set<String>
        let refreshFeed: Bool
    }
    struct ObservationTicket: Equatable {
        let articleID: String
        fileprivate let modelID: UUID
        fileprivate let token: UUID
    }
    typealias CurrentGuard = @MainActor () -> Bool
    typealias GuardedSubscribe = (String, @escaping CurrentGuard, @escaping (Result<Update, Error>) -> Void) -> (() -> Void)
    typealias Subscribe = (String, @escaping (Result<Update, Error>) -> Void) -> (() -> Void)
    typealias Schedule = (@escaping () -> Void) -> (() -> Void)

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var withdrawnIDs: Set<String> { state.withdrawnIDs }
    private(set) var projectionRevision = UUID()
    var checkingID: String? { active?.checking == true ? active?.ticket.articleID : nil }
    var errorMessage: String? { active?.failureMessage }
    private let modelID = UUID()
    private final class Observation {
        let ticket: ObservationTicket
        let permission: CurrentGuard
        var revoked = false
        var checking = true
        var failureMessage: String?
        var receivedServerUpdate = false
        var cancel: (() -> Void)?
        var deadline: (() -> Void)?
        init(ticket: ObservationTicket, permission: @escaping CurrentGuard) {
            self.ticket = ticket; self.permission = permission
        }
        func retire() {
            let oldCancel = cancel, oldDeadline = deadline
            cancel = nil; deadline = nil
            oldCancel?(); oldDeadline?()
        }
    }
    private let save: (Snapshot) -> Void
    private let changesSubject = PassthroughSubject<Change, Never>()
    var changes: AnyPublisher<Change, Never> { changesSubject.eraseToAnyPublisher() }
    private var state: Snapshot
    private let schedule: Schedule
    private var trackedPublicationIDs: Set<String> = []
    // Only full source reads accepted in this process can refresh saved
    // metadata. A persisted revision or a cache-only observation is not this
    // authority. No field is added to the durable editorial snapshot.
    private var freshPublicationReads: [String: String] = [:]
    private var revisions: [String: Int] = [:]
    private var active: Observation?
    private var entryRevision = UUID()
    private var batching = false
    private var pendingInvalidations = Set<String>()
    private var pendingRefresh = false
    private var pendingSave = false

    init(snapshot: Snapshot = .init(), save: @escaping (Snapshot) -> Void = { _ in },
         schedule: Schedule? = nil) {
        self.state = snapshot
        self.state.invalidatedIDs.formUnion(snapshot.withdrawnIDs)
        self.save = save
        self.schedule = schedule ?? { fire in
            let task = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                fire()
            }
            return { task.cancel() }
        }
    }

    deinit { active?.cancel?(); active?.deadline?() }

    func trackPublicationIDs(_ ids: Set<String>) {
        let safe = ids.filter(CMSMirrorDocumentPolicy.isSafeDocumentID)
        trackedPublicationIDs.formUnion(safe)
        // The public feed may complete before the private favorite journal.
        // Promote only a full read already witnessed in this process. Cached
        // approval and metadata observations never populate this receipt.
        batch {
            for id in safe {
                guard let revision = freshPublicationReads[id],
                      !state.withdrawnIDs.contains(id), state.approvedRevisions[id] != revision else { continue }
                revisions[id, default: 0] += 1
                setWithdrawn(false, id: id, approvedRevision: revision)
                freshPublicationReads[id] = revision
            }
        }
    }

    func wasInvalidated(_ id: String) -> Bool { state.invalidatedIDs.contains(id) }

    func approvedRevision(for id: String) -> String? { state.approvedRevisions[id] }

    func hasFreshPublicationRead(_ article: Article) -> Bool {
        guard let revision = article.bodyRevision, freshPublicationReads[article.id] == revision else { return false }
        return state.approvedRevisions[article.id] == revision && permitsBody(article)
    }

    func permitsBody(_ article: Article) -> Bool {
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(article.id), article.isPubliclyPublished, !state.withdrawnIDs.contains(article.id) else { return false }
        if let approved = state.approvedRevisions[article.id] { return approved == article.bodyRevision }
        return !state.invalidatedIDs.contains(article.id)
    }

    func sanitized(_ article: Article) -> Article? {
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(article.id), !state.withdrawnIDs.contains(article.id), article.isPubliclyPublished else { return nil }
        guard !permitsBody(article) else { return article }
        // Preserve bookmark identity, but do not show the obsolete headline,
        // excerpt, author, image or embeds while a new revision is unverified.
        return Article(id: article.id, name: "Artiklen er opdateret", slug: article.slug ?? article.id,
                       content: "", intro: "", topicID: "", isDraft: false,
                       createdOn: article.createdOn, lastPublished: article.lastPublished,
                       lastUpdated: article.lastUpdated, contentRevision: article.contentRevision,
                       isPremium: article.isPremium, contentLanguage: article.contentLanguage,
                       sourceArticleID: article.sourceArticleID, cmsLocaleId: article.cmsLocaleId)
    }

    func beginRead() -> ReadTicket { ReadTicket(revisions: revisions) }

    /// Query/point reads can block, but cannot restore a known withdrawn article.
    /// A later authoritative observer update invalidates older read tickets.
    func recordWithdrawals(_ ids: Set<String>, ticket: ReadTicket) {
        batch {
            for id in ids where (revisions[id] ?? 0) == (ticket.revisions[id] ?? 0) {
                revisions[id, default: 0] += 1
                setWithdrawn(true, id: id)
                if let observation = active, checkingID == id {
                    finishChecking(observation, error: nil)
                }
            }
        }
    }

    /// A fresh full catalog can update tracked revisions while the reader is
    /// closed. Unvisited public IDs do not become an extra local reading ledger.
    func recordPublications(_ articles: [Article], ticket: ReadTicket) {
        batch {
            for article in articles where article.isPubliclyPublished {
                let id = article.id
                guard (revisions[id] ?? 0) == (ticket.revisions[id] ?? 0),
                      let revision = article.bodyRevision, !revision.isEmpty else { continue }
                guard state.invalidatedIDs.contains(id) || state.approvedRevisions[id] != nil || active?.ticket.articleID == id || trackedPublicationIDs.contains(id) else {
                    // Keep only ephemeral full-source proof until a real saved
                    // membership is loaded. Fence overlapping older reads even
                    // though no durable availability entry is created here.
                    if freshPublicationReads[id] != revision { revisions[id, default: 0] += 1 }
                    freshPublicationReads[id] = revision
                    continue
                }
                if let observation = active, checkingID == id {
                    finishChecking(observation, error: nil)
                }
                guard (revisions[id] ?? 0) == (ticket.revisions[id] ?? 0) else { continue }
                if !state.withdrawnIDs.contains(id), state.approvedRevisions[id] == revision {
                    freshPublicationReads[id] = revision
                    continue
                }
                revisions[id, default: 0] += 1
                setWithdrawn(false, id: id, approvedRevision: revision)
                freshPublicationReads[id] = revision
            }
        }
    }

    /// Legacy local model users keep their two-argument transport. Real SDK
    /// paths use the explicit original permission below.
    @discardableResult
    func observe(id: String, subscribe: Subscribe) -> ObservationTicket {
        observe(id: id, stillCurrent: { true }) { id, _, completion in subscribe(id, completion) }
    }

    @discardableResult
    func observe(id: String, stillCurrent: @escaping CurrentGuard, subscribe: GuardedSubscribe) -> ObservationTicket {
        let ticket = ObservationTicket(articleID: id, modelID: modelID, token: UUID())
        let entry = UUID()
        entryRevision = entry
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(id), stillCurrent(), entryRevision == entry else { return ticket }
        let previous = active
        let observation = Observation(ticket: ticket, permission: stillCurrent)
        active = observation // Revoke old authority before any cancellation hook.
        previous?.retire()
        guard owns(observation) else { stop(observation: ticket); return ticket }
        objectWillChange.send()
        guard owns(observation) else { stop(observation: ticket); return ticket }
        let original: CurrentGuard = { [weak self, weak observation] in
            guard let self, let observation else { return false }
            return self.owns(observation)
        }
        let cancel = subscribe(id, original) { [weak self, weak observation] result in
            guard let self, let observation else { return }
            self.receive(result, observation: observation)
        }
        guard owns(observation) else { cancel(); stop(observation: ticket); return ticket }
        observation.cancel = cancel
        guard observation.checking else { return ticket }
        let deadline = schedule { [weak self, weak observation] in
            guard let self, let observation else { return }
            guard self.owns(observation) else { self.stop(observation: observation.ticket); return }
            guard observation.checking else { return }
            self.finishChecking(observation, error: "Status kunne ikke bekræftes. Prøv igen, når du er online.")
        }
        guard owns(observation) else { deadline(); stop(observation: ticket); return ticket }
        guard observation.checking else { deadline(); return ticket }
        observation.deadline = deadline
        return ticket
    }

    func isCurrent(_ ticket: ObservationTicket) -> Bool {
        guard ticket.modelID == modelID, let observation = active, observation.ticket == ticket else { return false }
        return owns(observation)
    }

    private func owns(_ observation: Observation) -> Bool {
        guard active === observation, !observation.revoked else { return false }
        let permitted = observation.permission() // An injected/provider getter may reenter.
        if !permitted { observation.revoked = true }
        return permitted && !observation.revoked && active === observation
    }

    func stop(observation ticket: ObservationTicket) {
        guard ticket.modelID == modelID, let previous = active, previous.ticket == ticket else { return }
        entryRevision = UUID()
        active = nil
        previous.retire()
        objectWillChange.send() // Computed state always reflects any nested replacement.
    }

    func stop(id: String? = nil) {
        guard let observation = active, id == nil || observation.ticket.articleID == id else { return }
        stop(observation: observation.ticket)
    }

    private func finishChecking(_ observation: Observation, error: String?) {
        guard owns(observation) else { return }
        let deadline = observation.deadline
        observation.deadline = nil
        observation.checking = false
        observation.failureMessage = error
        deadline?()
        guard owns(observation) else { return }
        objectWillChange.send()
    }

    private func receive(_ result: Result<Update, Error>, observation: Observation) {
        guard owns(observation) else { stop(observation: observation.ticket); return }
        let id = observation.ticket.articleID
        switch result {
        case .failure:
            finishChecking(observation, error: "Status kunne ikke bekræftes. Prøv igen, når du er online.")
        case .success(let update):
            if update.isFromCache {
                guard !observation.receivedServerUpdate else { return }
                if update.withdrawn {
                    revisions[id, default: 0] += 1
                    setWithdrawn(true, id: id)
                }
                return // Cached public data must never clear a known withdrawal.
            }
            observation.receivedServerUpdate = true
            var approvedRevision: String?
            if !update.withdrawn {
                guard let revision = update.revision, !revision.isEmpty else {
                    finishChecking(observation, error: "Status kunne ikke bekræftes. Prøv igen, når du er online.")
                    return
                }
                approvedRevision = revision
            }
            revisions[id, default: 0] += 1
            setWithdrawn(update.withdrawn, id: id, approvedRevision: approvedRevision, refreshFeed: true)
            // The editorial commit is global. A change subscriber may already
            // have replaced the observer; its new checking/error must survive.
            finishChecking(observation, error: nil)
        }
    }

    private func batch(_ update: () -> Void) {
        batching = true
        update()
        batching = false
        guard pendingSave else { return }
        let change = Change(withdrawnIDs: state.withdrawnIDs, invalidatedBodyIDs: pendingInvalidations, refreshFeed: pendingRefresh)
        pendingInvalidations = []
        pendingRefresh = false
        pendingSave = false
        changesSubject.send(change)
        objectWillChange.send()
        save(state)
    }

    private func setWithdrawn(_ withdrawn: Bool, id: String, approvedRevision: String? = nil, refreshFeed: Bool = false) {
        let wasWithdrawn = state.withdrawnIDs.contains(id)
        let wasInvalidated = state.invalidatedIDs.contains(id)
        let previousRevision = state.approvedRevisions[id]
        if withdrawn {
            state.invalidatedIDs.insert(id)
            state.approvedRevisions.removeValue(forKey: id)
            state.withdrawnIDs.insert(id)
        } else {
            state.withdrawnIDs.remove(id)
            if let approvedRevision { state.approvedRevisions[id] = approvedRevision }
        }
        let nextRevision = state.approvedRevisions[id]
        if withdrawn || freshPublicationReads[id] != nextRevision {
            freshPublicationReads.removeValue(forKey: id)
        }
        guard wasWithdrawn != withdrawn || wasInvalidated != state.invalidatedIDs.contains(id) || previousRevision != nextRevision else { return }
        projectionRevision = UUID()
        let invalidations: Set<String> = withdrawn || previousRevision != nextRevision ? [id] : []
        let refresh = refreshFeed && !withdrawn && (wasWithdrawn || (previousRevision != nil && previousRevision != nextRevision))
        if batching {
            pendingInvalidations.formUnion(invalidations)
            pendingRefresh = pendingRefresh || refresh
            pendingSave = true
        } else {
            // Fence old work before publishing the UI projection. No full-state
            // before/after copies are held while updating a large catalog batch.
            changesSubject.send(Change(withdrawnIDs: state.withdrawnIDs, invalidatedBodyIDs: invalidations, refreshFeed: refresh))
            objectWillChange.send()
            save(state)
        }
    }
}
