import Foundation

/// Playback decisions that can be verified without initializing AVPlayer or services.
enum PodcastPlaybackPolicy {
    enum StartReason {
        case userInitiated
        case automaticAdvance
        case resumeAfterFailure
    }

    /// The entered admission block, not an individual predicate or proof that
    /// media played. A successful request can still be preparing local bytes.
    enum AdmissionStage: CaseIterable, Sendable {
        case entry, request, publication, recording, reuse, offline
        case preparation, session, item, presentation

        func diagnosticCode(accepted: Bool) -> TelemetryDiagnosticPolicy.OperationalCode {
            if accepted { return .podcastAdmissionAccepted }
            switch self {
            case .entry: return .podcastAdmissionEntryRejected
            case .request: return .podcastAdmissionRequestRejected
            case .publication: return .podcastAdmissionPublicationRejected
            case .recording: return .podcastAdmissionRecordingRejected
            case .reuse: return .podcastAdmissionReuseRejected
            case .offline: return .podcastAdmissionOfflineRejected
            case .preparation: return .podcastAdmissionPreparationRejected
            case .session: return .podcastAdmissionSessionRejected
            case .item: return .podcastAdmissionItemRejected
            case .presentation: return .podcastAdmissionPresentationRejected
            }
        }
    }

    /// A valid unbound stream has nil articleID; nil result instead means the
    /// caller, raw episode and accepted recording contradict one another.
    struct ArticleIdentity: Equatable { let articleID: String? }
    static func articleIdentity(for episode: PodcastEpisode, requestedArticleID: String?, acceptedAsset: PodcastAudioAsset?) -> ArticleIdentity? {
        guard PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: requestedArticleID) else { return nil }
        if let asset = acceptedAsset {
            guard asset.episodeID == episode.id, asset.remoteURL == episode.audioURL,
                  asset.kind == (episode.isAINarration ? .ai : .human),
                  asset.sourceRevision == episode.sourceContentRevision else { return nil }
        }
        let id = requestedArticleID ?? episode.articleId ?? acceptedAsset?.canonicalArticleID
        guard id.map(CMSMirrorDocumentPolicy.isSafeDocumentID) ?? true,
              acceptedAsset.map({ $0.canonicalArticleID == id }) ?? true else { return nil }
        return ArticleIdentity(articleID: id)
    }

    static func canReuseItem(current: PodcastEpisode?, requested: PodcastEpisode,
                             currentArticleID: String?, requestedArticleID: String?, currentAudioURL: URL?, itemHasFailed: Bool) -> Bool {
        guard !itemHasFailed, let current else { return false }
        return current.id == requested.id
            && currentArticleID == (requestedArticleID ?? requested.articleId)
            && currentAudioURL == requested.audioURL && current.audioURL == requested.audioURL
            && current.isAINarration == requested.isAINarration
            && current.sourceContentRevision == requested.sourceContentRevision
    }

    /// Memory-only hit status is insufficient for a new file adoption. Even a
    /// warm/online file must be fully revalidated under its original request.
    static func requiresAssetPreparation(playbackURL: URL, isOnline: Bool, alreadyPrepared: Bool) -> Bool {
        !alreadyPrepared && (playbackURL.isFileURL || !isOnline)
    }

    static func canStart(playbackURL: URL, isOnline: Bool) -> Bool {
        playbackURL.isFileURL || isOnline
    }

    static func shouldPresentFullPlayer(reason: StartReason, isPresented: Bool) -> Bool {
        reason == .userInitiated || isPresented
    }

    static func explicitStart(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0, value <= 604_800 else { return nil }
        return value
    }

    static func boundedExplicitStart(_ value: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard explicitStart(value) != nil, let duration = knownDuration(duration), duration <= 604_800 else { return nil }
        return min(value, duration)
    }

    static func knownDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }
}

