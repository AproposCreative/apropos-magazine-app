import XCTest
@testable import Apropos_Magazine

final class PodcastPlaybackProgressStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        if let suite = UserDefaults(suiteName: "AproposMagazineTests") {
            suite.removePersistentDomain(forName: "AproposMagazineTests")
        }
    }

    func testPlayButtonTitleDefaultsToLyt() {
        XCTAssertEqual(PodcastPlaybackProgressStore.playButtonTitle(for: "episode-1"), "Lyt")
    }

    func testSaveAndResumeProgress() {
        PodcastPlaybackProgressStore.save(episodeId: "episode-1", seconds: 42, duration: 600)

        XCTAssertTrue(PodcastPlaybackProgressStore.hasResumableProgress(for: "episode-1"))
        XCTAssertEqual(PodcastPlaybackProgressStore.playButtonTitle(for: "episode-1"), "Fortsæt")
        XCTAssertEqual(PodcastPlaybackProgressStore.position(for: "episode-1"), 42)
    }

    func testNearCompletionClearsProgress() {
        PodcastPlaybackProgressStore.save(episodeId: "episode-2", seconds: 590, duration: 600)

        XCTAssertNil(PodcastPlaybackProgressStore.position(for: "episode-2"))
        XCTAssertFalse(PodcastPlaybackProgressStore.hasResumableProgress(for: "episode-2"))
    }

    func testMarkLastPlayedStoresArticleId() {
        PodcastPlaybackProgressStore.markLastPlayed(episodeId: "episode-3", articleId: "article-3")

        XCTAssertEqual(PodcastPlaybackProgressStore.lastPlayedEpisodeId(), "episode-3")
        XCTAssertEqual(PodcastPlaybackProgressStore.lastPlayedArticleId(), "article-3")
    }
}
