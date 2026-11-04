import Foundation

/// The existing v1.3 on-disk envelope. Moving it does not change its JSON schema.
struct CacheData: Codable, Sendable {
    let articles: [Article]
    let timestamp: Date
    let version: String
}

/// The actual cold-cache admission pipeline. Constructors start no storage,
/// worker, timer or SDK. A stale/cancelled caller cannot refund actual CPU work.
@MainActor
final class ArticleCacheHydrationCoordinator {
    enum Source: Equatable, Sendable {
        case encoded(Data)
        case memory(articles: [Article], timestamp: Date, articlesAreSorted: Bool)
    }
    struct Policy: Sendable {
        let version: String
        let maximumAge: TimeInterval
        let now: Date
        let generation: UUID
        init(version: String, maximumAge: TimeInterval, now: Date, generation: UUID = UUID()) {
            self.version = version; self.maximumAge = maximumAge; self.now = now; self.generation = generation
        }
    }
    struct Prepared: Equatable, Sendable {
        let articles: [Article]
        let timestamp: Date
        let articlesAreSorted: Bool
    }
    enum Rejection: Equatable, Sendable { case corrupt, versionMismatch, expired }
    enum Decoded: Equatable, Sendable { case ready(Prepared), rejected(Rejection) }
    enum Outcome: Equatable, Sendable {
        case ready(Prepared), missing, rejected(Rejection), stale
        var articles: [Article]? { if case .ready(let prepared) = self { return prepared.articles }; return nil }
    }
    struct Capture: Equatable, Sendable {
        let generation: UUID
        fileprivate let modelID: UUID
        fileprivate let source: Source?
        fileprivate let policy: PolicyValue
    }
    fileprivate struct PolicyValue: Equatable, Sendable {
        let version: String
        let maximumAge: TimeInterval
        let now: Date
        let generation: UUID
        var policy: Policy { Policy(version: version, maximumAge: maximumAge, now: now, generation: generation) }
    }
    typealias Guard = @MainActor () -> Bool
    typealias Read = @MainActor () -> Source?
    typealias Prepare = @Sendable (Source, Policy) async -> Decoded

    private final class Waiter {
        let id: UUID
        let capture: Capture
        let permitted: Guard
        var continuation: CheckedContinuation<Outcome, Never>?
        init(id: UUID, capture: Capture, permitted: @escaping Guard, continuation: CheckedContinuation<Outcome, Never>) {
            self.id = id; self.capture = capture; self.permitted = permitted; self.continuation = continuation
        }
        func finish(_ result: Outcome) {
            let held = continuation; continuation = nil; held?.resume(returning: result)
        }
    }
    private final class Job {
        let capture: Capture
        var waiters: [Waiter]
        init(capture: Capture, waiter: Waiter) { self.capture = capture; waiters = [waiter] }
    }
    private let modelID = UUID()
    private let read: Read
    private let prepare: Prepare
    private let now: @MainActor () -> Date
    private let version: String
    private let maximumAge: TimeInterval
    private var generation = UUID()
    private var active: Job?
    private var pending: Job?
    private var memoized: (generation: UUID, decoded: Decoded)?
    var activity: (active: Bool, pending: Bool, waiterCount: Int) {
        (active != nil, pending != nil, (active?.waiters.count ?? 0) + (pending?.waiters.count ?? 0))
    }

