import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PodcastPlayerManager: ObservableObject {
    static let shared = PodcastPlayerManager()

    enum SleepTimerOption: String, CaseIterable, Identifiable {
        case off
        case fifteenMinutes
        case thirtyMinutes
        case fortyFiveMinutes
        case endOfEpisode

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .fifteenMinutes: return "15 min"
            case .thirtyMinutes: return "30 min"
            case .fortyFiveMinutes: return "45 min"
            case .endOfEpisode: return "Ved slutning"
            }
        }

        var interval: TimeInterval? {
            switch self {
            case .off, .endOfEpisode:
                return nil
            case .fifteenMinutes:
                return 15 * 60
            case .thirtyMinutes:
                return 30 * 60
            case .fortyFiveMinutes:
                return 45 * 60
            }
        }
    }

    @Published private(set) var currentEpisode: PodcastEpisode?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    var isFullPlayerPresented: Bool = false {
        didSet { if oldValue != isFullPlayerPresented { objectWillChange.send() } }
    }
    @Published private(set) var queue: [PodcastEpisode] = []
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var sleepTimerOption: SleepTimerOption = .off
    @Published private(set) var sleepTimerEndsAt: Date?
    /// Shown when the user tries to play audio offline without a local download.
    private(set) var offlinePlaybackMessage: String? {
        didSet { if oldValue != offlinePlaybackMessage { objectWillChange.send() } }
    }
    /// A local asset is being verified; any previous currentEpisode/isPlaying
    /// still describes the previous item, never this requested title.
    private(set) var offlinePreparationTitle: String?
    private(set) var offlinePreparationID: UUID?

    func clearOfflinePlaybackMessage() {
        offlinePlaybackMessage = nil
    }

    // Playback metrics (Phase 1A)
    @Published private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    @Published private(set) var isPlaybackLikelyToKeepUp: Bool = false
    @Published private(set) var stallCount: Int = 0
    @Published private(set) var timeToFirstAudio: TimeInterval?
    @Published private(set) var lastCacheResult: PodcastAudioCacheResult?
    private(set) var playbackStartRequestedAt: Date?
    private(set) var firstAudioStartedAt: Date?

    private(set) var player: AVPlayer
    private var currentAudioURL: URL?
    private var currentAudioAsset: PodcastAudioAsset?
    private var deferredAudioAsset: PodcastAudioAsset?
    private var assetPreparation: (ticket: PodcastPlaybackSessionCoordinator.PreparationTicket, displayID: UUID, task: Task<Void, Never>?)?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var sleepTimer: Timer?
    private var nowPlayingInfo: [String: Any] = [:]
    private var cachedArtworkIdentifier: String?
    private var lastPublishedSecond: Int = -1
    private var remoteCommandsConfigured = false
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var artworkTask: Task<Void, Never>?
    private let progressStore: PodcastPlaybackProgressStore
    private lazy var sessionCoordinator = PodcastPlaybackSessionCoordinator(store: progressStore, effects: .init(
        cancelCallbacks: { [weak self] in self?.cancelPlaybackCallbacks() },
        stopPlayback: { [weak self] in
            self?.wantsPlayback = false
            self?.player.pause()
            self?.player.replaceCurrentItem(with: nil)
        },
        clearPresentation: { [weak self] in self?.clearPlaybackPresentation() },
        clearNowPlaying: { [weak self] in self?.clearNowPlaying() },
        deactivateAudio: { [weak self] in self?.deactivateAudioSessionForOtherApps() }
    ))

    private var wantsPlayback = false
    private var hasStartedAudioThisSession = false
    private var lastStallIncrementAt: Date?
    private var lastProgressPersistAt: Date?
    private var isHandlingProgressTick = false
    private var isAdoptingItem = false
    private var playbackStateUpdateTask: Task<Void, Never>?
    private var currentArticleId: String?
    private var availabilitySubscription: AnyCancellable?
    private var deferredCacheEpisode: PodcastEpisode?
    private var deferredCacheArticleID: String?
    private var deferredFavoriteAccess: FavoritesOfflineCoordinator.AccessTicket?
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var resumeSeekState = PodcastResumeSeekState()
    private var pendingStartTicket: PodcastPlaybackSessionCoordinator.StartTicket?

    private static var preferredForwardBufferSeconds: TimeInterval {
        FeatureFlags.podcastForwardBufferSeconds
    }

    private func permitsSelectedLanguage(_ episode: PodcastEpisode, articleID: String?) -> Bool {
        ArticleAudioLanguagePolicy.permitsPlayback(episode, articleID: articleID,
            language: PreferencesManager.shared.articleLanguage)
    }

    /// Language selection retires incompatible sessions and preparation using
    /// their existing cancellation/progress lifecycle. Cached bytes stay intact.
    func reconcileContentLanguage() {
        if let pending = assetPreparation,
           !ArticleAudioLanguagePolicy.permitsArticleID(pending.ticket.asset.canonicalArticleID,
               language: PreferencesManager.shared.articleLanguage) {
            cancelOfflinePreparation()
            if currentEpisode == nil { isFullPlayerPresented = false }
        }
        if let currentEpisode, !permitsSelectedLanguage(currentEpisode, articleID: currentArticleId) {
            closePlayer()
        }
        queue = episodesForSelectedLanguage(queue)
    }

    private func episodesForSelectedLanguage(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        episodes.filter { episode in
            let canonical = episode.articleId ?? PodcastAvailabilityService.model.audioAsset(for: episode)?.canonicalArticleID
            return permitsSelectedLanguage(episode, articleID: canonical)
        }
    }

    var hasActiveEpisode: Bool {
        currentEpisode != nil
    }

    /// True while an episode is loaded (playing or paused). Used to defer heavy
    /// background work that competes with streaming for memory and CPU.
    var isPlaybackSessionActive: Bool {
        currentEpisode != nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private init() {
        progressStore = PodcastProgressRuntime.store
        let configuredPlayer = AVPlayer()
        configuredPlayer.automaticallyWaitsToMinimizeStalling = true
        player = configuredPlayer
        _ = sessionCoordinator
        progressStore.onContextInvalidated = { [weak self] in
            self?.sessionCoordinator.contextInvalidated()
        }
        availabilitySubscription = PodcastAvailabilityService.model.changes.sink { [weak self] in
            self?.applyAvailability()
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        sleepTimer?.invalidate()
        playbackStateUpdateTask?.cancel()
        artworkTask?.cancel()
        playerObservation?.invalidate()
        itemObservations.forEach { $0.invalidate() }
    }

    /// True means this request was accepted, not that audio or its seek finished.
    @discardableResult
    func play(episode: PodcastEpisode, articleId: String? = nil,
              audioStartSeconds: TimeInterval? = nil,
              routeIsCurrent: (@MainActor () -> Bool)? = nil) -> Bool {
        var stage = PodcastPlaybackPolicy.AdmissionStage.entry
        let accepted = startPlayback(episode: episode, articleId: articleId, reason: .userInitiated,
            audioStartSeconds: audioStartSeconds, routeIsCurrent: routeIsCurrent,
            admissionStage: { stage = $0 })
        AppDiagnostics.recordOperational(stage.diagnosticCode(accepted: accepted))
        return accepted
    }

    func cancelIncomingLinkSeek() {
        if sessionCoordinator.cancelIncomingPositioning() { clearPreparationDisplay() }
    }

    @discardableResult
    func cancelOfflinePreparation(id: UUID) -> Bool {
        guard let current = assetPreparation, current.displayID == id, offlinePreparationID == id else { return false }
        cancelOfflinePreparation()
        return true
    }

    func cancelOfflinePreparation() {
        sessionCoordinator.invalidatePreparation()
        clearPreparationDisplay()
    }

    private func clearPreparationDisplay(expected: PodcastPlaybackSessionCoordinator.PreparationTicket? = nil, cancelTask: Bool = true) {
        if let expected, assetPreparation?.ticket != expected { return }
        let task = assetPreparation?.task
        assetPreparation = nil
        if cancelTask { task?.cancel() }
        // Revoke the request before notifying observers. A reentrant new request
        // owns its own title/ID and cannot be cleared by this older dismissal.
        objectWillChange.send()
        guard assetPreparation == nil else { return }
        offlinePreparationID = nil
        offlinePreparationTitle = nil
    }

    private func publishPreparation(_ request: PodcastPlaybackSessionCoordinator.PreparationTicket, title: String) -> Bool {
        guard let current = assetPreparation, current.ticket == request else { return false }
        objectWillChange.send()
        guard assetPreparation?.ticket == request, sessionCoordinator.isCurrent(request) else { return false }
        offlinePreparationID = current.displayID
        offlinePreparationTitle = title
        return true
    }

    @discardableResult
    private func startPlayback(
        episode: PodcastEpisode,
        articleId: String? = nil,
        reason: PodcastPlaybackPolicy.StartReason,
        audioStartSeconds: TimeInterval? = nil,
        routeIsCurrent: (@MainActor () -> Bool)? = nil,
        completedPreparation: PodcastPlaybackSessionCoordinator.PreparationTicket? = nil,
        expectedAccess: FavoritesOfflineCoordinator.AccessTicket? = nil,
        admissionStage: (@MainActor (PodcastPlaybackPolicy.AdmissionStage) -> Void)? = nil
    ) -> Bool {
        admissionStage?(.entry)
        guard !isAdoptingItem, progressStore.hasPlaybackAccess else { return false }
        isAdoptingItem = true
        defer { isAdoptingItem = false }
        let origin = sessionCoordinator.contextTicket
        var requestArticleID = articleId ?? episode.articleId
        func requestIsCurrent() -> Bool {
            guard progressStore.hasPlaybackAccess, origin == sessionCoordinator.contextTicket,
                  routeIsCurrent?() ?? true,
                  progressStore.hasPlaybackAccess, origin == sessionCoordinator.contextTicket,
                  expectedAccess.map({ OfflineManager.shared.isCurrentAccess($0) }) ?? true else { return false }
            return progressStore.hasPlaybackAccess && origin == sessionCoordinator.contextTicket
                && permitsSelectedLanguage(episode, articleID: requestArticleID)
        }
        admissionStage?(.request)
        if let completedPreparation {
            guard sessionCoordinator.isCurrent(completedPreparation), requestIsCurrent() else { return false }
            clearPreparationDisplay(expected: completedPreparation, cancelTask: false)
            guard sessionCoordinator.consumePreparation(completedPreparation), requestIsCurrent() else { return false }
        } else {
            cancelOfflinePreparation()
        }
        guard requestIsCurrent(), audioStartSeconds == nil || PodcastPlaybackPolicy.explicitStart(audioStartSeconds) != nil else { return false }
        admissionStage?(.publication)
        let availability = PodcastAvailabilityService.model
        guard PodcastAvailabilityModel.hasConsistentIdentity(episode, articleID: articleId) else {
            offlinePlaybackMessage = "Artiklen og lyden kunne ikke matches."
            return false
        }
        PodcastAvailabilityService.recordPlayback(episode, articleID: articleId)
        guard requestIsCurrent() else { return false }
        guard availability.allows(episode, articleID: articleId) else {
            offlinePlaybackMessage = availability.unavailableMessage(for: episode, articleID: articleId)
            return false
        }
        admissionStage?(.recording)
        guard let audioURL = episode.audioURL,
              PodcastAudioURLValidator.isPlayableAudioURL(audioURL) else {
            return false
        }

        let acceptedAsset = availability.audioAsset(for: episode, articleID: articleId)
        guard let identity = PodcastPlaybackPolicy.articleIdentity(for: episode, requestedArticleID: articleId,
            acceptedAsset: acceptedAsset) else { return false }
        let resolvedArticleID = identity.articleID
        requestArticleID = resolvedArticleID
        guard requestIsCurrent() else { return false }
        if let completedPreparation, acceptedAsset != completedPreparation.asset { return false }
        let canReuseItem = currentAudioAsset == acceptedAsset && PodcastPlaybackPolicy.canReuseItem(current: currentEpisode, requested: episode,
            currentArticleID: currentArticleId, requestedArticleID: resolvedArticleID, currentAudioURL: currentAudioURL,
            itemHasFailed: player.currentItem?.status == .failed)

        if canReuseItem && player.currentItem != nil {
            admissionStage?(.reuse)
            guard requestIsCurrent() else { return false }
            var adopted: PodcastPlaybackSessionCoordinator.Ticket?
            var accepted = false
            defer { if !accepted, let adopted { sessionCoordinator.abort(adopted) } }
            if let audioStartSeconds, let item = player.currentItem {
                guard let ticket = renewSessionForCurrentItem(item, expectedContext: origin) else { return false }
                adopted = ticket
                guard requestIsCurrent(), sessionCoordinator.isCurrent(ticket) else { return false }
                player.pause()
                resumeSeekState.prepareEpisode(savedPosition: nil, explicitStart: audioStartSeconds)
                pendingStartTicket = sessionCoordinator.beginPositioning(ticket, routeIsCurrent: routeIsCurrent)
                guard let pendingStartTicket, sessionCoordinator.isCurrent(pendingStartTicket), requestIsCurrent() else { return false }
                wantsPlayback = true
                updatePublishedPlaybackState()
            } else {
                let beforeResume = sessionCoordinator.currentTicket
                guard resumeOwnedSession(routeIsCurrent: routeIsCurrent) else { return false }
                if beforeResume != sessionCoordinator.currentTicket { adopted = sessionCoordinator.currentTicket }
            }
            guard requestIsCurrent(), let finalOwner = sessionCoordinator.currentTicket,
                  sessionCoordinator.isCurrent(finalOwner) else { return false }
            admissionStage?(.presentation)
            isFullPlayerPresented = PodcastPlaybackPolicy.shouldPresentFullPlayer(
                reason: reason, isPresented: isFullPlayerPresented
            )
            accepted = requestIsCurrent() && sessionCoordinator.isCurrent(finalOwner)
            return accepted
        }

        admissionStage?(.offline)
        let originalFavoriteAccess = resolvedArticleID.flatMap { OfflineManager.shared.captureAccess(articleID: $0) }
        let playbackResolution: PodcastPlaybackURLResolution
        if let acceptedAsset {
            playbackResolution = OfflineManager.shared.resolvePlaybackURL(asset: acceptedAsset, articleID: resolvedArticleID)
        } else {
            // Legacy/unbound media can stream, but URL bytes cannot prove an
            // offline asset's accepted source or canonical article identity.
            playbackResolution = PodcastPlaybackURLResolution(url: audioURL, cacheResult: .miss)
        }
        guard requestIsCurrent() else { return false }
        if PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: playbackResolution.url,
            isOnline: OfflineManager.shared.isOnline, alreadyPrepared: completedPreparation != nil),
           let acceptedAsset, let originalFavoriteAccess {
            admissionStage?(.preparation)
            return prepareOfflinePlayback(asset: acceptedAsset, access: originalFavoriteAccess, episode: episode,
                articleId: resolvedArticleID, reason: reason, audioStartSeconds: audioStartSeconds, routeIsCurrent: routeIsCurrent)
        }
        guard PodcastPlaybackPolicy.canStart(
            playbackURL: playbackResolution.url,
            isOnline: OfflineManager.shared.isOnline
        ) else {
            // Keep the previous episode/item and its metadata intact when the
            // selected episode cannot be opened offline.
            offlinePlaybackMessage = availability.offlineAssetEvidenceExhausted
                ? "Offlineadgang til lyd kunne ikke bekræftes. Genstart appen, og prøv igen."
                : "Ikke downloadet — gem artiklen på Min side, mens du er online, for at lytte offline."
            if reason == .automaticAdvance { pause(recordExplicitIntent: true, allowDeferredCache: true) }
            return false
        }

        admissionStage?(.session)
        guard requestIsCurrent() else { return false }
        let previousTicket = sessionCoordinator.currentTicket
        if let previousTicket { persistPlaybackProgress(force: true, ticket: previousTicket) }
        guard requestIsCurrent(),
              previousTicket == sessionCoordinator.currentTicket else { return false }
        guard let session = sessionCoordinator.beginSession(
            episodeID: episode.id, articleID: resolvedArticleID, expectedContext: origin
        ) else { return false }
        var accepted = false
        defer { if !accepted { sessionCoordinator.abort(session.ticket) } }
        detachPlaybackCallbacks()
        resumeSeekState.prepareEpisode(savedPosition: session.resumePosition, explicitStart: audioStartSeconds)
        pendingStartTicket = nil
        if resumeSeekState.pendingPosition != nil {
            pendingStartTicket = sessionCoordinator.beginPositioning(session.ticket, routeIsCurrent: routeIsCurrent)
            guard let pendingStartTicket, sessionCoordinator.isCurrent(pendingStartTicket) else { return false }
        }
        admissionStage?(.item)
        configureAudioSessionIfNeeded()
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }

        currentArticleId = resolvedArticleID

        currentEpisode = episode
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        currentAudioURL = audioURL
        currentAudioAsset = acceptedAsset
        currentTime = 0
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        duration = 0
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        lastProgressPersistAt = nil
        nowPlayingInfo = [:]
        cachedArtworkIdentifier = nil
        lastPublishedSecond = -1
        resetPlaybackMetrics()
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        playbackStartRequestedAt = Date()
        wantsPlayback = true
        AppDiagnostics.breadcrumb("podcast_play:\(episode.id)")

        lastCacheResult = playbackResolution.cacheResult
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        AppDiagnostics.breadcrumb("podcast_cache_\(playbackResolution.cacheResult.rawValue)")

        offlinePlaybackMessage = nil
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }

        if playbackResolution.cacheResult == .miss {
            // Defer disk caching until playback ends — downloading the full file
            // while streaming doubles network/memory pressure and has caused jetsam.
            deferredAudioAsset = acceptedAsset
            deferredCacheEpisode = episode
            deferredCacheArticleID = resolvedArticleID
            deferredFavoriteAccess = originalFavoriteAccess
        } else {
            deferredAudioAsset = nil
        }

        let item = makePlayerItem(url: playbackResolution.url)
        detachItemObservers()
        player.volume = 1.0
        volume = 1.0
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        // Replacing an item can retain the prior player's nonzero rate. Keep
        // the new item paused until its owned positioning succeeds or the
        // validated immediate-start path explicitly starts it below.
        player.pause()
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        player.replaceCurrentItem(with: item)
        bindPlaybackCallbacks(to: item, ticket: session.ticket)
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        let shouldDeferPlaybackForResume = resumeSeekState.pendingPosition != nil
        if shouldDeferPlaybackForResume {
            wantsPlayback = true
            updatePublishedPlaybackState()
        } else {
            // Cached audio is local, so skip the wait-to-minimize-stalling delay
            // and start instantly. Streaming misses keep the gentle start.
            let startImmediately = playbackResolution.cacheResult == .hit
            beginPlayback(useImmediate: startImmediately)
        }
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }
        admissionStage?(.presentation)
        isFullPlayerPresented = PodcastPlaybackPolicy.shouldPresentFullPlayer(
            reason: reason, isPresented: isFullPlayerPresented
        )
        guard retainsAdoption(session.ticket), requestIsCurrent() else { return false }

        refreshNowPlayingMetadataIfNeeded(force: true)
        updateNowPlayingPlaybackState()
        // Live Activity intentionally disabled — native Now Playing only.
        PodcastLiveActivityService.shared.endActivity()
        AnalyticsService.shared.trackPodcastPlay(episode: episode, articleId: resolvedArticleID)
        accepted = requestIsCurrent() && sessionCoordinator.isCurrent(session.ticket)
        return accepted
    }

    private func prepareOfflinePlayback(asset: PodcastAudioAsset, access: FavoritesOfflineCoordinator.AccessTicket,
        episode: PodcastEpisode, articleId: String?, reason: PodcastPlaybackPolicy.StartReason,
        audioStartSeconds: TimeInterval?, routeIsCurrent: (@MainActor () -> Bool)?) -> Bool {
        let currentRoute: @MainActor () -> Bool = { [weak self] in
            guard let self, self.permitsSelectedLanguage(episode, articleID: asset.canonicalArticleID),
                  routeIsCurrent?() ?? true else { return false }
            return self.permitsSelectedLanguage(episode, articleID: asset.canonicalArticleID)
        }
        guard let request = sessionCoordinator.beginPreparation(asset: asset, routeIsCurrent: currentRoute,
            accessIsCurrent: { OfflineManager.shared.isCurrentAccess(access) }) else { return false }
        let clearClosedPresentation: @MainActor () -> Void = { [weak self] in
            guard let self, !self.progressStore.hasPlaybackAccess else { return }
            self.clearPlaybackPresentation()
        }
        assetPreparation = (request, UUID(), nil)
        offlinePlaybackMessage = nil
        guard publishPreparation(request, title: episode.title), sessionCoordinator.isCurrent(request) else {
            sessionCoordinator.discardPreparation(request)
            clearPreparationDisplay(expected: request); return false
        }
        guard sessionCoordinator.performPreparationPublication(request, publish: {
            self.isFullPlayerPresented = PodcastPlaybackPolicy.shouldPresentFullPlayer(reason: reason, isPresented: self.isFullPlayerPresented)
        }, clearClosedPresentation: clearClosedPresentation) else {
            sessionCoordinator.discardPreparation(request)
            clearPreparationDisplay(expected: request); return false
        }
        let origin = sessionCoordinator.contextTicket
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.sessionCoordinator.prepare(request) {
                await OfflineManager.shared.preparePlaybackAsset(asset, articleID: access.articleID)
            }
            guard let prepared = result else {
                self.sessionCoordinator.discardPreparation(request)
                self.clearPreparationDisplay(expected: request, cancelTask: false); return
            }
            guard prepared else {
                self.clearPreparationDisplay(expected: request, cancelTask: false)
                guard self.sessionCoordinator.consumePreparation(request) else { return }
                if self.currentEpisode == nil {
                    guard self.sessionCoordinator.performPreparationPublication(request, isResult: true, publish: {
                        self.isFullPlayerPresented = false
                    }, clearClosedPresentation: clearClosedPresentation) else { return }
                }
                guard self.sessionCoordinator.performPreparationPublication(request, isResult: true, publish: {
                    self.offlinePlaybackMessage = "Den gemte lyd kunne ikke bekræftes. Hent artiklen igen, mens du er online."
                }, clearClosedPresentation: clearClosedPresentation) else { return }
                if reason == .automaticAdvance { self.pause(recordExplicitIntent: true, allowDeferredCache: false) }
                return
            }
            let started = self.startPlayback(episode: episode, articleId: articleId, reason: reason,
                audioStartSeconds: audioStartSeconds, routeIsCurrent: currentRoute,
                completedPreparation: request, expectedAccess: access)
            if !started, origin == self.sessionCoordinator.contextTicket,
               self.sessionCoordinator.isCurrentPreparationResult(request), self.offlinePlaybackMessage == nil {
                if self.currentEpisode == nil {
                    guard self.sessionCoordinator.performPreparationPublication(request, isResult: true, publish: {
                        self.isFullPlayerPresented = false
                    }, clearClosedPresentation: clearClosedPresentation) else { return }
                }
                _ = self.sessionCoordinator.performPreparationPublication(request, isResult: true, publish: {
                    self.offlinePlaybackMessage = "Den gemte lyd kunne ikke bekræftes. Hent artiklen igen, mens du er online."
                }, clearClosedPresentation: clearClosedPresentation)
            }
        }
        if let displayID = assetPreparation?.displayID, assetPreparation?.ticket == request,
           sessionCoordinator.isCurrent(request), assetPreparation?.ticket == request {
            assetPreparation = (request, displayID, task)
        } else { task.cancel() }
        return sessionCoordinator.isCurrent(request)
    }

    func pause() {
        guard !isAdoptingItem else { return }
        pause(recordExplicitIntent: true, allowDeferredCache: true)
    }

    private func pause(recordExplicitIntent: Bool, allowDeferredCache: Bool) {
        cancelOfflinePreparation()
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket) else { return }
        if recordExplicitIntent { sessionCoordinator.recordExplicitAction() }
        wantsPlayback = false
        resumeSeekState.invalidate()
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        persistPlaybackProgress(force: true, ticket: ticket)
        guard sessionCoordinator.isCurrent(ticket) else { return }
        updatePublishedPlaybackState()
        if let episodeID = currentEpisode?.id {
            AppDiagnostics.breadcrumb("podcast_pause:\(episodeID)")
        }
        updateNowPlayingPlaybackState()
        if allowDeferredCache { scheduleDeferredCacheDownloadIfNeeded(ticket: ticket) }
    }

    func resume() {
        guard !isAdoptingItem else { return }
        if player.currentItem?.status == .failed, let episode = currentEpisode {
            // Failed AVPlayerItems cannot be resumed. Re-enter the same guarded
            // adoption path used by the article button, retaining a pending seek.
            let explicitStart = resumeSeekState.hasExplicitStart ? resumeSeekState.pendingPosition : nil
            _ = startPlayback(episode: episode, articleId: currentArticleId,
                reason: .resumeAfterFailure, audioStartSeconds: explicitStart)
            return
        }
        cancelOfflinePreparation()
        isAdoptingItem = true
        defer { isAdoptingItem = false }
        resumeOwnedSession()
    }

    @discardableResult
    private func resumeOwnedSession(routeIsCurrent: (@MainActor () -> Bool)? = nil) -> Bool {
        var adopted: PodcastPlaybackSessionCoordinator.Ticket?
        var accepted = false
        defer { if !accepted, let adopted { sessionCoordinator.abort(adopted) } }
        guard routeIsCurrent?() ?? true,
              let currentEpisode, let original = sessionCoordinator.currentTicket,
              sessionCoordinator.isCurrent(original), let item = player.currentItem else { return false }
        guard permitsSelectedLanguage(currentEpisode, articleID: currentArticleId) else {
            reconcileContentLanguage(); return false
        }
        guard PodcastAvailabilityService.model.allows(currentEpisode, articleID: currentArticleId) else {
            applyAvailability(); return false
        }
        guard sessionCoordinator.isCurrent(original), routeIsCurrent?() ?? true else { return false }
        if resumeSeekState.isCompleted {
            guard let session = sessionCoordinator.beginSession(episodeID: currentEpisode.id, articleID: currentArticleId) else { return false }
            adopted = session.ticket
            pendingStartTicket = nil
            detachPlaybackCallbacks()
            bindPlaybackCallbacks(to: item, ticket: session.ticket)
            cachedArtworkIdentifier = nil
            refreshNowPlayingMetadataIfNeeded(force: false)
        } else {
            sessionCoordinator.recordExplicitAction()
        }
        resumeSeekState.invalidate()
        item.cancelPendingSeeks()
        resumeSeekState.prepareExplicitResume()
        guard let owner = sessionCoordinator.currentTicket, retainsAdoption(owner), routeIsCurrent?() ?? true else { return false }
        if resumeSeekState.pendingPosition != nil {
            if pendingStartTicket == nil || routeIsCurrent != nil {
                pendingStartTicket = sessionCoordinator.beginPositioning(owner, routeIsCurrent: routeIsCurrent)
            }
            guard let pendingStartTicket, sessionCoordinator.isCurrent(pendingStartTicket) else {
                sessionCoordinator.cancelIncomingPositioning(); return false
            }
        }
        wantsPlayback = true
        if playbackStartRequestedAt == nil {
            playbackStartRequestedAt = Date()
        }
        if resumeSeekState.pendingPosition != nil || resumeSeekState.activeRequest != nil {
            updatePublishedPlaybackState()
        } else {
            beginPlayback(useImmediate: true)
        }
        guard retainsAdoption(owner) else { return false }
        AppDiagnostics.breadcrumb("podcast_resume:\(currentEpisode.id)")
        updateNowPlayingPlaybackState()
        accepted = (routeIsCurrent?() ?? true) && sessionCoordinator.isCurrent(owner)
        return accepted
    }

    func togglePlayPause() {
        wantsPlayback ? pause() : resume()
    }

    func seek(to seconds: TimeInterval) {
        guard !isAdoptingItem else { return }
        cancelOfflinePreparation()
        isAdoptingItem = true
        defer { isAdoptingItem = false }
        guard seconds.isFinite, duration > 0, duration <= PodcastProgressRecordCodec.maximumDurationSeconds,
              let item = player.currentItem,
              let original = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(original),
              let ticket = renewSessionForCurrentItem(item),
              let request = sessionCoordinator.beginManualSeek(ticket) else { return }
        resumeSeekState.prepareManualSeek()
        player.currentItem?.cancelPendingSeeks()
        let bounded = max(0, min(seconds, duration))
        currentTime = bounded
        guard retainsAdoption(ticket) else { return }
        let time = CMTime(seconds: bounded, preferredTimescale: 600)
        player.seek(to: time) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                let actual = self.player.currentTime().seconds
                guard actual.isFinite,
                      self.sessionCoordinator.finishManualSeek(request, observedPosition: max(0, actual)) else { return }
                self.currentTime = max(0, actual)
                guard self.retainsAdoption(ticket) else { return }
                if finished {
                    self.persistPlaybackProgress(force: true, ticket: ticket)
                }
                guard self.sessionCoordinator.isCurrent(ticket) else { return }
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    func seekForward(seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func openFullPlayer() {
        reconcileContentLanguage()
        guard currentEpisode != nil, let ticket = sessionCoordinator.currentTicket,
              sessionCoordinator.isCurrent(ticket) else { return }
        isFullPlayerPresented = true
        _ = retainsAdoption(ticket)
    }

    func dismissFullPlayer() {
        isFullPlayerPresented = false
    }

    func closePlayer() {
        cancelOfflinePreparation()
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket) else { return }
        persistPlaybackProgress(force: true, ticket: ticket)
        guard sessionCoordinator.isCurrent(ticket) else { return }
        sessionCoordinator.close()
    }

    private func cancelPlaybackCallbacks() {
        clearPreparationDisplay()
        deferredAudioAsset = nil
        deferredFavoriteAccess = nil
        deferredCacheEpisode = nil
        deferredCacheArticleID = nil
        detachPlaybackCallbacks()
        sleepTimer?.invalidate()
        sleepTimer = nil
        pendingStartTicket = nil
        resumeSeekState.prepareEpisode(savedPosition: nil)
    }

    private func clearPlaybackPresentation() {
        currentEpisode = nil
        currentArticleId = nil
        currentAudioURL = nil
        currentAudioAsset = nil
        currentTime = 0
        duration = 0
        isFullPlayerPresented = false
        queue = []
        sleepTimerEndsAt = nil
        sleepTimerOption = .off
        lastProgressPersistAt = nil
        offlinePlaybackMessage = nil
        resetPlaybackMetrics()
        updatePublishedPlaybackState()
    }

    /// A one-shot synchronous publisher may invalidate ownership during willSet.
    /// Adoption is serialized so a stale setter cannot overwrite a newer item;
    /// clear any just-committed old UI value before leaving the rejected start.
    private func retainsAdoption(_ ticket: PodcastPlaybackSessionCoordinator.Ticket) -> Bool {
        guard !sessionCoordinator.isCurrent(ticket) else { return true }
        if sessionCoordinator.currentTicket == nil || !progressStore.hasPlaybackAccess {
            clearPlaybackPresentation()
            clearNowPlaying()
        }
        return false
    }

    private func clearNowPlaying() {
        nowPlayingInfo = [:]
        cachedArtworkIdentifier = nil
        lastPublishedSecond = -1
        PodcastLiveActivityService.shared.endActivity()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func scheduleDeferredCacheDownloadIfNeeded(ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard sessionCoordinator.isCurrent(ticket) else { return }
        guard FeatureFlags.podcastCacheAfterPlay else {
            deferredAudioAsset = nil
            return
        }
        guard !wantsPlayback, !isPlaying else { return }
        guard let originalAccess = deferredFavoriteAccess, let originalAsset = deferredAudioAsset else { return }
        guard let episode = deferredCacheEpisode,
              PodcastAvailabilityService.model.audioAsset(for: episode, articleID: deferredCacheArticleID) == originalAsset else {
            deferredAudioAsset = nil
            deferredCacheEpisode = nil
            deferredCacheArticleID = nil
            return
        }
        deferredAudioAsset = nil
        deferredFavoriteAccess = nil
        OfflineManager.shared.savePodcastForOffline(ticket: originalAccess, asset: originalAsset)
    }

    private func applyAvailability() {
        let availability = PodcastAvailabilityService.model
        if let pending = assetPreparation, !availability.availableAudioAssets.contains(pending.ticket.asset) {
            sessionCoordinator.discardPreparation(pending.ticket)
            clearPreparationDisplay(expected: pending.ticket)
        }
        let plan = availability.playbackPlan(current: currentEpisode, articleID: currentArticleId, queue: queue)
        let invalidLocalAsset = lastCacheResult == .hit && currentAudioAsset.map { asset in
            guard let episode = currentEpisode else { return true }
            return availability.audioAsset(for: episode, articleID: currentArticleId) != asset
        } == true
        if plan.stopCurrent || invalidLocalAsset {
            let message = currentEpisode.map { PodcastAvailabilityService.model.unavailableMessage(for: $0, articleID: currentArticleId) }
            sessionCoordinator.close()
            offlinePlaybackMessage = message
        }
        queue = plan.queue
    }

    func prepareQueueIfNeeded(episodes: [PodcastEpisode]) {
        guard currentEpisode != nil, let ticket = sessionCoordinator.currentTicket,
              sessionCoordinator.isCurrent(ticket) else { queue = []; return }
        let availability = PodcastAvailabilityService.model
        PodcastAvailabilityService.recordEpisodes(episodes)
        let episodes = episodesForSelectedLanguage(episodes.filter { availability.allows($0) })
        applyAvailability()
        guard sessionCoordinator.isCurrent(ticket), currentEpisode != nil else { queue = []; return }
        let prepared = PodcastPlaybackQueue.prepared(
            existing: episodesForSelectedLanguage(queue), candidates: episodes, currentEpisode: currentEpisode
        )
        if prepared != queue { queue = prepared }
    }

    func playFromQueue(_ episode: PodcastEpisode) {
        play(episode: episode)
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        guard let currentIndex = rates.firstIndex(of: playbackRate) else {
            setPlaybackRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % rates.count
        setPlaybackRate(rates[nextIndex])
    }

    func setPlaybackRate(_ rate: Float) {
        let owner = currentEpisode == nil ? nil : sessionCoordinator.currentTicket
        guard currentEpisode == nil || owner.map(sessionCoordinator.isCurrent) == true else { return }
        let clamped = max(0.5, min(rate, 2.0))
        playbackRate = clamped
        // A rate chosen without an episode remains a local preference. It is
        // not permission to touch an old player or publish its system state.
        guard let owner, retainsAdoption(owner) else { return }
        if isPlaying {
            player.rate = clamped
        }
        guard retainsAdoption(owner) else { return }
        refreshNowPlayingMetadataIfNeeded(force: false)
        updateNowPlayingPlaybackState()
    }

    func setVolume(_ newValue: Float) {
        // Keep player at full level; system volume is controlled via MPVolumeView in the UI.
        volume = 1.0
        player.volume = 1.0
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        sessionCoordinator.invalidateSleepTimer()
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        guard let owner = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(owner) else {
            sleepTimerOption = .off
            return
        }
        sleepTimerOption = option

        if let interval = option.interval, let timerTicket = sessionCoordinator.beginSleepTimer() {
            sleepTimerEndsAt = Date().addingTimeInterval(interval)
            sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sessionCoordinator.consumeSleepTimer(timerTicket) else { return }
                    self.pause()
                    self.sleepTimerOption = .off
                    self.sleepTimerEndsAt = nil
                    self.sleepTimer = nil
                }
            }
        }
    }

    // MARK: - Playback control internals

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = Self.preferredForwardBufferSeconds
        return item
    }

    private func beginPlayback(useImmediate: Bool) {
        if let currentEpisode, !permitsSelectedLanguage(currentEpisode, articleID: currentArticleId) {
            reconcileContentLanguage(); return
        }
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket), let currentEpisode,
              PodcastAvailabilityService.model.allows(currentEpisode, articleID: currentArticleId) else {
            applyAvailability(); return
        }
        updatePublishedPlaybackState()
        guard sessionCoordinator.isCurrent(ticket), permitsSelectedLanguage(currentEpisode, articleID: currentArticleId) else { return }

        if useImmediate {
            player.playImmediately(atRate: playbackRate)
        } else {
            player.play()
            player.rate = playbackRate
        }

        updatePublishedPlaybackState()
    }

    private func resetPlaybackMetrics() {
        playbackStartRequestedAt = nil
        firstAudioStartedAt = nil
        timeToFirstAudio = nil
        stallCount = 0
        hasStartedAudioThisSession = false
        lastStallIncrementAt = nil
        lastCacheResult = nil
    }

    private func recordFirstAudioIfNeeded() {
        guard !hasStartedAudioThisSession, let ticket = sessionCoordinator.currentTicket,
              sessionCoordinator.isCurrent(ticket) else { return }
        hasStartedAudioThisSession = true
        firstAudioStartedAt = Date()

        if let start = playbackStartRequestedAt, let firstAudio = firstAudioStartedAt {
            let elapsed = firstAudio.timeIntervalSince(start)
            timeToFirstAudio = elapsed
            guard retainsAdoption(ticket) else { return }
            AppDiagnostics.breadcrumb(String(format: "podcast_ttf_audio:%.2fs", elapsed))
        }
    }

    private func recordStallIfNeeded(reason: String) {
        guard hasStartedAudioThisSession, let ticket = sessionCoordinator.currentTicket,
              sessionCoordinator.isCurrent(ticket) else { return }

        let now = Date()
        if let lastStall = lastStallIncrementAt, now.timeIntervalSince(lastStall) < 1.0 {
            return
        }

        lastStallIncrementAt = now
        stallCount += 1
        guard retainsAdoption(ticket) else { return }
        AppDiagnostics.breadcrumb("podcast_stall:\(stallCount):\(reason)")
    }

    private func updatePublishedPlaybackState() {
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket),
              let item = player.currentItem else {
            timeControlStatus = .paused
            isPlaying = false
            isBuffering = false
            isPlaybackLikelyToKeepUp = false
            return
        }

        timeControlStatus = player.timeControlStatus
        guard retainsAdoption(ticket) else { return }
        isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
        guard retainsAdoption(ticket) else { return }
        isPlaying = player.timeControlStatus == .playing
        guard retainsAdoption(ticket) else { return }

        if item.status == .failed {
            isPlaying = false
            guard retainsAdoption(ticket) else { return }
            isBuffering = false
            guard retainsAdoption(ticket) else { return }
            wantsPlayback = false
            offlinePlaybackMessage = "Lyden kunne ikke indlæses. Prøv igen."
            guard retainsAdoption(ticket) else { return }
            AppDiagnostics.breadcrumb("podcast_item_failed")
            return
        }

        let itemNotReady = item.status != .readyToPlay
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let bufferEmptyWhileWantingPlay = wantsPlayback && item.isPlaybackBufferEmpty && item.status == .readyToPlay
        let cannotKeepUp = wantsPlayback
            && item.status == .readyToPlay
            && !item.isPlaybackLikelyToKeepUp
            && (player.rate > 0 || waiting)

        isBuffering = wantsPlayback && !isPlaying && (resumeSeekState.pendingPosition != nil || itemNotReady || waiting || bufferEmptyWhileWantingPlay || cannotKeepUp)
        guard retainsAdoption(ticket) else { return }

        if isPlaying {
            recordFirstAudioIfNeeded()
        }
        guard retainsAdoption(ticket) else { return }
        applyPendingResumePositionIfNeeded()
        guard retainsAdoption(ticket) else { return }

        if isBuffering && hasStartedAudioThisSession {
            if waiting {
                recordStallIfNeeded(reason: "waiting")
            } else if bufferEmptyWhileWantingPlay {
                recordStallIfNeeded(reason: "buffer_empty")
            } else if cannotKeepUp {
                recordStallIfNeeded(reason: "cannot_keep_up")
            }
        }

    }

    private func bindPlaybackCallbacks(to item: AVPlayerItem, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        startPlayerObservationIfNeeded(item: item, ticket: ticket)
        attachItemObservers(to: item, ticket: ticket)
        configureRemoteCommandsIfNeeded(ticket: ticket)
        observeAudioSessionInterruptionsIfNeeded(ticket: ticket)
        observeAudioRouteChangesIfNeeded(ticket: ticket)
        startProgressObservationIfNeeded(item: item, ticket: ticket)
        startPlaybackCompletionObservationIfNeeded(item: item, ticket: ticket)
    }

    private func startPlayerObservationIfNeeded(item: AVPlayerItem, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard playerObservation == nil else { return }
        playerObservation = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
            }
        }
    }

    private func schedulePublishedPlaybackStateUpdate(ticket: PodcastPlaybackSessionCoordinator.Ticket, item: AVPlayerItem?) {
        guard sessionCoordinator.isCurrent(ticket), let item, player.currentItem === item else { return }
        playbackStateUpdateTask?.cancel()
        playbackStateUpdateTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled, self.sessionCoordinator.isCurrent(ticket),
                  let item, self.player.currentItem === item else { return }
            self.updatePublishedPlaybackState()
            self.updateNowPlayingPlaybackState()
        }
    }

    private func attachItemObservers(to item: AVPlayerItem, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        detachItemObservers()

        itemObservations = [
            item.observe(\.duration, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
                }
            },
            item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
                }
            },
            item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    self?.schedulePublishedPlaybackStateUpdate(ticket: ticket, item: item)
                }
            }
        ]
    }

    private func detachItemObservers() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
    }

    /// Exact registrations are removed as well as fenced. A callback already
    /// queued by a system API still carries its old immutable ownership ticket.
    private func detachPlaybackCallbacks() {
        playbackStateUpdateTask?.cancel()
        playbackStateUpdateTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        player.currentItem?.cancelPendingSeeks()
        detachItemObservers()
        playerObservation?.invalidate()
        playerObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        for observer in [endObserver, interruptionObserver, routeChangeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        interruptionObserver = nil
        routeChangeObserver = nil
        for registration in remoteCommandTargets {
            registration.command.removeTarget(registration.target)
            registration.command.isEnabled = false
        }
        remoteCommandTargets = []
        remoteCommandsConfigured = false
    }

    private func configureAudioSessionIfNeeded() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.allowAirPlay, .allowBluetoothA2DP, .allowBluetoothHFP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Called when playback is fully torn down. Deactivates our session (so other
    /// apps can resume their audio) and restores the mixable ambient default the
    /// app launches with, so the splash/UI never interrupts other apps again.
    private func deactivateAudioSessionForOtherApps() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func startProgressObservationIfNeeded(item: AVPlayerItem, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, !self.isHandlingProgressTick, self.sessionCoordinator.isCurrent(ticket),
                      let item, self.player.currentItem === item else { return }
                self.isHandlingProgressTick = true
                defer { self.isHandlingProgressTick = false }
                self.handleProgressTick(ticket: ticket)
            }
        }
    }

    private func handleProgressTick(ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        // A queued callback may have belonged to a previous item/seek. Read the
        // player's current position instead of applying its captured old time.
        guard sessionCoordinator.isCurrent(ticket) else { return }
        updateDurationFromCurrentItem()
        guard retainsAdoption(ticket) else { return }
        applyPendingResumePositionIfNeeded()
        guard sessionCoordinator.canPublishProgress(ticket), !resumeSeekState.isCompleted else { return }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds <= PodcastProgressRecordCodec.maximumDurationSeconds else { return }
        let observedTime = max(0, seconds)
        let uiPublishThreshold: TimeInterval = isFullPlayerPresented
            ? FeatureFlags.playerForegroundPublishThreshold
            : FeatureFlags.playerBackgroundPublishThreshold
        if resumeSeekState.canPersistProgress,
           abs(observedTime - currentTime) >= uiPublishThreshold {
            currentTime = observedTime
            guard retainsAdoption(ticket) else { return }
        }

        updateDurationFromCurrentItem()
        guard retainsAdoption(ticket) else { return }
        persistPlaybackProgress(force: false, ticket: ticket)

        if sessionCoordinator.isCurrent(ticket) { updateNowPlayingPlaybackState() }
    }

    private func startPlaybackCompletionObservationIfNeeded(item: AVPlayerItem, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard endObserver == nil else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            let revision = MainActor.assumeIsolated { self?.resumeSeekState.revision }
            Task { @MainActor [weak self, weak item] in
                guard let self, self.sessionCoordinator.isCurrent(ticket) else { return }
                guard self.resumeSeekState.revision == revision else { return }
                guard let item, item === self.player.currentItem,
                      self.sessionCoordinator.complete(ticket) else { return }

                self.resumeSeekState.confirmCompletion()
                if let duration = PodcastPlaybackPolicy.knownDuration(self.player.currentItem?.duration.seconds) {
                    self.duration = duration
                    guard self.retainsAdoption(ticket) else { return }
                    self.currentTime = duration
                    guard self.retainsAdoption(ticket) else { return }
                }

                if self.sleepTimerOption == .endOfEpisode {
                    self.pause()
                    guard self.retainsAdoption(ticket) else { return }
                    self.sleepTimerOption = .off
                    return
                }

                self.playNextInQueueIfAvailable()
            }
        }
    }

    private func playNextInQueueIfAvailable() {
        guard let currentEpisode,
              let next = PodcastPlaybackQueue.next(in: queue, after: currentEpisode.id) else {
            pause()
            return
        }
        startPlayback(episode: next, reason: .automaticAdvance)
    }

    private func configureRemoteCommandsIfNeeded(ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        let play = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.resume() } }
            return .success
        }
        let pause = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.pause() } }
            return .success
        }
        let toggle = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.togglePlayPause() } }
            return .success
        }
        let position = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent, event.positionTime.isFinite else {
                return .commandFailed
            }
            let seconds = event.positionTime
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.seek(to: seconds) } }
            return .success
        }
        let forward = commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.seekForward(seconds: 30) } }
            return .success
        }
        let backward = commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.sessionCoordinator.perform(ifCurrent: ticket) { self?.seekBackward(seconds: 15) } }
            return .success
        }
        remoteCommandTargets = [(commandCenter.playCommand, play), (commandCenter.pauseCommand, pause),
                                (commandCenter.togglePlayPauseCommand, toggle), (commandCenter.changePlaybackPositionCommand, position),
                                (commandCenter.skipForwardCommand, forward), (commandCenter.skipBackwardCommand, backward)]
    }

    private func observeAudioSessionInterruptionsIfNeeded(ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.sessionCoordinator.isCurrent(ticket),
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    return
                }

                switch type {
                case .began:
                    self.sessionCoordinator.beginInterruption(ticket, wantedPlayback: self.wantsPlayback)
                    self.pause(recordExplicitIntent: false, allowDeferredCache: false)
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if self.sessionCoordinator.endInterruption(ticket, shouldResume: options.contains(.shouldResume)) {
                        self.resume()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeAudioRouteChangesIfNeeded(ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            Task { @MainActor [weak self] in
                guard let self, self.sessionCoordinator.isCurrent(ticket),
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                    return
                }

                if reason == .oldDeviceUnavailable {
                    AppDiagnostics.breadcrumb("podcast_route_old_device_unavailable")
                    self.pause(recordExplicitIntent: true, allowDeferredCache: false)
                }
            }
        }
    }

    private func refreshNowPlayingMetadataIfNeeded(force: Bool) {
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket),
              let episode = currentEpisode else { return }

        let identifier = episode.id
        if force || nowPlayingInfo[MPMediaItemPropertyTitle] as? String != episode.title {
            nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = episode.subtitle ?? "Lyt til artiklen"
            nowPlayingInfo[MPMediaItemPropertyArtist] = episode.hosts.first ?? "Apropos Magazine"
        }
        if duration.isFinite, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if cachedArtworkIdentifier != identifier {
            cachedArtworkIdentifier = identifier
            let isAINarration = episode.isAINarration
            if let url = episode.artworkURL {
                artworkTask = Task.detached(priority: .utility) { [weak self] in
                    guard !Task.isCancelled else { return }
                    let baseImage = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
                    guard !Task.isCancelled else { return }
                    // For AI narrations, show the branded Apropos cover (white bar + logo)
                    // instead of the raw article image on the lock screen / Now Playing.
                    let finalImage: UIImage?
                    if isAINarration {
                        finalImage = Self.brandedNarrationArtwork(from: baseImage)
                    } else {
                        finalImage = baseImage
                    }
                    guard let finalImage else { return }
                    let displayImage = Self.downscaledArtwork(finalImage, maxSide: 600)
                    let artwork = MPMediaItemArtwork(boundsSize: displayImage.size) { _ in displayImage }
                    await MainActor.run { [weak self] in
                        guard let self, !Task.isCancelled, self.sessionCoordinator.isCurrent(ticket),
                              self.currentEpisode?.id == identifier, self.currentEpisode?.artworkURL == url else { return }
                        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
                        self.artworkTask = nil
                    }
                }
            } else if isAINarration {
                let branded = Self.brandedNarrationArtwork(from: nil)
                nowPlayingInfo[MPMediaItemPropertyArtwork] =
                    MPMediaItemArtwork(boundsSize: branded.size) { _ in branded }
            } else {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Builds a square branded cover for AI narrations: the article image (aspect-fill)
    /// with a white bar across the bottom holding the Apropos logo. Falls back to a
    /// dark branded background when no article image is available.
    nonisolated static func brandedNarrationArtwork(from baseImage: UIImage?) -> UIImage {
        let side: CGFloat = 600
        let canvas = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { context in
            if let baseImage {
                let scale = max(side / baseImage.size.width, side / baseImage.size.height)
                let width = baseImage.size.width * scale
                let height = baseImage.size.height * scale
                let origin = CGPoint(x: (side - width) / 2, y: (side - height) / 2)
                baseImage.draw(in: CGRect(origin: origin, size: CGSize(width: width, height: height)))
            } else {
                UIColor(white: 0.07, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: canvas))
            }

            let barHeight = side * 0.19
            let barRect = CGRect(x: 0, y: side - barHeight, width: side, height: barHeight)
            UIColor.white.setFill()
            context.fill(barRect)

            // Apropos wordmark (dark, since the bar is white), centered in the bar.
            if let logo = UIImage(named: "AproposLogoBlack") ?? UIImage(named: "AM_logo_white 1") {
                let maxLogoHeight = barHeight * 0.5
                let maxLogoWidth = side * 0.7
                let aspect = logo.size.width / max(logo.size.height, 1)
                var logoHeight = maxLogoHeight
                var logoWidth = logoHeight * aspect
                if logoWidth > maxLogoWidth {
                    logoWidth = maxLogoWidth
                    logoHeight = logoWidth / aspect
                }
                let logoRect = CGRect(
                    x: (side - logoWidth) / 2,
                    y: barRect.midY - logoHeight / 2,
                    width: logoWidth,
                    height: logoHeight
                )
                logo.draw(in: logoRect)
            }
        }
    }

    nonisolated static func downscaledArtwork(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func updateNowPlayingPlaybackState() {
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket),
              currentEpisode != nil, currentTime.isFinite,
              currentTime >= 0, currentTime <= PodcastProgressRecordCodec.maximumDurationSeconds else { return }

        let second = Int(currentTime.rounded(.down))
        let shouldPublishTime = second != lastPublishedSecond
        if shouldPublishTime {
            lastPublishedSecond = second
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }

        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }

    func persistPlaybackProgress(force: Bool) {
        guard let ticket = sessionCoordinator.currentTicket else { return }
        persistPlaybackProgress(force: force, ticket: ticket)
    }

    private func persistPlaybackProgress(force: Bool, ticket: PodcastPlaybackSessionCoordinator.Ticket) {
        guard currentEpisode != nil, sessionCoordinator.canPublishProgress(ticket), resumeSeekState.canPersistProgress else { return }
        updateDurationFromCurrentItem()
        guard let knownDuration = PodcastPlaybackPolicy.knownDuration(duration) else { return }

        if !force {
            if let lastProgressPersistAt,
               Date().timeIntervalSince(lastProgressPersistAt) < 10 {
                return
            }
        }

        if sessionCoordinator.save(ticket, seconds: currentTime, duration: knownDuration) {
            lastProgressPersistAt = Date()
        }
    }

    private func updateDurationFromCurrentItem() {
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket),
              let itemDuration = PodcastPlaybackPolicy.knownDuration(player.currentItem?.duration.seconds),
              itemDuration <= PodcastProgressRecordCodec.maximumDurationSeconds,
              abs(itemDuration - duration) >= 0.35 else { return }
        duration = itemDuration
        guard retainsAdoption(ticket) else { return }
        refreshNowPlayingMetadataIfNeeded(force: false)
    }

    private func applyPendingResumePositionIfNeeded() {
        guard let ticket = sessionCoordinator.currentTicket, sessionCoordinator.isCurrent(ticket),
              let start = pendingStartTicket, sessionCoordinator.isCurrent(start), let item = player.currentItem,
              let position = resumeSeekState.positionToResume(wantsPlayback: wantsPlayback, itemReady: item.status == .readyToPlay),
              let itemDuration = PodcastPlaybackPolicy.knownDuration(item.duration.seconds),
              itemDuration <= PodcastProgressRecordCodec.maximumDurationSeconds else { return }

        let safePosition: TimeInterval
        if resumeSeekState.hasExplicitStart {
            guard let bounded = PodcastPlaybackPolicy.boundedExplicitStart(position, duration: itemDuration) else { return }
            safePosition = bounded
        } else {
            safePosition = PodcastPlaybackSessionCoordinator.safeResumePosition(position, currentDuration: itemDuration)
        }
        resumeSeekState.setResolvedPosition(safePosition)
        let request = resumeSeekState.begin()
        let time = CMTime(seconds: safePosition, preferredTimescale: 600)
        player.seek(to: time) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, self.sessionCoordinator.isCurrent(ticket), self.sessionCoordinator.isCurrent(start),
                      let item, self.player.currentItem === item else { return }
                let observed = self.player.currentTime().seconds
                let observedDuration = PodcastPlaybackPolicy.knownDuration(item.duration.seconds)
                let validObserved = observed.isFinite && observed >= 0
                    && observed <= PodcastProgressRecordCodec.maximumDurationSeconds
                    && observedDuration.map { observed <= $0 } == true
                switch self.resumeSeekState.finishResume(request, itemMatches: true, seekFinished: finished,
                                                        observedPosition: validObserved ? observed : nil) {
                case .ignored:
                    return
                case .retryRequired:
                    // Keep the positioning barrier and desired position. An
                    // explicit Resume may retry; cancellation never endorses a target.
                    self.wantsPlayback = false
                    self.player.pause()
                    self.offlinePlaybackMessage = self.resumeSeekState.hasExplicitStart
                        ? "Lyden kunne ikke starte på det valgte tidspunkt. Prøv at afspille igen."
                        : "Afspilningen kunne ikke fortsætte. Prøv igen."
                    guard self.retainsAdoption(ticket) else { return }
                    self.updatePublishedPlaybackState()
                case .positioned(let position):
                    guard self.sessionCoordinator.finishPositioning(start, observedPosition: position) else { return }
                    self.pendingStartTicket = nil
                    self.offlinePlaybackMessage = nil
                    guard self.retainsAdoption(ticket) else { return }
                    self.currentTime = position
                    guard self.retainsAdoption(ticket) else { return }
                    self.persistPlaybackProgress(force: true, ticket: ticket)
                    if PodcastResumeSeekState.shouldResume(seekFinished: finished, wantsPlayback: self.wantsPlayback) {
                        self.beginPlayback(useImmediate: true)
                    }
                }
                if self.sessionCoordinator.isCurrent(ticket) { self.updateNowPlayingPlaybackState() }
            }
        }
    }

    /// Scrubbing or replaying is an explicit new save session, even when the
    /// previous store ticket completed before AVPlayer's end notification.
    private func renewSessionForCurrentItem(_ item: AVPlayerItem, expectedContext: PodcastPlaybackSessionCoordinator.ContextTicket? = nil) -> PodcastPlaybackSessionCoordinator.Ticket? {
        guard let currentEpisode, player.currentItem === item,
              let session = sessionCoordinator.beginSession(episodeID: currentEpisode.id, articleID: currentArticleId, expectedContext: expectedContext) else { return nil }
        pendingStartTicket = nil
        detachPlaybackCallbacks()
        bindPlaybackCallbacks(to: item, ticket: session.ticket)
        cachedArtworkIdentifier = nil
        refreshNowPlayingMetadataIfNeeded(force: false)
        return session.ticket
    }
}
