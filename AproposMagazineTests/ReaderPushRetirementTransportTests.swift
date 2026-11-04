import FirebaseCore
import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderPushRetirementTransportTests: XCTestCase {
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Transport = ReaderDeletionHTTPTransport
    private typealias Coordinator = ReaderAccountDeletionCoordinator
    private static let appID = "1:123456789:ios:abcdef123456"
    private static let installationID = "123e4567-e89b-42d3-a456-426614174000"

    @MainActor private final class Gate<Value> {
        let entered = XCTestExpectation(description: "Injected physical effect entered")
        private var continuation: CheckedContinuation<Value, Error>?
        func wait() async throws -> Value {
            try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        }
        func finish(_ value: Value) { let held = continuation; continuation = nil; held?.resume(returning: value) }
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let configuration: Transport.Configuration
        let parent: Contract.Request
        let ledger: Contract.LedgerRequest
        let preparation: Contract.PushRequest
        let commit: Contract.PushRequest
        var time: Int64 = 100_123
        var allowed = true, didReturn = false
        var credentialCalls = 0
        var requests: [URLRequest] = []
        var admission: (@MainActor () -> Bool)?
        var credentialHook: (@MainActor () async throws -> Transport.Credentials)?
        var executeHook: (@MainActor (URLRequest) async throws -> (Data, HTTPURLResponse))?
        var validationHook: (@MainActor () async throws -> Void)?
        var currentHook: (@MainActor () -> Void)?
        var rawResponse: Data?
        var status = 200
        init() throws {
            configuration = try .init(projectID: "fixture-project", appID: ReaderPushRetirementTransportTests.appID,
                endpointURL: URL(string: "https://reader.example.invalid/delete")!)
            parent = try .init(expectedUID: "reader_a", membershipEpoch: 4)
            ledger = try .init(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: parent.requestID)
            let installation = try Contract.PushInstallation(installationId: ReaderPushRetirementTransportTests.installationID,
                key: String(repeating: "k", count: 43), requestId: "retirement_request_001",
                expected: .init(ownerEpoch: 7, revision: 11, clientRevision: 23))
            preparation = try .init(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: parent.requestID,
                ledgerRequestID: ledger.requestID, installation: installation)
            let snapshot = try Contract.PushSnapshot(requestId: installation.requestId, installationId: installation.installationId,
                appId: configuration.appID, ownerUID: "reader_a", ownerEpoch: 7, revision: 11, clientRevision: 23,
                stateDigest: String(repeating: "d", count: 64))
            commit = try preparation.committing(snapshot)
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: false))
        }
        func action(_ request: Contract.PushRequest, phase: Coordinator.Phase? = nil) -> Coordinator.ActionTicket {
            .init(actionID: UUID(), context: canonical.contextTicket(), request: parent,
                phase: phase ?? (request.scope == Contract.pushPreparationScope ? .pushPreparation : .pushRetirement),
                ledgerRequest: ledger, pushRequest: request, startedAtMs: 100_123, coordinatorID: UUID())
        }
        func make(_ request: Contract.PushRequest, phase: Coordinator.Phase? = nil,
                  proofOwner: String = "reader_a", proofKind: Coordinator.ReauthenticationResult.Kind = .reauthenticated) -> Transport {
            let action = action(request, phase: phase)
            let proof = Coordinator.ReauthenticationResult(action: action, authenticatedUID: proofOwner, authTimeMs: 100_000, kind: proofKind)
            return Transport(configuration: configuration, action: action, proof: proof,
                credentials: { [unowned self] check in
                    credentialCalls += 1; admission = check
                    if let credentialHook { return try await credentialHook() }
                    return tokens()
                }, isCurrent: { [unowned self] in
                    currentHook?(); return allowed && canonical.isCurrent(action.context)
                }, execute: { [unowned self] input in
                    requests.append(input)
                    if let executeHook { return try await executeHook(input) }
                    return try reply(input, request: request)
                }, now: { [unowned self] in time }, validateOriginal: validationHook)
        }
        func tokens(owner: String = "reader_a", appID: String = "1:123456789:ios:abcdef123456",
                    authExpiry: Int64 = 600_000, appExpiry: Int64 = 500_000) -> Transport.Credentials {
            .init(ownerUID: owner, projectID: configuration.projectID, appID: appID, idToken: "local.auth.token",
                appCheckToken: "limited.use.token", authTimeMs: 100_000, authValidUntilMs: authExpiry, appCheckValidUntilMs: appExpiry)
        }
        func prepareObject() throws -> [String: Any] {
            let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(commit.installation.snapshot)))
            return ["schemaVersion": 1, "scope": Contract.pushPreparationScope, "expectedUID": preparation.expectedUID,
                "membershipEpoch": preparation.membershipEpoch, "parentRequestID": preparation.parentRequestID,
                "ledgerRequestID": preparation.ledgerRequestID, "installationId": preparation.installation.installationId,
                "status": "prepared", "preparedOnly": true, "retirementComplete": false, "accountDeletionComplete": false,
                "historicalMaterialComplete": false, "deliveriesRecalled": false, "unresolved": Contract.pushUnresolved, "snapshot": snapshot]
        }
        func commitObject() -> [String: Any] {
            ["requestID": commit.requestID, "scope": Contract.pushScope, "parentRequestID": commit.parentRequestID,
                "ledgerRequestID": commit.ledgerRequestID, "installationId": commit.installation.installationId,
                "status": "installationRetired", "accountDeletionComplete": false, "historicalMaterialComplete": false,
                "deliveriesRecalled": false, "unresolved": Contract.pushUnresolved,
                "retirementReceipt": ["schemaVersion": 1, "status": "retired", "requestId": commit.installation.requestId,
                    "installationId": commit.installation.installationId, "ownerUID": "reader_a", "appId": configuration.appID,
                    "ownerEpoch": 7, "revision": 12, "clientRevision": 23, "retiredAtMs": 100_100,
                    "retiredChallenges": 1, "removedTokenOwners": 1, "preservedForeignChallenges": 1,
                    "preservedForeignTokenOwners": 0, "preservedUnprovenTokenOwners": 0,
                    "historicalMaterialComplete": false, "accountDeletionComplete": false, "deliveriesRecalled": false]]
        }
        func reply(_ input: URLRequest, request: Contract.PushRequest) throws -> (Data, HTTPURLResponse) {
            let object = request.scope == Contract.pushPreparationScope ? try prepareObject() : commitObject()
            return (try rawResponse ?? JSONSerialization.data(withJSONObject: object),
                try XCTUnwrap(HTTPURLResponse(url: input.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
        }
        func roundTrip() {
            _ = canonical.adopt(.init(uid: "reader_b", email: "local@example.invalid", isEmailVerified: false))
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: false))
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected rejection", file: file, line: line) } catch {}
    }
    private func wait<T>(_ gate: Gate<T>) async {
        let result = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 3); XCTAssertEqual(result, .completed)
    }

    func testRequestPreservesOriginalFamilyAndIndependentEpochsWithServerHashVector() throws {
        let f = try Fixture()
        XCTAssertEqual(f.parent.requestID, "4917fcb67f0d15d32a1c3784d58228cd34e17eb47a3d50242a98a6dfcb6dded6")
        XCTAssertEqual(f.ledger.requestID, "17ab8fce084767cb0b556d4df8f86d006f8aad97045a41e61c913d91dea89ef5")
        XCTAssertEqual(f.commit.requestID, "dd8ef888d7c77bd5b83f01d6b84ec7e12f8ab9e438e1f2bdd41fb204437e5170")
        XCTAssertEqual(f.preparation.membershipEpoch, 4); XCTAssertEqual(f.preparation.installation.expected.ownerEpoch, 7)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.preparation)) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID", "ledgerRequestID", "installation"])
        XCTAssertNil((raw["installation"] as? [String: Any])?["snapshot"])
        XCTAssertEqual(try JSONDecoder().decode(Contract.PushRequest.self, from: JSONEncoder().encode(f.commit)), f.commit)
        XCTAssertEqual(f.commit.installation.key, f.preparation.installation.key)
        XCTAssertEqual(f.commit.installation.requestId, f.preparation.installation.requestId)
    }
    func testConstructorsRejectGuestUnsafeCountersChangedParentsAndReplacementSnapshot() throws {
        let f = try Fixture()
        for n in [Int64.min, -1, 0, Contract.maximumSafeInteger, Int64.max] {
            XCTAssertThrowsError(try Contract.PushCounters(ownerEpoch: n, revision: 1, clientRevision: 1))
            XCTAssertThrowsError(try Contract.PushCounters(ownerEpoch: 1, revision: n, clientRevision: 1))
            XCTAssertThrowsError(try Contract.PushCounters(ownerEpoch: 1, revision: 1, clientRevision: n))
        }
        XCTAssertNoThrow(try Contract.PushCounters(ownerEpoch: Contract.maximumSafeInteger - 1, revision: 1, clientRevision: 1))
        XCTAssertThrowsError(try Contract.PushRequest(expectedUID: "", membershipEpoch: 4, parentRequestID: f.parent.requestID,
            ledgerRequestID: f.ledger.requestID, installation: f.preparation.installation))
        XCTAssertThrowsError(try Contract.PushRequest(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: String(repeating: "a", count: 64),
            ledgerRequestID: f.ledger.requestID, installation: f.preparation.installation))
        XCTAssertThrowsError(try Contract.PushRequest(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: f.parent.requestID,
            ledgerRequestID: f.parent.requestID, installation: f.preparation.installation))
        XCTAssertThrowsError(try Contract.PushRequest(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: f.parent.requestID,
            ledgerRequestID: f.ledger.requestID, installation: f.preparation.installation, scope: Contract.pushScope))
        XCTAssertThrowsError(try f.commit.committing(XCTUnwrap(f.commit.installation.snapshot)))
        let changed = try Contract.PushSnapshot(requestId: f.preparation.installation.requestId, installationId: Self.installationID,
            appId: Self.appID, ownerUID: "reader_b", ownerEpoch: 7, revision: 11, clientRevision: 23, stateDigest: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try f.preparation.committing(changed))
    }
    func testRequestDecoderRejectsExtraAndNullSnapshotInsteadOfInferringAnotherPhase() throws {
        let f = try Fixture(); let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.preparation)) as? [String: Any])
        var extra = original; extra["endpoint"] = "private"; XCTAssertThrowsError(try JSONDecoder().decode(Contract.PushRequest.self, from: data(extra)))
        for replacement in [NSNull(), ["stateDigest": String(repeating: "a", count: 64)]] as [Any] {
            var changed = original; var installation = try XCTUnwrap(changed["installation"] as? [String: Any])
            installation["snapshot"] = replacement; changed["installation"] = installation
            XCTAssertThrowsError(try JSONDecoder().decode(Contract.PushRequest.self, from: data(changed)))
        }
        var changed = original; var installation = try XCTUnwrap(changed["installation"] as? [String: Any])
        var expected = try XCTUnwrap(installation["expected"] as? [String: Any]); expected["authority"] = true
        installation["expected"] = expected; changed["installation"] = installation
        XCTAssertThrowsError(try JSONDecoder().decode(Contract.PushRequest.self, from: data(changed)))
    }
    func testPreparedReceiptIsExactReadOnlyObservationNotCompletion() throws {
        let f = try Fixture(), r = try Contract.decodePushPreparationReceipt(data: data(Fixture().prepareObject()), for: f.preparation, appID: Self.appID)
        XCTAssertEqual(r.status, "prepared"); XCTAssertTrue(r.preparedOnly); XCTAssertFalse(r.retirementComplete)
        XCTAssertFalse(r.accountDeletionComplete); XCTAssertFalse(r.deliveriesRecalled); XCTAssertFalse(r.historicalMaterialComplete)
        XCTAssertEqual(try f.preparation.committing(r.snapshot), f.commit)
    }
    func testPreparedReceiptRejectsEveryChangedBindingAndClaim() throws {
        let f = try Fixture(), original = try f.prepareObject()
        let fields: [String: Any] = ["schemaVersion": 2, "scope": Contract.pushScope, "expectedUID": "reader_b", "membershipEpoch": 7,
            "parentRequestID": f.ledger.requestID, "ledgerRequestID": f.parent.requestID, "installationId": "123e4567-e89b-42d3-a456-426614174001",
            "status": "retired", "preparedOnly": false, "retirementComplete": true, "accountDeletionComplete": true,
            "historicalMaterialComplete": true, "deliveriesRecalled": true, "unresolved": Array(Contract.pushUnresolved.reversed()),
            "authorizationValidUntilMs": 123_456, "key": f.preparation.installation.key]
        for (key, value) in fields { var altered = original; altered[key] = value
            XCTAssertThrowsError(try Contract.decodePushPreparationReceipt(data: data(altered), for: f.preparation, appID: Self.appID), key)
        }
        let nested: [String: Any] = ["requestId": "different_request_001", "installationId": "123e4567-e89b-42d3-a456-426614174001",
            "appId": "1:123456789:ios:abcdef999999", "ownerUID": "reader_b", "ownerEpoch": 4, "revision": 12, "clientRevision": 24,
            "stateDigest": String(repeating: "D", count: 64), "token": "private", "schemaVersion": true]
        for (key, value) in nested { var altered = original; var snapshot = try XCTUnwrap(altered["snapshot"] as? [String: Any])
            snapshot[key] = value; altered["snapshot"] = snapshot
            XCTAssertThrowsError(try Contract.decodePushPreparationReceipt(data: data(altered), for: f.preparation, appID: Self.appID), key)
        }
    }
    func testRetirementReceiptAcceptsOnlyHistoricalSingleInstallationResult() throws {
        let f = try Fixture(), r = try Contract.decodePushReceipt(data: data(Fixture().commitObject()), for: f.commit, appID: Self.appID)
        XCTAssertEqual(r.status, "installationRetired"); XCTAssertEqual(r.retirementReceipt.revision, 12)
        XCTAssertEqual(r.retirementReceipt.ownerEpoch, 7); XCTAssertFalse(r.accountDeletionComplete)
        XCTAssertFalse(r.deliveriesRecalled); XCTAssertFalse(r.historicalMaterialComplete)
        XCTAssertEqual(r.unresolved, Contract.pushUnresolved)
    }
    func testRetirementReceiptRejectsCountsPrivateExtrasUnsafeNumbersAndBroadenedClaims() throws {
        let f = try Fixture(), original = f.commitObject()
        let fields: [String: Any] = ["requestID": f.parent.requestID, "scope": Contract.pushPreparationScope, "parentRequestID": f.ledger.requestID,
            "ledgerRequestID": f.parent.requestID, "installationId": "123e4567-e89b-42d3-a456-426614174001", "status": "accountDeleted",
            "accountDeletionComplete": true, "historicalMaterialComplete": true, "deliveriesRecalled": true,
            "unresolved": Contract.ledgerUnresolved, "snapshot": [:]]
        for (key, value) in fields { var altered = original; altered[key] = value
            XCTAssertThrowsError(try Contract.decodePushReceipt(data: data(altered), for: f.commit, appID: Self.appID), key)
        }
        let nested: [String: Any] = ["schemaVersion": true, "status": "active", "requestId": "different_request_001",
            "installationId": "123e4567-e89b-42d3-a456-426614174001", "ownerUID": "reader_b", "appId": "other-app",
            "ownerEpoch": 4, "revision": 11, "clientRevision": 24, "retiredAtMs": Contract.maximumSafeInteger + 1,
            "retiredChallenges": 3, "removedTokenOwners": -1, "preservedForeignChallenges": true,
            "preservedForeignTokenOwners": 0.5, "preservedUnprovenTokenOwners": 2,
            "historicalMaterialComplete": true, "accountDeletionComplete": true, "deliveriesRecalled": true, "deliveryNonce": "private"]
        for (key, value) in nested { var altered = original; var child = try XCTUnwrap(altered["retirementReceipt"] as? [String: Any])
            child[key] = value; altered["retirementReceipt"] = child
            XCTAssertThrowsError(try Contract.decodePushReceipt(data: data(altered), for: f.commit, appID: Self.appID), key)
        }
    }
    func testDuplicateEscapedNestedKeysAndOversizedJSONCannotBeCollapsedIntoValidReceipt() throws {
        let f = try Fixture(); let raw = try XCTUnwrap(String(data: data(f.prepareObject()), encoding: .utf8))
        let cases = [raw.replacingOccurrences(of: "\"scope\":", with: "\"scope\":\"wrong\",\"scope\":"),
            raw.replacingOccurrences(of: "\"ownerUID\":", with: "\"ownerUID\":\"reader_b\",\"owner\\u0055ID\":"),
            raw.replacingOccurrences(of: "\"accountDeletionComplete\":", with: "\"accountDeletionComplete\":true,\"accountDeletionComplete\":"),
            String(repeating: " ", count: 16_385) + raw]
        for raw in cases { XCTAssertThrowsError(try Contract.decodePushPreparationReceipt(data: Data(raw.utf8), for: f.preparation, appID: Self.appID)) }
        var partial = try f.prepareObject(); partial.removeValue(forKey: "deliveriesRecalled")
        XCTAssertThrowsError(try Contract.decodePushPreparationReceipt(data: data(partial), for: f.preparation, appID: Self.appID))
    }
    func testActualTransportUsesFreshCredentialsAndOriginalRequestForEachExplicitPhase() async throws {
        let f = try Fixture()
        let prepared = try await f.make(f.preparation).sendPushPreparation(f.preparation)
        let accepted = try Contract.decodePushPreparationReceipt(data: prepared, for: f.preparation, appID: Self.appID)
        let commit = try f.preparation.committing(accepted.snapshot)
        _ = try await f.make(commit).sendPushRetirement(commit)
        XCTAssertEqual(f.credentialCalls, 2); XCTAssertEqual(f.requests.count, 2)
        let first = try XCTUnwrap(f.requests.first), last = try XCTUnwrap(f.requests.last)
        XCTAssertEqual(try JSONDecoder().decode(Contract.PushRequest.self, from: XCTUnwrap(first.httpBody)), f.preparation)
        XCTAssertEqual(try JSONDecoder().decode(Contract.PushRequest.self, from: XCTUnwrap(last.httpBody)), f.commit)
        for request in f.requests {
            XCTAssertEqual(request.url, f.configuration.endpointURL); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local.auth.token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "limited.use.token")
            XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertEqual(request.timeoutInterval, 60)
        }
        XCTAssertEqual(f.admission?(), false)
    }
    func testWrongPhaseChangedDigestOrSnapshotAppRejectBeforeCredentials() async throws {
        let f = try Fixture()
        await rejected { try await f.make(f.preparation).sendPushRetirement(f.preparation) }
        await rejected { try await f.make(f.commit).sendPushPreparation(f.commit) }
        let s = try XCTUnwrap(f.commit.installation.snapshot)
        let changed = try Contract.PushSnapshot(requestId: s.requestId, installationId: s.installationId, appId: s.appId, ownerUID: s.ownerUID,
            ownerEpoch: s.ownerEpoch, revision: s.revision, clientRevision: s.clientRevision, stateDigest: String(repeating: "a", count: 64))
        await rejected { try await f.make(f.commit).sendPushRetirement(f.preparation.committing(changed)) }
        let wrongApp = try Contract.PushSnapshot(requestId: s.requestId, installationId: s.installationId, appId: "other-app", ownerUID: s.ownerUID,
            ownerEpoch: s.ownerEpoch, revision: s.revision, clientRevision: s.clientRevision, stateDigest: s.stateDigest)
        let wrong = try f.preparation.committing(wrongApp)
        await rejected { try await f.make(wrong).sendPushRetirement(wrong) }
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testOldCredentialCallbackAfterAToBToACannotSendEitherPhase() async throws {
        for phase in [false, true] {
            let f = try Fixture(), gate = Gate<Transport.Credentials>(), request = phase ? f.commit : f.preparation
            f.credentialHook = { try await gate.wait() }; let transport = f.make(request)
            let task = Task { phase ? try await transport.sendPushRetirement(request) : try await transport.sendPushPreparation(request) }
            await wait(gate); f.roundTrip(); gate.finish(f.tokens()); await rejected { try await task.value }
            XCTAssertTrue(f.requests.isEmpty)
        }
    }
    func testObservedCredentialDenialIsMonotoneEvenWhenSameUIDReturns() async throws {
        let f = try Fixture()
        f.credentialHook = {
            f.allowed = false; XCTAssertEqual(f.admission?(), false)
            f.allowed = true; XCTAssertEqual(f.admission?(), false); return f.tokens()
        }
        await rejected { try await f.make(f.commit).sendPushRetirement(f.commit) }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testCancelledCredentialWaitKeepsPhysicalWaitAndRejectsLateCompletion() async throws {
        let f = try Fixture(), gate = Gate<Transport.Credentials>(), transport = f.make(f.commit)
        f.credentialHook = { try await gate.wait() }
        let task = Task { defer { f.didReturn = true }; return try await transport.sendPushRetirement(f.commit) }
        await wait(gate); task.cancel(); await Task.yield(); XCTAssertFalse(f.didReturn)
        gate.finish(f.tokens()); await rejected { try await task.value }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testSingleUseReservationPrecedesCredentialReentryAndCannotPrepareAgainAfterCommit() async throws {
        let f = try Fixture(), gate = Gate<Transport.Credentials>(), transport = f.make(f.commit)
        f.credentialHook = { try await gate.wait() }
        let first = Task { try await transport.sendPushRetirement(f.commit) }; await wait(gate)
        await rejected { try await transport.sendPushRetirement(f.commit) }
        gate.finish(f.tokens()); _ = try await first.value
        await rejected { try await transport.sendPushPreparation(f.preparation) }
        XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, 1)
    }
    func testProofAndCredentialsMustBelongToOriginalReauthenticatedAccountAndApp() async throws {
        let f = try Fixture()
        await rejected { try await f.make(f.preparation, proofOwner: "reader_b").sendPushPreparation(f.preparation) }
        await rejected { try await f.make(f.preparation, proofKind: .sessionRefresh).sendPushPreparation(f.preparation) }
        XCTAssertEqual(f.credentialCalls, 0)
        for tokens in [f.tokens(owner: "reader_b"), f.tokens(appID: "1:123456789:ios:abcdef999999")] {
            f.credentialHook = { tokens }; await rejected { try await f.make(f.commit).sendPushRetirement(f.commit) }
        }
        XCTAssertTrue(f.requests.isEmpty)
    }
    func testIndependentShortestExpiryRejectsLateHTTPReceiptWithoutAnotherRequest() async throws {
        for kind in 0..<3 {
            let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
            let deadline: Int64 = kind == 2 ? 400_000 : 100_200
            f.credentialHook = { f.tokens(authExpiry: kind == 0 ? deadline : 600_000, appExpiry: kind == 1 ? deadline : 500_000) }
            f.executeHook = { _ in try await gate.wait() }
            let task = Task { try await f.make(f.commit).sendPushRetirement(f.commit) }
            await wait(gate); f.time = deadline
            gate.finish(try f.reply(XCTUnwrap(f.requests.first), request: f.commit))
            await rejected { try await task.value }; XCTAssertEqual(f.requests.count, 1)
        }
    }
    func testOldHTTPReceiptAfterAToBToAAndMalformedPreparedResponseCannotPublish() async throws {
        let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
        f.executeHook = { _ in try await gate.wait() }
        let task = Task { try await f.make(f.preparation).sendPushPreparation(f.preparation) }
        await wait(gate); f.roundTrip(); gate.finish(try f.reply(XCTUnwrap(f.requests.first), request: f.preparation))
        await rejected { try await task.value }
        let bad = try Fixture(); var object = try bad.prepareObject(); object["key"] = bad.preparation.installation.key
        bad.rawResponse = try data(object)
        await rejected { try await bad.make(bad.preparation).sendPushPreparation(bad.preparation) }
        XCTAssertEqual(bad.requests.count, 1)
    }
    func testUncertainTimeoutHasNoAutomaticPreparationAndExplicitRetryKeepsExactSnapshot() async throws {
        let f = try Fixture()
        f.executeHook = { _ in throw URLError(.timedOut) }
        await rejected { try await f.make(f.commit).sendPushRetirement(f.commit) }
        let original = try XCTUnwrap(f.requests.first?.httpBody)
        f.executeHook = nil
        let result = try await f.make(f.commit).sendPushRetirement(f.commit)
        XCTAssertEqual(try Contract.decodePushReceipt(data: result, for: f.commit, appID: Self.appID).status, "installationRetired")
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.credentialCalls, 2)
        XCTAssertEqual(f.requests.last?.httpBody, original)
        XCTAssertTrue(f.requests.allSatisfy { String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains(Contract.pushPreparationScope) == false })
    }
    func testOriginalStorageValidationRunsAroundEachAsyncPhaseAndRejectsChangedBinding() async throws {
        enum Changed: Error { case binding }
        for failureAt in 1...4 {
            let f = try Fixture(); var validations = 0
            f.validationHook = { validations += 1; if validations == failureAt { throw Changed.binding } }
            let transport = f.make(f.commit)
            if failureAt <= 3 { await rejected { try await transport.sendPushRetirement(f.commit) } }
            else { _ = try await transport.sendPushRetirement(f.commit) }
            XCTAssertEqual(validations, min(failureAt, 3))
            XCTAssertEqual(f.credentialCalls, failureAt == 1 ? 0 : 1)
            XCTAssertEqual(f.requests.count, failureAt <= 2 ? 0 : 1)
        }
    }
    func testCancellationDuringOriginalStorageReadRetainsPhysicalWaitAndBlocksDispatch() async throws {
        let f = try Fixture(), gate = Gate<Void>(); var validations = 0
        f.validationHook = { validations += 1; if validations == 2 { try await gate.wait() } }
        let transport = f.make(f.commit)
        let task = Task { defer { f.didReturn = true }; return try await transport.sendPushRetirement(f.commit) }
        await wait(gate); task.cancel(); await Task.yield(); XCTAssertFalse(f.didReturn)
        gate.finish(()); await rejected { try await task.value }
        XCTAssertEqual(f.credentialCalls, 1); XCTAssertTrue(f.requests.isEmpty)
    }
    func testOriginalStorageReadAfterResponseCannotOutliveCredentialExpiryOrAccount() async throws {
        for accountChanges in [false, true] {
            let f = try Fixture(), gate = Gate<Void>(); var validations = 0
            f.validationHook = { validations += 1; if validations == 3 { try await gate.wait() } }
            let task = Task { try await f.make(f.commit).sendPushRetirement(f.commit) }
            await wait(gate)
            if accountChanges { f.roundTrip() } else { f.time = 400_000 }
            gate.finish(()); await rejected { try await task.value }
            XCTAssertEqual(f.requests.count, 1)
        }
    }

}
