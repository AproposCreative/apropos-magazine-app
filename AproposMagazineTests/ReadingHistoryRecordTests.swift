import XCTest
@testable import Apropos

final class ReadingHistoryRecordTests: XCTestCase {
    func testHashedContextIsStableSeparateAndRejectsInvalidIdentitiesWithoutGuestFallback() throws {
        let a = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: "private-A").namespace)
        XCTAssertEqual(a, ReadingHistoryContext.confirmed(userID: "private-A").namespace)
        XCTAssertNotEqual(a, ReadingHistoryContext.confirmed(userID: "private-B").namespace)
        XCTAssertNotEqual(a, .guest)
        XCTAssertFalse(a.storageKey.contains("private-A"))
        XCTAssertEqual(a.recordBinding.count, 72)
        XCTAssertEqual(ReadingHistoryContext.confirmed(userID: nil), .guest)
        for invalid in ["", " ", "private\nA", String(repeating: "x", count: 513)] {
            XCTAssertEqual(ReadingHistoryContext.confirmed(userID: invalid), .unresolved)
        }
        XCTAssertNil(ReadingHistoryContext.account(.guest).namespace)
    }

    func testRoundTripPreservesReadAndProgressInOneOwnedRecordWithoutUID() throws {
        let namespace = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: "private-uid").namespace)
        let record = ReadingHistoryRecord(entries: [
            .init(articleID: "artikel-æøå", read: true, progress: 0.8),
            .init(articleID: "kun-åbnet", read: true, progress: nil),
            .init(articleID: "kun-progress", read: false, progress: 0)
        ])
        let data = try ReadingHistoryRecordCodec.encode(record, namespace: namespace)
        XCTAssertEqual(try ReadingHistoryRecordCodec.decode(data, namespace: namespace), record)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-uid"))
        XCTAssertThrowsError(try ReadingHistoryRecordCodec.decode(data, namespace: .guest))
    }

    func testUnknownVersionIsDistinctFromInvalidOrAdditionalFields() throws {
        var object: [String: Any] = ["schemaVersion": 2, "namespace": "guest", "entries": []]
        XCTAssertThrowsError(try ReadingHistoryRecordCodec.decode(json(object), namespace: .guest)) {
            XCTAssertEqual($0 as? ReadingHistoryRecordCodec.Failure, .unsupportedVersion)
        }
        object["schemaVersion"] = 1
        object["rawUID"] = "forbidden"
        invalid(try json(object))
        object.removeValue(forKey: "rawUID")
        object["schemaVersion"] = true
        invalid(try json(object))
        object["schemaVersion"] = 1
        object["entries"] = [["articleID": "a", "read": true, "extra": "no"]]
        invalid(try json(object))
    }

    func testPayloadCountUTF8AndDuplicateBoundsAreStrict() throws {
        invalid(Data(repeating: 32, count: 131_073))
        invalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": (0...200).map { ["articleID": "a-\($0)", "read": true] }]))
        invalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": [["articleID": "a", "read": true], ["articleID": "a", "read": true]]]))
        invalid(try json(["schemaVersion": 1, "namespace": "guest", "entries": [["articleID": String(repeating: "ø", count: 257), "read": true]]]))
        invalid(Data())
        invalid(Data("[]".utf8))
    }

    func testTwoHundredMaximumUnicodeIDsRoundTripWithinActualByteLimit() throws {
        let entries = (0..<200).map { ReadingHistoryRecord.Entry(articleID: String(format: "%04d", $0) + String(repeating: "ø", count: 254), read: true, progress: 1) }
        let record = ReadingHistoryRecord(entries: entries)
        let data = try ReadingHistoryRecordCodec.encode(record, namespace: .guest)
        XCTAssertLessThanOrEqual(data.count, 131_072)
        XCTAssertEqual(try ReadingHistoryRecordCodec.decode(data, namespace: .guest), record)
    }

    func testEscapedIDByteBudgetCannotBeBypassedByRawIDCount() {
        let entries = (0..<200).map { ReadingHistoryRecord.Entry(articleID: String(format: "%04d", $0) + String(repeating: "\"\\", count: 254), read: true, progress: 1) }
        XCTAssertTrue(entries.allSatisfy { $0.articleID.utf8.count == 512 })
        XCTAssertThrowsError(try ReadingHistoryRecordCodec.encode(.init(entries: entries), namespace: .guest))
    }

    func testNonFiniteOutOfRangeEmptyAndInvalidIDsAreRejected() throws {
        for value in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try ReadingHistoryRecordCodec.encode(.init(entries: [.init(articleID: "a", read: true, progress: value)]), namespace: .guest))
        }
        XCTAssertThrowsError(try ReadingHistoryRecordCodec.encode(.init(entries: [.init(articleID: "a", read: false, progress: nil)]), namespace: .guest))
        for id in ["", " a", "a\n"] {
            XCTAssertThrowsError(try ReadingHistoryRecordCodec.encode(.init(entries: [.init(articleID: id, read: true, progress: nil)]), namespace: .guest))
        }
        invalid(Data("{\"schemaVersion\":1,\"namespace\":\"guest\",\"entries\":[{\"articleID\":\"a\",\"read\":true,\"progress\":1e300}]}".utf8))
    }

    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func invalid(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ReadingHistoryRecordCodec.decode(data, namespace: .guest), file: file, line: line) {
            XCTAssertEqual($0 as? ReadingHistoryRecordCodec.Failure, .invalidRecord, file: file, line: line)
        }
    }
}
