import FirebaseCore
import Foundation
import XCTest
@testable import Apropos

/// Real request/response adapter and existing strict membership decoder. HTTP,
/// credentials and clock are local effects; no URLSession or SDK is created.
@MainActor
final class ReaderStartupHTTPTransportTests: XCTestCase {
    private typealias Transport = ReaderStartupHTTPTransport
    private typealias Coordinator = ReaderStartupCoordinator
    private enum Fault: Error { case unavailable }
    @MainActor private final class Gate<Value> {
        let entered = XCTestExpectation(description: "Original effect suspended")
        private var continuation: CheckedContinuation<Value, Error>?
        func wait() async throws -> Value {
            try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        }
        func finish(_ value: Value) { let held = continuation; continuation = nil; held?.resume(returning: value) }
    }
    @MainActor private final class Fixture {
        let canonical: CanonicalSessionState
        let original: Coordinator.Context
        let configuration: Transport.Configuration
        let request: Coordinator.MembershipRequest
        let binding: ReaderMembershipContract.Binding
        var time: Int64 = 10_000
        var allowed = true
        var credentialCalls = 0, currentCalls = 0, clockCalls = 0
        var requests: [URLRequest] = []
        var membership: Any = ["schemaVersion": 1, "ownerUID": "reader_a", "epoch": 4, "state": "active"]
        var memberExpiry: Int64 = 70_000, permitExpiry: Int64 = 50_000
        var status = 200, mime = "application/json"
        var responseURL: URL?, contentLength: String?, rawResponse: Data?
        var credentialHook: (@MainActor (Int) async throws -> Transport.Credentials)?
        var executionHook: (@MainActor (URLRequest, Int) async throws -> (Data, HTTPURLResponse))?
        var responseHook: (@MainActor ([String: Any]) -> [String: Any])?
        var clockHook: (@MainActor () -> Void)?, currentHook: (@MainActor () -> Void)?
        lazy var transport = Transport(configuration: configuration, context: original,
            credentials: { [unowned self] context in
                XCTAssertEqual(context, self.original)
                self.credentialCalls += 1
                if let hook = self.credentialHook { return try await hook(self.credentialCalls) }
                return self.tokens()
            }, isCurrent: { [unowned self] context in
                self.currentCalls += 1; self.currentHook?()
                return self.allowed && self.canonical.isCurrent(context)
            }, execute: { [unowned self] request in
                self.requests.append(request)
                if let hook = self.executionHook { return try await hook(request, self.requests.count) }
                return try self.reply(request)
            }, now: { [unowned self] in self.clockCalls += 1; self.clockHook?(); return self.time })

