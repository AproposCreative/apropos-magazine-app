import Foundation

/// Image preparation may run concurrently, but file publication happens only
/// after the coordinator has accepted the result's generation on MainActor.
struct WidgetFeedImageUpdate {
    let commit: @MainActor () -> Set<String>

    static let unchanged = WidgetFeedImageUpdate(commit: { [] })
}

/// Owns widget publication and image completion. Its injected operations let tests
/// exercise cancellation and retries without App Groups, WidgetKit or networking.
@MainActor
final class WidgetFeedSyncCoordinator {
    typealias Prepare = (WidgetFeedSource) async throws -> [WidgetArticle]
    typealias CacheImages = ([WidgetArticle]) async -> WidgetFeedImageUpdate

    private let prepare: Prepare
    private let persist: ([WidgetArticle]) -> Void
    private let cacheImages: CacheImages
    private let reloadImages: () -> Void
    private let now: () -> Date
    private let imageRetryInterval: TimeInterval

    private var source: WidgetFeedSource?
    private var payload: [WidgetArticle]?
    private var generation = UUID()
    private var pending: Task<Void, Never>?
    private var lastImageAttempt: Date?

    init(
        prepare: @escaping Prepare,
        persist: @escaping ([WidgetArticle]) -> Void,
        cacheImages: @escaping CacheImages,
        reloadImages: @escaping () -> Void,
        now: @escaping () -> Date = Date.init,
        imageRetryInterval: TimeInterval = 30
    ) {
        self.prepare = prepare
        self.persist = persist
        self.cacheImages = cacheImages
        self.reloadImages = reloadImages
        self.now = now
        self.imageRetryInterval = max(0, imageRetryInterval)
    }

    @discardableResult
    func sync(_ latest: WidgetFeedSource) -> Task<Void, Never>? {
        guard !latest.entries.isEmpty else {
            // Keep the existing stored widget on a transient empty feed, but stop
            // an obsolete preparation/image operation from publishing afterwards.
            invalidate()
            return nil
        }

        let sourceChanged = source != latest
        if !sourceChanged, let pending { return pending }
        if !sourceChanged, payload != nil, !canRetryImages { return nil }

        generation = UUID()
        let ticket = generation
        if sourceChanged, pending != nil {
            // The canceled image attempt cannot commit, so it must not consume
            // the retry window of a replacement with an equivalent payload.
            lastImageAttempt = nil
        }
        pending?.cancel()
        source = latest
        let existingPayload = sourceChanged ? nil : payload

        let task = Task { [weak self, prepare, cacheImages] in
            do {
                let prepared: [WidgetArticle]
                if let existingPayload {
                    prepared = existingPayload
                } else {
                    prepared = try await prepare(latest)
                }
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                guard !prepared.isEmpty else {
                    self.pending = nil
                    return
                }

                if self.payload != prepared {
                    self.payload = prepared
                    self.lastImageAttempt = nil
                    // Exactly one metadata save/reload for this changed payload.
                    self.persist(prepared)
                }

                guard self.canRetryImages else {
                    self.pending = nil
                    return
                }
                self.lastImageAttempt = self.now()
                let imageUpdate = await cacheImages(prepared)
                guard self.generation == ticket, !Task.isCancelled else { return }
                let changedImageIDs = imageUpdate.commit()
                self.pending = nil
                if prepared.contains(where: { changedImageIDs.contains($0.id) }) {
                    // Image bytes changed; the metadata has already been stored.
                    self.reloadImages()
                }
            } catch {
                guard let self, self.generation == ticket else { return }
                self.pending = nil
                // A failed preparation remains retryable even for the same source.
                self.source = nil
            }
        }
        pending = task
        return task
    }

    func invalidate() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        source = nil
        payload = nil
        lastImageAttempt = nil
    }

    private var canRetryImages: Bool {
        guard let lastImageAttempt else { return true }
        let age = now().timeIntervalSince(lastImageAttempt)
        return age < 0 || age >= imageRetryInterval
    }
}
