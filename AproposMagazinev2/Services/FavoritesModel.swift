import Combine
import Foundation

/// Visible membership and durable intent authority. Storage registers immutable
/// work synchronously; its codec and I/O execute outside this actor.
@MainActor
final class FavoritesModel: ObservableObject {
    typealias Guard = @MainActor () -> Bool
    struct Storage {
        let read: @MainActor (FavoritesNamespace, @escaping @MainActor (Result<FavoritesRecord?, Error>) -> Void) -> Void
        let write: @MainActor (FavoritesNamespace, FavoritesRecord, UUID?, @escaping @MainActor (Result<Void, Error>) -> Void) -> Void
        init(read: @escaping @MainActor (FavoritesNamespace, @escaping @MainActor (Result<FavoritesRecord?, Error>) -> Void) -> Void,
             write: @escaping @MainActor (FavoritesNamespace, FavoritesRecord, UUID?, @escaping @MainActor (Result<Void, Error>) -> Void) -> Void) {
            self.read = read; self.write = write
        }
        /// Hermetic memory-fixture adapter. Production uses FavoritesFileJournal.
        /// This still enters the identical typed admission/receipt engine.
        init(read: @escaping @MainActor (FavoritesNamespace) throws -> Data?,
             write: @escaping @MainActor (FavoritesNamespace, Data) throws -> Void) {
            self.read = { namespace, complete in
                complete(Result { try read(namespace).map { try FavoritesRecordCodec.decode($0, namespace: namespace) } })
            }
            self.write = { namespace, record, _, complete in
                complete(Result { try write(namespace, FavoritesRecordCodec.encode(record, namespace: namespace)) })
            }
        }
    }
    struct Mutation: Equatable {
        let id: UUID
        let namespace: FavoritesNamespace
        let article: Article
        let enabled: Bool
        let generation: UUID
        var articleID: String { article.id }
        fileprivate let modelID: UUID
    }
    struct DispatchTicket: Equatable {
        let mutation: Mutation
        let attemptID: UUID
        fileprivate let modelID: UUID
    }
    struct RecoveryTicket: Equatable {
        let namespace: FavoritesNamespace
        let generation: UUID
        fileprivate let modelID: UUID
        fileprivate let recoveryID: UUID
    }
    struct MembershipTicket: Equatable {
        let namespace: FavoritesNamespace
        let generation: UUID
        let articleID: String
        let contentRevision: String?
        let article: Article
        fileprivate let modelID: UUID
        fileprivate let membershipID: UUID

        /// Status refresh ownership follows membership and body revision. Pure
        /// title/metadata enrichment must not restart filesystem validation.
        func identifiesSameMembership(as other: Self) -> Bool {
            modelID == other.modelID && membershipID == other.membershipID &&
            generation == other.generation && namespace == other.namespace &&
            articleID == other.articleID && contentRevision == other.contentRevision
        }
    }
    struct ObservationTicket: Equatable {
        fileprivate let observationID: UUID
        fileprivate let modelID: UUID
        fileprivate let generation: UUID
        fileprivate let namespace: FavoritesNamespace
    }
    struct RemoteSnapshot {
        let articles: [Article]
        let isFromCache: Bool
        let hasPendingWrites: Bool
    }
    enum Receipt { case acknowledged, failed }
    private enum Recovery { case required, running, ready, failed }
    private struct Intent {
        let mutation: Mutation
        var article: Article
        var phase: FavoritesRecord.Phase
        var attemptID: UUID?
        var serverMatched = false
        var retiring = false
        var available = true
        var record: FavoritesRecord.Pending {
            .init(intentID: mutation.id, payload: .init(mutation.article), article: .init(article),
                  enabled: mutation.enabled, phase: phase, attemptID: attemptID)
        }
    }
    private struct Job {
        let sequence: UInt64
        let generation: UUID
        let namespace: FavoritesNamespace
        let record: FavoritesRecord?
        let retirements: [String: UUID]
        var expectedRevision: UUID?
    }
    private struct RetryCandidate {
        let record: FavoritesRecord
        let expectedRevision: UUID?
        let retirements: [String: UUID]
        let sequence: UInt64
    }
    private struct Waiter { let sequence: UInt64; let continuation: CheckedContinuation<Bool, Never> }

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var context = FavoritesContext.unresolved
    private(set) var snapshot: FavoritesSnapshot
    /// The local collection must be loaded before a visible selection can change.
    /// This is not server authority, sync confirmation or offline availability.
    var canChangeSelection: Bool { loaded && !transitioning && context.namespace != nil }
    var changes: AnyPublisher<FavoritesSnapshot, Never> { changeSubject.eraseToAnyPublisher() }
    var recoveryIsRequired: Bool { loaded && !transitioning && recovery == .required && context.namespace != .guest }
    var pendingMutations: [Mutation] { intents.values.map(\.mutation).sorted { $0.articleID < $1.articleID } }
    var dispatchableMutations: [Mutation] {
        guard loaded, !transitioning, recovery == .ready else { return [] }
        return intents.values.filter { $0.phase == .queued && admitted($0) }.map(\.mutation).sorted { $0.articleID < $1.articleID }
    }

