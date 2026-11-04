import Foundation
import XCTest
@testable import Apropos

final class ReaderAccountDeletionContractTests: XCTestCase {
    private typealias Contract = ReaderAccountDeletionContract

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-account-deletion-wire-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func request() throws -> Contract.Request {
        try Contract.Request(expectedUID: "reader_a", membershipEpoch: 1)
    }
    private func response(_ status: String = "partial") throws -> [String: Any] {
        let all = try XCTUnwrap(fixture()["receipts"] as? [String: [String: Any]])
        return try XCTUnwrap(all[status])
    }
    private func decode(_ value: [String: Any], request: Contract.Request? = nil) throws -> Contract.Receipt {
        try Contract.decodeReceipt(data: JSONSerialization.data(withJSONObject: value), for: request ?? self.request())
    }

    func testActualJavaScriptWorkerFixturesDecodeWithExplicitPartialScope() throws {
        for key in ["pending", "partial", "paused"] {
            let result = try decode(response(key))
            XCTAssertFalse(result.accountDeletionComplete)
            XCTAssertEqual(result.unresolved, Contract.unresolved)
            XCTAssertEqual(result.requestID, try request().requestID)
        }
        XCTAssertEqual(try decode(response()).status, .scopedCloudDataRemoved)
    }

    func testRequestEncodingContainsOnlyTheServerAdmissionFields() throws {
        let encoded = try JSONEncoder().encode(request())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["expectedUID", "membershipEpoch"])
        XCTAssertEqual(object["expectedUID"] as? String, "reader_a")
        XCTAssertEqual(object["membershipEpoch"] as? Int, 1)
    }

    func testRequestHashMatchesIndependentServerVectorsIncludingMaximumSafeEpoch() throws {
        let vectors = try XCTUnwrap(fixture()["vectors"] as? [[String: Any]])
        for vector in vectors {
            let object = try XCTUnwrap(vector["request"] as? [String: Any])
            let request = try JSONDecoder().decode(Contract.Request.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(request.requestID, vector["requestID"] as? String)
        }
        XCTAssertNotEqual(try request().requestID, try Contract.Request(expectedUID: "reader_a", membershipEpoch: 2).requestID)
    }

    func testInvalidUIDsAndUnsafeEpochsNeverCreateRequests() {
        for uid in ["", "a/b", "a b", "é", "a\n", "a\"", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try Contract.Request(expectedUID: uid, membershipEpoch: 1))
        }
        for epoch: Int64 in [0, -1, Contract.maximumSafeInteger + 1, Int64.max] {
            XCTAssertThrowsError(try Contract.Request(expectedUID: "reader_a", membershipEpoch: epoch))
        }
    }

    func testDecodingCannotBypassRequestValidation() throws {
        let bad = Data(#"{"expectedUID":"../other","membershipEpoch":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Contract.Request.self, from: bad))
    }

    func testAnotherOwnerOrMembershipReceiptIsRejected() throws {
        let response = try response()
        for foreign in [try Contract.Request(expectedUID: "reader_b", membershipEpoch: 1),
                        try Contract.Request(expectedUID: "reader_a", membershipEpoch: 2)] {
            XCTAssertThrowsError(try decode(response, request: foreign))
        }
    }

    func testFullDeletionClaimUnknownScopeAndMissingUnresolvedScopesAreRejected() throws {
        let original = try response()
        for change: [String: Any] in [
            ["accountDeletionComplete": true], ["scope": "all-account-data"],
            ["status": "accountDeleted"], ["unresolved": []],
            ["unresolved": Array(Contract.unresolved.reversed())], ["unexpected": true]
        ] {
            XCTAssertThrowsError(try decode(original.merging(change) { _, new in new }))
        }
    }

    func testCountsRequireNonnegativeSafeIntegersAndPartialRequiresCount() throws {
        let original = try response()
        for value: Any in [-1, 0.25, Contract.maximumSafeInteger + 1, "2", true] {
            var bad = original; bad["removedFavoriteDocuments"] = value
            XCTAssertThrowsError(try decode(bad))
        }
        var missing = original; missing.removeValue(forKey: "removedFavoriteDocuments")
        XCTAssertThrowsError(try decode(missing))
        var pending = try response("pending"); pending.removeValue(forKey: "removedFavoriteDocuments")
        XCTAssertNil(try decode(pending).removedFavoriteDocuments)
    }

    func testPausedDiagnosticsCannotBeTurnedIntoSuccessOrLeakArbitraryErrorText() throws {
        var paused = try response("paused")
        paused["code"] = "private-token-detail"
        XCTAssertThrowsError(try decode(paused))
        paused.removeValue(forKey: "code")
        XCTAssertThrowsError(try decode(paused))
        var partial = try response(); partial["code"] = "transport_unavailable"
        XCTAssertThrowsError(try decode(partial))
    }

    func testMalformedAndUnboundedPayloadsAreRejected() throws {
        for data in [Data(), Data("[]".utf8), Data("not-json".utf8), Data(repeating: 32, count: 16_385)] {
            XCTAssertThrowsError(try Contract.decodeReceipt(data: data, for: request()))
        }
    }
}
