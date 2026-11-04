import FirebaseCore
import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderDeletionHTTPTransportTests: XCTestCase {
    private typealias Transport = ReaderDeletionHTTPTransport
    private typealias Coordinator = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private enum Fault: Error { case unavailable }
    @MainActor private final class Gate<Value> {
        let entered = XCTestExpectation(description: "Physical local effect entered")
        private var continuation: CheckedContinuation<Value, Error>?
        func wait() async throws -> Value {
            try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        }
        func finish(_ value: Value) { let held = continuation; continuation = nil; held?.resume(returning: value) }
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let configuration: Transport.Configuration
        let request: Contract.Request
        var time: Int64 = 100_123
        var allowed = true, completed = false
        var action: Coordinator.ActionTicket!
        var proof: Coordinator.ReauthenticationResult!
        var admission: (@MainActor () -> Bool)?
        var credentialCalls = 0, clockCalls = 0, currentCalls = 0
        var requests: [URLRequest] = []
        var credentialHook: (@MainActor () async throws -> Transport.Credentials)?
        var executeHook: (@MainActor (URLRequest) async throws -> (Data, HTTPURLResponse))?
        var currentHook: (@MainActor () -> Void)?, clockHook: (@MainActor () -> Void)?
        var responseURL: URL?, status = 200, mime = "application/json", contentLength: String?
        var rawData: Data?
        let parentDone = XCTestExpectation(description: "Actual parent coordinator receipt")
        let childDone = XCTestExpectation(description: "Actual ledger coordinator receipt")
        lazy var coordinator = Coordinator(canonical: canonical, currentMembershipEpoch: { _ in 4 },
            reauthenticate: { [unowned self] action in
                self.action = action
                let proof = Coordinator.ReauthenticationResult(action: action, authenticatedUID: "reader_a", authTimeMs: 100_000, kind: .reauthenticated)
                self.proof = proof; return proof
            }, send: { [unowned self] request, _ in
                let data = try self.receipt(request: request); self.parentDone.fulfill(); return data
            }, sendLedger: { [unowned self] request, _ in
                let data = try self.ledgerReceipt(request: request); self.childDone.fulfill(); return data
            }, nowMilliseconds: { [unowned self] in self.time }, scheduleTimeout: { _, _ in {} })

        init() throws {
            configuration = try .init(projectID: "fixture-project", appID: "1:123456789:ios:abcdef123456",
                endpointURL: URL(string: "https://reader.example.invalid/delete")!)
            request = try .init(expectedUID: "reader_a", membershipEpoch: 4)
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: false))
        }
        func capture(ledger: Bool = false) async {
            XCTAssertTrue(coordinator.begin(context: canonical.contextTicket(), membershipEpoch: 4, userConfirmed: true))
            let first = await XCTWaiter.fulfillment(of: [parentDone], timeout: 3); XCTAssertEqual(first, .completed)
            XCTAssertEqual(coordinator.status, .scopedCloudDataRemoved)
            if ledger {
                XCTAssertTrue(coordinator.beginLedgerCleanup(userConfirmed: true))
                let second = await XCTWaiter.fulfillment(of: [childDone], timeout: 3); XCTAssertEqual(second, .completed)
                XCTAssertEqual(coordinator.status, .ledgerDataRemoved)
            }
        }
        func make(proof: Coordinator.ReauthenticationResult? = nil) -> Transport {
            let original = action!
            return Transport(configuration: configuration, action: original, proof: proof ?? self.proof!,
                credentials: { [unowned self] admission in
                    self.credentialCalls += 1; self.admission = admission
                    if let hook = self.credentialHook { return try await hook() }
                    return self.tokens()
                }, isCurrent: { [unowned self] in
                    self.currentCalls += 1; self.currentHook?()
                    return self.allowed && self.canonical.isCurrent(original.context)
                }, execute: { [unowned self] request in
                    self.requests.append(request)
                    if let hook = self.executeHook { return try await hook(request) }
                    return try self.reply(request)
                }, now: { [unowned self] in self.clockCalls += 1; self.clockHook?(); return self.time })
        }
        func tokens(owner: String = "reader_a", project: String? = nil, app: String? = nil,
                    id: String = "local.id.token", appCheck: String = "limited.use.token", authTime: Int64 = 100_000,
                    authExpiry: Int64 = 600_000, appExpiry: Int64 = 500_000) -> Transport.Credentials {
            .init(ownerUID: owner, projectID: project ?? configuration.projectID, appID: app ?? configuration.appID,
                idToken: id, appCheckToken: appCheck, authTimeMs: authTime, authValidUntilMs: authExpiry, appCheckValidUntilMs: appExpiry)
        }
        func receipt(request: Contract.Request) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "scope": Contract.scope,
                "status": "scopedCloudDataRemoved", "accountDeletionComplete": false, "unresolved": Contract.unresolved,
                "removedFavoriteDocuments": 2])
        }
        func ledgerReceipt(request: Contract.LedgerRequest) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "parentRequestID": request.parentRequestID,
                "scope": Contract.ledgerScope, "status": "ledgerDataRemoved", "accountDeletionComplete": false,
                "unresolved": Contract.ledgerUnresolved, "removedReceiptDocuments": 3, "removedRevisionDocuments": 3])
        }
        func reply(_ input: URLRequest) throws -> (Data, HTTPURLResponse) {
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(input.httpBody)) as? [String: Any]
            let data: Data
            if let rawData { data = rawData }
            else if body?["scope"] as? String == Contract.ledgerScope {
                data = try ledgerReceipt(request: JSONDecoder().decode(Contract.LedgerRequest.self, from: XCTUnwrap(input.httpBody)))
            } else { data = try receipt(request: JSONDecoder().decode(Contract.Request.self, from: XCTUnwrap(input.httpBody))) }
            var headers = ["Content-Type": mime]; if let contentLength { headers["Content-Length"] = contentLength }
            return (data, try XCTUnwrap(HTTPURLResponse(url: responseURL ?? configuration.endpointURL, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: headers)))
        }
        func roundTrip() {
            _ = canonical.adopt(.init(uid: "reader_b", email: "local@example.invalid", isEmailVerified: false))
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: false))
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected original attempt rejection", file: file, line: line) } catch {}
    }
    private func wait<T>(_ gate: Gate<T>) async {
        let result = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 3); XCTAssertEqual(result, .completed)
    }

    func testConstructionIsInertAndConfigurationRequiresExactProjectAppAndHTTPS() async throws {
        let f = try Fixture(); await f.capture(); _ = f.make()
        XCTAssertEqual(f.currentCalls, 0); XCTAssertEqual(f.clockCalls, 0); XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
        for raw in ["http://reader.example.invalid/delete", "https://reader.example.invalid/", "https://user:pass@reader.example.invalid/delete",
                    "https://reader.example.invalid/delete?q=1", "https://reader.example.invalid/delete#secret"] {
            XCTAssertThrowsError(try Transport.Configuration(projectID: f.configuration.projectID, appID: f.configuration.appID, endpointURL: URL(string: raw)!))
        }
        for project in ["", "bad", "fixture-project\n", "other project"] {
            XCTAssertThrowsError(try Transport.Configuration(projectID: project, appID: f.configuration.appID, endpointURL: f.configuration.endpointURL))
        }
        for app in ["", "1:local:ios:fixture", f.configuration.appID + "\n"] {
            XCTAssertThrowsError(try Transport.Configuration(projectID: f.configuration.projectID, appID: app, endpointURL: f.configuration.endpointURL))
        }
    }
    func testActualParentRequestKeepsExactWireHeadersAndStrictPartialReceipt() async throws {
        let f = try Fixture(); await f.capture(); let transport = f.make()
        let data = try await transport.send(f.request), receipt = try Contract.decodeReceipt(data: data, for: f.request)
        XCTAssertFalse(receipt.accountDeletionComplete); XCTAssertEqual(receipt.status, .scopedCloudDataRemoved)
        let request = try XCTUnwrap(f.requests.first)
        XCTAssertEqual(f.requests.count, 1); XCTAssertEqual(f.credentialCalls, 1)
        XCTAssertEqual(request.httpBody, Data("{\"expectedUID\":\"reader_a\",\"membershipEpoch\":4}".utf8))
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url, f.configuration.endpointURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local.id.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "limited.use.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 60); XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData); XCTAssertEqual(f.admission?(), false)
    }
    func testActualLedgerPhaseUsesOriginalParentAndIndependentWireShape() async throws {
        let f = try Fixture(); await f.capture(ledger: true); let request = try XCTUnwrap(f.action.ledgerRequest)
        let data = try await f.make().sendLedger(request), receipt = try Contract.decodeLedgerReceipt(data: data, for: request)
        XCTAssertEqual(receipt.status, .ledgerDataRemoved); XCTAssertFalse(receipt.accountDeletionComplete)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.requests.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID"])
        XCTAssertEqual(object["parentRequestID"] as? String, f.request.requestID)
        XCTAssertEqual(object["scope"] as? String, Contract.ledgerScope)
    }
    func testWrongPhaseOrChangedOriginalRequestNeverObtainsCredentials() async throws {
        let f = try Fixture(); await f.capture()
        let child = try Contract.LedgerRequest(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: f.request.requestID)
        await rejected { try await f.make().sendLedger(child) }
        await rejected { try await f.make().send(Contract.Request(expectedUID: "reader_b", membershipEpoch: 4)) }
        await rejected { try await f.make().send(Contract.Request(expectedUID: "reader_a", membershipEpoch: 5)) }
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
        let ledger = try Fixture(); await ledger.capture(ledger: true)
        await rejected { try await ledger.make().send(ledger.request) }; XCTAssertEqual(ledger.credentialCalls, 0)
    }
    func testProofMustBeOriginalReauthenticationAndWithinCurrentActionSecond() async throws {
        let f = try Fixture(); await f.capture(); let other = try Fixture(); await other.capture()
        let invalid = [Coordinator.ReauthenticationResult(action: other.action, authenticatedUID: "reader_a", authTimeMs: 100_000, kind: .reauthenticated),
            .init(action: f.action, authenticatedUID: "reader_b", authTimeMs: 100_000, kind: .reauthenticated),
            .init(action: f.action, authenticatedUID: "reader_a", authTimeMs: 100_000, kind: .sessionRefresh),
            .init(action: f.action, authenticatedUID: "reader_a", authTimeMs: 99_000, kind: .reauthenticated),
            .init(action: f.action, authenticatedUID: "reader_a", authTimeMs: 101_000, kind: .reauthenticated),
            .init(action: f.action, authenticatedUID: "reader_a", authTimeMs: 100_001, kind: .reauthenticated)]
        for proof in invalid { await rejected { try await f.make(proof: proof).send(f.request) } }
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testCredentialsCannotReplaceOwnerProjectAppProofOrBoundedToken() async throws {
        let f = try Fixture(); await f.capture()
        let cases = [f.tokens(owner: "reader_b"), f.tokens(project: "other-project"), f.tokens(app: "1:123456789:ios:abcdef999999"),
            f.tokens(authTime: 99_000), f.tokens(authTime: 101_000), f.tokens(id: ""), f.tokens(id: "line\r\ninjection"),
            f.tokens(appCheck: "token with spaces"), f.tokens(appCheck: String(repeating: "a", count: 8193)),
            f.tokens(authExpiry: 0), f.tokens(appExpiry: -1), f.tokens(authExpiry: Int64.max)]
        for tokens in cases { f.credentialHook = { tokens }; await rejected { try await f.make().send(f.request) } }
        XCTAssertTrue(f.requests.isEmpty)
    }
    func testCancellationBeforeEntryHasNoCredentialOrTransportEffects() async throws {
        let f = try Fixture(); await f.capture(); let transport = f.make()
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await transport.send(f.request) }
        await rejected { try await task.value }; XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testOldCredentialCompletionAfterAToBToACannotDispatch() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<Transport.Credentials>()
        f.credentialHook = { try await gate.wait() }; let transport = f.make()
        let task = Task { try await transport.send(f.request) }; await wait(gate)
        f.roundTrip(); gate.finish(f.tokens()); await rejected { try await task.value }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testObservedCredentialDenialCannotReviveWhenHookLaterReturnsTrue() async throws {
        let f = try Fixture(); await f.capture()
        f.credentialHook = {
            f.allowed = false; XCTAssertEqual(f.admission?(), false)
            f.allowed = true; XCTAssertEqual(f.admission?(), false); return f.tokens()
        }
        await rejected { try await f.make().send(f.request) }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testSingleUseReservationPrecedesCredentialAndClockReentry() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<Transport.Credentials>(), transport = f.make()
        f.credentialHook = { try await gate.wait() }
        let first = Task { try await transport.send(f.request) }; await wait(gate)
        await rejected { try await transport.send(f.request) }; XCTAssertEqual(f.credentialCalls, 1)
        gate.finish(f.tokens()); _ = try await first.value
        await rejected { try await transport.send(f.request) }; XCTAssertEqual(f.requests.count, 1)
    }
    func testCancelledCredentialWaitRetainsPhysicalAwaitAndRejectsLateTokens() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<Transport.Credentials>(), transport = f.make()
        f.credentialHook = { try await gate.wait() }
        let task = Task { defer { f.completed = true }; return try await transport.send(f.request) }
        await wait(gate); task.cancel(); await Task.yield(); XCTAssertFalse(f.completed)
        gate.finish(f.tokens()); await rejected { try await task.value }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testCancelledHTTPWaitRetainsPhysicalAwaitAndRejectsLateReceipt() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<(Data, HTTPURLResponse)>(), transport = f.make()
        f.executeHook = { _ in try await gate.wait() }
        let task = Task { defer { f.completed = true }; return try await transport.send(f.request) }
        await wait(gate); task.cancel(); await Task.yield(); XCTAssertFalse(f.completed)
        gate.finish(try f.reply(XCTUnwrap(f.requests.first))); await rejected { try await task.value }; XCTAssertEqual(f.requests.count, 1)
    }
    func testReceiptAfterAccountReplacementNeverPublishesOrRetries() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<(Data, HTTPURLResponse)>(), transport = f.make()
        f.executeHook = { _ in try await gate.wait() }
        let task = Task { try await transport.send(f.request) }; await wait(gate)
        f.roundTrip(); gate.finish(try f.reply(XCTUnwrap(f.requests.first))); await rejected { try await task.value }
        await rejected { try await transport.send(f.request) }; XCTAssertEqual(f.requests.count, 1)
    }
    func testExpiredCredentialsAfterWaitNeverReachHTTP() async throws {
        let f = try Fixture(); await f.capture(); let gate = Gate<Transport.Credentials>()
        f.credentialHook = { try await gate.wait() }; let transport = f.make()
        let task = Task { try await transport.send(f.request) }; await wait(gate)
        f.time = 101_000; gate.finish(f.tokens(appExpiry: 101_000)); await rejected { try await task.value }; XCTAssertTrue(f.requests.isEmpty)
    }
    func testEachShortestDeadlineIsCheckedAfterPhysicalHTTPReturn() async throws {
        for expiry: Int64 in [101_000, 102_000, 400_000] {
            let f = try Fixture(); await f.capture()
            f.credentialHook = { f.tokens(authExpiry: expiry == 101_000 ? expiry : 600_000, appExpiry: expiry == 102_000 ? expiry : 500_000) }
            f.executeHook = { request in f.time = Int64(expiry); return try f.reply(request) }
            await rejected { try await f.make().send(f.request) }; XCTAssertEqual(f.requests.count, 1)
        }
    }
    func testClockHookAccountChangeCannotStartHTTP() async throws {
        let f = try Fixture(); await f.capture(); f.clockHook = { f.roundTrip() }
        await rejected { try await f.make().send(f.request) }; XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testHTTPStatusURLMIMEAndBodyBoundsAreRequiredWithoutAutomaticRetry() async throws {
        for variant in 0..<7 {
            let f = try Fixture(); await f.capture()
            switch variant {
            case 0: f.status = 503
            case 1: f.responseURL = URL(string: "https://other.example.invalid/delete")
            case 2: f.mime = "text/html"
            case 3: f.rawData = Data()
            case 4: f.rawData = Data(repeating: 1, count: 16_385)
            case 5: f.contentLength = "16385"
            default: f.contentLength = "1, 1"
            }
            let transport = f.make(); await rejected { try await transport.send(f.request) }
            await rejected { try await transport.send(f.request) }; XCTAssertEqual(f.requests.count, 1)
        }
    }
    func testExistingStrictDecoderRejectsWrongOwnerFullDeletionAndCrossPhaseReceipts() async throws {
        for variant in 0..<3 {
            let f = try Fixture(); await f.capture()
            if variant == 0 { f.rawData = try f.receipt(request: Contract.Request(expectedUID: "reader_b", membershipEpoch: 4)) }
            else if variant == 1 {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: f.receipt(request: f.request)) as? [String: Any])
                object["accountDeletionComplete"] = true; f.rawData = try JSONSerialization.data(withJSONObject: object)
            } else {
                f.rawData = try f.ledgerReceipt(request: Contract.LedgerRequest(expectedUID: "reader_a", membershipEpoch: 4, parentRequestID: f.request.requestID))
            }
            await rejected { try await f.make().send(f.request) }
        }
        let ledger = try Fixture(); await ledger.capture(ledger: true); ledger.rawData = try ledger.receipt(request: ledger.request)
        await rejected { try await ledger.make().sendLedger(XCTUnwrap(ledger.action.ledgerRequest)) }
    }
    func testProviderFailureAndTransportFailureNeverAutomaticallyRetry() async throws {
        for failCredentials in [true, false] {
            let f = try Fixture(); await f.capture()
            if failCredentials { f.credentialHook = { throw Fault.unavailable } }
            else { f.executeHook = { _ in throw Fault.unavailable } }
            let transport = f.make(); await rejected { try await transport.send(f.request) }; await rejected { try await transport.send(f.request) }
            XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, failCredentials ? 0 : 1)
        }
    }
}
