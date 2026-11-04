import XCTest
@testable import Apropos

final class PodcastProgressRecordTests: XCTestCase {
    func testConfirmedNamespacesAreStableHashedAndSeparateFromGuestWithoutTrimmingIdentity() throws {
        let a = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "private-reader-A").namespace)
        let again = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "private-reader-A").namespace)
        let b = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "private-reader-B").namespace)
        XCTAssertEqual(a, again)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, .guest)
        XCTAssertEqual(a.recordBinding.count, 72)
        XCTAssertTrue(a.recordBinding.hasPrefix("account_"))
        XCTAssertFalse(a.storageKey.contains("private-reader"))
        XCTAssertNotEqual(a, PodcastProgressContext.confirmed(userID: " private-reader-A").namespace)
        XCTAssertEqual(PodcastProgressContext.confirmed(userID: nil), .guest)
    }

    func testInvalidAccountIdentifiersStayUnresolvedRatherThanBecomingGuest() {
        for value in ["", " \t", "A\nB", String(repeating: "x", count: 513)] {
            XCTAssertEqual(PodcastProgressContext.confirmed(userID: value), .unresolved)
        }
        XCTAssertNil(PodcastProgressContext.account(.guest).namespace)
    }

    func testRoundTripKeepsExactUnicodeEpisodeArticleAndAtomicLastAssociation() throws {
        let namespace = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "private-uid").namespace)
        let record = PodcastProgressRecord(entries: [entry("🎧-æøå", article: "artikel-ø")], lastEpisodeID: "🎧-æøå")
        let data = try PodcastProgressRecordCodec.encode(record, namespace: namespace)
        XCTAssertEqual(try PodcastProgressRecordCodec.decode(data, namespace: namespace), record)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-uid"))
    }

    func testRecordCannotBeCopiedToAnotherAccountOrGuestPartition() throws {
        let a = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "A").namespace)
        let b = try XCTUnwrap(PodcastProgressContext.confirmed(userID: "B").namespace)
        let data = try PodcastProgressRecordCodec.encode(.init(entries: [entry("episode")], lastEpisodeID: "episode"), namespace: a)
        assertInvalid(data, namespace: b)
        assertInvalid(data, namespace: .guest)
    }

    func testUnknownVersionIsExplicitButMalformedSchemaAndFieldsAreRejected() throws {
        let base: [String: Any] = ["schemaVersion": 1, "namespace": "guest", "entries": []]
        var value = base
        value["schemaVersion"] = 2
        XCTAssertThrowsError(try PodcastProgressRecordCodec.decode(json(value), namespace: .guest)) {
            XCTAssertEqual($0 as? PodcastProgressRecordCodec.Failure, .unsupportedVersion)
        }
        value = base;value["rawUID"] = "not-allowed";assertInvalid(try json(value))
        value = base;value["schemaVersion"] = true;assertInvalid(try json(value))
        value = base;value.removeValue(forKey: "namespace");assertInvalid(try json(value))
        value = base;value["entries"] = [["episodeID": "episode", "positionSeconds": 42, "durationSeconds": 600, "token": "private"]]
        assertInvalid(try json(value))
    }

    func testDuplicateIDsAndDanglingLastPointerAreRejected() throws {
        let duplicate = PodcastProgressRecord(entries: [entry("episode"), entry("episode")], lastEpisodeID: "episode")
        XCTAssertThrowsError(try PodcastProgressRecordCodec.encode(duplicate, namespace: .guest))
        let dangling = PodcastProgressRecord(entries: [entry("episode")], lastEpisodeID: "missing")
        XCTAssertThrowsError(try PodcastProgressRecordCodec.encode(dangling, namespace: .guest))
        let rows: [[String: Any]] = [row("episode"), row("episode")]
        assertInvalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": rows]))
    }

    func testDecodeBoundsPayloadRowsAndUTF8IdentifiersBeforeAcceptingAnyPosition() throws {
        assertInvalid(Data(repeating: 32, count: PodcastProgressRecordCodec.maximumRecordBytes + 1))
        assertInvalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": (0...100).map { row("e-\($0)") }]))
        assertInvalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": [row(String(repeating: "ø", count: 257))]]))
        assertInvalid(Data("[]".utf8))
        assertInvalid(Data())
    }

    func testMaximumBoundedRecordStillRoundTripsAndRemainsUnderByteBudget() throws {
        let entries = (0..<100).map { index in
            entry(String(format: "%03d", index) + String(repeating: "ø", count: 254), article: String(repeating: "ø", count: 256))
        }
        let record = PodcastProgressRecord(entries: entries, lastEpisodeID: entries.last?.episodeID)
        let data = try PodcastProgressRecordCodec.encode(record, namespace: .guest)
        XCTAssertLessThanOrEqual(data.count, PodcastProgressRecordCodec.maximumRecordBytes)
        XCTAssertEqual(try PodcastProgressRecordCodec.decode(data, namespace: .guest), record)
    }

    func testNonFiniteEnormousAndCompletedPositionsCannotBecomeCMTimeResumeInputs() throws {
        for values in [(Double.nan, 600.0), (.infinity, 600), (42, .infinity), (1e300, 1e301), (42, 604801), (4.9, 600), (585, 600), (10, 10), (-1, 600)] {
            let record = PodcastProgressRecord(entries: [.init(episodeID: "episode", articleID: nil,
                positionSeconds: values.0, durationSeconds: values.1)], lastEpisodeID: "episode")
            XCTAssertThrowsError(try PodcastProgressRecordCodec.encode(record, namespace: .guest))
        }
        assertInvalid(Data("{\"schemaVersion\":1,\"namespace\":\"guest\",\"entries\":[{\"episodeID\":\"episode\",\"positionSeconds\":1e300,\"durationSeconds\":1e301}]}".utf8))
    }

    func testWhitespaceControlAndOversizeIDsAreNeverNormalizedIntoAnotherEpisode() throws {
        for id in ["", " episode", "episode ", "episode\n", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try PodcastProgressRecordCodec.encode(.init(entries: [entry(id)], lastEpisodeID: id), namespace: .guest))
        }
    }

    private func entry(_ id: String, article: String? = nil) -> PodcastProgressRecord.Entry {
        .init(episodeID: id, articleID: article, positionSeconds: 42, durationSeconds: 600)
    }
    private func row(_ id: String) -> [String: Any] { ["episodeID": id, "positionSeconds": 42, "durationSeconds": 600] }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func assertInvalid(_ data: Data, namespace: PodcastProgressNamespace = .guest, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PodcastProgressRecordCodec.decode(data, namespace: namespace), file: file, line: line) {
            XCTAssertEqual($0 as? PodcastProgressRecordCodec.Failure, .invalidRecord, file: file, line: line)
        }
    }
}