enum PodcastPlaybackQueue {
    /// Keep the session's order when a sheet reappears or the current episode
    /// advances. A newly selected episode outside the session starts a new queue.
    static func prepared(
        existing: [PodcastEpisode],
        candidates: [PodcastEpisode],
        currentEpisode: PodcastEpisode?
    ) -> [PodcastEpisode] {
        if let currentEpisode, existing.contains(where: { $0.id == currentEpisode.id }) {
            return existing
        }

        var result = candidates.filter(\.hasPlayableAudioURL)
        if let currentEpisode, currentEpisode.hasPlayableAudioURL,
           !result.contains(where: { $0.id == currentEpisode.id }) {
            result.insert(currentEpisode, at: 0)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    static func next(in queue: [PodcastEpisode], after currentEpisodeID: String) -> PodcastEpisode? {
        guard let index = queue.firstIndex(where: { $0.id == currentEpisodeID }),
              queue.indices.contains(index + 1) else { return nil }
        return queue[index + 1]
    }
}

/// A pause, manual seek or item replacement invalidates an outstanding resume
/// seek, so its completion cannot apply obsolete state or restart playback.
struct PodcastResumeSeekState {
    enum Completion: Equatable {
        case ignored
        case positioned(TimeInterval)
        case retryRequired
    }

    private(set) var activeRequest: UUID?
    private(set) var pendingPosition: TimeInterval?
    private(set) var isCompleted = false
    private(set) var revision = UUID()
    private(set) var hasExplicitStart = false

    mutating func prepareEpisode(savedPosition: TimeInterval?, explicitStart: TimeInterval? = nil) {
        invalidate()
        if let explicitStart {
            pendingPosition = PodcastPlaybackPolicy.explicitStart(explicitStart)
            hasExplicitStart = pendingPosition != nil
        } else {
            pendingPosition = savedPosition.flatMap { $0.isFinite && $0 > 1 ? $0 : nil }
            hasExplicitStart = false
        }
        isCompleted = false
    }

    func positionToResume(wantsPlayback: Bool, itemReady: Bool) -> TimeInterval? {
        guard wantsPlayback, itemReady, !isCompleted, activeRequest == nil else { return nil }
        return pendingPosition
    }

    mutating func begin() -> UUID {
        let request = UUID()
        activeRequest = request
        return request
    }

    mutating func invalidate() {
        activeRequest = nil
        revision = UUID()
    }

    mutating func consume(_ request: UUID, itemMatches: Bool) -> Bool {
        guard activeRequest == request, itemMatches else { return false }
        activeRequest = nil
        return true
    }

    mutating func finishResume(_ request: UUID, itemMatches: Bool, seekFinished: Bool, observedPosition: TimeInterval? = nil) -> Completion {
        guard consume(request, itemMatches: itemMatches), pendingPosition != nil else { return .ignored }
        guard seekFinished, let observedPosition, observedPosition.isFinite,
              observedPosition >= 0, observedPosition <= 604_800 else { return .retryRequired }
        pendingPosition = nil
        hasExplicitStart = false
        return .positioned(observedPosition)
    }

    mutating func setResolvedPosition(_ position: TimeInterval) {
        guard pendingPosition != nil, activeRequest == nil, position.isFinite, position >= 0, position <= 604_800 else { return }
        pendingPosition = position
    }

    mutating func confirmCompletion() {
        invalidate()
        pendingPosition = nil
        hasExplicitStart = false
        isCompleted = true
    }

    mutating func prepareExplicitResume() {
        guard isCompleted else { return }
        invalidate()
        isCompleted = false
        pendingPosition = 0
        hasExplicitStart = true
    }

    mutating func prepareManualSeek() {
        invalidate()
        pendingPosition = nil
        hasExplicitStart = false
        isCompleted = false
    }

    var canPersistProgress: Bool {
        !isCompleted && pendingPosition == nil && activeRequest == nil
    }

    static func shouldResume(seekFinished: Bool, wantsPlayback: Bool) -> Bool {
        seekFinished && wantsPlayback
    }
}

/// English articles currently offer text only. Canonical article audio remains
/// Danish; an actually unbound human podcast retains its existing stream route.
/// This policy never grants publication, account or source-revision authority.
enum ArticleAudioLanguagePolicy {
    static func requiresAudio(for article: Article) -> Bool {
        article.contentLanguage == .danish
    }

    static func permitsArticleID(_ articleID: String, language: ArticleContentLanguage) -> Bool {
        CMSMirrorDocumentPolicy.isSafeDocumentID(articleID)
            && !articleID.hasPrefix("en_") && language == .danish
    }

    /// The manager supplies the identity resolved from the accepted asset before
    /// adopting a file. Raw legacy AI is Danish even without a canonical ID.
    static func permitsPlayback(_ episode: PodcastEpisode, articleID: String?,
                                language: ArticleContentLanguage) -> Bool {
        guard PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: articleID) else { return false }
        if let canonical = articleID ?? episode.articleId {
            return permitsArticleID(canonical, language: language)
        }
        return !episode.isAINarration || language == .danish
    }
}
