import XCTest
@testable import Apropos

final class ShareLanguageTests: XCTestCase {
    func testRichShareLocalizesOwnWrapperButKeepsEditorialTitleAndIntroVerbatim() {
        let article = Article(id: "source", name: "Gem", slug: "source", content: "Editorial body",
                              intro: "Log ind — editorial text, not an interface key", topicID: "topic")
        let english = ArticleShareComposer.richShareText(for: article, categories: ["Anmeldelser", "TV-serier"], language: .english)
        let danish = ArticleShareComposer.richShareText(for: article, categories: ["Anmeldelser", "TV-serier"], language: .danish)
        XCTAssertTrue(english.hasPrefix("📰 Gem"))
        XCTAssertTrue(english.contains("Log ind — editorial text, not an interface key"))
        XCTAssertTrue(english.contains("Reviews, TV series"))
        XCTAssertTrue(english.contains("Read the full article at Apropos Magazine"))
        XCTAssertTrue(danish.contains("Læs hele artiklen på Apropos Magazine"))
        XCTAssertEqual(article.name, "Gem")
        XCTAssertEqual(article.intro, "Log ind — editorial text, not an interface key")
    }

    @MainActor
    func testPodcastShareKeepsTheExactLinkAndTimestampAcrossInterfaceLanguages() {
        let episode = PodcastEpisode(id: "episode", articleId: "article", articleSlug: "same-slug", title: "Gem",
            subtitle: nil, audioURL: nil, productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil, isAINarration: false)
        let english = ArticleShareComposer.podcastClipShareItems(episode: episode, article: nil, timestamp: 125.1, language: .english)
        let danish = ArticleShareComposer.podcastClipShareItems(episode: episode, article: nil, timestamp: 125.1, language: .danish)
        XCTAssertEqual(english.compactMap { $0 as? URL }, danish.compactMap { $0 as? URL })
        XCTAssertTrue((english.first as? String)?.contains("Listen from 2:05") == true)
        XCTAssertTrue((english.first as? String)?.hasPrefix("🎧 Gem") == true)
        XCTAssertTrue((danish.first as? String)?.contains("Hør fra 2:05") == true)
    }
}
