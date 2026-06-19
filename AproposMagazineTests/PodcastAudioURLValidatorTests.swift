import XCTest
@testable import Apropos_Magazine

final class PodcastAudioURLValidatorTests: XCTestCase {
    func testAcceptsCommonAudioExtensions() {
        for ext in ["mp3", "m4a", "aac", "wav", "mp4", "m3u8"] {
            let url = URL(string: "https://cdn.example.com/audio/file.\(ext)")!
            XCTAssertTrue(
                PodcastAudioURLValidator.isPlayableAudioURL(url),
                ".\(ext) should be considered playable"
            )
        }
    }

    func testRejectsNonAudioExtension() {
        let url = URL(string: "https://cdn.example.com/file.pdf")!
        XCTAssertFalse(PodcastAudioURLValidator.isPlayableAudioURL(url))
    }

    func testRejectsBlockedHosts() {
        XCTAssertFalse(
            PodcastAudioURLValidator.isPlayableAudioURL(
                URL(string: "https://notebooklm.google.com/file.mp3")!
            )
        )
        XCTAssertFalse(
            PodcastAudioURLValidator.isPlayableAudioURL(
                URL(string: "https://accounts.google.com/file.mp3")!
            )
        )
    }

    func testRejectsGoogleDomains() {
        XCTAssertFalse(
            PodcastAudioURLValidator.isPlayableAudioURL(URL(string: "https://drive.google.com/file.mp3")!)
        )
        XCTAssertFalse(
            PodcastAudioURLValidator.isPlayableAudioURL(URL(string: "https://google.com/file.mp3")!)
        )
    }

    func testAcceptsFirebaseStorageAudio() {
        let url = URL(
            string: "https://firebasestorage.googleapis.com/v0/b/bucket/o/podcasts%2Fep.mp3?alt=media"
        )!
        XCTAssertTrue(PodcastAudioURLValidator.isPlayableAudioURL(url))
    }

    func testEpisodeHasPlayableAudioReflectsValidator() {
        let playable = PodcastEpisode(
            id: "1", articleId: nil, articleSlug: nil, title: "T", subtitle: nil,
            audioURL: URL(string: "https://example.com/a.mp3"),
            productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil
        )
        let blocked = PodcastEpisode(
            id: "2", articleId: nil, articleSlug: nil, title: "T", subtitle: nil,
            audioURL: URL(string: "https://notebooklm.google.com/a.mp3"),
            productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil
        )
        XCTAssertTrue(playable.hasPlayableAudioURL)
        XCTAssertFalse(blocked.hasPlayableAudioURL)
    }
}
