import Foundation
import XCTest
@testable import Apropos

final class ReaderLedgerDeletionContractTests: XCTestCase {
    private typealias Contract = ReaderAccountDeletionContract

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-ledger-cleanup-wire-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func request(uid: String = "reader_a", epoch: Int64 = 1) throws -> Contract.LedgerRequest {
        let parent = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
        return try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch, parentRequestID: parent.requestID)
    }

    private func response(_ name: String = "complete") throws -> [String: Any] {
        let receipts = try XCTUnwrap(fixture()["receipts"] as? [String: [String: Any]])
        return try XCTUnwrap(receipts[name])
    }

    private func decode(_ value: [String: Any], request: Contract.LedgerRequest? = nil) throws -> Contract.LedgerReceipt {
        try Contract.decodeLedgerReceipt(data: JSONSerialization.data(withJSONObject: value), for: request ?? self.request())
    }

    private func decodeRequest(_ value: [String: Any]) throws -> Contract.LedgerRequest {
        try JSONDecoder().decode(Contract.LedgerRequest.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testActualWorkerAdmissionProgressBoundedAndTerminalFixturesDecodeAsIncompleteAccountCleanup() throws {
        for name in ["admissionPending", "boundedPending", "progressPending", "paused", "complete"] {
            let result = try decode(response(name))
            XCTAssertEqual(result.requestID, try request().requestID)
            XCTAssertEqual(result.scope, Contract.ledgerScope)
            XCTAssertEqual(result.unresolved, Contract.ledgerUnresolved)
            XCTAssertFalse(result.accountDeletionComplete)
        }
        XCTAssertEqual(try decode(response("admissionPending")).status, .pending)
        XCTAssertEqual(try decode(response("progressPending")).removedReceiptDocuments, 3)
        XCTAssertEqual(try decode(response("progressPending")).removedRevisionDocuments, 0)
        XCTAssertEqual(try decode(response("paused")).status, .paused)
        XCTAssertEqual(try decode(response()).status, .ledgerDataRemoved)
        XCTAssertEqual(try decode(response()).removedReceiptDocuments, 3)
        XCTAssertEqual(try decode(response()).removedRevisionDocuments, 3)
    }

    func testBoundedWorkerResponsesRetainMissingParentAndCountersWithoutInventingEchoes() throws {
        for name in ["boundedPending", "paused"] {
            let result = try decode(response(name))
            XCTAssertNil(result.parentRequestID)
            XCTAssertNil(result.removedReceiptDocuments)
            XCTAssertNil(result.removedRevisionDocuments)
        }
        XCTAssertEqual(try decode(response("admissionPending")).parentRequestID, try request().parentRequestID)
    }

    func testRequestEncodingHasExactlyTheVersionedServerAdmissionFields() throws {
        let value = try request()
        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["scope"] as? String, Contract.ledgerScope)
        XCTAssertEqual(object["parentRequestID"] as? String, try Contract.Request(expectedUID: "reader_a", membershipEpoch: 1).requestID)
        XCTAssertEqual(try JSONDecoder().decode(Contract.LedgerRequest.self, from: data), value)
    }

    func testChildHashMatchesActualStoreVectorsIncludingMaximumUIDAndSafeEpoch() throws {
        let vectors = try XCTUnwrap(fixture()["vectors"] as? [[String: Any]])
        XCTAssertEqual(vectors.count, 4)
        for vector in vectors {
            let value = try decodeRequest(XCTUnwrap(vector["request"] as? [String: Any]))
            XCTAssertEqual(value.requestID, vector["requestID"] as? String)
            XCTAssertEqual(value.parentRequestID, try Contract.Request(expectedUID: value.expectedUID, membershipEpoch: value.membershipEpoch).requestID)
            XCTAssertNotEqual(value.requestID, value.parentRequestID)
        }
        XCTAssertNotEqual(try request().requestID, try request(uid: "reader_b").requestID)
        XCTAssertNotEqual(try request().requestID, try request(epoch: 2).requestID)
    }

    func testLedgerRequestReusesParentUIDEpochValidationAndRequiresTheExactOriginalParent() throws {
        for uid in ["", "a/b", "a b", "é", "a\n", "a\"", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: 1, parentRequestID: "a"))
        }
        for epoch: Int64 in [0, -1, Contract.maximumSafeInteger + 1, Int64.max] {
            XCTAssertThrowsError(try Contract.LedgerRequest(expectedUID: "reader_a", membershipEpoch: epoch, parentRequestID: "a"))
        }
        let valid = try request()
        for parent in ["", valid.parentRequestID.uppercased(), String(repeating: "f", count: 64),
                       try Contract.Request(expectedUID: "reader_b", membershipEpoch: 1).requestID,
                       try Contract.Request(expectedUID: "reader_a", membershipEpoch: 2).requestID] {
            XCTAssertThrowsError(try Contract.LedgerRequest(expectedUID: "reader_a", membershipEpoch: 1, parentRequestID: parent))
        }
    }

    func testRequestDecodingCannotIgnoreUnknownMissingNullOrInconsistentVersionedFields() throws {
        let original = try XCTUnwrap(fixture()["request"] as? [String: Any])
        let changes: [[String: Any]] = [
            ["schemaVersion": 2], ["schemaVersion": true], ["schemaVersion": "1"],
            ["scope": Contract.scope], ["scope": "unknown"], ["expectedUID": "reader_b"],
            ["membershipEpoch": 2], ["membershipEpoch": true], ["parentRequestID": "wrong"],
            ["path": "users/reader_a"],
        ]
        for change in changes {
            XCTAssertThrowsError(try decodeRequest(original.merging(change) { _, new in new }))
        }
        for field in original.keys {
            var missing = original; missing.removeValue(forKey: field)
            XCTAssertThrowsError(try decodeRequest(missing))
            var null = original; null[field] = NSNull()
            XCTAssertThrowsError(try decodeRequest(null))
        }
    }

    func testOldAndNewWireScopesRejectEachOtherAndOriginalParentStillDecodesUnchanged() throws {
        let parent = try XCTUnwrap(fixture()["parentReceipt"] as? [String: Any])
        let parentRequest = try Contract.Request(expectedUID: "reader_a", membershipEpoch: 1)
        let acceptedParent = try Contract.decodeReceipt(data: JSONSerialization.data(withJSONObject: parent), for: parentRequest)
        XCTAssertEqual(acceptedParent.status, .scopedCloudDataRemoved)
        XCTAssertEqual(acceptedParent.unresolved, Contract.unresolved)
        XCTAssertThrowsError(try decode(parent))
        for name in ["admissionPending", "boundedPending", "progressPending", "paused", "complete"] {
            let data = try JSONSerialization.data(withJSONObject: response(name))
            XCTAssertThrowsError(try Contract.decodeReceipt(data: data, for: parentRequest))
        }
    }

    func testForeignOwnerEpochChildIDAndParentEchoAreRejected() throws {
        for name in ["admissionPending", "boundedPending", "paused", "complete"] {
            let value = try response(name)
            XCTAssertThrowsError(try decode(value, request: request(uid: "reader_b")))
            XCTAssertThrowsError(try decode(value, request: request(epoch: 2)))
            var wrongID = value; wrongID["requestID"] = try request().parentRequestID
            XCTAssertThrowsError(try decode(wrongID))
        }
        for name in ["admissionPending", "progressPending", "complete"] {
            var value = try response(name); value["parentRequestID"] = String(repeating: "f", count: 64)
            XCTAssertThrowsError(try decode(value))
        }
    }

    func testFullDeletionClaimsUnknownFieldsAndChangedUnresolvedScopesAreRejected() throws {
        for name in ["admissionPending", "boundedPending", "paused", "complete"] {
            let original = try response(name)
            let changes: [[String: Any]] = [
                ["accountDeletionComplete": true], ["scope": Contract.scope], ["scope": "all-account-data"],
                ["status": "accountDeleted"], ["unresolved": Contract.unresolved], ["unresolved": []],
                ["unresolved": Array(Contract.ledgerUnresolved.reversed())], ["unexpected": true],
            ]
            for change in changes {
                XCTAssertThrowsError(try decode(original.merging(change) { _, new in new }))
            }
        }
    }

    func testParentAndCountersAreAnAllOrNothingGroupAndExplicitNullNeverMeansAbsent() throws {
        let fields = ["parentRequestID", "removedReceiptDocuments", "removedRevisionDocuments"]
        for name in ["admissionPending", "progressPending", "complete"] {
            let original = try response(name)
            for field in fields {
                var missing = original; missing.removeValue(forKey: field)
                XCTAssertThrowsError(try decode(missing))
                var null = original; null[field] = NSNull()
                XCTAssertThrowsError(try decode(null))
            }
            var code = original; code["code"] = NSNull()
            XCTAssertThrowsError(try decode(code))
        }
        for name in ["boundedPending", "paused"] {
            let original = try response(name), full = try response("admissionPending")
            for field in fields {
                var mixed = original; mixed[field] = full[field]
                XCTAssertThrowsError(try decode(mixed))
                mixed[field] = NSNull()
                XCTAssertThrowsError(try decode(mixed))
            }
            var allNull = original
            for field in fields { allNull[field] = NSNull() }
            XCTAssertThrowsError(try decode(allNull))
        }
    }

    func testCountersRequireBothNonnegativeSafeIntegers() throws {
        for name in ["admissionPending", "complete"] {
            for field in ["removedReceiptDocuments", "removedRevisionDocuments"] {
                for value: Any in [-1, 0.25, Contract.maximumSafeInteger + 1, "3", true, NSNull()] {
                    var invalid = try response(name); invalid[field] = value
                    XCTAssertThrowsError(try decode(invalid))
                }
            }
        }
        var limits = try response(); limits["removedReceiptDocuments"] = 0
        limits["removedRevisionDocuments"] = Contract.maximumSafeInteger
        let accepted = try decode(limits)
        XCTAssertEqual(accepted.removedReceiptDocuments, 0)
        XCTAssertEqual(accepted.removedRevisionDocuments, Contract.maximumSafeInteger)
    }

    func testPausedUsesOnlyFixedCodesAndCannotCarryFullProgressOrTerminalEvidence() throws {
        let original = try response("paused")
        for code in ["transport_unavailable", "parent_cleanup_required", "invalid_ledger_record", "reader_boundary_changed"] {
            var allowed = original; allowed["code"] = code
            XCTAssertEqual(try decode(allowed).code, code)
        }
        for value: Any in ["PRIVATE TOKEN DETAIL", "", true, NSNull()] {
            var bad = original; bad["code"] = value
            XCTAssertThrowsError(try decode(bad))
        }
        var missing = original; missing.removeValue(forKey: "code")
        XCTAssertThrowsError(try decode(missing))
        var fullPaused = try response("admissionPending")
        fullPaused["status"] = "paused"; fullPaused["code"] = "transport_unavailable"
        XCTAssertThrowsError(try decode(fullPaused))
        var boundedCode = try response("boundedPending"); boundedCode["code"] = NSNull()
        XCTAssertThrowsError(try decode(boundedCode))
    }

    func testMalformedOrOversizeResponsesAndMissingBaseFieldsAreRejected() throws {
        for data in [Data(), Data("[]".utf8), Data("not-json".utf8), Data(repeating: 32, count: 16_385)] {
            XCTAssertThrowsError(try Contract.decodeLedgerReceipt(data: data, for: request()))
        }
        for field in ["requestID", "scope", "status", "accountDeletionComplete", "unresolved"] {
            var missing = try response("boundedPending"); missing.removeValue(forKey: field)
            XCTAssertThrowsError(try decode(missing))
            var null = try response("boundedPending"); null[field] = NSNull()
            XCTAssertThrowsError(try decode(null))
        }
    }
}
