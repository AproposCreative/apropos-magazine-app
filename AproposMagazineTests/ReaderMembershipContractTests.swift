import Foundation
import XCTest
@testable import Apropos

final class ReaderMembershipContractTests: XCTestCase {
    private typealias Contract = ReaderMembershipContract

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-membership-wire-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func vectors() throws -> [[String: Any]] { try XCTUnwrap(fixture()["vectors"] as? [[String: Any]]) }
    private func row(_ state: String = "active") throws -> [String: Any] {
        try XCTUnwrap(vectors().first?[state] as? [String: Any])
    }
    private func decode(_ row: [String: Any], expectedUID: String = "reader_a") throws -> Contract.Record {
        try Contract.decode(data: JSONSerialization.data(withJSONObject: row), expectedUID: expectedUID)
    }
    private func assertInvalid(_ row: [String: Any], expectedUID: String = "reader_a",
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decode(row, expectedUID: expectedUID), file: file, line: line) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidMembership, file: file, line: line)
        }
    }

    func testSharedWorkerVectorsDecodeActiveAndExactlyBoundFrozenMemberships() throws {
        for vector in try vectors() {
            let rawBinding = try XCTUnwrap(vector["binding"] as? [String: Any])
            let binding = try JSONDecoder().decode(Contract.Binding.self, from: JSONSerialization.data(withJSONObject: rawBinding))
            let active = try decode(XCTUnwrap(vector["active"] as? [String: Any]), expectedUID: binding.ownerUID)
            let frozen = try decode(XCTUnwrap(vector["frozen"] as? [String: Any]), expectedUID: binding.ownerUID)
            XCTAssertEqual(active.binding, binding)
            XCTAssertEqual(active.state, .active)
            XCTAssertNil(active.deletionRequestID)
            XCTAssertEqual(frozen.binding, binding)
            XCTAssertEqual(frozen.state, .deletionFrozen)
            XCTAssertEqual(frozen.deletionRequestID, vector["requestID"] as? String)
            let deletion = try ReaderAccountDeletionContract.Request(expectedUID: binding.ownerUID, membershipEpoch: binding.epoch)
            XCTAssertEqual(frozen.deletionRequestID, deletion.requestID)
        }
    }

    func testBindingEncodingRetainsOnlyOriginalUIDAndSafeIntegerEpoch() throws {
        for vector in try vectors() {
            let original = try XCTUnwrap(vector["binding"] as? [String: Any])
            let binding = try JSONDecoder().decode(Contract.Binding.self, from: JSONSerialization.data(withJSONObject: original))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["ownerUID", "epoch"])
            XCTAssertEqual(object["ownerUID"] as? String, original["ownerUID"] as? String)
            XCTAssertEqual(object["epoch"] as? Int64, original["epoch"] as? Int64)
        }
    }

    func testBindingInitializerUsesTheExistingDeletionUIDAndEpochBoundary() {
        for uid in ["", "a/b", ".", "..", "a b", "a\n", "é", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try Contract.Binding(ownerUID: uid, epoch: 1)) {
                XCTAssertEqual($0 as? Contract.Failure, .invalidMembership)
            }
        }
        for epoch: Int64 in [0, -1, ReaderAccountDeletionContract.maximumSafeInteger + 1, Int64.max] {
            XCTAssertThrowsError(try Contract.Binding(ownerUID: "reader_a", epoch: epoch))
        }
    }

    func testCodableCannotBypassBindingValidationOrAddAuthorityClaims() throws {
        let badJSON = [
            #"{"ownerUID":"reader_a","epoch":true}"#,
            #"{"ownerUID":"reader_a","epoch":"1"}"#,
            #"{"ownerUID":"reader_a","epoch":1.5}"#,
            #"{"ownerUID":"reader_a","epoch":9007199254740992}"#,
            #"{"ownerUID":"../reader_a","epoch":1}"#,
            #"{"ownerUID":"reader_a","epoch":0}"#,
            #"{"ownerUID":"reader_a","epoch":1,"active":true}"#,
            #"{"ownerUID":"reader_a"}"#,
            #"{"ownerUID":null,"epoch":1}"#
        ]
        for json in badJSON {
            XCTAssertThrowsError(try JSONDecoder().decode(Contract.Binding.self, from: Data(json.utf8))) {
                XCTAssertEqual($0 as? Contract.Failure, .invalidMembership)
            }
        }
    }

    func testExpectedOwnerMustMatchExactlyWithoutNormalization() throws {
        let original = try row()
        for expected in ["reader_b", "READER_A", "reader_a ", "", "../reader_a"] {
            assertInvalid(original, expectedUID: expected)
        }
        for uid in ["", "a/b", "é", String(repeating: "a", count: 129)] {
            var invalid = original; invalid["ownerUID"] = uid
            assertInvalid(invalid, expectedUID: uid)
        }
    }

    func testNewEpochIsASeparateBindingAndCannotReuseTheOriginalFrozenRequest() throws {
        let original = try decode(row())
        var next = try row(); next["epoch"] = 2
        XCTAssertNotEqual(try decode(next).binding, original.binding)
        var frozen = try row("frozen"); frozen["epoch"] = 2
        assertInvalid(frozen)
        frozen["deletionRequestID"] = try ReaderAccountDeletionContract.Request(expectedUID: "reader_a", membershipEpoch: 2).requestID
        XCTAssertEqual(try decode(frozen).binding.epoch, 2)
    }

    func testInvalidWorkerAdmissionFixturesAlsoFailProjectionExceptAValidDifferentEpoch() throws {
        let invalid = try XCTUnwrap(fixture()["invalidAdmissionRows"] as? [[String: Any]])
        for vector in invalid where vector["name"] as? String != "different-epoch" {
            let raw = try XCTUnwrap(vector["row"])
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed])
            XCTAssertThrowsError(try Contract.decode(data: data, expectedUID: "reader_a")) {
                XCTAssertEqual($0 as? Contract.Failure, .invalidMembership)
            }
        }
    }

    func testFrozenRequestMustMatchBothOriginalOwnerAndEpoch() throws {
        let original = try row("frozen")
        let foreign = try ReaderAccountDeletionContract.Request(expectedUID: "reader_b", membershipEpoch: 1).requestID
        for id: Any in [foreign, String(repeating: "a", count: 64), original["deletionRequestID"].map { String(describing: $0).uppercased() } ?? "", "", true, 1, NSNull()] {
            var invalid = original; invalid["deletionRequestID"] = id
            assertInvalid(invalid)
        }
        var missing = original; missing.removeValue(forKey: "deletionRequestID")
        assertInvalid(missing)
    }

    func testActiveMembershipRejectsEveryDeletionRequestFieldIncludingNull() throws {
        let original = try row(), requestID = try XCTUnwrap(row("frozen")["deletionRequestID"])
        for id: Any in [requestID, NSNull(), "", false] {
            var invalid = original; invalid["deletionRequestID"] = id
            assertInvalid(invalid)
        }
    }

    func testUnknownSchemaStateAndWrongScalarTypesAreRejected() throws {
        let original = try row()
        for replacement: [String: Any] in [
            ["schemaVersion": 2], ["schemaVersion": true], ["schemaVersion": "1"], ["schemaVersion": NSNull()],
            ["schemaVersion": 1.5], ["state": "deleted"], ["state": "ACTIVE"], ["state": NSNull()],
            ["state": true], ["epoch": true], ["epoch": "1"], ["epoch": NSNull()], ["epoch": 1.5],
            ["ownerUID": ["reader_a"]]
        ] {
            assertInvalid(original.merging(replacement) { _, new in new })
        }
    }

    func testMissingFieldsOrAdditionalProfileAndAuthorityFieldsCannotBecomeMembership() throws {
        let original = try row()
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key)
            assertInvalid(missing)
        }
        for key in ["email", "researchRole", "membershipEpoch", "verified", "writerFenceRevision", "unexpected"] {
            assertInvalid(original.merging([key: true]) { _, new in new })
        }
        assertInvalid(["uid": "reader_a", "email": "reader@example.invalid", "role": "editor"])
    }

    func testMalformedEmptyAndOversizedProjectionHasOneBoundedFailure() throws {
        for data in [Data(), Data("null".utf8), Data("[]".utf8), Data("not-json".utf8), Data(repeating: 32, count: 16_385)] {
            XCTAssertThrowsError(try Contract.decode(data: data, expectedUID: "reader_a")) {
                XCTAssertEqual($0 as? Contract.Failure, .invalidMembership)
            }
        }
        var maximum = try JSONSerialization.data(withJSONObject: row())
        maximum.append(Data(repeating: 32, count: 16_384 - maximum.count))
        XCTAssertEqual(try Contract.decode(data: maximum, expectedUID: "reader_a").state, .active)
        maximum.append(32)
        XCTAssertThrowsError(try Contract.decode(data: maximum, expectedUID: "reader_a"))
    }
}
