import XCTest
@testable import Apropos

final class PodcastShareComposerTests: XCTestCase {
    @MainActor func testActualShareComposerBoundsBeforeIntegerConversionAndKeepsLabelConsistent() {
        let episode = PodcastEpisode(id: "episode", articleId: "article", articleSlug: "slug", title: "Title",
            subtitle: nil, audioURL: nil, productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil, isAINarration: false)
        let cases: [(TimeInterval, Int)] = [(.nan, 0), (.infinity, 0), (-.infinity, 0),
            (-1, 0), (.greatestFiniteMagnitude, DeepLink.maximumStartSeconds), (125.1, 125)]
        for (timestamp, expected) in cases {
            let items = ArticleShareComposer.podcastClipShareItems(episode: episode, article: nil, timestamp: timestamp)
            let urls = items.compactMap { $0 as? URL }
            XCTAssertEqual(urls.count, 1)
            XCTAssertEqual(urls.first.flatMap(DeepLink.parse), .podcast(id: "slug", startSeconds: expected))
            XCTAssertTrue((items.first as? String)?.contains("Hør fra \(ShareLinkBuilder.formattedTimestamp(TimeInterval(expected)))") == true)
        }
    }
}