    private let storage: Storage
    private let now: @MainActor () -> Date
    private let sanitize: @MainActor (Article) -> Article?
    private let modelID = UUID()
    private let changeSubject = PassthroughSubject<FavoritesSnapshot, Never>()
    private var generation = UUID()
    private var revision: UInt64 = 0
    private var operation = UUID()
    private var base: [Article] = []
    private var visible: [Article] = []
    private var intents: [String: Intent] = [:]
    private var guestMutation: Mutation?
    private var membershipIDs: [String: UUID] = [:]
    private var storageState = FavoritesStorageState.unresolved
    private var recovery = Recovery.required
    private var recoveryID = UUID()
    private var requiresRecovery = false
    private var serverConfirmed = false
    private var observationError = false
    private var currentObservationID: UUID?
    private var loaded = false
    private var dirty = false
    private var transitioning = false
    private var notifying = false
    private var uncertainWrite: RetryCandidate?
    private var durableRecord: FavoritesRecord?
    private var durableSequence: UInt64 = 0
    private var lastIssuedRevision: UUID?
    private var sequence: UInt64 = 0
    private var jobs: [UUID: Job] = [:]
    private var waiters: [UUID: Waiter] = [:]
    private static let maximumWaiters = 256

    init(storage: Storage, now: @escaping @MainActor () -> Date = { Date() },
         sanitize: @escaping @MainActor (Article) -> Article? = { $0 }) {
        self.storage = storage; self.sanitize = sanitize; self.now = now
        snapshot = FavoritesSnapshot(generation: generation, revision: 0, articles: [], pendingArticleIDs: [], serverConfirmed: false, state: .unresolved)
    }

    func changeContext(to proposed: FavoritesContext) {
        let desired: FavoritesContext = proposed.namespace == nil ? .unresolved : proposed
        guard context != desired else { return }
        let token = beginOperation()
        generation = UUID(); recoveryID = UUID(); context = desired
        base = []; visible = []; intents = [:]; membershipIDs = [:]; guestMutation = nil
        serverConfirmed = false; observationError = false; currentObservationID = nil
        dirty = false; loaded = false; uncertainWrite = nil; durableRecord = nil; lastIssuedRevision = nil; durableSequence = 0
        requiresRecovery = false; recovery = desired == .guest ? .ready : .required
        transitioning = desired.namespace != nil; storageState = transitioning ? .loading : .unresolved
        guard publish(token), desired.namespace != nil else { return }
        load(token)
    }

    func setFavorite(_ article: Article, enabled: Bool) -> Mutation? {
        guard loaded, !transitioning, let namespace = context.namespace,
              visible.contains(where: { $0.id == article.id }) != enabled else { return nil }
        let token = beginOperation()
        let light: Article
        if enabled {
            guard let value = accepted(article, token: token) else { return nil }
            let savedAt = now().timeIntervalSince1970
            guard operation == token, FavoriteArticlesLogic.validSavedAt(savedAt) else { return nil }
            light = value.withFavoriteSavedAt(savedAt)
        } else {
            guard let value = visible.first(where: { $0.id == article.id }) else { return nil }; light = value
        }
        if namespace != .guest, intents[light.id] == nil, intents.count >= FavoritesRecordCodec.maximumPending {
            storageState = .limitExceeded; _ = publish(token); return nil
        }
        var candidate = visible.filter { $0.id != light.id }; if enabled { candidate.append(light) }
        guard validateCandidate(candidate, token: token) else { return nil }
        let mutation = Mutation(id: UUID(), namespace: namespace, article: light, enabled: enabled, generation: generation, modelID: modelID)
        if namespace == .guest { base = candidate; guestMutation = mutation }
        else { intents[light.id] = Intent(mutation: mutation, article: light, phase: .queued) }
        adopt(candidate); dirty = true
        // Enqueue before publication: a synchronous observer may change owner.
        persist(token)
        return operation == token && isCurrent(mutation) ? mutation : nil
    }

