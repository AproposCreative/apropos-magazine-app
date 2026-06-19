import XCTest
@testable import Apropos_Magazine

final class PodcastPrefetchSelectionTests: XCTestCase {
    private func episode(id: String, audio: String?) -> PodcastEpisode {
        PodcastEpisode(
            id: id,
            articleId: nil,
            articleSlug: nil,
            title: id,
            subtitle: nil,
            audioURL: audio.flatMap { URL(string: $0) },
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: [],
            publishedDate: nil
        )
    }

    /// Newest-first order; index 2 is blocked and index 4 has no audio.
    private var sampleEpisodes: [PodcastEpisode] {
        [
            episode(id: "1", audio: "https://example.com/1.mp3"),
            episode(id: "2", audio: "https://example.com/2.m4a"),
            episode(id: "3", audio: "https://notebooklm.google.com/3.mp3"),
            episode(id: "4", audio: "https://example.com/4.mp3"),
            episode(id: "5", audio: nil)
        ]
    }

    func testReturnsEmptyWhenDiskCacheDisabled() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: false,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testReturnsEmptyWhenPrefetchDisabled() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: false,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testReturnsEmptyWhenWifiOnlyAndNotAllowed() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: true,
            allowsHeavyDownloads: false,
            limit: 3
        )
        XCTAssertTrue(urls.isEmpty)
    }

    func testProceedsWhenWifiOnlyAndAllowed() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: true,
            allowsHeavyDownloads: true,
            limit: 3
        )
        XCTAssertFalse(urls.isEmpty)
    }

    func testRespectsLimitAfterFiltering() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: false,
            limit: 2
        )
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.com/1.mp3",
            "https://example.com/2.m4a"
        ])
    }

    func testFiltersUnplayableWhenLimitIsLarge() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: false,
            limit: 10
        )
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.com/1.mp3",
            "https://example.com/2.m4a",
            "https://example.com/4.mp3"
        ])
    }

    func testZeroLimitReturnsEmpty() {
        let urls = PodcastRepository.episodesToPrefetch(
            from: sampleEpisodes,
            diskCacheEnabled: true,
            prefetchEnabled: true,
            wifiOnly: false,
            allowsHeavyDownloads: true,
            limit: 0
        )
        XCTAssertTrue(urls.isEmpty)
    }
}
