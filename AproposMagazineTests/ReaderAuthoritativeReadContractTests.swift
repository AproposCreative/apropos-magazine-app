import Foundation
import XCTest
@testable import Apropos

final class ReaderAuthoritativeReadContractTests: XCTestCase {
    private typealias Contract = ReaderAuthoritativeReadContract
    private let readID = "12345678-1234-1234-1234-123456789abc"
    private let maximum = ReaderMutationContract.maximumSafeInteger
    private func binding(_ uid: String = "reader_a", epoch: Int64 = 1) throws -> ReaderMembershipContract.Binding {
        try .init(ownerUID: uid, epoch: epoch)
    }
    private func memberRequest() throws -> Contract.MembershipRequest { try .init(expectedUID: "reader_a", readID: readID) }
    private func resourceRequest(_ target: Contract.Target = .favorite(id: "article-1")) throws -> Contract.ResourceRequest {
        try .init(binding: binding(), target: target, readID: readID)
    }
    private func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try object(Data(contentsOf: root.appendingPathComponent("functions/fixtures/reader-authoritative-read-wire-v1.json")))
    }
    private func member(_ request: Contract.ResourceRequest? = nil) -> [String: Any] {
        ["schemaVersion": 1, "ownerUID": request?.expectedUID ?? "reader_a", "epoch": request?.membershipEpoch ?? 1, "state": "active"]
    }
    private func memberResponse(_ request: Contract.MembershipRequest) throws -> [String: Any] {
        ["schemaVersion": 1, "scope": Contract.membershipScope, "request": try object(Contract.encode(request)),
         "membership": member(), "validUntilMs": 1_792_756_860_000 as Int64]
    }
    private func resourceResponse(_ request: Contract.ResourceRequest, revision: Int64 = 1,
                                  exists: Bool = true, payload: Any? = nil) throws -> [String: Any] {
        let value: Any = payload ?? (exists ? ["id": request.target.id, "pressAccreditation": false] as Any : NSNull())
        return ["schemaVersion": 1, "scope": Contract.resourceScope, "request": try object(Contract.encode(request)),
                "membership": member(request), "validUntilMs": 1_792_756_860_000 as Int64,
                "boundary": ["readerSchemaVersion": 1, "writerFenceRevision": String(repeating: "a", count: 64), "migrationRevision": String(repeating: "b", count: 64)],
                "resource": ["revision": revision, "exists": exists, "payload": value]]
    }
    private func invalidMember(_ row: [String: Any], request: Contract.MembershipRequest,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Contract.decodeMembershipResponse(data: data(row), for: request), file: file, line: line) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidResponse, file: file, line: line)
        }
    }
    private func invalidResource(_ row: [String: Any], request: Contract.ResourceRequest,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Contract.decodeResourceResponse(data: data(row), for: request), file: file, line: line) {
            XCTAssertEqual($0 as? Contract.Failure, .invalidResponse, file: file, line: line)
        }
    }

    func testSharedMembershipVectorsRoundTripExactRequestAndMissingActiveFrozenSnapshots() throws {
        let vectors = try XCTUnwrap(fixture()["membershipVectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 5)
        var sawMissing = false, sawFrozen = false
        for vector in vectors {
            let raw = try XCTUnwrap(vector["request"] as? [String: Any]), uid = try XCTUnwrap(raw["expectedUID"] as? String)
            let request = try Contract.decodeMembershipRequest(data: data(raw), expectedUID: uid)
            XCTAssertEqual(try data(object(Contract.encode(request))), try data(raw))
            XCTAssertEqual(try JSONDecoder().decode(Contract.MembershipRequest.self, from: Contract.encode(request)), request)
            let response = try XCTUnwrap(vector["response"] as? [String: Any])
            let result = try Contract.decodeMembershipResponse(data: data(response), for: request)
            XCTAssertEqual(result.request, request); XCTAssertGreaterThan(result.validUntilMs, 0)
            if response["membership"] is NSNull { XCTAssertNil(result.membership); sawMissing = true }
            else {
                let expected = try ReaderMembershipContract.decode(data: data(XCTUnwrap(response["membership"])), expectedUID: uid)
                XCTAssertEqual(result.membership, expected); sawFrozen = sawFrozen || expected.state == .deletionFrozen
            }
        }
        XCTAssertTrue(sawMissing); XCTAssertTrue(sawFrozen)
    }

    func testSharedResourceVectorsPreserveCurrentRevisionTombstoneAndExactPayloadBytes() throws {
        let vectors = try XCTUnwrap(fixture()["resourceVectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 6)
        var sawPreferences = false, sawMaximum = false, sawTombstone = false
        for vector in vectors {
            let raw = try XCTUnwrap(vector["request"] as? [String: Any])
            let owner = try XCTUnwrap(raw["expectedUID"] as? String), epoch = try XCTUnwrap(raw["membershipEpoch"] as? Int64)
            let request = try Contract.decodeResourceRequest(data: data(raw), binding: binding(owner, epoch: epoch))
            XCTAssertEqual(try data(object(Contract.encode(request))), try data(raw))
            XCTAssertEqual(try JSONDecoder().decode(Contract.ResourceRequest.self, from: Contract.encode(request)), request)
            let response = try XCTUnwrap(vector["response"] as? [String: Any]), state = try XCTUnwrap(response["resource"] as? [String: Any])
            let result = try Contract.decodeResourceResponse(data: data(response), for: request)
            XCTAssertEqual(result.request, request); XCTAssertEqual(result.membership.binding, request.binding)
            XCTAssertEqual(result.resource.revision, state["revision"] as? Int64)
            XCTAssertEqual(result.boundary.writerFenceRevision, String(repeating: "a", count: 64))
            sawMaximum = sawMaximum || result.resource.revision == maximum
            switch result.resource.payload {
            case .favorite(let metadata):
                let expected = try XCTUnwrap(state["payload"] as? [String: Any])
                XCTAssertEqual(Data(metadata.id.utf8), Data(request.target.id.utf8))
                XCTAssertEqual(metadata.name.map { Data($0.utf8) }, (expected["name"] as? String).map { Data($0.utf8) })
            case .preferences(let preferences):
                sawPreferences = true
                let expected = try XCTUnwrap(state["payload"] as? [String: Any]), ids = try XCTUnwrap(expected["interestTopicIDs"] as? [String])
                XCTAssertEqual(preferences.interestTopicIDs.map { Data($0.utf8) }, ids.map { Data($0.utf8) })
                XCTAssertFalse(preferences.onboardingCompleted)
            case nil:
                XCTAssertFalse(result.resource.exists); XCTAssertTrue(state["payload"] is NSNull)
                sawTombstone = sawTombstone || result.resource.revision > 0
            }
        }
        XCTAssertTrue(sawPreferences); XCTAssertTrue(sawMaximum); XCTAssertTrue(sawTombstone)
    }

    func testSharedMalformedRequestsAndResponsesAreRejectedWithoutAuthorityFallback() throws {
        let all = try fixture()
        for vector in try XCTUnwrap(all["invalidRequests"] as? [[String: Any]]) {
            let raw = try XCTUnwrap(vector["request"])
            if vector["kind"] as? String == "membership" {
                XCTAssertThrowsError(try Contract.decodeMembershipRequest(data: data(raw), expectedUID: "reader_a"))
            } else { XCTAssertThrowsError(try Contract.decodeResourceRequest(data: data(raw), binding: binding())) }
        }
        for vector in try XCTUnwrap(all["invalidResponses"] as? [[String: Any]]) {
            let raw = try XCTUnwrap(vector["request"]), response = try XCTUnwrap(vector["response"] as? [String: Any])
            if vector["kind"] as? String == "membership" {
                let request = try Contract.decodeMembershipRequest(data: data(raw), expectedUID: "reader_a")
                invalidMember(response, request: request)
            } else {
                let request = try Contract.decodeResourceRequest(data: data(raw), binding: binding())
                invalidResource(response, request: request)
            }
        }
    }

    func testConstructorsRejectInvalidUIDReadIDAndUnsafeTargetsWithoutNormalizing() throws {
        for id in [readID.uppercased(), " " + readID, readID + " ", "", "bad", readID.replacingOccurrences(of: "-", with: "")] {
            XCTAssertThrowsError(try Contract.MembershipRequest(expectedUID: "reader_a", readID: id))
            XCTAssertThrowsError(try Contract.ResourceRequest(binding: binding(), target: .preferences, readID: id))
        }
        for uid in ["", "reader/a", "reader a", "é", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try Contract.MembershipRequest(expectedUID: uid, readID: readID))
        }
        for id in ["", ".", "..", "a/b", "__system__", " a", "a ", "a\n", "a\u{200B}", String(repeating: "é", count: 257)] {
            XCTAssertThrowsError(try resourceRequest(.favorite(id: id)))
        }
        for id in ["é", "e\u{301}", "___", String(repeating: "é", count: 256)] {
            let request = try resourceRequest(.favorite(id: id))
            XCTAssertEqual(Data(request.target.id.utf8), Data(id.utf8))
        }
    }

    func testRequestRestorationCannotAdoptAnotherOwnerOrEpoch() throws {
        let membership = try memberRequest(), original = try resourceRequest()
        XCTAssertThrowsError(try Contract.decodeMembershipRequest(data: Contract.encode(membership), expectedUID: "reader_b"))
        for other in [try binding("reader_b"), try binding(epoch: 2)] {
            XCTAssertThrowsError(try Contract.decodeResourceRequest(data: Contract.encode(original), binding: other))
        }
        XCTAssertEqual(try Contract.decodeResourceRequest(data: Contract.encode(original), binding: binding()), original)
    }

    func testRequestsRequireEveryExactKeyAndStrictScalarTypes() throws {
        let member = try object(Contract.encode(memberRequest())), resource = try object(Contract.encode(resourceRequest()))
        for row in [member, resource] {
            let isResource = row["target"] != nil
            var variants: [[String: Any]] = []
            for key in row.keys {
                var missing = row; missing.removeValue(forKey: key); variants.append(missing)
                var null = row; null[key] = NSNull(); variants.append(null)
            }
            for extra: [String: Any] in [["unknown": true], ["schemaVersion": true], ["schemaVersion": "1"], ["schemaVersion": 2], ["expectedUID": 1], ["readID": 1]] {
                variants.append(row.merging(extra) { _, new in new })
            }
            for variant in variants {
                if isResource { XCTAssertThrowsError(try Contract.decodeResourceRequest(data: data(variant), binding: binding())) }
                else { XCTAssertThrowsError(try Contract.decodeMembershipRequest(data: data(variant), expectedUID: "reader_a")) }
            }
        }
        for changes: [String: Any] in [["membershipEpoch": true], ["membershipEpoch": "1"], ["membershipEpoch": 1.5], ["membershipEpoch": maximum + 1],
            ["target": ["kind": "preferences", "id": "other"]], ["target": ["kind": "favorite", "id": "article-1", "extra": true]], ["target": []]] {
            XCTAssertThrowsError(try Contract.decodeResourceRequest(data: data(resource.merging(changes) { _, new in new }), binding: binding()))
        }
    }

    func testResponseEchoBindsReadIDOwnerEpochAndByteExactUnicodeTarget() throws {
        let original = try resourceRequest(.favorite(id: "café")), nfd = try resourceRequest(.favorite(id: "cafe\u{301}"))
        XCTAssertNotEqual(original, nfd)
        invalidResource(try resourceResponse(nfd), request: original)
        let response = try resourceResponse(original)
        for changes: [String: Any] in [["readID": "22345678-1234-1234-1234-123456789abc"], ["expectedUID": "reader_b"], ["membershipEpoch": 2], ["extra": true]] {
            var altered = response; let raw = try XCTUnwrap(response["request"] as? [String: Any])
            altered["request"] = raw.merging(changes) { _, new in new }; invalidResource(altered, request: original)
        }
        invalidResource(try resourceResponse(original, payload: ["id": "cafe\u{301}", "pressAccreditation": false]), request: original)
        let membership = try memberRequest(); var wrong = try memberResponse(membership)
        var echo = try XCTUnwrap(wrong["request"] as? [String: Any]); echo["readID"] = "22345678-1234-1234-1234-123456789abc"
        wrong["request"] = echo; invalidMember(wrong, request: membership)
    }

    func testExpiryIsPositiveJSSafeDataAndNeverAnImplicitClockOrSDKPermission() throws {
        let request = try memberRequest(), resource = try resourceRequest()
        for value in [Int64(1), maximum] {
            var response = try memberResponse(request); response["validUntilMs"] = value
            XCTAssertEqual(try Contract.decodeMembershipResponse(data: data(response), for: request).validUntilMs, value)
        }
        for value: Any in [Int64(0), Int64(-1), maximum + 1, true, "100", 1.5, NSNull()] {
            var response = try memberResponse(request); response["validUntilMs"] = value; invalidMember(response, request: request)
            var other = try resourceResponse(resource); other["validUntilMs"] = value; invalidResource(other, request: resource)
        }
        // Expiry 1 can be structurally decoded. The composition must separately
        // reject it against its trusted clock before starting any SDK operation.
    }

    func testMissingMembershipAndFrozenMembershipRemainDistinctFromActiveAuthority() throws {
        let request = try memberRequest(); var response = try memberResponse(request); response["membership"] = NSNull()
        XCTAssertNil(try Contract.decodeMembershipResponse(data: data(response), for: request).membership)
        let deletion = try ReaderAccountDeletionContract.Request(expectedUID: "reader_a", membershipEpoch: 1)
        var frozen = member(); frozen["state"] = "deletion_frozen"; frozen["deletionRequestID"] = deletion.requestID
        response["membership"] = frozen
        XCTAssertEqual(try Contract.decodeMembershipResponse(data: data(response), for: request).membership?.state, .deletionFrozen)
        for row: [String: Any] in [member().merging(["deletionRequestID": NSNull()]) { _, new in new },
            frozen.merging(["deletionRequestID": String(repeating: "a", count: 64)]) { _, new in new },
            member().merging(["ownerUID": "reader_b"]) { _, new in new }, member().merging(["unknown": true]) { _, new in new },
            member().merging(["epoch": true]) { _, new in new }] {
            response["membership"] = row; invalidMember(response, request: request)
        }
        let resource = try resourceRequest()
        for membership: Any in [NSNull(), frozen, member().merging(["epoch": 2]) { _, new in new }] {
            var other = try resourceResponse(resource); other["membership"] = membership; invalidResource(other, request: resource)
        }
    }

    func testBoundaryRequiresExactLowercaseHashesAndSchemaWithoutExtraAuthorityClaims() throws {
        let request = try resourceRequest(), original = try resourceResponse(request)
        let boundary = try XCTUnwrap(original["boundary"] as? [String: Any])
        var variants: [[String: Any]] = []
        for key in boundary.keys {
            var missing = boundary; missing.removeValue(forKey: key); variants.append(missing)
            var null = boundary; null[key] = NSNull(); variants.append(null)
        }
        for changes: [String: Any] in [["readerSchemaVersion": 2], ["readerSchemaVersion": true], ["writerFenceRevision": String(repeating: "A", count: 64)],
            ["migrationRevision": String(repeating: "a", count: 63)], ["migrationRevision": String(repeating: "z", count: 64)], ["sdkStartAllowed": true]] {
            variants.append(boundary.merging(changes) { _, new in new })
        }
        for variant in variants { var response = original; response["boundary"] = variant; invalidResource(response, request: request) }
    }

    func testResourceStateDistinguishesMissingTombstoneAndValueAtMaximumRevision() throws {
        let favorite = try resourceRequest(), preferences = try resourceRequest(.preferences)
        for revision in [Int64(0), Int64(1), maximum] {
            let result = try Contract.decodeResourceResponse(data: data(resourceResponse(favorite, revision: revision, exists: false)), for: favorite)
            XCTAssertEqual(result.resource.revision, revision); XCTAssertNil(result.resource.payload)
        }
        let missing = try Contract.decodeResourceResponse(data: data(resourceResponse(preferences, revision: 0, exists: false)), for: preferences)
        XCTAssertFalse(missing.resource.exists)
        invalidResource(try resourceResponse(preferences, revision: 1, exists: false), request: preferences)
        invalidResource(try resourceResponse(favorite, revision: 0), request: favorite)
        invalidResource(try resourceResponse(favorite, revision: maximum + 1), request: favorite)
        invalidResource(try resourceResponse(favorite, revision: -1), request: favorite)
        invalidResource(try resourceResponse(favorite, payload: NSNull()), request: favorite)
        invalidResource(try resourceResponse(favorite, exists: false, payload: ["id": "article-1", "pressAccreditation": false]), request: favorite)
        var bad = try resourceResponse(favorite); bad["resource"] = ["revision": 1, "exists": 1, "payload": NSNull()]; invalidResource(bad, request: favorite)
        let maxValue = try Contract.decodeResourceResponse(data: data(resourceResponse(favorite, revision: maximum)), for: favorite)
        XCTAssertEqual(maxValue.resource.revision, maximum)
    }

    func testMetadataUsesExistingStrictMutationValidatorIncludingOptionalNullsAndContentExclusion() throws {
        let request = try resourceRequest(), payload: [String: Any] = ["id": "article-1", "pressAccreditation": false]
        for key in FavoritesRecord.Metadata.keys {
            let invalid = payload.merging([key: NSNull()]) { _, new in new }
            invalidResource(try resourceResponse(request, payload: invalid), request: request)
        }
        for changes: [String: Any] in [["content": "private"], ["readerMutation": [:]], ["pressAccreditation": 1], ["stjerne": 11], ["stjerne": true],
            ["name": String(repeating: "é", count: 1025)], ["subtitle": "a\u{0}b"], ["coverURL": "file:///private/image"], ["coverURL": "https:example.com"],
            ["coverURL": "https://user:pass@example.com/image"], ["topicsIDs": Array(repeating: "topic", count: 33)]] {
            invalidResource(try resourceResponse(request, payload: payload.merging(changes) { _, new in new }), request: request)
        }
    }

    func testPreferencesKeepUnicodeOrderAndExplicitFalseWithNoDuplicateNormalization() throws {
        let request = try resourceRequest(.preferences), ids = ["é", "e\u{301}", "a/b", "film 🎬"]
        let valid: [String: Any] = ["interestTopicIDs": ids, "onboardingCompleted": false]
        let result = try Contract.decodeResourceResponse(data: data(resourceResponse(request, payload: valid)), for: request)
        guard case .preferences(let preferences) = result.resource.payload else { return XCTFail("Expected preferences") }
        XCTAssertEqual(preferences.interestTopicIDs.map { Data($0.utf8) }, ids.map { Data($0.utf8) }); XCTAssertFalse(preferences.onboardingCompleted)
        for changes: [String: Any] in [["interestTopicIDs": ["a", "a"]], ["interestTopicIDs": Array(repeating: "a", count: 21)], ["interestTopicIDs": NSNull()],
            ["interestTopicIDs": [""]], ["onboardingCompleted": 0], ["onboardingCompleted": NSNull()], ["newsletterOptIn": true]] {
            invalidResource(try resourceResponse(request, payload: valid.merging(changes) { _, new in new }), request: request)
        }
    }

    func testSnapshotEqualityDoesNotFoldUnicodePayloadsIntoTheSameCurrentValue() throws {
        let request = try resourceRequest()
        let a = try Contract.decodeResourceResponse(data: data(resourceResponse(request, payload: ["id": "article-1", "pressAccreditation": false, "name": "é"])), for: request)
        let b = try Contract.decodeResourceResponse(data: data(resourceResponse(request, payload: ["id": "article-1", "pressAccreditation": false, "name": "e\u{301}"])), for: request)
        XCTAssertNotEqual(a, b)
        let prefs = try resourceRequest(.preferences)
        let first = try Contract.decodeResourceResponse(data: data(resourceResponse(prefs, payload: ["interestTopicIDs": ["é"], "onboardingCompleted": false])), for: prefs)
        let second = try Contract.decodeResourceResponse(data: data(resourceResponse(prefs, payload: ["interestTopicIDs": ["e\u{301}"], "onboardingCompleted": false])), for: prefs)
        XCTAssertNotEqual(first, second)
    }

    func testResponseRequiresEveryKeyExactScopeAndNoFalseSDKOrDeletionClaim() throws {
        let membership = try memberRequest(), resource = try resourceRequest()
        for isResource in [false, true] {
            let row = try isResource ? resourceResponse(resource) : memberResponse(membership)
            var variants: [[String: Any]] = []
            for key in row.keys {
                var missing = row; missing.removeValue(forKey: key); variants.append(missing)
                if isResource || key != "membership" { var null = row; null[key] = NSNull(); variants.append(null) }
            }
            for changes: [String: Any] in [["schemaVersion": true], ["schemaVersion": 2], ["scope": "reader-mutation-v1"], ["sdkStartAllowed": true], ["accountDeletionComplete": true]] {
                variants.append(row.merging(changes) { _, new in new })
            }
            for variant in variants {
                if isResource { invalidResource(variant, request: resource) } else { invalidMember(variant, request: membership) }
            }
        }
    }

    func testBoundedWireRejectsOversizeAndMalformedDataBeforeAnyFallback() throws {
        let member = try memberRequest(), resource = try resourceRequest()
        let encoded = try Contract.encode(member)
        let exact = encoded + Data(repeating: 32, count: Contract.maximumRequestBytes - encoded.count)
        XCTAssertEqual(try Contract.decodeMembershipRequest(data: exact, expectedUID: "reader_a"), member)
        XCTAssertThrowsError(try Contract.decodeMembershipRequest(data: exact + Data([32]), expectedUID: "reader_a"))
        let response = try data(memberResponse(member))
        let exactResponse = response + Data(repeating: 32, count: Contract.maximumResponseBytes - response.count)
        XCTAssertEqual(try Contract.decodeMembershipResponse(data: exactResponse, for: member).request, member)
        for bytes in [Data(), Data("broken".utf8), Data("[]".utf8), Data("null".utf8), exactResponse + Data([32])] {
            XCTAssertThrowsError(try Contract.decodeMembershipResponse(data: bytes, for: member))
            XCTAssertThrowsError(try Contract.decodeResourceResponse(data: bytes, for: resource))
        }
        XCTAssertThrowsError(try Contract.decodeResourceRequest(data: Data(repeating: 32, count: Contract.maximumRequestBytes + 1), binding: binding()))
    }
}
