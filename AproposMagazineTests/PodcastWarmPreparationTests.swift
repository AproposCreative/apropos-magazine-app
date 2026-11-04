import XCTest
@testable import Apropos

/// Actual file receipt validation plus the actual player decision/coordinator.
/// No AVPlayer, shared cache, network, SDK or standard defaults is initialized.
@MainActor
final class PodcastWarmPreparationTests: XCTestCase {
    func testEveryNewLocalFileAdoptionRequiresPreparationIncludingWarmOnlineHit() {
        let file = URL(fileURLWithPath: "/fixture/audio.m4a"), remote = URL(string: "https://audio.example.com/a.m4a")!
        XCTAssertTrue(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: file, isOnline: true, alreadyPrepared: false))
        XCTAssertTrue(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: file, isOnline: false, alreadyPrepared: false))
        XCTAssertTrue(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: remote, isOnline: false, alreadyPrepared: false))
        XCTAssertFalse(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: remote, isOnline: true, alreadyPrepared: false))
        XCTAssertFalse(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: file, isOnline: true, alreadyPrepared: true))
    }
    func testActualWarmFileTamperFailsFullPreparationAndPreservesPreviousPlayingOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "PodcastWarmPreparationTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let asset = try XCTUnwrap(PodcastAudioAsset(episodeID: "episode", canonicalArticleID: "article", kind: .human,
            sourceRevision: "cms-sha256-v1:" + String(repeating: "a", count: 64), remoteURL: URL(string: "https://audio.example.com/a.m4a")!))
        let cache = PodcastAudioCache(cacheDirectory: root.appendingPathComponent("cache"), defaults: defaults, download: { url in
            let path = root.appendingPathComponent(UUID().uuidString + ".download")
            try Data([1, 2, 3, 4]).write(to: path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4", "Content-Length": "4", "Content-Encoding": "identity"])!
            return .init(temporaryURL: path, response: response)
        })
        defer { cache.removeAllCachedFiles(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        cache.scheduleBackgroundDownload(for: asset)
        for _ in 0..<2000 { if cache.isDownloaded(for: asset) { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(cache.isDownloaded(for: asset))
        let warm = cache.resolvePlaybackURL(for: asset)
        XCTAssertEqual(warm.cacheResult, .hit); XCTAssertTrue(warm.url.isFileURL)
        XCTAssertTrue(PodcastPlaybackPolicy.requiresAssetPreparation(playbackURL: warm.url, isOnline: true, alreadyPrepared: false))
        // The warm index deliberately has no disk reads. Same-size corruption
        // must be caught at the real full prepare boundary before new adoption.
        try Data([9, 9, 9, 9]).write(to: warm.url)
        XCTAssertEqual(cache.resolvePlaybackURL(for: asset).cacheResult, .hit)
        var records: [PodcastProgressNamespace: Data] = [:]
        let store = PodcastPlaybackProgressStore(storage: .init(read: { records[$0] }, write: { records[$0] = $1 }))
        store.changeContext(to: .guest)
        var effects = 0
        let coordinator = PodcastPlaybackSessionCoordinator(store: store, effects: .init(cancelCallbacks: { effects += 1 }, stopPlayback: { effects += 1 }, clearPresentation: { effects += 1 }, clearNowPlaying: { effects += 1 }, deactivateAudio: { effects += 1 }))
        let old = try XCTUnwrap(coordinator.beginSession(episodeID: "previous", articleID: "previous-article")).ticket
        let request = try XCTUnwrap(coordinator.beginPreparation(asset: asset, accessIsCurrent: { true }))
        let prepared = await cache.prepare(asset)
        XCTAssertFalse(prepared); XCTAssertEqual(cache.resolvePlaybackURL(for: asset).cacheResult, .miss)
        XCTAssertTrue(coordinator.isCurrent(request)); XCTAssertTrue(coordinator.isCurrent(old))
        XCTAssertEqual(effects, 0); XCTAssertTrue(records.isEmpty)
    }
}