    func isCurrent(_ mutation: Mutation) -> Bool {
        guard mutation.modelID == modelID, mutation.generation == generation,
              mutation.namespace == context.namespace, !transitioning else { return false }
        if mutation.namespace == .guest { return guestMutation?.id == mutation.id }
        return intents[mutation.articleID]?.mutation.id == mutation.id
    }
    func isCurrent(_ ticket: DispatchTicket) -> Bool {
        ticket.modelID == modelID && isCurrent(ticket.mutation)
            && intents[ticket.mutation.articleID]?.phase == .started
            && intents[ticket.mutation.articleID]?.attemptID == ticket.attemptID && recovery == .ready
    }

    func beginDispatch(_ mutation: Mutation, stillCurrent: @escaping Guard = { true }) async -> DispatchTicket? {
        guard stillCurrent(), isCurrent(mutation), mutation.namespace != .guest, recovery == .ready else { return nil }
        guard await waitForStorage(), stillCurrent(), isCurrent(mutation), recovery == .ready,
              var intent = intents[mutation.articleID], intent.phase == .queued, admitted(intent) else { return nil }
        let attemptID = UUID(); intent.phase = .started; intent.attemptID = attemptID
        intents[mutation.articleID] = intent; requiresRecovery = true; dirty = true
        let ticket = DispatchTicket(mutation: mutation, attemptID: attemptID, modelID: modelID)
        let token = beginOperation(); persist(token, publicationPermission: stillCurrent)
        guard await waitForStorage(), isCurrent(ticket),
              let current = intents[mutation.articleID], admitted(current) else { return nil }
        guard stillCurrent(), isCurrent(ticket) else {
            // A durable started record must not strand a provider attempt that
            // was never sent. Keep its original payload and await local cleanup.
            if isCurrent(ticket) { _ = await finishDispatch(ticket, result: .failed, stillCurrent: { false }) }
            return nil
        }
        return ticket
    }

    @discardableResult
    func finishDispatch(_ ticket: DispatchTicket, result: Receipt,
                        stillCurrent: @escaping Guard = { true }) async -> Bool {
        let permitted = stillCurrent()
        guard isCurrent(ticket), var intent = intents[ticket.mutation.articleID] else { return false }
        let acknowledge = result == .acknowledged && permitted
        intent.phase = acknowledge ? .acknowledged : .failed
        intents[ticket.mutation.articleID] = intent; dirty = true
        // Once registered, an ACK disk write is a historical receipt. A later
        // denial cannot retract that physical write, but cannot grant success
        // or start retirement after its completion either.
        let token = beginOperation()
        persist(token, publicationPermission: acknowledge ? stillCurrent : { true })
        guard await waitForStorage(), stillCurrent(), isCurrent(ticket.mutation),
              let current = intents[ticket.mutation.articleID], current.attemptID == ticket.attemptID,
              admitted(current) else { return false }
        if current.phase == .acknowledged && current.serverMatched {
            retireAcknowledged(token: beginOperation(), stillCurrent: stillCurrent)
            guard await waitForStorage(), stillCurrent() else { return false }
            return ticket.mutation.generation == generation && ticket.mutation.namespace == context.namespace
        }
        return true
    }

    func retryMutation(articleID: String) -> Mutation? {
        guard loaded, !transitioning, let old = intents[articleID], [.failed, .blocked].contains(old.phase) else { return nil }
        let token = beginOperation()
        guard let light = accepted(old.article, token: token) else { return nil }
        let mutation = Mutation(id: UUID(), namespace: old.mutation.namespace, article: light,
                                enabled: old.mutation.enabled, generation: generation, modelID: modelID)
        intents[articleID] = Intent(mutation: mutation, article: light, phase: .queued)
        dirty = true; persist(token)
        return operation == token && isCurrent(mutation) ? mutation : nil
    }

