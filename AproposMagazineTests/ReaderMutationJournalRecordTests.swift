import CryptoKit
import Foundation
import XCTest
@testable import Apropos

final class ReaderMutationJournalRecordTests: XCTestCase {
    private typealias Record = ReaderMutationJournalRecord
    private typealias Codec = ReaderMutationJournalCodec
    private let uid = "reader_a"

    private func request(_ number: Int = 1, owner: String = "reader_a", epoch: Int64 = 1,
                         revision: Int64 = 0, target: String = "article_a") throws -> ReaderMutationContract.Request {
        try .init(binding: .init(ownerUID: owner, epoch: epoch),
                  mutationID: String(format: "12345678-1234-1234-1234-%012x", number),
                  expectedRevision: revision, payload: .favoriteRemove(articleID: target))
    }
    private func bytes(_ object: Any, pretty: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys])
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func receipt(_ request: ReaderMutationContract.Request, pretty: Bool = false) throws -> Data {
        try bytes(["schemaVersion": 1, "scope": ReaderMutationContract.scope,
                   "requestID": request.requestID, "status": "committed",
                   "request": object(ReaderMutationContract.encode(request)),
                   "committedRevision": request.expectedRevision + 1], pretty: pretty)
    }
    private func namespace(_ owner: String?) throws -> FavoritesNamespace {
        try XCTUnwrap(FavoritesContext.confirmed(userID: owner).namespace)
    }
    private func metadata(_ id: String = "article_a") throws -> FavoritesRecord.Metadata {
        try JSONDecoder().decode(FavoritesRecord.Metadata.self, from: bytes(["id": id, "pressAccreditation": false]))
    }
    private func legacyV1(owner: String? = "reader_a") throws -> Data {
        try bytes(["schemaVersion": 1, "namespace": namespace(owner).recordBinding,
                   "entries": [["id": "article_a", "pressAccreditation": false]]], pretty: true)
    }
    private func legacyV2(owner: String = "reader_a") throws -> Data {
        let phases: [FavoritesRecord.Phase] = [.queued, .started, .acknowledged, .failed, .blocked]
        let pending = try phases.enumerated().map { index, phase -> FavoritesRecord.Pending in
            .init(intentID: UUID(), payload: try metadata("article_\(index)"), enabled: index.isMultiple(of: 2),
                  phase: phase, attemptID: [.started, .acknowledged, .failed].contains(phase) ? UUID() : nil)
        }
        let record = FavoritesRecord(base: [], pending: pending, requiresRecovery: true)
        return try FavoritesRecordCodec.encode(record, namespace: namespace(owner))
    }
    private func invalid(_ data: Data, owner: String = "reader_a", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Codec.decode(data, ownerUID: owner), file: file, line: line)
    }

    func testEmptyRecordRoundTripsWithoutInventingRequestsMembershipOrLegacyRecovery() throws {
        let record = try Record(ownerUID: uid)
        let restored = try Codec.decode(Codec.encode(record), ownerUID: uid)
        XCTAssertEqual(restored, record)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertTrue(restored.unacknowledgedEntries.isEmpty)
        XCTAssertTrue(restored.legacySnapshots.isEmpty)
        XCTAssertEqual(Set(try object(Codec.encode(record)).keys), ["schemaVersion", "ownerUID", "recordRevision", "entries", "legacySnapshots"])
    }

    func testAppendPreservesEveryOriginalEpochMutationAndCASAcrossRestart() throws {
        let first = try request(epoch: 7, revision: 12), second = try request(2, epoch: 8, revision: 3)
        let empty = try Record(ownerUID: uid)
        let one = try empty.appending(first), two = try one.appending(second)
        XCTAssertNotEqual(empty.recordRevision, one.recordRevision)
        XCTAssertNotEqual(one.recordRevision, two.recordRevision)
        let restored = try Codec.decode(Codec.encode(two), ownerUID: uid)
        XCTAssertEqual(restored.entries.map(\.request), [first, second])
        XCTAssertEqual(restored.entries.map { $0.request.membershipEpoch }, [7, 8])
        XCTAssertEqual(restored.entries.map { $0.request.expectedRevision }, [12, 3])
        XCTAssertEqual(try restored.appending(first), restored)
        XCTAssertEqual(try restored.appending(first).recordRevision, restored.recordRevision)
        XCTAssertEqual(try ReaderMutationContract.encode(restored.entries[0].request), try ReaderMutationContract.encode(first))
    }

    func testMutationIdentityCannotBeReusedWithChangedPayloadRevisionOrEpoch() throws {
        let original = try request(), record = try Record(ownerUID: uid).appending(original)
        for changed in [try request(target: "article_b"), try request(revision: 1), try request(epoch: 2)] {
            XCTAssertThrowsError(try record.appending(changed)) { XCTAssertEqual($0 as? Codec.Failure, .conflictingMutation) }
            XCTAssertThrowsError(try Record(ownerUID: uid, entries: [.init(request: original), .init(request: changed)]))
        }
        XCTAssertThrowsError(try Record(ownerUID: uid, entries: [.init(request: original), .init(request: original)]))
        XCTAssertEqual(try record.appending(original), record)
    }

    func testForeignOwnersAndGuestCannotAdoptOrRelabelTheJournal() throws {
        let record = try Record(ownerUID: uid).appending(request())
        XCTAssertThrowsError(try record.appending(request(2, owner: "reader_b")))
        XCTAssertThrowsError(try Record(ownerUID: uid, entries: [.init(request: request(owner: "reader_b"))]))
        invalid(try Codec.encode(record), owner: "reader_b")
        invalid(try Codec.encode(record), owner: "")
        var relabeled = try object(Codec.encode(record)); relabeled["ownerUID"] = "reader_b"
        invalid(try bytes(relabeled), owner: "reader_b")
        for owner in ["", "../reader_a", "reader_a ", "é"] { XCTAssertThrowsError(try Record(ownerUID: owner)) }
    }

    func testAcknowledgementPersistsOnlyExactHistoricalReceiptAndOriginalRequest() throws {
        let request = try request(epoch: 7, revision: 9), initial = try Record(ownerUID: uid).appending(request)
        let proof = try receipt(request, pretty: true)
        let acknowledged = try initial.acknowledging(requestID: request.requestID, receiptData: proof)
        XCTAssertNotEqual(acknowledged.recordRevision, initial.recordRevision)
        XCTAssertEqual(acknowledged.entries[0].request, request)
        XCTAssertEqual(acknowledged.entries[0].receiptData, proof)
        XCTAssertTrue(acknowledged.entries[0].historicallyAcknowledged)
        XCTAssertTrue(acknowledged.unacknowledgedEntries.isEmpty)
        let restored = try Codec.decode(Codec.encode(acknowledged), ownerUID: uid)
        XCTAssertEqual(restored, acknowledged)
        XCTAssertEqual(restored.entries[0].request.expectedRevision, 9)
        XCTAssertEqual(try ReaderMutationContract.decodeReceipt(data: XCTUnwrap(restored.entries[0].receiptData), for: request).committedRevision, 10)
    }

    func testSemanticAckRetryKeepsFirstBytesAndLocalRevisionButRejectsChangedReceipt() throws {
        let request = try request(), firstBytes = try receipt(request, pretty: true)
        let record = try Record(ownerUID: uid).appending(request).acknowledging(requestID: request.requestID, receiptData: firstBytes)
        let compact = try receipt(request)
        XCTAssertNotEqual(firstBytes, compact)
        let retry = try record.acknowledging(requestID: request.requestID, receiptData: compact)
        XCTAssertEqual(retry, record)
        XCTAssertEqual(retry.recordRevision, record.recordRevision)
        XCTAssertEqual(retry.entries[0].receiptData, firstBytes)
        var altered = try object(compact); altered["committedRevision"] = 2
        XCTAssertThrowsError(try record.acknowledging(requestID: request.requestID, receiptData: bytes(altered)))
        XCTAssertThrowsError(try record.acknowledging(requestID: "missing", receiptData: compact))
        XCTAssertThrowsError(try record.acknowledging(requestID: request.requestID, receiptData: receipt(self.request(2))))
    }

    func testLateHistoricalAckNeverRetiresOrChangesANewerIntentForTheSameTarget() throws {
        let old = try request(), newer = try request(2, revision: 1)
        let record = try Record(ownerUID: uid).appending(old).appending(newer)
        let acknowledged = try record.acknowledging(requestID: old.requestID, receiptData: receipt(old))
        XCTAssertEqual(acknowledged.entries.map(\.request), [old, newer])
        XCTAssertEqual(acknowledged.unacknowledgedEntries.map(\.request), [newer])
        XCTAssertNil(acknowledged.entries[1].receiptData)
        XCTAssertEqual(acknowledged.entries[1].request.expectedRevision, 1)
        XCTAssertEqual(try acknowledged.appending(old), acknowledged)
    }

    func testLegacyV1AndEveryV2PhaseRemainOriginalBytesAndNeverBecomeRequests() throws {
        let v1 = try legacyV1(), v2 = try legacyV2()
        let record = try Record(ownerUID: uid).preservingLegacy(kind: .favoritesV1, data: v1)
            .preservingLegacy(kind: .favoritesV2, data: v2)
        let restored = try Codec.decode(Codec.encode(record), ownerUID: uid)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertTrue(restored.unacknowledgedEntries.isEmpty)
        XCTAssertEqual(restored.legacySnapshots.map(\.rawData), [v1, v2])
        for snapshot in restored.legacySnapshots {
            let digest = SHA256.hash(data: snapshot.rawData).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(snapshot.sha256, digest)
        }
        let originalLegacy = try FavoritesRecordCodec.decode(v2, namespace: namespace(uid))
        let recoveredLegacy = try FavoritesRecordCodec.decode(restored.legacySnapshots[1].rawData, namespace: namespace(uid))
        XCTAssertEqual(recoveredLegacy, originalLegacy)
        XCTAssertEqual(Set(recoveredLegacy.pending.map { $0.phase.rawValue }), ["queued", "started", "acknowledged", "failed", "blocked"])
    }

    func testLegacyImportIsExplicitIdempotentAndCannotReplaceAnExistingSourceSnapshot() throws {
        let bytes = try legacyV1(), initial = try Record(ownerUID: uid)
        let imported = try initial.preservingLegacy(kind: .favoritesV1, data: bytes)
        XCTAssertNotEqual(imported.recordRevision, initial.recordRevision)
        XCTAssertEqual(try imported.preservingLegacy(kind: .favoritesV1, data: bytes), imported)
        XCTAssertThrowsError(try imported.preservingLegacy(kind: .favoritesV1, data: bytes + Data([0x20]))) {
            XCTAssertEqual($0 as? Codec.Failure, .conflictingLegacy)
        }
        let same = try Record.LegacySnapshot(kind: .favoritesV1, data: bytes, ownerUID: uid)
        XCTAssertThrowsError(try Record(ownerUID: uid, legacySnapshots: [same, same]))
        XCTAssertThrowsError(try Record(ownerUID: uid, legacySnapshots: [same, same, same]))
    }

    func testGuestForeignCorruptOrWrongVersionLegacyDataIsNeverAdopted() throws {
        let initial = try Record(ownerUID: uid)
        for bad in [try legacyV1(owner: nil), try legacyV1(owner: "reader_b"), Data(), Data("{}".utf8),
                    Data([0xff]), Data(repeating: 0x20, count: FavoritesRecordCodec.maximumRecordBytes + 1)] {
            XCTAssertThrowsError(try initial.preservingLegacy(kind: .favoritesV1, data: bad))
        }
        XCTAssertThrowsError(try initial.preservingLegacy(kind: .favoritesV1, data: legacyV2()))
        XCTAssertThrowsError(try initial.preservingLegacy(kind: .favoritesV2, data: legacyV1()))
        XCTAssertThrowsError(try initial.preservingLegacy(kind: .favoritesV2, data: legacyV2(owner: "reader_b")))
        let foreign = try Record.LegacySnapshot(kind: .favoritesV1, data: legacyV1(owner: "reader_b"), ownerUID: "reader_b")
        XCTAssertThrowsError(try Record(ownerUID: uid, legacySnapshots: [foreign]))
    }

    func testStrictRecordEntryAndLegacySchemasRejectUnknownMissingNullAndTamperedHash() throws {
        let request = try request()
        let record = try Record(ownerUID: uid).appending(request)
            .acknowledging(requestID: request.requestID, receiptData: receipt(request))
            .preservingLegacy(kind: .favoritesV1, data: legacyV1())
        let original = try object(Codec.encode(record))
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key); invalid(try bytes(missing))
            var null = original; null[key] = NSNull(); invalid(try bytes(null))
        }
        for changes: [String: Any] in [["schemaVersion": true], ["schemaVersion": "1"], ["schemaVersion": 2],
                                      ["recordRevision": true], ["recordRevision": "invalid"], ["active": true]] {
            invalid(try bytes(original.merging(changes) { _, new in new }))
        }
        let entry = try XCTUnwrap((original["entries"] as? [[String: Any]])?.first)
        for changed: [String: Any] in [[:], entry.merging(["receiptData": NSNull()]) { _, new in new },
                                      entry.merging(["currentRevision": 1]) { _, new in new },
                                      entry.merging(["receiptData": Data("{}".utf8).base64EncodedString()]) { _, new in new }] {
            var value = original; value["entries"] = [changed]; invalid(try bytes(value))
        }
        let legacy = try XCTUnwrap((original["legacySnapshots"] as? [[String: Any]])?.first)
        for key in legacy.keys {
            var changed = legacy; changed[key] = NSNull()
            var value = original; value["legacySnapshots"] = [changed]; invalid(try bytes(value))
        }
        for changes: [String: Any] in [["sha256": String(repeating: "a", count: 64)], ["kind": "preferences"],
                                      ["rawData": "invalid base64"], ["approvedEpoch": 1]] {
            var value = original; value["legacySnapshots"] = [legacy.merging(changes) { _, new in new }]
            invalid(try bytes(value))
        }
    }

    func testActualJSONEntryAndTotalByteLimitsRejectWithoutTruncating() throws {
        let entries = try (1...256).map { try Record.Entry(request: request($0)) }
        let largestCount = try Record(ownerUID: uid, entries: entries)
        XCTAssertEqual(try Codec.decode(Codec.encode(largestCount), ownerUID: uid).entries.count, 256)
        XCTAssertThrowsError(try largestCount.appending(request(257))) { XCTAssertEqual($0 as? Codec.Failure, .limitExceeded) }
        let emptyBytes = try Codec.encode(Record(ownerUID: uid))
        let padded = emptyBytes + Data(repeating: 0x20, count: Codec.maximumRecordBytes - emptyBytes.count)
        XCTAssertNoThrow(try Codec.decode(padded, ownerUID: uid))
        invalid(padded + Data([0x20]))
        for bad in [Data(), Data([0xff]), Data("[]".utf8), Data("null".utf8)] { invalid(bad) }
        let oversized = try (1...13).map { index -> Record.Entry in
            let request = try request(index), data = try receipt(request)
            let paddedReceipt = data + Data(repeating: 0x20, count: ReaderMutationContract.maximumReceiptBytes - data.count)
            return try Record.Entry(request: request, receiptData: paddedReceipt)
        }
        XCTAssertThrowsError(try Record(ownerUID: uid, entries: oversized)) { XCTAssertEqual($0 as? Codec.Failure, .limitExceeded) }
    }

    func testReplacementAllowsOnlyAppendAndFirstAcknowledgementWithANewLocalRevision() throws {
        let request = try request(), empty = try Record(ownerUID: uid)
        let appended = try empty.appending(request)
        let acknowledged = try appended.acknowledging(requestID: request.requestID, receiptData: receipt(request))
        let legacy = try acknowledged.preservingLegacy(kind: .favoritesV1, data: legacyV1())
        for (before, after) in [(empty, appended), (appended, acknowledged), (acknowledged, legacy), (legacy, legacy)] {
            XCTAssertNoThrow(try Codec.validateReplacement(current: before, next: after))
        }
        let sameRevision = try Record(ownerUID: uid, recordRevision: empty.recordRevision, entries: appended.entries)
        XCTAssertThrowsError(try Codec.validateReplacement(current: empty, next: sameRevision))
    }

    func testReplacementRejectsDroppedReorderedRetaggedAndModifiedOriginalRequests() throws {
        let first = try request(), second = try request(2), current = try Record(ownerUID: uid).appending(first).appending(second)
        let changedFirst = try request(epoch: 2)
        let candidates = [
            try Record(ownerUID: uid),
            try Record(ownerUID: uid, entries: [current.entries[1]]),
            try Record(ownerUID: uid, entries: Array(current.entries.reversed())),
            try Record(ownerUID: uid, entries: [.init(request: changedFirst), current.entries[1]]),
            try Record(ownerUID: uid, entries: [.init(request: request(target: "article_b")), current.entries[1]]),
            try Record(ownerUID: "reader_b")
        ]
        for candidate in candidates { XCTAssertThrowsError(try Codec.validateReplacement(current: current, next: candidate)) }
    }

    func testReplacementCannotEraseOrReformatAlreadyStoredReceiptBytes() throws {
        let request = try request(), data = try receipt(request, pretty: true)
        let current = try Record(ownerUID: uid, entries: [.init(request: request, receiptData: data)])
        let removed = try Record(ownerUID: uid, entries: [.init(request: request)])
        let reformatted = try Record(ownerUID: uid, entries: [.init(request: request, receiptData: receipt(request))])
        XCTAssertThrowsError(try Codec.validateReplacement(current: current, next: removed))
        XCTAssertThrowsError(try Codec.validateReplacement(current: current, next: reformatted))
        let retry = try current.acknowledging(requestID: request.requestID, receiptData: receipt(request))
        XCTAssertNoThrow(try Codec.validateReplacement(current: current, next: retry))
        XCTAssertEqual(retry.entries[0].receiptData, data)
    }

    func testReplacementCannotDropReorderOrChangeLegacyRawSnapshots() throws {
        let v1 = try legacyV1(), v2 = try legacyV2()
        let current = try Record(ownerUID: uid).preservingLegacy(kind: .favoritesV1, data: v1)
            .preservingLegacy(kind: .favoritesV2, data: v2)
        let changed = try Record.LegacySnapshot(kind: .favoritesV1, data: v1 + Data([0x20]), ownerUID: uid)
        for next in [try Record(ownerUID: uid),
                     try Record(ownerUID: uid, legacySnapshots: Array(current.legacySnapshots.reversed())),
                     try Record(ownerUID: uid, legacySnapshots: [changed, current.legacySnapshots[1]])] {
            XCTAssertThrowsError(try Codec.validateReplacement(current: current, next: next))
        }
    }

    func testRecordEqualityAndSameRevisionCannotHideCanonicalUnicodePayloadSubstitution() throws {
        let composed = try request(target: "café"), decomposed = try request(target: "cafe\u{301}")
        let original = try Record(ownerUID: uid, entries: [.init(request: composed)])
        let changed = try Record(ownerUID: uid, recordRevision: original.recordRevision, entries: [.init(request: decomposed)])
        XCTAssertNotEqual(original, changed)
        XCTAssertNotEqual(try Codec.encode(original), try Codec.encode(changed))
        XCTAssertThrowsError(try Codec.validateReplacement(current: original, next: changed))
        XCTAssertThrowsError(try original.appending(decomposed))
    }
}