        init(projectID: String = "apropos-local") throws {
            let canonical = CanonicalSessionState()
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: true))
            self.canonical = canonical
            original = canonical.contextTicket()
            let startup = try Coordinator.Configuration(projectID: projectID, appID: "1:local:ios:fixture",
                installationID: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
                writerFenceRevision: String(repeating: "a", count: 64), migrationRevision: String(repeating: "b", count: 64))
            configuration = try .init(startup: startup, membershipURL: URL(string: "https://reader.example.invalid/membership")!,
                attestationURL: URL(string: "https://reader.example.invalid/attest")!, deploymentEvidenceSHA256: String(repeating: "c", count: 64))
            request = try .init(expectedUID: "reader_a", readID: "22345678-1234-1234-1234-123456789abc")
            binding = try .init(ownerUID: "reader_a", epoch: 4)
        }
        func tokens(owner: String = "reader_a", project: String? = nil, app: String? = nil,
                    id: String = "local-id-token", appCheck: String = "local-app-check", authExpiry: Int64 = 90_000,
                    appCheckExpiry: Int64 = 80_000) -> Transport.Credentials {
            .init(ownerUID: owner, projectID: project ?? configuration.startup.projectID,
                appID: app ?? configuration.startup.appID, idToken: id, appCheckToken: appCheck,
                authValidUntilMs: authExpiry, appCheckValidUntilMs: appCheckExpiry)
        }
        func challenge(readID: String? = nil, binding: ReaderMembershipContract.Binding? = nil,
                       context: Coordinator.Context? = nil, configuration: Coordinator.Configuration? = nil,
                       marker: ReaderTransitionRecoveryStore.Marker? = nil) -> Coordinator.Challenge {
            .init(configuration: configuration ?? self.configuration.startup, context: context ?? original,
                binding: binding ?? self.binding, marker: marker, readID: readID ?? request.readID)
        }
        func read() async throws -> Coordinator.MembershipSnapshot { try await transport.readMembership(request) }
        func verify() async throws -> Coordinator.Permit { try await transport.verify(challenge()) }
        func roundTrip() {
            _ = canonical.adopt(nil)
            _ = canonical.adopt(.init(uid: "reader_a", email: "local@example.invalid", isEmailVerified: true))
        }
        func reply(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
            let echo = try Self.object(XCTUnwrap(request.httpBody))
            var object: [String: Any]
            if request.url == configuration.membershipURL {
                object = ["schemaVersion": 1, "scope": "reader-membership-read-v1", "request": echo,
                    "membership": membership, "validUntilMs": memberExpiry]
            } else {
                object = ["schemaVersion": 1, "scope": "reader-startup-attestation-v1", "request": echo,
                    "coverage": "all_persisted_writers_including_previous_accounts",
                    "deploymentEvidenceSHA256": configuration.deploymentEvidenceSHA256, "validUntilMs": permitExpiry]
            }
            if let hook = responseHook { object = hook(object) }
            let data = try rawResponse ?? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            var headers = ["Content-Type": mime]
            if let contentLength { headers["Content-Length"] = contentLength }
            return (data, try XCTUnwrap(HTTPURLResponse(url: responseURL ?? XCTUnwrap(request.url), statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: headers)))
        }
        static func object(_ data: Data) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected closed attempt", file: file, line: line) } catch {}
    }
    private func wait<T>(_ gate: Gate<T>) async {
        let result = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(result, .completed)
    }

    func testConstructionIsInertAndConfigurationRequiresDistinctExactSameOriginHTTPS() throws {
        let f = try Fixture(); _ = f.transport
        XCTAssertEqual(f.currentCalls, 0); XCTAssertEqual(f.credentialCalls, 0); XCTAssertEqual(f.clockCalls, 0)
        XCTAssertTrue(f.requests.isEmpty)
        for raw in ["http://reader.example.invalid/member", "https://other.example.invalid/member",
                    "https://reader.example.invalid:444/member", "https://u:p@reader.example.invalid/member",
                    "https://reader.example.invalid/member?q=1", "https://reader.example.invalid/member#hash",
                    "https://reader.example.invalid/", f.configuration.attestationURL.absoluteString] {
            XCTAssertThrowsError(try Transport.Configuration(startup: f.configuration.startup,
                membershipURL: XCTUnwrap(URL(string: raw)), attestationURL: f.configuration.attestationURL,
                deploymentEvidenceSHA256: f.configuration.deploymentEvidenceSHA256), raw)
        }
        XCTAssertThrowsError(try Transport.Configuration(startup: f.configuration.startup,
            membershipURL: f.configuration.membershipURL, attestationURL: f.configuration.attestationURL, deploymentEvidenceSHA256: "flag"))
        // The shared configuration rejects format characters before the HTTP
        // configuration can be constructed; this is already a closed path.
        XCTAssertThrowsError(try Coordinator.Configuration(projectID: "project\u{200B}", appID: "app", installationID: UUID(),
            writerFenceRevision: String(repeating: "a", count: 64), migrationRevision: String(repeating: "b", count: 64)))
    }

    func testRealWireSuccessKeepsOriginalChallengeHeadersExpiryAndMarker() async throws {
        let f = try Fixture(); let snapshot = try await f.read()
        let marker = ReaderTransitionRecoveryStore.Marker(binding: f.binding, transitionID: UUID())
        let challenge = f.challenge(marker: marker)
        let permit = try await f.transport.verify(challenge)
        XCTAssertEqual(snapshot.membership?.binding, f.binding); XCTAssertEqual(permit.challenge, challenge)
        XCTAssertEqual(permit.coverage, .allPersistedWritersIncludingPreviousAccounts)
        XCTAssertEqual(permit.validUntilMs, 50_000); XCTAssertEqual(f.credentialCalls, 2)
        XCTAssertEqual(f.requests.map(\.url), [f.configuration.membershipURL, f.configuration.attestationURL])
        for request in f.requests {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.timeoutInterval, 60)
            XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-id-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "local-app-check")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
        let wire = try Fixture.object(XCTUnwrap(f.requests.last?.httpBody))
        XCTAssertEqual(Set(wire.keys), Set(["schemaVersion", "configuration", "context", "binding", "marker", "readID"]))
        XCTAssertEqual((wire["context"] as? [String: Any])?["generation"] as? String, f.original.generation.uuidString.lowercased())
        XCTAssertEqual((wire["marker"] as? [String: Any])?["transitionID"] as? String, marker.transitionID.uuidString.lowercased())
        XCTAssertEqual((wire["configuration"] as? [String: Any])?["installationID"] as? String,
            f.configuration.startup.installationID.uuidString.lowercased())
        await rejected { try await f.verify() }; XCTAssertEqual(f.requests.count, 2)
    }

    func testMembershipExpiryCapsPermitAcrossCredentialRefresh() async throws {
        let f = try Fixture(); f.memberExpiry = 30_000
        f.credentialHook = { index in index == 1 ? f.tokens(authExpiry: 40_000) : f.tokens(authExpiry: 90_000) }
        _ = try await f.read(); let permit = try await f.verify()
        XCTAssertEqual(permit.validUntilMs, 30_000)
    }

    func testSecondCredentialExpiryCapsOtherwiseLongerProof() async throws {
        let f = try Fixture(); f.permitExpiry = 25_000
        f.credentialHook = { index in f.tokens(appCheckExpiry: index == 1 ? 80_000 : 25_000) }
        _ = try await f.read(); let permit = try await f.verify()
        XCTAssertEqual(permit.validUntilMs, 25_000)
    }

    func testClosedContextAndWrongRequestNeverAcquireCredentials() async throws {
        let f = try Fixture(); f.allowed = false
        await rejected { try await f.read() }; f.allowed = true
        await rejected { try await f.read() }
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
        let other = try Fixture()
        let request = try Coordinator.MembershipRequest(expectedUID: "reader_b", readID: other.request.readID)
        await rejected { try await other.transport.readMembership(request) }
        XCTAssertEqual(other.credentialCalls, 0)
    }

    func testOneReadIDCannotBeReplacedWhileOriginalCredentialsArePending() async throws {
        let f = try Fixture(), gate = Gate<Transport.Credentials>()
        f.credentialHook = { _ in try await gate.wait() }
        let first = Task { try await f.read() }; await wait(gate)
        let replacement = try Coordinator.MembershipRequest(expectedUID: "reader_a", readID: UUID().uuidString.lowercased())
        await rejected { try await f.transport.readMembership(replacement) }
        gate.finish(f.tokens()); let result = try await first.value
        XCTAssertEqual(result.request, f.request); XCTAssertEqual(f.credentialCalls, 1)
        XCTAssertEqual(f.requests.count, 1)
    }

    func testAccountABADuringCredentialAwaitNeverSendsRequest() async throws {
        let f = try Fixture(), gate = Gate<Transport.Credentials>()
        f.credentialHook = { _ in try await gate.wait() }
        let task = Task { try await f.read() }; await wait(gate)
        f.roundTrip(); gate.finish(f.tokens()); await rejected { try await task.value }
        XCTAssertTrue(f.requests.isEmpty); await rejected { try await f.read() }
    }

    func testAccountABAAfterHTTPReturnCannotDeliverMembership() async throws {
        let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
        f.executionHook = { _, _ in try await gate.wait() }
        let task = Task { try await f.read() }; await wait(gate)
        let response = try f.reply(XCTUnwrap(f.requests.first))
        f.roundTrip(); gate.finish(response); await rejected { try await task.value }
        await rejected { try await f.verify() }; XCTAssertEqual(f.requests.count, 1)
    }

    func testCancelledUncooperativeHTTPReturnCannotDeliverOrStartAnotherPhase() async throws {
        let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
        f.executionHook = { _, _ in try await gate.wait() }
        let task = Task { try await f.read() }; await wait(gate); task.cancel()
        gate.finish(try f.reply(XCTUnwrap(f.requests.first))); await rejected { try await task.value }
        await rejected { try await f.verify() }; XCTAssertEqual(f.credentialCalls, 1)
    }

    func testClockHookAccountReplacementCannotStartHTTP() async throws {
        let f = try Fixture()
        f.clockHook = { f.clockHook = nil; f.roundTrip() }
        await rejected { try await f.read() }
        XCTAssertEqual(f.credentialCalls, 1); XCTAssertTrue(f.requests.isEmpty)
    }

    func testCredentialOwnerProjectAppTokenAndExpiryValidationPrecedesHTTP() async throws {
        let values: [(Fixture) -> Transport.Credentials] = [
            { $0.tokens(owner: "reader_b") }, { $0.tokens(project: "other") }, { $0.tokens(app: "other") },
            { $0.tokens(id: "") }, { $0.tokens(appCheck: "bad\r\nheader") }, { $0.tokens(id: String(repeating: "x", count: 16_385)) },
            { $0.tokens(authExpiry: 10_000) }, { $0.tokens(appCheckExpiry: 0) }, { $0.tokens(authExpiry: 9_007_199_254_740_992) }
        ]
        for make in values {
            let f = try Fixture(); f.credentialHook = { _ in make(f) }
            await rejected { try await f.read() }; XCTAssertTrue(f.requests.isEmpty)
        }
    }

    func testMissingAndFrozenMembershipCannotRequestAttestation() async throws {
        for missing in [true, false] {
            let f = try Fixture()
            if missing { f.membership = NSNull() }
            else {
                let deletion = try ReaderAccountDeletionContract.Request(expectedUID: "reader_a", membershipEpoch: 4)
                f.membership = ["schemaVersion": 1, "ownerUID": "reader_a", "epoch": 4,
                    "state": "deletion_frozen", "deletionRequestID": deletion.requestID]
            }
            _ = try await f.read(); await rejected { try await f.verify() }
            XCTAssertEqual(f.requests.count, 1); XCTAssertEqual(f.credentialCalls, 1)
        }
    }

    func testVerifyRequiresOriginalReadContextBindingConfigurationAndMarker() async throws {
        for mutation in 0..<5 {
            let f = try Fixture(); _ = try await f.read()
            let challenge: Coordinator.Challenge
            switch mutation {
            case 0: challenge = f.challenge(readID: UUID().uuidString.lowercased())
            case 1: challenge = f.challenge(binding: try .init(ownerUID: "reader_a", epoch: 5))
            case 2:
                let other = try Fixture(); challenge = f.challenge(context: other.original)
            case 3:
                let other = try Fixture(projectID: "other"); challenge = f.challenge(configuration: other.configuration.startup)
            default:
                challenge = f.challenge(marker: .init(binding: try .init(ownerUID: "reader_b", epoch: 4), transitionID: UUID()))
            }
            await rejected { try await f.transport.verify(challenge) }
            XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, 1)
        }
    }

    func testMembershipResponseUsesExistingStrictDecoderAndOriginalRequestEcho() async throws {
        let mutations: [([String: Any]) -> [String: Any]] = [
            { var v = $0; v["schemaVersion"] = true; return v },
            { var v = $0; v["unknown"] = "field"; return v },
            { var v = $0; v["validUntilMs"] = true; return v },
            { var v = $0; v["validUntilMs"] = 9_007_199_254_740_992 as Int64; return v },
            { var v = $0; var r = v["request"] as! [String: Any]; r["readID"] = UUID().uuidString.lowercased(); v["request"] = r; return v },
            { var v = $0; v["membership"] = ["schemaVersion": 1, "ownerUID": "reader_b", "epoch": 4, "state": "active"]; return v }
        ]
        for mutate in mutations {
            let f = try Fixture(); f.responseHook = mutate
            await rejected { try await f.read() }; await rejected { try await f.verify() }
            XCTAssertEqual(f.requests.count, 1)
        }
    }

    func testHTTPStatusMIMEExactURLDeclaredAndActualBoundsApplyToBothPhases() async throws {
        for attest in [false, true] {
            for variant in 0..<7 {
                let f = try Fixture(); if attest { _ = try await f.read() }
                switch variant {
                case 0: f.status = 401
                case 1: f.mime = "text/html"
                case 2: f.responseURL = URL(string: "https://reader.example.invalid/redirect")
                case 3: f.rawResponse = Data(repeating: 32, count: 16_385)
                case 4: f.contentLength = "16385"
                case 5: f.contentLength = "-1"
                default: f.rawResponse = Data()
                }
                if attest { await rejected { try await f.verify() } }
                else { await rejected { try await f.read() } }
                XCTAssertEqual(f.requests.count, attest ? 2 : 1)
            }
        }
    }

    func testAttestationStrictKeysCoverageDigestAndTypedEcho() async throws {
        let mutations: [([String: Any]) -> [String: Any]] = [
            { var v = $0; v["schemaVersion"] = true; return v },
            { var v = $0; v["scope"] = "reader-resource-read-v1"; return v },
            { var v = $0; v["coverage"] = "current_reader_only"; return v },
            { var v = $0; v["deploymentEvidenceSHA256"] = String(repeating: "d", count: 64); return v },
            { var v = $0; v["extra"] = 1; return v },
            { var v = $0; v["validUntilMs"] = true; return v },
            { var v = $0; v["validUntilMs"] = 12_345.5; return v },
            { var v = $0; v["validUntilMs"] = 9_007_199_254_740_992 as Int64; return v },
            { var v = $0; var r = v["request"] as! [String: Any]; r["schemaVersion"] = true; v["request"] = r; return v },
            { var v = $0; var r = v["request"] as! [String: Any]; var b = r["binding"] as! [String: Any]; b["epoch"] = true; r["binding"] = b; v["request"] = r; return v },
            { var v = $0; var r = v["request"] as! [String: Any]; r.removeValue(forKey: "marker"); v["request"] = r; return v },
            { var v = $0; var r = v["request"] as! [String: Any]; r["readID"] = (r["readID"] as! String).uppercased(); v["request"] = r; return v }
        ]
        for mutate in mutations {
            let f = try Fixture(); _ = try await f.read(); f.responseHook = mutate
            await rejected { try await f.verify() }; XCTAssertEqual(f.requests.count, 2)
        }
    }

    func testCanonicalUnicodeEquivalentProjectCannotReplaceExactEchoBytes() async throws {
        let f = try Fixture(projectID: "café"); _ = try await f.read()
        f.responseHook = { value in
            var value = value, request = value["request"] as! [String: Any]
            var config = request["configuration"] as! [String: Any]
            config["projectID"] = "cafe\u{301}"; request["configuration"] = config; value["request"] = request
            return value
        }
        await rejected { try await f.verify() }
    }

    func testMembershipExpiryAndCredentialExpiryRecheckedAfterHTTPPhysicalReturn() async throws {
        for expireCredential in [false, true] {
            let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
            f.executionHook = { _, _ in try await gate.wait() }
            let task = Task { try await f.read() }; await wait(gate)
            let response = try f.reply(XCTUnwrap(f.requests.first))
            f.time = expireCredential ? 80_000 : 70_000
            gate.finish(response); await rejected { try await task.value }
        }
    }

    func testAttestationHasSixtySecondMaximumAndCannotOutliveAuth() async throws {
        for expiry: Int64 in [80_001, 10_000] {
            let f = try Fixture(); _ = try await f.read(); f.permitExpiry = expiry
            await rejected { try await f.verify() }
        }
        let allowed = try Fixture(); allowed.memberExpiry = 80_000; _ = try await allowed.read()
        // Fresh server evidence was obtained two seconds after client send.
        // Accept its valid wire expiry, but never extend the local 60s permit.
        allowed.permitExpiry = 72_000
        allowed.executionHook = { request, _ in allowed.time = 12_000; return try allowed.reply(request) }
        let permit = try await allowed.verify()
        XCTAssertEqual(permit.validUntilMs, 70_000)
    }

    func testVerifyCannotRenewExpiredFirstProofWithFreshCredentials() async throws {
        let f = try Fixture(); f.memberExpiry = 20_000; _ = try await f.read(); f.time = 20_000
        await rejected { try await f.verify() }
        XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, 1)
    }

    func testAttestationHeldResultIsRejectedAfterDenialEvenIfProviderLaterReturnsTrue() async throws {
        let f = try Fixture(), gate = Gate<(Data, HTTPURLResponse)>()
        _ = try await f.read(); f.executionHook = { _, _ in try await gate.wait() }
        let task = Task { try await f.verify() }; await wait(gate)
        let response = try f.reply(XCTUnwrap(f.requests.last))
        f.allowed = false; gate.finish(response); await rejected { try await task.value }
        f.allowed = true; await rejected { try await f.verify() }
        XCTAssertEqual(f.requests.count, 2)
    }

    func testClockHookAfterValidAttestationCannotReturnPermitForReplacedContext() async throws {
        let f = try Fixture(); _ = try await f.read()
        f.executionHook = { request, _ in
            let response = try f.reply(request)
            f.clockHook = { f.clockHook = nil; f.roundTrip() }
            return response
        }
        await rejected { try await f.verify() }
        XCTAssertEqual(f.requests.count, 2)
    }

    func testTransportErrorClosesAttemptAndDoesNotRecaptureOnRetry() async throws {
        let f = try Fixture(); f.executionHook = { _, _ in throw Fault.unavailable }
        await rejected { try await f.read() }
        f.executionHook = nil; await rejected { try await f.read() }; await rejected { try await f.verify() }
        XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, 1)
    }
}