    func recoveryTicket() -> RecoveryTicket? {
        guard loaded, !transitioning, let namespace = context.namespace, namespace != .guest else { return nil }
        return RecoveryTicket(namespace: namespace, generation: generation, modelID: modelID, recoveryID: recoveryID)
    }
    func isCurrent(_ ticket: RecoveryTicket) -> Bool {
        ticket.modelID == modelID && ticket.generation == generation && ticket.namespace == context.namespace
            && ticket.recoveryID == recoveryID && loaded && !transitioning
    }
    func beginRecovery(_ ticket: RecoveryTicket, stillCurrent: @escaping Guard = { true }) -> Bool {
        guard stillCurrent(), isCurrent(ticket), recovery == .required else { return false }
        recovery = .running
        let token = beginOperation()
        guard publish(token, stillCurrent: stillCurrent), stillCurrent(), isCurrent(ticket), recovery == .running else {
            failOriginalRecovery(ticket)
            return false
        }
        return true
    }
    private func failOriginalRecovery(_ ticket: RecoveryTicket) {
        guard isCurrent(ticket), recovery == .running || recovery == .ready else { return }
        recovery = .failed; serverConfirmed = false; currentObservationID = nil
        _ = publish(beginOperation())
    }
    @discardableResult
    func finishRecovery(_ ticket: RecoveryTicket, success: Bool,
                        stillCurrent: @escaping Guard = { true }) async -> Bool {
        guard isCurrent(ticket), recovery == .running else { return false }
        guard success, stillCurrent(), isCurrent(ticket), recovery == .running else {
            failOriginalRecovery(ticket); return false
        }
        var changed = false
        for key in Array(intents.keys) {
            guard var intent = intents[key], intent.phase == .started else { continue }
            intent.phase = .queued; intent.attemptID = nil; intent.serverMatched = false
            intents[key] = intent; changed = true
        }
        if changed { dirty = true; persist(beginOperation(), publicationPermission: stillCurrent) }
        guard await waitForStorage(), stillCurrent(), isCurrent(ticket), recovery == .running else {
            failOriginalRecovery(ticket); return false
        }
        if changed && !intents.values.filter({ $0.phase == .queued }).allSatisfy(admitted) {
            failOriginalRecovery(ticket); return false
        }
        recovery = .ready; serverConfirmed = false; currentObservationID = nil
        guard publish(beginOperation(), stillCurrent: stillCurrent), stillCurrent(),
              isCurrent(ticket), recovery == .ready else {
            failOriginalRecovery(ticket); return false
        }
        return true
    }
    func retryRecovery() {
        guard loaded, !transitioning, context.namespace != .guest, recovery == .failed else { return }
        recoveryID = UUID(); recovery = .required; serverConfirmed = false; currentObservationID = nil
        _ = publish(beginOperation())
    }

    func observationTicket() -> ObservationTicket? {
        guard let namespace = context.namespace, namespace != .guest, !transitioning, loaded, recovery == .ready else { return nil }
        let id = UUID(); currentObservationID = id
        return ObservationTicket(observationID: id, modelID: modelID, generation: generation, namespace: namespace)
    }
    func endObservation(_ ticket: ObservationTicket) { if isCurrent(ticket) { currentObservationID = nil } }
    func observationFailed(ticket: ObservationTicket) {
        guard isCurrent(ticket) else { return }; observationError = true; _ = publish(beginOperation())
    }
    @discardableResult
    func applyRemote(_ remote: RemoteSnapshot, ticket: ObservationTicket) -> Bool {
        guard isCurrent(ticket), loaded else { return false }
        let token = beginOperation()
        guard remote.articles.count <= FavoritesRecordCodec.maximumEntries,
              Set(remote.articles.map(\.id)).count == remote.articles.count else {
            storageState = .limitExceeded; _ = publish(token); return false
        }
        var acceptedArticles: [Article] = []
        for article in remote.articles {
            guard let light = try? FavoritesRecordCodec.lightweight(article) else {
                observationError = true; _ = publish(token); return false
            }
            if let value = accepted(light, token: token) {
                // Retain the known current membership stamp while old/cache
                // replies omit it, and while the latest local intent is pending.
                let local = visible.first(where: { $0.id == value.id })?.favoriteSavedAt
                let pending = intents[value.id].flatMap { $0.mutation.enabled ? $0.mutation.article.favoriteSavedAt : nil }
                let unconfirmed = remote.isFromCache || remote.hasPendingWrites
                let savedAt = pending ?? (unconfirmed ? (local ?? value.favoriteSavedAt) : (value.favoriteSavedAt ?? local))
                acceptedArticles.append(value.withFavoriteSavedAt(savedAt))
            }
            guard operation == token else { return false }
        }
        let confirmed = !remote.isFromCache && !remote.hasPendingWrites && recovery == .ready
        let ignoreEmptyCache = remote.isFromCache && remote.articles.isEmpty
        let nextBase = ignoreEmptyCache ? base : acceptedArticles
        guard let refreshed = refreshedIntents(token: token) else { return false }
        let candidate = overlaid(nextBase, intents: refreshed)
        guard validateCandidate(candidate, token: token) else { return false }
        base = nextBase; intents = refreshed
        // Proof belongs to the base it confirmed. Replacing that base with an
        // unconfirmed snapshot cannot carry an earlier match into retirement.
        if !ignoreEmptyCache {
            for key in Array(intents.keys) {
                guard var intent = intents[key] else { continue }
                intent.serverMatched = confirmed && (nextBase.contains(where: { $0.id == key }) == intent.mutation.enabled)
                intents[key] = intent
            }
        }
        if !ignoreEmptyCache { serverConfirmed = confirmed }
        observationError = false; adopt(candidate); dirty = true
        persist(token)
        guard operation == token else { return false }
        retireAcknowledged(token: token)
        return operation == token
    }

