import XCTest
@testable import Apropos

final class PodcastAudioAssetTests: XCTestCase {
    private func asset(episode: String = "episode", article: String = "article", kind: PodcastAudioAsset.Kind = .human, revision: String = "source-r1", url: String = "https://audio.example.com/shared.m4a") -> PodcastAudioAsset? {
        URL(string: url).flatMap { PodcastAudioAsset(episodeID: episode, canonicalArticleID: article, kind: kind, sourceRevision: revision, remoteURL: $0) }
    }
    func testSameURLDifferentAcceptedIdentityHasDifferentStableKeysAndNoRawIdentifierKey() throws {
        let original = try XCTUnwrap(asset())
        XCTAssertEqual(original.key, try XCTUnwrap(asset()).key);XCTAssertEqual(original.key.count, 64)
        XCTAssertNotEqual(original.key, asset(episode: "other")?.key)
        XCTAssertNotEqual(original.key, asset(article: "other")?.key)
        XCTAssertNotEqual(original.key, asset(kind: .ai)?.key)
        XCTAssertNotEqual(original.key, asset(revision: "source-r2")?.key)
        XCTAssertFalse(original.key.contains("article"))
    }
    func testDescriptorRejectsUnboundOversizedOrUnsafeInputs() {
        for value in ["", " article", "article/other", "..", "__private__", "a\n", String(repeating: "x", count: 513)] {
            XCTAssertNil(asset(article: value));XCTAssertNil(asset(episode: value))
        }
        for value in ["", " source", "source\n", String(repeating: "x", count: 1025)] { XCTAssertNil(asset(revision: value)) }
        for url in ["http://audio.example.com/a.mp3", "file:///a.mp3", "https://user@audio.example.com/a.mp3", "https://audio.example.com/a.mp3#fragment", "https://audio.example.com/a.m3u8", "https://accounts.google.com/a.mp3"] { XCTAssertNil(asset(url: url)) }
    }
    func testBoundedStrictReceiptRoundTripsFullAssetWithoutPersistingAnAuthorizationClaim() throws {
        let accepted = try XCTUnwrap(asset())
        let receipt = try PodcastAudioReceipt(asset: accepted, byteCount: 8, sha256: String(repeating: "a", count: 64))
        let data = try receipt.encoded()
        XCTAssertLessThan(data.count, PodcastAudioReceipt.maximumBytes)
        XCTAssertEqual(try PodcastAudioReceipt.decode(data, expectedAsset: accepted), receipt)
        XCTAssertTrue(receipt.fileName.hasPrefix(accepted.key + "-"));XCTAssertTrue(receipt.fileName.hasSuffix(".m4a"))
        XCTAssertThrowsError(try PodcastAudioReceipt.decode(data, expectedAsset: XCTUnwrap(asset(revision: "source-r2"))))
    }
    func testReceiptRejectsUnknownFieldsSchemaForeignBindingInvalidCountAndDigest() throws {
        let accepted = try XCTUnwrap(asset())
        let data = try PodcastAudioReceipt(asset: accepted, byteCount: 8, sha256: String(repeating: "b", count: 64)).encoded()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("schemaVersion", 1 as Any), ("byteCount", 0 as Any), ("byteCount", Int64.max as Any), ("sha256", "BAD" as Any), ("commitID", "../../escape" as Any), ("unexpected", true as Any)] {
            var object = original;object[key] = value
            XCTAssertThrowsError(try PodcastAudioReceipt.decode(JSONSerialization.data(withJSONObject: object), expectedAsset: accepted))
        }
        var object = original;var nested = try XCTUnwrap(object["asset"] as? [String: Any]);nested["ownerUID"] = "private";object["asset"] = nested
        XCTAssertThrowsError(try PodcastAudioReceipt.decode(JSONSerialization.data(withJSONObject: object), expectedAsset: accepted))
        XCTAssertThrowsError(try PodcastAudioReceipt.decode(Data(repeating: 0x20, count: PodcastAudioReceipt.maximumBytes + 1), expectedAsset: accepted))
    }
}
