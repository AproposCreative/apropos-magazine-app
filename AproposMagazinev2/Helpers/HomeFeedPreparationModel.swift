import Combine
import Foundation

/// The production receiver is inert until update. One real worker occupies its
/// slot until it returns; a newer input only replaces the single pending value.
@MainActor
final class HomeFeedPreparationModel: ObservableObject {
    typealias Prepare = @Sendable (HomeFeedInput) async throws -> HomeFeedSnapshot
    typealias ScheduleBoundary = (TimeInterval, @escaping @MainActor () -> Void) -> Void
    struct State: Equatable {
        let snapshot: HomeFeedSnapshot?
        let isPreparing: Bool
        let errorMessage: String?
        let generation: UUID
        let revision: UInt64
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    var state: State { committed }
    var snapshot: HomeFeedSnapshot? { committed.snapshot }
    var changes: AnyPublisher<State, Never> {
        subject.filter { [weak self] value in
            guard let self else { return false }
            return value.generation == self.state.generation && value.revision == self.state.revision
        }.eraseToAnyPublisher()
    }
    private let prepare: Prepare
    private let currentAuthority: () -> HomeFeedAuthority?
    private let now: () -> Date
    private let scheduleBoundary: ScheduleBoundary?
    private let subject = PassthroughSubject<State, Never>()
    private var committed = State(snapshot: nil, isPreparing: false, errorMessage: nil, generation: UUID(), revision: 0)
    private var operation = UUID(), demand = UUID()
    private var notifying = false
    private var latestInput: HomeFeedInput?
    private var pending: (UUID, HomeFeedInput)?
    private var active: UUID?
    private var workTask: Task<Void, Never>?
    private var boundaryTask: Task<Void, Never>?
    private var boundaryID = UUID()