    func membershipTicket(articleID: String) -> MembershipTicket? {
        guard !transitioning, let namespace = context.namespace,
              let article = visible.first(where: { $0.id == articleID }), let id = membershipIDs[articleID] else { return nil }
        return MembershipTicket(namespace: namespace, generation: generation, articleID: articleID,
                                contentRevision: article.bodyRevision, article: article, modelID: modelID, membershipID: id)
    }
    func isCurrent(_ ticket: MembershipTicket) -> Bool {
        ticket.modelID == modelID && ticket.generation == generation && ticket.namespace == context.namespace
            && !transitioning && membershipIDs[ticket.articleID] == ticket.membershipID
            && visible.contains(where: { $0.id == ticket.articleID && $0.bodyRevision == ticket.contentRevision })
    }
    @discardableResult
    func updateMetadata(_ article: Article, ticket: MembershipTicket) -> Bool {
        guard isCurrent(ticket), article.id == ticket.articleID, loaded else { return false }
        let token = beginOperation()
        guard let accepted = accepted(article, token: token), accepted.bodyRevision == ticket.contentRevision else { return false }
        let light = accepted.withFavoriteSavedAt(visible.first { $0.id == ticket.articleID }?.favoriteSavedAt)
        let candidate = visible.map { $0.id == light.id ? light : $0 }
        guard validateCandidate(candidate, token: token) else { return false }
        base = base.map { $0.id == light.id ? light : $0 }
        if var intent = intents[light.id], intent.mutation.enabled { intent.article = light; intents[light.id] = intent }
        adopt(candidate); dirty = true; persist(token)
        return operation == token
    }

