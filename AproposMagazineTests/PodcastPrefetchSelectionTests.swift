import XCTest
@testable import Apropos

final class PodcastPrefetchSelectionTests: XCTestCase {
    private var sampleAssets: [PodcastAudioAsset] {
        ["1.mp3", "2.m4a", "4.mp3"].enumerated().compactMap { index, file in
            PodcastAudioAsset(episodeID: "episode-\(index)", canonicalArticleID: "article-\(index)", kind: .human,
                sourceRevision: "cms-sha256-v1:" + String(repeating: "a", count: 64), remoteURL: URL(string: "https://example.com/" + file)!)
        }
    }

    func testReturnsEmptyWhenDiskCacheDisabled() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: false,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testReturnsEmptyWhenPrefetchDisabled() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: false,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testReturnsEmptyWhenWifiOnlyAndNotAllowed() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: true,
            allowsHeavyDownloads: false,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testProceedsWhenWifiOnlyAndAllowed() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: true,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertFalse(urls.isEmpty)
    }

    func testRespectsAcceptedAssetLimit() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: false,
            limit: 2
        )
        XCTAssertEqual(urls.map(\.remoteURL.absoluteString), [
            "https://example.com/1.mp3",
            "https://example.com/2.m4a"
        ])
    }

    func testReturnsAllAcceptedAssetsWhenLimitIsLarge() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: false,
            limit: 10
        )
        XCTAssertEqual(urls.map(\.remoteURL.absoluteString), [
            "https://example.com/1.mp3",
            "https://example.com/2.m4a",
            "https://example.com/4.mp3"
        ])
    }

    func testZeroLimitReturnsEmpty() {
        let urls = PodcastRepository.assetsToPrefetch(
            from: sampleAssets,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 0
        )
        XCTAssertTrue(urls.isEmpty)
    }
}

extension PodcastPrefetchSelectionTests {
    func testEnglishArticleAssetsDoNotConsumePrefetchSlotsOrBorrowDanishSupport() throws {
        let id = "0123456789abcdef01234567", revision = "cms-sha256-v1:" + String(repeating: "a", count: 64)
        func asset(_ episode: String, article: String, kind: PodcastAudioAsset.Kind) throws -> PodcastAudioAsset {
            try XCTUnwrap(PodcastAudioAsset(episodeID: episode, canonicalArticleID: article, kind: kind,
                sourceRevision: revision, remoteURL: URL(string: "https://audio.example.test/" + episode + ".m4a")!))
        }
        let englishHuman = try asset("en-human", article: "en_" + id, kind: .human)
        let englishAI = try asset("en-ai", article: "en_" + id, kind: .ai)
        let danishHuman = try asset("da-human", article: id, kind: .human)
        let danishAI = try asset("da-ai", article: id, kind: .ai)
        let result = PodcastRepository.assetsToPrefetch(from: [englishHuman, danishHuman, englishAI, danishAI],
            diskCacheEnabled: true, prefetchEnabled: true, wifiOnly: false, allowsHeavyDownloads: true, limit: 2)
        XCTAssertEqual(result, [danishHuman, danishAI])
    }
}