    init(prepare: Prepare? = nil, currentAuthority: @escaping () -> HomeFeedAuthority?,
         now: @escaping () -> Date = Date.init, scheduleBoundary: ScheduleBoundary? = nil) {
        let worker = HomeFeedWorker()
        self.prepare = prepare ?? { input in await worker.prepare(input) }
        self.currentAuthority = currentAuthority; self.now = now; self.scheduleBoundary = scheduleBoundary
    }
    func isCurrent(_ original: HomeFeedAuthority) -> Bool {
        let token = operation
        let accepted = currentAuthority()
        return operation == token && accepted == original && latestInput?.authority == original
    }
    func update(_ input: HomeFeedInput) {
        let token = reserve()
        let accepted = currentAuthority()
        guard operation == token, accepted == input.authority else { return }
        if !notifying, state.errorMessage == nil, let prior = latestInput, Self.sameSources(prior, input),
           snapshot?.nextBoundary.map({ input.now < $0 }) ?? true, input.now >= prior.now {
            // Clock/progress/render notifications before the next deadline need no worker.
            latestInput = input
            return
        }
        demand = UUID(); let originalDemand = demand
        latestInput = input
        pending = (originalDemand, input)
        invalidateBoundary()
        let restricted = snapshot.map { Self.restricted($0, to: input) }
        guard publish(snapshot: restricted, preparing: true, error: nil, token: token, authority: input.authority) else { return }
        guard demand == originalDemand else { return }
        startPendingIfPossible()
    }
    func sceneBecameActive() {
        guard let input = latestInput else { return }
        update(input.replacingNow(now()))
    }
    /// Deterministic test/drain seam; this awaits real return, never a UI deadline.
    func waitForCurrentWork() async {
        while let task = workTask { await task.value }
    }
    private func startPendingIfPossible() {
        guard active == nil, let (originalDemand, input) = pending else { return }
        let token = operation
        let accepted = currentAuthority()
        guard operation == token, accepted == input.authority, demand == originalDemand else { return }
        pending = nil
        let slot = UUID(); active = slot
        let effect = prepare
        workTask = Task { [weak self] in
            let result: Result<HomeFeedSnapshot, Error>
            do { result = .success(try await effect(input)) } catch { result = .failure(error) }
            self?.finish(result, slot: slot, demand: originalDemand, input: input)
        }
    }
    private func finish(_ result: Result<HomeFeedSnapshot, Error>, slot: UUID, demand originalDemand: UUID, input: HomeFeedInput) {
        guard active == slot else { return }
        // The effect really returned. Only now is the occupied slot released.
        active = nil; workTask = nil
        if demand == originalDemand {
            let token = reserve()
            let accepted = currentAuthority()
            if operation == token, accepted == input.authority, latestInput?.authority == input.authority {
                switch result {
                case .success(let value):
                    if value.authority == input.authority,
                       publish(snapshot: value, preparing: false, error: nil, token: token, authority: input.authority) {
                        armBoundary(value.nextBoundary, authority: input.authority)
                    }
                case .failure:
                    _ = publish(snapshot: snapshot, preparing: false, error: "Indholdet kunne ikke forberedes. Prøv at opdatere igen.", token: token, authority: input.authority)
                }
            }
        }
        startPendingIfPossible()
    }
    private func armBoundary(_ date: Date?, authority: HomeFeedAuthority) {
        invalidateBoundary()
        guard let date else { return }
        let id = boundaryID, delay = max(0.001, date.timeIntervalSince(now()))
        let callback: @MainActor () -> Void = { [weak self] in
            guard let self, self.boundaryID == id, self.isCurrent(authority) else { return }
            if self.now() < date { self.armBoundary(date, authority: authority); return }
            self.sceneBecameActive()
        }
        if let scheduleBoundary { scheduleBoundary(delay, callback) }
        else {
            boundaryTask = Task {
                do { try await Task.sleep(nanoseconds: UInt64(min(delay, 31_536_000) * 1_000_000_000)) } catch { return }
                callback()
            }
        }
    }
    private func invalidateBoundary() { boundaryID = UUID(); boundaryTask?.cancel(); boundaryTask = nil }
    private func reserve() -> UUID { let token = UUID(); operation = token; return token }
    private func publish(snapshot: HomeFeedSnapshot?, preparing: Bool, error: String?, token: UUID, authority: HomeFeedAuthority) -> Bool {
        let before = currentAuthority()
        guard operation == token, before == authority, state.revision < UInt64.max else { return false }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        let after = currentAuthority()
        guard operation == token, after == authority else { return false }
        let value = State(snapshot: snapshot, isPreparing: preparing, errorMessage: error,
                          generation: demand, revision: state.revision + 1)
        committed = value
        subject.send(value)
        return operation == token && state.generation == value.generation && state.revision == value.revision
    }
    private static func sameSources(_ lhs: HomeFeedInput, _ rhs: HomeFeedInput) -> Bool {
        lhs.authority == rhs.authority && lhs.articles == rhs.articles && lhs.topics == rhs.topics
            && lhs.sections == rhs.sections && lhs.authors == rhs.authors && lhs.episodes == rhs.episodes
            && lhs.recommendations == rhs.recommendations
    }
    /// Restriction only uses accepted membership and identity. No sort, matching,
    /// date parsing or HTML work runs on this synchronous revocation boundary.
    private static func restricted(_ value: HomeFeedSnapshot, to input: HomeFeedInput) -> HomeFeedSnapshot {
        let accepted = HomeFeedBuilder.acceptedArticles(input.articles)
        let current = Dictionary(uniqueKeysWithValues: accepted.map { ($0.id, $0) })
        func article(_ old: Article) -> Article? {
            guard let next = current[old.id], old.contentRevision == next.contentRevision,
                  old.lastUpdated == next.lastUpdated, old.lastPublished == next.lastPublished else { return nil }
            return next
        }
        let oldOwner = value.authority.owner != input.authority.owner || value.authority.recommendations != input.authority.recommendations
        let rails = value.rails.map { rail -> HomeRail in
            let visible = rail.kind == .recommended && oldOwner ? [] : rail.visible.compactMap(article)
            let ids = Set(visible.map(\.id))
            return HomeRail(kind: rail.kind, visible: visible, all: rail.all.compactMap(article),
                reasonsByID: rail.reasonsByID.filter { ids.contains($0.key) })
        }
        let raw = Dictionary(grouping: input.episodes, by: \.id)
        func pair(_ pair: PodcastArticlePair) -> PodcastArticlePair? {
            guard let next = article(pair.article), next.name == pair.article.name, next.slug == pair.article.slug,
                  raw[pair.episode.id]?.contains(where: {
                HomePodcastIndex.enriched($0, with: next) == pair.episode
            }) == true else { return nil }
            return PodcastArticlePair(article: next, episode: pair.episode)
        }
        let retained = value.resumeIndex.articlesByID.compactMapValues(article)
        var episodes: [String: [PodcastEpisode]] = [:]
        for (id, previous) in value.resumeIndex.playableEpisodesByID {
            let candidates = (raw[id] ?? []).filter(\.hasPlayableAudioURL)
            // Newly introduced duplicates are already ambiguous BEFORE the
            // worker returns. Filtering just old rows would counterfeit uniqueness.
            if candidates.count == 1, let only = candidates.first, previous.contains(only) {
                episodes[id] = candidates
            }
        }
        let fallback = value.resumeIndex.fallbackArticleByEpisode.compactMapValues(article).filter { raw[$0.key.id]?.contains($0.key) == true }
        let metadata = value.authority.metadata == input.authority.metadata ? value.metadataByID.filter { id, _ in
            guard let old = value.resumeIndex.articlesByID[id], let next = retained[id],
                  old.topicID == next.topicID, old.topicsIDs == next.topicsIDs, old.sectionID == next.sectionID,
                  old.authorID == next.authorID, old.mobileImageURL == next.mobileImageURL,
                  old.thumbURL == next.thumbURL, old.coverURL == next.coverURL else { return false }
            return next.mobileImageURL != nil || next.thumbURL != nil || next.coverURL != nil || old.content == next.content
        } : [:]
        return HomeFeedSnapshot(authority: input.authority, hero: value.hero.compactMap(article), rails: rails,
            metadataByID: metadata, podcastPairs: value.podcastPairs.compactMap(pair),
            resumeIndex: HomeResumeIndex(playableEpisodesByID: episodes, articlesByID: retained, fallbackArticleByEpisode: fallback),
            nextBoundary: value.nextBoundary, metrics: value.metrics)
    }
}