    /// A separately confirmed public source may advance metadata for an existing
    /// bookmark. It never creates membership or rewrites an outstanding reader
    /// intention, its immutable payload, dispatch phase or server-match proof.
    /// The caller owns fresh source/auth authority; this model owns membership.
    @discardableResult
    func adoptPublishedMetadata(_ article: Article, ticket: MembershipTicket,
                                stillCurrent: @escaping Guard,
                                permitsPublication: @escaping @MainActor (Article) -> Bool) -> MembershipTicket? {
        let originalOperation = operation
        func originalIsCurrent() -> Bool {
            operation == originalOperation && loaded && isCurrent(ticket)
                && intents[ticket.articleID] == nil && base.contains(where: { $0.id == ticket.articleID })
        }
        guard originalIsCurrent(), article.id == ticket.articleID, article.isPubliclyPublished,
              article.bodyRevision?.isEmpty == false,
              stillCurrent(), originalIsCurrent(), permitsPublication(article), originalIsCurrent(),
              let admittedLight = accepted(article, token: originalOperation), originalIsCurrent(),
              admittedLight.isPubliclyPublished, admittedLight.bodyRevision == article.bodyRevision,
              permitsPublication(admittedLight), originalIsCurrent(), stillCurrent(), originalIsCurrent() else { return nil }
        let light = admittedLight.withFavoriteSavedAt(visible.first { $0.id == ticket.articleID }?.favoriteSavedAt)
        let candidate = visible.map { $0.id == ticket.articleID ? light : $0 }
        guard validateCandidate(candidate, token: originalOperation), originalIsCurrent(),
              stillCurrent(), originalIsCurrent(), permitsPublication(light), originalIsCurrent() else { return nil }
        // A repeated fresh source need not rewrite the journal or replace a
        // stable lease. Body and transport data are absent from this comparison.
        if FavoritesRecord.Metadata(light) == FavoritesRecord.Metadata(ticket.article) {
            return membershipTicket(articleID: ticket.articleID)
        }
        // No user/provider callback runs between the final original-ticket
        // check and this replacement. Every later callback owns the new ticket.
        let token = beginOperation()
        base = base.map { $0.id == light.id ? light : $0 }
        adopt(candidate); dirty = true
        guard let replacement = membershipTicket(articleID: ticket.articleID) else { return nil }
        let permission: Guard = { [weak self] in
            guard let self, self.operation == token, self.loaded, self.isCurrent(replacement),
                  self.intents[replacement.articleID] == nil else { return false }
            let current = stillCurrent()
            guard current, self.operation == token, self.isCurrent(replacement),
                  self.intents[replacement.articleID] == nil else { return false }
            let published = permitsPublication(light)
            return published && self.operation == token && self.loaded && self.isCurrent(replacement)
                && self.intents[replacement.articleID] == nil
        }
        persist(token, publicationPermission: permission)
        return permission() ? replacement : nil
    }
    func reconcileAvailability() {
        guard loaded, !transitioning else { return }
        let token = beginOperation()
        var nextBase: [Article] = []
        for article in base {
            if let light = accepted(article, token: token) { nextBase.append(light) }
            guard operation == token else { return }
        }
        guard let nextIntents = refreshedIntents(token: token) else { return }
        let candidate = overlaid(nextBase, intents: nextIntents)
        guard validateCandidate(candidate, token: token) else { return }
        base = nextBase; intents = nextIntents; adopt(candidate); dirty = true; persist(token)
    }
    func retryStorage() {
        guard let namespace = context.namespace, !transitioning,
              !jobs.values.contains(where: { $0.namespace == namespace }) else { return }
        let token = beginOperation()
        if loaded && dirty {
            let finishLatest: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                self.lastIssuedRevision = self.durableRecord?.recordRevision
                if self.dirty {
                    self.persist(self.operation, success: { [weak self] in
                        guard let self else { return }; self.retireAcknowledged(token: self.operation)
                    })
                } else { self.retireAcknowledged(token: self.operation) }
            }
            if let candidate = uncertainWrite {
                // Reuse exact bytes/UUID before advancing the known head. The
                // journal may acknowledge an earlier committed-but-unreported
                // replacement; an unknown foreign head still fails its CAS.
                persist(token, replay: candidate, success: finishLatest)
            } else {
                lastIssuedRevision = durableRecord?.recordRevision
                persist(token, success: { [weak self] in
                    guard let self else { return }; self.retireAcknowledged(token: self.operation)
                })
            }
        }
        else if !loaded { load(token) }
        else { _ = publish(token) }
    }

    /// Waits only for work registered at invocation; later publications cannot
    /// make an old waiter endorse a new generation or an unbounded stream.
    @discardableResult
    func waitForStorage() async -> Bool {
        let target = sequence
        guard jobs.values.contains(where: { $0.sequence <= target }) else { return true }
        guard waiters.count < Self.maximumWaiters else { return false }
        return await withCheckedContinuation { continuation in
            waiters[UUID()] = Waiter(sequence: target, continuation: continuation)
        }
    }

    func isCurrent(_ ticket: ObservationTicket) -> Bool {
        ticket.modelID == modelID && ticket.generation == generation && ticket.namespace == context.namespace
            && ticket.observationID == currentObservationID && !transitioning && recovery == .ready
    }
    private func accepted(_ article: Article, token: UUID) -> Article? {
        guard operation == token, let light = try? FavoritesRecordCodec.lightweight(article) else { return nil }
        let sanitized = sanitize(light)
        guard operation == token, let sanitized, sanitized.id == article.id else { return nil }
        return try? FavoritesRecordCodec.lightweight(sanitized.withFavoriteSavedAt(light.favoriteSavedAt))
    }
    private func refreshedIntents(token: UUID) -> [String: Intent]? {
        var result = intents
        for key in Array(result.keys) {
            guard var intent = result[key], intent.mutation.enabled else { continue }
            let light = accepted(intent.article, token: token)
            guard operation == token else { return nil }
            // Preserve both intent and any unknown attempt when editorial policy
            // hides/corrects a member. A fresh explicit retry may replace payload.
            if let light {
                intent.article = light; intent.available = true
                if light.bodyRevision != intent.mutation.article.bodyRevision { intent.phase = .blocked }
            } else { intent.phase = .blocked; intent.available = false }
            result[key] = intent
        }
        return result
    }
    private func validateCandidate(_ articles: [Article], token: UUID) -> Bool {
        guard operation == token else { return false }
        guard articles.count <= FavoritesRecordCodec.maximumEntries,
              articles.allSatisfy({ FavoritesRecord.Metadata($0).valid }) else {
            storageState = .limitExceeded; _ = publish(token); return false
        }
        return true
    }
    private func overlaid(_ articles: [Article], intents: [String: Intent]) -> [Article] {
        let ids = Set(intents.keys)
        return (articles.filter { !ids.contains($0.id) }
            + intents.values.filter { $0.mutation.enabled && $0.available }.map(\.article)).sorted { $0.id < $1.id }
    }
    private func adopt(_ articles: [Article]) {
        let previous = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var next: [String: UUID] = [:]
        for article in articles {
            next[article.id] = previous[article.id]?.bodyRevision == article.bodyRevision && previous[article.id] != nil
                ? membershipIDs[article.id] ?? UUID() : UUID()
        }
        visible = articles.sorted { $0.id < $1.id }; membershipIDs = next
    }
    private func load(_ token: UUID) {
        guard operation == token, let namespace = context.namespace,
              let id = register(namespace: namespace, record: nil) else { return }
        let expectedGeneration = generation
        storage.read(namespace) { [weak self] result in
            guard let self else { return }
            defer { self.completed(id) }
            guard self.generation == expectedGeneration, self.context.namespace == namespace, self.operation == token else { return }
            switch result {
            case .failure(let error):
                self.transitioning = false; self.loaded = false; self.storageState = self.failureState(error, reading: true)
                _ = self.publish(token)
            case .success(let value):
                do {
                    if let value { try FavoritesRecordCodec.validate(value, namespace: namespace) }
                    let record = value ?? .empty
                    var nextBase: [Article] = []
                    for metadata in record.base {
                        if let article = self.accepted(metadata.article, token: token) { nextBase.append(article) }
                        guard self.operation == token else { return }
                    }
                    self.base = nextBase; self.intents = [:]
                    for pending in record.pending {
                        let mutation = Mutation(id: pending.intentID, namespace: namespace, article: pending.payload.article,
                                                enabled: pending.enabled, generation: self.generation, modelID: self.modelID)
                        self.intents[pending.articleID] = Intent(mutation: mutation, article: pending.article.article,
                                                               phase: pending.phase, attemptID: pending.attemptID)
                    }
                    self.requiresRecovery = record.requiresRecovery
                    guard let refreshed = self.refreshedIntents(token: token) else { return }
                    self.intents = refreshed; self.adopt(self.overlaid(nextBase, intents: refreshed))
                    self.durableRecord = value; self.lastIssuedRevision = value?.recordRevision
                    self.loaded = true; self.transitioning = false; self.storageState = .ready
                    self.recovery = namespace == .guest ? .ready : .required
                    self.dirty = !self.contentMatches(record)
                    _ = self.publish(token)
                } catch {
                    guard self.operation == token else { return }
                    self.transitioning = false; self.loaded = false; self.storageState = self.failureState(error, reading: true)
                    _ = self.publish(token)
                }
            }
        }
    }
    private func record(excluding: Set<String> = []) -> FavoritesRecord {
        FavoritesRecord(base: base.map(FavoritesRecord.Metadata.init),
                        pending: intents.filter { !excluding.contains($0.key) }.values.map(\.record).sorted { $0.articleID < $1.articleID },
                        requiresRecovery: requiresRecovery)
    }
    private func contentMatches(_ record: FavoritesRecord) -> Bool {
        let current = self.record()
        return current.base == record.base && current.pending == record.pending && current.requiresRecovery == record.requiresRecovery
    }
    private func admitted(_ intent: Intent) -> Bool {
        guard let pending = durableRecord?.pending.first(where: { $0.articleID == intent.mutation.articleID }) else { return false }
        return pending.intentID == intent.mutation.id && pending.payload == FavoritesRecord.Metadata(intent.mutation.article)
            && pending.enabled == intent.mutation.enabled && pending.phase == intent.phase && pending.attemptID == intent.attemptID
    }
    private func persist(_ token: UUID, excluding: Set<String> = [], replay: RetryCandidate? = nil, success: (@MainActor () -> Void)? = nil, publicationPermission: @escaping Guard = { true }) {
        guard operation == token, loaded, let namespace = context.namespace else { return }
        // Carry an in-flight retirement into every later snapshot. Otherwise
        // coalescing could replace the excluding record with an ACK-inclusive one.
        let carried = intents.filter { $0.value.retiring && $0.value.phase == .acknowledged && $0.value.serverMatched }
        let excluded = excluding.union(carried.keys)
        let retirementIDs = replay?.retirements ?? intents.filter { excluded.contains($0.key) }.mapValues { $0.mutation.id }
        let value = replay?.record ?? record(excluding: excluded)
        do { try FavoritesRecordCodec.validate(value, namespace: namespace) }
        catch { storageState = failureState(error, reading: false); _ = publish(token); return }
        let expected: UUID? = replay == nil ? lastIssuedRevision : replay!.expectedRevision
        guard let id = register(namespace: namespace, record: value, retirements: retirementIDs, expectedRevision: expected), let job = jobs[id] else { return }
        lastIssuedRevision = value.recordRevision
        storage.write(namespace, value, expected) { [weak self] result in
            guard let self else { return }
            let job = self.jobs[id] ?? job
            defer { self.completed(id) }
            guard self.generation == job.generation, self.context.namespace == namespace, self.loaded else { return }
            switch result {
            case .success:
                if self.uncertainWrite.map({ $0.sequence < job.sequence }) ?? false { self.uncertainWrite = nil }
                if job.sequence > self.durableSequence {
                    self.durableSequence = job.sequence; self.durableRecord = value
                }
                for (key, originalID) in job.retirements {
                    guard self.intents[key]?.mutation.id == originalID,
                          self.intents[key]?.phase == .acknowledged, self.intents[key]?.serverMatched == true else { continue }
                    // A later accepted snapshot that includes the intent wins;
                    // this older completion cannot declare it durably retired.
                    let laterIncludes = self.jobs.values.contains { later in
                        later.sequence > job.sequence && later.generation == job.generation
                            && later.record?.pending.contains(where: { $0.intentID == originalID }) == true
                    }
                    if !laterIncludes { self.intents.removeValue(forKey: key) }
                }
                self.dirty = !self.contentMatches(value)
                if !self.dirty { self.storageState = .ready }
                success?()
                _ = self.publish(self.operation, stillCurrent: publicationPermission)
            case .failure(let error):
                for (key, originalID) in job.retirements where self.intents[key]?.mutation.id == originalID {
                    let stillQueued = self.jobs.contains { otherID, other in
                        otherID != id && other.generation == job.generation && other.retirements[key] == originalID
                    }
                    if !stillQueued { self.intents[key]?.retiring = false }
                }
                if error as? FavoritesJournalFailure == .superseded {
                    // The actual journal coalesces only this exact revision
                    // chain and keeps the earliest expected on-disk head.
                    for otherID in Array(self.jobs.keys) where otherID != id {
                        if self.jobs[otherID]?.expectedRevision == value.recordRevision {
                            self.jobs[otherID]?.expectedRevision = job.expectedRevision
                        }
                    }
                    return
                }
                if error as? FavoritesJournalFailure != .staleRevision,
                   !(error is FavoritesRecordCodec.Failure),
                   self.uncertainWrite.map({ $0.sequence <= job.sequence }) ?? true {
                    self.uncertainWrite = RetryCandidate(record: value, expectedRevision: job.expectedRevision,
                                                        retirements: job.retirements, sequence: job.sequence)
                }
                self.dirty = true; self.storageState = self.failureState(error, reading: false)
                _ = self.publish(self.operation, stillCurrent: publicationPermission)
            }
        }
        // The journal has registered this immutable snapshot before observers run.
        if operation == token { _ = publish(token, stillCurrent: publicationPermission) }
    }
    private func retireAcknowledged(token: UUID, stillCurrent: @escaping Guard = { true }) {
        guard stillCurrent(), operation == token else { return }
        let eligible = intents.filter { !$0.value.retiring && $0.value.phase == .acknowledged
            && $0.value.serverMatched && admitted($0.value) }.mapValues { $0.mutation.id }
        guard !eligible.isEmpty else { return }
        for key in eligible.keys { intents[key]?.retiring = true }
        persist(token, excluding: Set(eligible.keys), publicationPermission: stillCurrent)
    }

    private func register(namespace: FavoritesNamespace, record: FavoritesRecord?, retirements: [String: UUID] = [:], expectedRevision: UUID? = nil) -> UUID? {
        guard sequence < UInt64.max, jobs.count < 512 else {
            storageState = .limitExceeded; _ = publish(operation); return nil
        }
        sequence += 1; let id = UUID()
        jobs[id] = Job(sequence: sequence, generation: generation, namespace: namespace, record: record, retirements: retirements, expectedRevision: expectedRevision)
        return id
    }
    private func completed(_ id: UUID) {
        jobs.removeValue(forKey: id)
        for (key, waiter) in Array(waiters) where !jobs.values.contains(where: { $0.sequence <= waiter.sequence }) {
            waiters.removeValue(forKey: key); waiter.continuation.resume(returning: true)
        }
    }
    private func failureState(_ error: Error, reading: Bool) -> FavoritesStorageState {
        switch error as? FavoritesRecordCodec.Failure {
        case .invalidRecord: return .invalidRecord
        case .unsupportedVersion: return .unsupportedVersion
        case .limitExceeded: return .limitExceeded
        case nil: return reading ? .readFailed : .writeFailed
        }
    }
    private func beginOperation() -> UUID { operation = UUID(); return operation }
    @discardableResult private func publish(_ token: UUID, stillCurrent: @escaping Guard = { true }) -> Bool {
        guard stillCurrent(), operation == token else { return false }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard stillCurrent(), operation == token, revision < UInt64.max else { return false }
        revision += 1
        var state = storageState
        if state == .ready {
            if recovery == .failed { state = .recoveryFailed }
            else if context.namespace != .guest && recovery != .ready { state = .recovering }
            else if observationError || intents.values.contains(where: { [.failed, .blocked].contains($0.phase) }) { state = .cloudFailed }
            else if !intents.isEmpty || dirty { state = .pending }
        }
        snapshot = FavoritesSnapshot(generation: generation, revision: revision, articles: visible,
                                     pendingArticleIDs: Set(intents.keys), serverConfirmed: serverConfirmed, state: state,
                                     recoveryReady: loaded && recovery == .ready)
        changeSubject.send(snapshot)
        return stillCurrent() && operation == token
    }
}
