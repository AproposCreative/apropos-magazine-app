import XCTest
@testable import Apropos_Magazine

final class PodcastManifestDecodingTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testDecodesDashboardKeys() throws {
        let json = """
        {
          "version": 2,
          "episodes": [
            {
              "id": "ep-1",
              "slug": "min-artikel",
              "title": "Min Artikel",
              "audioUrl": "https://example.com/audio/ep-1.mp3",
              "hosts": ["Anna", "Bo"],
              "publishedAt": "2026-01-15T10:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try makeDecoder().decode(PodcastManifest.self, from: json)
        XCTAssertEqual(manifest.version, 2)
        XCTAssertEqual(manifest.episodes.count, 1)

        let episode = try XCTUnwrap(manifest.episodes.first?.toEpisode())
        XCTAssertEqual(episode.id, "ep-1")
        XCTAssertEqual(episode.articleSlug, "min-artikel")
        XCTAssertEqual(episode.title, "Min Artikel")
        XCTAssertEqual(episode.audioURL?.absoluteString, "https://example.com/audio/ep-1.mp3")
        XCTAssertEqual(episode.hosts, ["Anna", "Bo"])
        XCTAssertNotNil(episode.publishedDate)
    }

    func testDecodesLegacyKeys() throws {
        let json = """
        {
          "episodes": [
            {
              "id": "ep-legacy",
              "articleSlug": "legacy-slug",
              "title": "Legacy",
              "audioURL": "https://example.com/legacy.m4a"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try makeDecoder().decode(PodcastManifest.self, from: json)
        XCTAssertEqual(manifest.version, 1, "version defaults to 1 when missing")
        let entry = try XCTUnwrap(manifest.episodes.first)
        XCTAssertEqual(entry.articleSlug, "legacy-slug")
        XCTAssertEqual(entry.audioURL, "https://example.com/legacy.m4a")
    }

    func testDefaultsAppliedWhenFieldsMissing() throws {
        let json = """
        {
          "episodes": [
            { "id": "ep-2", "slug": "s2", "title": "No Subtitle", "audioUrl": "https://example.com/a.mp3" }
          ]
        }
        """.data(using: .utf8)!

        let episode = try XCTUnwrap(
            makeDecoder().decode(PodcastManifest.self, from: json).episodes.first?.toEpisode()
        )
        XCTAssertEqual(episode.subtitle, "Lyt til artiklen")
        XCTAssertEqual(episode.hosts, ["Apropos Magazine"])
    }

    func testEmptyAudioYieldsNilEpisode() throws {
        let json = """
        {
          "episodes": [
            { "id": "ep-3", "slug": "s3", "title": "No Audio", "audioUrl": "" }
          ]
        }
        """.data(using: .utf8)!

        let entry = try XCTUnwrap(makeDecoder().decode(PodcastManifest.self, from: json).episodes.first)
        XCTAssertEqual(entry.audioURL, "")
        XCTAssertNil(entry.toEpisode(), "An empty audio URL must not produce a playable episode")
    }

    func testIdFallsBackToSlugWhenMissing() throws {
        let json = """
        {
          "episodes": [
            { "slug": "fallback-id", "title": "No Id", "audioUrl": "https://example.com/a.mp3" }
          ]
        }
        """.data(using: .utf8)!

        let entry = try XCTUnwrap(makeDecoder().decode(PodcastManifest.self, from: json).episodes.first)
        XCTAssertEqual(entry.id, "fallback-id")
        XCTAssertEqual(entry.articleSlug, "fallback-id")
    }

    func testMissingEpisodesArrayThrows() {
        let json = """
        { "version": 1 }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try makeDecoder().decode(PodcastManifest.self, from: json))
    }
}