    init(version: String = "1.3", maximumAge: TimeInterval = 7 * 24 * 60 * 60,
         read: @escaping Read, prepare: @escaping Prepare, now: @escaping @MainActor () -> Date = Date.init) {
        self.version = version; self.maximumAge = maximumAge
        self.read = read; self.prepare = prepare; self.now = now
    }
    /// Capture on the platform/storage owner before the caller creates a Task.
    /// Getter reentry leaves the original generation stale, never borrowed.
    func capture() -> Capture {
        let original = generation
        let source = read()
        let date = now()
        return Capture(generation: original, modelID: modelID, source: source,
                       policy: PolicyValue(version: version, maximumAge: maximumAge, now: date, generation: original))
    }
    func isCurrent(_ capture: Capture) -> Bool { capture.modelID == modelID && capture.generation == generation }
    func invalidate() {
        generation = UUID(); memoized = nil
        let oldPending = pending; pending = nil
        oldPending?.waiters.forEach { $0.finish(.stale) }
        // The actual occupied worker remains held until it returns.
        let oldActiveWaiters = active?.waiters ?? []
        active?.waiters = []
        oldActiveWaiters.forEach { $0.finish(.stale) }
    }
    func load(_ original: Capture, stillPermitted: @escaping Guard = { true }) async -> Outcome {
        guard !Task.isCancelled, permitted(original, stillPermitted) else { return .stale }
        guard original.source != nil else { return .missing }
        if let memoized, memoized.generation == original.generation {
            return outcome(memoized.decoded, capture: original, permitted: stillPermitted)
        }
        let id = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let waiter = Waiter(id: id, capture: original, permitted: stillPermitted, continuation: continuation)
                if let active, active.capture.generation == original.generation {
                    active.waiters.append(waiter)
                } else if let pending, pending.capture.generation == original.generation {
                    pending.waiters.append(waiter)
                } else {
                    let superseded = pending
                    pending = Job(capture: original, waiter: waiter)
                    superseded?.waiters.forEach { $0.finish(.stale) }
                }
                pump()
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelWaiter(id) }
        })
    }
    private func cancelWaiter(_ id: UUID) {
        for job in [active, pending].compactMap({ $0 }) {
            let cancelled = job.waiters.filter { $0.id == id }
            job.waiters.removeAll { $0.id == id }
            cancelled.forEach { $0.finish(.stale) }
        }
        if pending?.waiters.isEmpty == true { pending = nil }
    }
    private func permitted(_ capture: Capture, _ check: Guard) -> Bool {
        guard isCurrent(capture) else { return false }
        let accepted = check()
        return accepted && isCurrent(capture)
    }
    private func outcome(_ decoded: Decoded, capture: Capture, permitted check: Guard) -> Outcome {
        guard permitted(capture, check) else { return .stale }
        switch decoded {
        case .rejected(let reason): return .rejected(reason)
        case .ready(let prepared):
            let date = now()
            guard permitted(capture, check) else { return .stale }
            return date.timeIntervalSince(prepared.timestamp) < capture.policy.maximumAge ? .ready(prepared) : .rejected(.expired)
        }
    }
    private func pump() {
        guard active == nil, let job = pending else { return }
        pending = nil
        guard isCurrent(job.capture), let source = job.capture.source else {
            job.waiters.forEach { $0.finish(.stale) }; pump(); return
        }
        active = job
        Task { @MainActor [self, job] in
            guard isCurrent(job.capture), !job.waiters.isEmpty else {
                if active === job { active = nil }; pump(); return
            }
            // A real prepare returns before this slot can be released. Caller
            // cancellation or a newer cache epoch does not create another lane.
            let decoded = await prepare(source, job.capture.policy.policy)
            if isCurrent(job.capture) { memoized = (job.capture.generation, decoded) }
            // Remove this job before callbacks/guards can synchronously reenter.
            if active === job { active = nil }
            let waiters = job.waiters; job.waiters = []
            for waiter in waiters where waiter.continuation != nil {
                waiter.finish(outcome(decoded, capture: waiter.capture, permitted: waiter.permitted))
            }
            pump()
        }
    }
}

/// The decoder and formatter instance belong to this worker actor. Platform
/// UserDefaults access and the final availability/admission remain on MainActor.
actor ArticleCacheDecodeWorker {
    private lazy var dates = ArticlePresentationDateParser()
    func prepare(_ source: ArticleCacheHydrationCoordinator.Source,
                 policy: ArticleCacheHydrationCoordinator.Policy) -> ArticleCacheHydrationCoordinator.Decoded {
        let articles: [Article], timestamp: Date, sorted: Bool
        switch source {
        case .encoded(let data):
            let envelope: CacheData
            do { envelope = try JSONDecoder().decode(CacheData.self, from: data) }
            catch { return .rejected(.corrupt) }
            guard envelope.version == policy.version else { return .rejected(.versionMismatch) }
            articles = envelope.articles; timestamp = envelope.timestamp; sorted = false
        case .memory(let values, let date, let articlesAreSorted):
            articles = values; timestamp = date; sorted = articlesAreSorted
        }
        guard policy.now.timeIntervalSince(timestamp) < policy.maximumAge else { return .rejected(.expired) }
        let publicArticles = articles.filter(\.isPubliclyPublished)
        let prepared = sorted ? publicArticles : dates.sortedByCreatedNewestFirst(publicArticles)
        return .ready(.init(articles: prepared, timestamp: timestamp, articlesAreSorted: true))
    }
}

