import Foundation
import XCTest
@testable import Apropos

final class ReaderMutationContractTests: XCTestCase {
    private typealias Contract = ReaderMutationContract
    private let mutationID = "12345678-1234-5678-9abc-123456789abc"
    private let maximum = ReaderAccountDeletionContract.maximumSafeInteger

    private func binding(_ uid: String = "reader_a", epoch: Int64 = 1) throws -> ReaderMembershipContract.Binding {
        try ReaderMembershipContract.Binding(ownerUID: uid, epoch: epoch)
    }
    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-mutation-wire-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func row(kind: String = "favorite_set", payload: [String: Any]? = nil) -> [String: Any] {
        ["schemaVersion": 1, "expectedUID": "reader_a", "membershipEpoch": 1,
         "mutationID": mutationID, "expectedRevision": 0, "kind": kind,
         "payload": payload ?? ["id": "article_a", "pressAccreditation": false]]
    }
    private func decode(_ row: [String: Any]) throws -> Contract.Request {
        try Contract.decodeRequest(data: data(row), binding: binding())
    }
    private func receipt(for request: Contract.Request) throws -> [String: Any] {
        ["schemaVersion": 1, "scope": Contract.scope, "requestID": request.requestID,
         "status": "committed", "request": try object(Contract.encode(request)),
         "committedRevision": request.expectedRevision + 1]
    }
    private func assertInvalid(_ row: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decode(row), file: file, line: line) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidRequest, file: file, line: line)
        }
    }
    private func assertInvalidReceipt(_ row: [String: Any], for request: Contract.Request,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Contract.decodeReceipt(data: data(row), for: request), file: file, line: line) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidReceipt, file: file, line: line)
        }
    }

    func testSharedActualWorkerVectorsRoundTripExactRequestsIDsAndHistoricalReceipts() throws {
        let vectors = try XCTUnwrap(fixture()["vectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 3)
        var kinds = Set<String>()
        for vector in vectors {
            let original = try XCTUnwrap(vector["request"] as? [String: Any])
            let uid = try XCTUnwrap(original["expectedUID"] as? String)
            let epoch = try XCTUnwrap(original["membershipEpoch"] as? Int64)
            let request = try Contract.decodeRequest(data: data(original), binding: binding(uid, epoch: epoch))
            XCTAssertEqual(request.requestID, vector["requestID"] as? String)
            XCTAssertEqual(try data(object(Contract.encode(request))), try data(original))
            XCTAssertEqual(try JSONDecoder().decode(Contract.Request.self, from: Contract.encode(request)), request)
            let historical = try Contract.decodeReceipt(data: data(XCTUnwrap(vector["receipt"])), for: request)
            XCTAssertEqual(historical.request, request)
            XCTAssertEqual(historical.status, .committed)
            XCTAssertEqual(historical.committedRevision, request.expectedRevision + 1)
            kinds.insert(request.kind.rawValue)
        }
        XCTAssertEqual(kinds, ["favorite_set", "favorite_remove", "preferences_set"])
    }

    func testSharedMalformedWorkerRequestsAreAlsoRejectedByNativeDecoder() throws {
        let vectors = try XCTUnwrap(fixture()["invalidRequests"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)
        for vector in vectors {
            let original = try XCTUnwrap(vector["request"])
            XCTAssertThrowsError(try Contract.decodeRequest(data: data(original), binding: binding()),
                                 vector["name"] as? String ?? "unnamed invalid fixture")
        }
    }

    func testRestoredIntentCannotBeRetaggedToAnotherOwnerOrMembershipEpoch() throws {
        let original = try decode(row())
        let persisted = try Contract.encode(original)
        for other in [try binding("reader_b"), try binding(epoch: 2), try binding(epoch: maximum)] {
            XCTAssertThrowsError(try Contract.decodeRequest(data: persisted, binding: other)) {
                XCTAssertEqual($0 as? Contract.Failure, .invalidRequest)
            }
        }
        XCTAssertEqual(try Contract.decodeRequest(data: persisted, binding: binding()), original)
        XCTAssertEqual(original.expectedUID, "reader_a")
        XCTAssertEqual(original.membershipEpoch, 1)
    }

    func testIdentityHashChangesOnlyWithOriginalUIDEpochAndMutationID() throws {
        let original = try decode(row())
        let alternatePayload = try decode(row(kind: "favorite_remove", payload: ["articleID": "article_b"]))
        XCTAssertEqual(original.requestID, alternatePayload.requestID)
        XCTAssertNotEqual(original, alternatePayload)
        for other in [try binding("reader_b"), try binding(epoch: 2)] {
            let request = try Contract.Request(binding: other, mutationID: mutationID,
                                               expectedRevision: 0, payload: original.payload)
            XCTAssertNotEqual(request.requestID, original.requestID)
        }
        let newID = try Contract.Request(binding: binding(), mutationID: "12345678-1234-5678-9abc-123456789abd",
                                         expectedRevision: 0, payload: original.payload)
        XCTAssertNotEqual(newID.requestID, original.requestID)
    }

    func testUUIDAndSafeIntegerRevisionAreStrictAndNeverNormalized() throws {
        let payload = Contract.Payload.favoriteRemove(articleID: "article_a")
        for id in [mutationID.uppercased(), " " + mutationID, mutationID + " ", "", "not-a-uuid",
                   mutationID.replacingOccurrences(of: "-", with: ""), "{\(mutationID)}"] {
            XCTAssertThrowsError(try Contract.Request(binding: binding(), mutationID: id, expectedRevision: 0, payload: payload))
        }
        for revision: Int64 in [-1, maximum, Int64.max] {
            XCTAssertThrowsError(try Contract.Request(binding: binding(), mutationID: mutationID, expectedRevision: revision, payload: payload))
        }
        let last = try Contract.Request(binding: binding(epoch: maximum), mutationID: mutationID,
                                         expectedRevision: maximum - 1, payload: payload)
        let accepted = try Contract.decodeReceipt(data: data(receipt(for: last)), for: last)
        XCTAssertEqual(accepted.committedRevision, maximum)
    }

    func testRequestRejectsUnknownMissingNullAndWrongScalarTypes() throws {
        let original = row()
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key); assertInvalid(missing)
            var null = original; null[key] = NSNull(); assertInvalid(null)
        }
        for changes: [String: Any] in [
            ["schemaVersion": 2], ["schemaVersion": true], ["schemaVersion": "1"], ["schemaVersion": 1.5],
            ["expectedUID": "reader_b"], ["expectedUID": "../reader_a"], ["expectedUID": 1],
            ["membershipEpoch": true], ["membershipEpoch": 1.5], ["membershipEpoch": "1"],
            ["membershipEpoch": 0], ["membershipEpoch": maximum + 1],
            ["expectedRevision": true], ["expectedRevision": 0.5], ["expectedRevision": "0"],
            ["expectedRevision": maximum], ["kind": "favorite_delete"], ["kind": false],
            ["payload": []], ["payload": "article_a"], ["active": true], ["binding": ["epoch": 1]]
        ] { assertInvalid(original.merging(changes) { _, new in new }) }
        XCTAssertThrowsError(try JSONDecoder().decode(Contract.Request.self, from: data(original.merging(["active": true]) { _, new in new })))
    }

    func testFavoriteMetadataRejectsUnknownKeysAndEveryExplicitNull() throws {
        for key in FavoritesRecord.Metadata.keys {
            var payload: [String: Any] = ["id": "article_a", "pressAccreditation": false]
            payload[key] = NSNull()
            assertInvalid(row(payload: payload))
        }
        for key in ["content", "html", "membershipEpoch", "isPublic", "ownerUID", "revision"] {
            assertInvalid(row(payload: ["id": "article_a", "pressAccreditation": false, key: "injected"]))
        }
        assertInvalid(row(payload: ["id": "article_a"]))
        assertInvalid(row(payload: ["pressAccreditation": false]))
    }

    func testFavoriteMetadataRetainsExistingTypeStringURLAndRatingBounds() throws {
        let original: [String: Any] = ["id": "article_a", "pressAccreditation": false]
        for changes: [String: Any] in [
            ["pressAccreditation": 1], ["isDraft": 0], ["isArchived": "false"], ["isPremium": []],
            ["featured": "true"], ["name": true], ["name": String(repeating: "é", count: 1025)],
            ["subtitle": "a\u{0}b"], ["stjerne": true], ["stjerne": -1], ["stjerne": 11], ["stjerne": 2.5],
            ["topicsIDs": [true]], ["topicsIDs": [""]], ["topicsIDs": Array(repeating: "topic", count: 33)],
            ["mobileImageURL": "file:///private/image"], ["thumbURL": "https://user:pass@example.com/image"],
            ["coverURL": "https://"], ["coverURL": "https:example.com"], ["coverURL": "https:/example.com"],
            ["coverURL": "https://@example.com/image"], ["contentRevision": String(repeating: "x", count: 1025)]
        ] { assertInvalid(row(payload: original.merging(changes) { _, new in new })) }
        let allowed = try decode(row(payload: original.merging([
            "name": "Kultur / København", "subtitle": "En ærlig artikel", "stjerne": 10,
            "coverURL": "https://example.com/a/b?image=ø", "isDraft": false, "topicsIDs": ["topic_a", "topic_b"]
        ]) { _, new in new }))
        guard case .favoriteSet(let metadata) = allowed.payload else { return XCTFail("Expected metadata") }
        XCTAssertEqual(metadata.name, "Kultur / København")
        XCTAssertEqual(metadata.topicsIDs, ["topic_a", "topic_b"])
        XCTAssertNil(metadata.featured)
        let encodedPayload = try XCTUnwrap(object(Contract.encode(allowed))["payload"] as? [String: Any])
        XCTAssertNil(encodedPayload["featured"])
        XCTAssertFalse(encodedPayload.values.contains { $0 is NSNull })
    }

    func testBothFavoriteOperationsRequireSafeDirectDocumentIDs() throws {
        for id in ["", ".", "..", "a/b", "__system__", "____", " a", "a ", "a\n", "a\u{200B}",
                   "a\u{85}", "\u{A0}a", "a\u{FEFF}", String(repeating: "é", count: 257)] {
            assertInvalid(row(payload: ["id": id, "pressAccreditation": false]))
            assertInvalid(row(kind: "favorite_remove", payload: ["articleID": id]))
        }
        for id in ["article_a", "musik-ø", "__", "___", "__prefix", "suffix__", String(repeating: "é", count: 256)] {
            XCTAssertNoThrow(try decode(row(payload: ["id": id, "pressAccreditation": false])))
            XCTAssertNoThrow(try decode(row(kind: "favorite_remove", payload: ["articleID": id])))
        }
        for payload: [String: Any] in [[:], ["articleID": NSNull()], ["articleID": true],
                                     ["articleID": "article_a", "enabled": false], ["id": "article_a"]] {
            assertInvalid(row(kind: "favorite_remove", payload: payload))
        }
    }

    func testPreferencesPreserveExplicitOrderEmptySelectionAndFalseWithoutNormalization() throws {
        for ids in [[], ["z", "a"], (1...20).map { "topic_\($0)" }, ["é", "e\u{301}"], ["a/b"]] {
            let preferences = try Contract.Preferences(interestTopicIDs: ids, onboardingCompleted: false)
            let request = try Contract.Request(binding: binding(), mutationID: mutationID, expectedRevision: 9,
                                               payload: .preferencesSet(preferences))
            let decoded = try Contract.decodeRequest(data: Contract.encode(request), binding: binding())
            XCTAssertEqual(decoded, request)
            guard case .preferencesSet(let actual) = decoded.payload else { return XCTFail("Expected preferences") }
            XCTAssertEqual(actual.interestTopicIDs.map { Data($0.utf8) }, ids.map { Data($0.utf8) })
            XCTAssertFalse(actual.onboardingCompleted)
        }
        for ids in [["a", "a"], [""], [" a"], ["a\n"], ["a\u{200B}"], ["a\u{85}"], ["\u{A0}a"], ["a\u{FEFF}"],
                    [String(repeating: "é", count: 257)],
                    (1...21).map { "topic_\($0)" }] {
            XCTAssertThrowsError(try Contract.Preferences(interestTopicIDs: ids, onboardingCompleted: true))
            assertInvalid(row(kind: "preferences_set", payload: ["interestTopicIDs": ids, "onboardingCompleted": true]))
        }
    }

    func testPreferencesRequireExactKeysAndBooleanRatherThanTruthyScalars() {
        for payload: [String: Any] in [
            ["interestTopicIDs": [], "onboardingCompleted": 1], ["interestTopicIDs": [], "onboardingCompleted": "false"],
            ["interestTopicIDs": [], "onboardingCompleted": NSNull()], ["interestTopicIDs": NSNull(), "onboardingCompleted": true],
            ["interestTopicIDs": [1], "onboardingCompleted": true], ["interestTopicIDs": []],
            ["onboardingCompleted": false], ["interestTopicIDs": [], "onboardingCompleted": false, "newsletterOptIn": true]
        ] { assertInvalid(row(kind: "preferences_set", payload: payload)) }
    }

    func testReceiptMustMatchWholeOriginalIntentEvenWhenRequestIDIsUnchanged() throws {
        let original = try decode(row(payload: ["id": "article_a", "pressAccreditation": false, "name": "Original"]))
        let originalReceipt = try receipt(for: original)
        for changes: [String: Any] in [
            ["payload": ["id": "article_b", "pressAccreditation": false, "name": "Original"]],
            ["payload": ["id": "article_a", "pressAccreditation": true, "name": "Original"]],
            ["payload": ["id": "article_a", "pressAccreditation": false, "name": "Changed"]],
            ["kind": "favorite_remove", "payload": ["articleID": "article_a"]],
            ["expectedRevision": 1], ["expectedUID": "reader_b"], ["membershipEpoch": 2],
            ["mutationID": "12345678-1234-5678-9abc-123456789abd"]
        ] {
            var changed = originalReceipt
            let echoed = try XCTUnwrap(changed["request"] as? [String: Any])
            changed["request"] = echoed.merging(changes) { _, new in new }
            assertInvalidReceipt(changed, for: original)
        }
        var injected = originalReceipt
        var echoed = try XCTUnwrap(injected["request"] as? [String: Any]); echoed["active"] = true
        injected["request"] = echoed
        assertInvalidReceipt(injected, for: original)
    }

    func testReceiptRejectsCanonicalUnicodeSubstitutionAndReorderedPreferences() throws {
        let original = try decode(row(payload: ["id": "article_a", "pressAccreditation": false, "name": "é"]))
        let changed = try decode(row(payload: ["id": "article_a", "pressAccreditation": false, "name": "e\u{301}"]))
        XCTAssertEqual(original.requestID, changed.requestID)
        XCTAssertNotEqual(original, changed)
        assertInvalidReceipt(try receipt(for: changed), for: original)
        let preferences = try decode(row(kind: "preferences_set", payload: ["interestTopicIDs": ["a", "b"], "onboardingCompleted": true]))
        let reordered = try decode(row(kind: "preferences_set", payload: ["interestTopicIDs": ["b", "a"], "onboardingCompleted": true]))
        assertInvalidReceipt(try receipt(for: reordered), for: preferences)
    }

    func testReceiptRejectsMissingUnknownNullIncorrectRevisionAndAuthorityClaims() throws {
        let request = try decode(row())
        let original = try receipt(for: request)
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key); assertInvalidReceipt(missing, for: request)
            var null = original; null[key] = NSNull(); assertInvalidReceipt(null, for: request)
        }
        for changes: [String: Any] in [
            ["schemaVersion": true], ["schemaVersion": 2], ["schemaVersion": "1"],
            ["scope": "reader-cloud-slice-v1"], ["requestID": request.requestID.uppercased()],
            ["status": "pending"], ["status": true], ["committedRevision": true],
            ["committedRevision": "1"], ["committedRevision": 1.5], ["committedRevision": 0],
            ["committedRevision": 2], ["committedRevision": maximum + 1],
            ["currentRevision": 1], ["active": true], ["replayed": true], ["currentFavorite": true]
        ] { assertInvalidReceipt(original.merging(changes) { _, new in new }, for: request) }
    }

    func testEarlierReceiptRemainsHistoricalAndCannotAcknowledgeANewerIntent() throws {
        let earlier = try decode(row())
        let earlierBytes = try data(receipt(for: earlier))
        let next = try Contract.Request(binding: binding(), mutationID: "12345678-1234-5678-9abc-123456789abd",
                                        expectedRevision: 1, payload: .favoriteRemove(articleID: "article_a"))
        XCTAssertThrowsError(try Contract.decodeReceipt(data: earlierBytes, for: next))
        let historicReplay = try Contract.decodeReceipt(data: earlierBytes, for: earlier)
        XCTAssertEqual(historicReplay.committedRevision, 1)
        XCTAssertEqual(historicReplay.request, earlier)
        // No server-current resource value is synthesized from this old receipt.
        XCTAssertEqual(Set(try object(earlierBytes).keys), ["schemaVersion", "scope", "requestID", "status", "request", "committedRevision"])
    }

    func testByteLimitsApplyToActualJSONAndMalformedUTF8IsRejected() throws {
        let request = try decode(row())
        let requestBytes = try Contract.encode(request)
        let paddedRequest = requestBytes + Data(repeating: 0x20, count: Contract.maximumRequestBytes - requestBytes.count)
        XCTAssertEqual(try Contract.decodeRequest(data: paddedRequest, binding: binding()), request)
        XCTAssertThrowsError(try Contract.decodeRequest(data: paddedRequest + Data([0x20]), binding: binding()))
        let receiptBytes = try data(receipt(for: request))
        let paddedReceipt = receiptBytes + Data(repeating: 0x20, count: Contract.maximumReceiptBytes - receiptBytes.count)
        XCTAssertEqual(try Contract.decodeReceipt(data: paddedReceipt, for: request).request, request)
        XCTAssertThrowsError(try Contract.decodeReceipt(data: paddedReceipt + Data([0x20]), for: request))
        for invalid in [Data(), Data([0xff]), Data("[]".utf8), Data("null".utf8), Data("{broken".utf8)] {
            XCTAssertThrowsError(try Contract.decodeRequest(data: invalid, binding: binding()))
            XCTAssertThrowsError(try Contract.decodeReceipt(data: invalid, for: request))
        }
    }

    func testTypedMetadataCannotBypassTheActualEscapedJSONByteLimit() throws {
        var payload: [String: Any] = ["id": "article_a", "pressAccreditation": false]
        for (key, length) in [("name", 2048), ("subtitle", 4096), ("fotoCredit", 2048),
                              ("slug", 1024), ("location", 1024), ("contentRevision", 1024)] {
            payload[key] = String(repeating: "\u{1}", count: length)
        }
        let metadata = try JSONDecoder().decode(FavoritesRecord.Metadata.self, from: data(payload))
        XCTAssertTrue(metadata.valid)
        XCTAssertThrowsError(try Contract.Request(binding: binding(), mutationID: mutationID, expectedRevision: 0,
                                                  payload: .favoriteSet(metadata))) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidRequest)
        }
    }
}
