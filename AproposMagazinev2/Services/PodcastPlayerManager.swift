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
    @Published private(set) var duration: TimeInterval = 1
    @Published var isFullPlayerPresented: Bool = false
    @Published private(set) var queue: [PodcastEpisode] = []
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var sleepTimerOption: SleepTimerOption = .off
    @Published private(set) var sleepTimerEndsAt: Date?

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
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var sleepTimer: Timer?
    private var nowPlayingInfo: [String: Any] = [:]
    private var cachedArtworkIdentifier: String?
    private var lastPublishedSecond: Int = -1
    private var remoteCommandsConfigured = false

    private var wantsPlayback = false
    private var hasStartedAudioThisSession = false
    private var lastStallIncrementAt: Date?
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []

    private static var preferredForwardBufferSeconds: TimeInterval {
        FeatureFlags.podcastForwardBufferSeconds
    }

    var hasActiveEpisode: Bool {
        currentEpisode != nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private init() {
        let configuredPlayer = AVPlayer()
        configuredPlayer.automaticallyWaitsToMinimizeStalling = true
        player = configuredPlayer
        startPlayerObservationIfNeeded()
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
        playerObservation?.invalidate()
        itemObservations.forEach { $0.invalidate() }
    }

    func play(episode: PodcastEpisode) {
        guard let audioURL = episode.audioURL,
              PodcastAudioURLValidator.isPlayableAudioURL(audioURL) else {
            return
        }

        let isSameEpisode = currentEpisode?.id == episode.id
        let isSameURL = currentAudioURL == audioURL

        if isSameEpisode && isSameURL && player.currentItem != nil {
            resume()
            isFullPlayerPresented = true
            return
        }

        configureAudioSessionIfNeeded()

        currentEpisode = episode
        currentAudioURL = audioURL
        currentTime = 0
        duration = 1
        resetPlaybackMetrics()
        playbackStartRequestedAt = Date()
        wantsPlayback = true
        AppDiagnostics.breadcrumb("podcast_play:\(episode.id)")

        let playbackResolution = PodcastAudioCache.shared.resolvePlaybackURL(for: audioURL)
        lastCacheResult = playbackResolution.cacheResult
        AppDiagnostics.breadcrumb("podcast_cache_\(playbackResolution.cacheResult.rawValue)")
        #if DEBUG
        print("[Podcast] cache: \(playbackResolution.cacheResult.rawValue)")
        #endif

        if playbackResolution.cacheResult == .miss {
            PodcastAudioCache.shared.scheduleBackgroundDownload(from: audioURL)
        }

        let item = makePlayerItem(url: playbackResolution.url)
        detachItemObservers()
        player.volume = 1.0
        volume = 1.0
        player.replaceCurrentItem(with: item)
        attachItemObservers(to: item)
        beginPlayback(useImmediate: false)
        isFullPlayerPresented = true

        configureRemoteCommandsIfNeeded()
        observeAudioSessionInterruptionsIfNeeded()
        observeAudioRouteChangesIfNeeded()
        startProgressObservationIfNeeded()
        startPlaybackCompletionObservationIfNeeded()
        refreshNowPlayingMetadataIfNeeded(force: true)
        updateNowPlayingPlaybackState()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        updatePublishedPlaybackState()
        if let episodeID = currentEpisode?.id {
            AppDiagnostics.breadcrumb("podcast_pause:\(episodeID)")
        }
        updateNowPlayingPlaybackState()
    }

    func resume() {
        guard currentEpisode != nil else { return }
        wantsPlayback = true
        if playbackStartRequestedAt == nil {
            playbackStartRequestedAt = Date()
        }
        beginPlayback(useImmediate: true)
        if let episodeID = currentEpisode?.id {
            AppDiagnostics.breadcrumb("podcast_resume:\(episodeID)")
        }
        updateNowPlayingPlaybackState()
    }

    func togglePlayPause() {
        wantsPlayback ? pause() : resume()
    }

    func seek(to seconds: TimeInterval) {
        let bounded = max(0, min(seconds, duration))
        currentTime = bounded
        let time = CMTime(seconds: bounded, preferredTimescale: 600)
        player.seek(to: time)
    }

    func seekForward(seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func openFullPlayer() {
        guard currentEpisode != nil else { return }
        isFullPlayerPresented = true
    }

    func dismissFullPlayer() {
        isFullPlayerPresented = false
    }

    func closePlayer() {
        wantsPlayback = false
        player.pause()
        detachItemObservers()
        player.replaceCurrentItem(with: nil)
        currentEpisode = nil
        currentAudioURL = nil
        currentTime = 0
        duration = 1
        isFullPlayerPresented = false
        queue = []
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        sleepTimerOption = .off
        nowPlayingInfo = [:]
        cachedArtworkIdentifier = nil
        resetPlaybackMetrics()
        updatePublishedPlaybackState()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func setQueue(episodes: [PodcastEpisode]) {
        let playable = episodes.filter(\.hasPlayableAudioURL)
        queue = uniqueEpisodes(playable)
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
        let clamped = max(0.5, min(rate, 2.0))
        playbackRate = clamped
        if isPlaying {
            player.rate = clamped
        }
        refreshNowPlayingMetadataIfNeeded(force: false)
        updateNowPlayingPlaybackState()
    }

    func setVolume(_ newValue: Float) {
        // Keep player at full level; system volume is controlled via MPVolumeView in the UI.
        volume = 1.0
        player.volume = 1.0
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerOption = option
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil

        if let interval = option.interval {
            sleepTimerEndsAt = Date().addingTimeInterval(interval)
            sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.pause()
                    self?.sleepTimerOption = .off
                    self?.sleepTimerEndsAt = nil
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
        updatePublishedPlaybackState()

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
        guard !hasStartedAudioThisSession else { return }
        hasStartedAudioThisSession = true
        firstAudioStartedAt = Date()

        if let start = playbackStartRequestedAt, let firstAudio = firstAudioStartedAt {
            let elapsed = firstAudio.timeIntervalSince(start)
            timeToFirstAudio = elapsed
            AppDiagnostics.breadcrumb(String(format: "podcast_ttf_audio:%.2fs", elapsed))
            #if DEBUG
            print("[Podcast] timeToFirstAudio: \(String(format: "%.2f", elapsed))s")
            #endif
        }
    }

    private func recordStallIfNeeded(reason: String) {
        guard hasStartedAudioThisSession else { return }

        let now = Date()
        if let lastStall = lastStallIncrementAt, now.timeIntervalSince(lastStall) < 1.0 {
            return
        }

        lastStallIncrementAt = now
        stallCount += 1
        AppDiagnostics.breadcrumb("podcast_stall:\(stallCount):\(reason)")
        #if DEBUG
        print("[Podcast] stall #\(stallCount) (\(reason))")
        #endif
    }

    private func updatePublishedPlaybackState() {
        timeControlStatus = player.timeControlStatus

        guard let item = player.currentItem else {
            isPlaying = false
            isBuffering = false
            isPlaybackLikelyToKeepUp = false
            return
        }

        isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
        isPlaying = player.timeControlStatus == .playing

        if item.status == .failed {
            isPlaying = false
            isBuffering = false
            wantsPlayback = false
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

        isBuffering = wantsPlayback && !isPlaying && (itemNotReady || waiting || bufferEmptyWhileWantingPlay || cannotKeepUp)

        if isPlaying {
            recordFirstAudioIfNeeded()
        }

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

    private func startPlayerObservationIfNeeded() {
        guard playerObservation == nil else { return }
        playerObservation = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updatePublishedPlaybackState()
                self?.updateNowPlayingPlaybackState()
            }
        }
    }

    private func attachItemObservers(to item: AVPlayerItem) {
        detachItemObservers()

        itemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePublishedPlaybackState()
                    self?.updateNowPlayingPlaybackState()
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePublishedPlaybackState()
                    self?.updateNowPlayingPlaybackState()
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePublishedPlaybackState()
                    self?.updateNowPlayingPlaybackState()
                }
            },
            item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePublishedPlaybackState()
                    self?.updateNowPlayingPlaybackState()
                }
            }
        ]
    }

    private func detachItemObservers() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
    }

    private func configureAudioSessionIfNeeded() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.allowAirPlay, .allowBluetoothA2DP, .allowBluetoothHFP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startProgressObservationIfNeeded() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let observedTime = max(0, CMTimeGetSeconds(time))
                let uiPublishThreshold: TimeInterval = self.isFullPlayerPresented
                    ? FeatureFlags.playerForegroundPublishThreshold
                    : FeatureFlags.playerBackgroundPublishThreshold
                if abs(observedTime - self.currentTime) >= uiPublishThreshold {
                    self.currentTime = observedTime
                }

                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0,
                   abs(itemDuration - self.duration) >= 0.35 {
                    self.duration = itemDuration
                    self.refreshNowPlayingMetadataIfNeeded(force: false)
                }

                self.updateNowPlayingPlaybackState()
            }
        }
    }

    private func startPlaybackCompletionObservationIfNeeded() {
        guard endObserver == nil else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard notification.object as? AVPlayerItem === self.player.currentItem else { return }

                if self.sleepTimerOption == .endOfEpisode {
                    self.pause()
                    self.sleepTimerOption = .off
                    return
                }

                self.playNextInQueueIfAvailable()
            }
        }
    }

    private func playNextInQueueIfAvailable() {
        guard let currentEpisode else { return }
        guard let currentIndex = queue.firstIndex(where: { $0.id == currentEpisode.id }) else {
            pause()
            return
        }
        let nextIndex = currentIndex + 1
        guard queue.indices.contains(nextIndex) else {
            pause()
            return
        }
        play(episode: queue[nextIndex])
    }

    private func uniqueEpisodes(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        var seen = Set<String>()
        var result: [PodcastEpisode] = []
        for episode in episodes {
            if seen.insert(episode.id).inserted {
                result.append(episode)
            }
        }
        return result
    }

    private func configureRemoteCommandsIfNeeded() {
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

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seekForward(seconds: 30) }
            return .success
        }
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seekBackward(seconds: 15) }
            return .success
        }
    }

    private func observeAudioSessionInterruptionsIfNeeded() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    return
                }

                switch type {
                case .began:
                    self.pause()
                case .ended:
                    let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.resume()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeAudioRouteChangesIfNeeded() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let userInfo = notification.userInfo,
                      let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                    return
                }

                if reason == .oldDeviceUnavailable {
                    AppDiagnostics.breadcrumb("podcast_route_old_device_unavailable")
                    self.pause()
                }
            }
        }
    }

    private func refreshNowPlayingMetadataIfNeeded(force: Bool) {
        guard let episode = currentEpisode else { return }

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
            if let url = episode.artworkURL {
                Task.detached(priority: .utility) { [weak self] in
                    guard let self else { return }
                    if let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            guard self.currentEpisode?.id == identifier else { return }
                            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
                        }
                    }
                }
            } else {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingPlaybackState() {
        guard currentEpisode != nil else { return }

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
}
