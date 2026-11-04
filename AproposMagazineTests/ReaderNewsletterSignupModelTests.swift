import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderNewsletterSignupModelTests: XCTestCase {
    private typealias Model = ReaderNewsletterSignupModel
    private enum TestFailure: Error { case transport }

    @MainActor private final class Transport {
        var requests: [Model.Request] = []
        var contexts: [CanonicalSessionState.ContextTicket] = []
        var pending: [Int: CheckedContinuation<Model.Response, Error>] = [:]

        func send(_ request: Model.Request, _ context: CanonicalSessionState.ContextTicket) async throws -> Model.Response {
            let index = requests.count
            requests.append(request)
            contexts.append(context)
            // Intentionally ignores cancellation, like an already accepted HTTP
            // request. The model must wait for its actual return before another.
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func finish(_ index: Int, status: Model.ResponseStatus = .subscribed, requestID: String? = nil,
                    challenge: String? = nil) {
            pending.removeValue(forKey: index)?.resume(returning: Model.Response(
                status: status, requestID: requestID ?? requests[index].requestID,
                reconfirmationChallenge: challenge))
        }
        func fail(_ index: Int, error: Error = TestFailure.transport) {
            pending.removeValue(forKey: index)?.resume(throwing: error)
        }
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let transport = Transport()
        lazy var model = Model(canonical: canonical, send: { [transport] request, context in
            try await transport.send(request, context)
        })

        @discardableResult
        func select(_ uid: String = "reader-A", email: String? = nil, verified: Bool = true,
                    forceNewGeneration: Bool = false) -> ReaderAccountSession {
            let session = ReaderAccountSession(uid: uid, email: email ?? uid + "@example.invalid", isEmailVerified: verified)
            _ = canonical.adopt(session, forceNewGeneration: forceNewGeneration)
            return session
        }
        @discardableResult
        func begin(_ session: ReaderAccountSession) -> Bool {
            model.begin(session: session, context: canonical.contextTicket())
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local asynchronous state was not reached", file: file, line: line)
    }

    func testConstructionAndCanonicalChangesDoNotInventOptIn() async {
        let f = Fixture()
        XCTAssertEqual(f.model.status, .idle)
        f.select(verified: false)
        f.select(verified: true)
        f.select("reader-B")
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertNil(f.model.requestID)
        XCTAssertNil(f.model.message)
        XCTAssertFalse(f.model.canRetry)
    }

    func testVerifiedAcceptedOwnerSendsExactConsentAndWaitsForMatchingReceipt() async throws {
        let f = Fixture()
        let original = f.select(email: "Reader.Mixed@example.invalid")
        let context = f.canonical.contextTicket()
        XCTAssertTrue(f.begin(original))
        XCTAssertEqual(f.model.status, .submitting)
        XCTAssertTrue(f.model.isWorking)
        await eventually { f.transport.requests.count == 1 }
        let request = try XCTUnwrap(f.transport.requests.first)
        XCTAssertNotNil(UUID(uuidString: request.requestID))
        XCTAssertEqual(request.expectedUserID, original.uid)
        XCTAssertEqual(request.expectedEmail, "Reader.Mixed@example.invalid")
        XCTAssertTrue(request.consent)
        XCTAssertEqual(request.consentVersion, "apropos-newsletter-v1")
        XCTAssertEqual(request.source, "ios-onboarding")
        XCTAssertEqual(f.transport.contexts.first, context)
        f.transport.finish(0)
        await eventually { f.model.status == .subscribed }
        XCTAssertFalse(f.model.isWorking)
        XCTAssertFalse(f.model.canRetry)
    }

    func testUnverifiedIntentWaitsAndOnlySameOwnerVerificationStartsIt() async {
        let f = Fixture(), session = ReaderAccountSession(uid: "reader-A", email: "a@example.invalid", isEmailVerified: false)
        _ = f.canonical.adopt(session)
        XCTAssertTrue(f.begin(session))
        let requestID = f.model.requestID
        XCTAssertEqual(f.model.status, .verificationRequired)
        XCTAssertFalse(f.model.canRetry)
        XCTAssertTrue(f.transport.requests.isEmpty)
        f.select(email: session.email, verified: true)
        await eventually { f.transport.requests.count == 1 }
        XCTAssertEqual(f.transport.requests.first?.requestID, requestID)
        f.transport.finish(0)
        await eventually { f.model.status == .subscribed }
    }

    func testUnverifiedConsentNeverTransfersToAccountBOrReturningA() async {
        let f = Fixture()
        let a = f.select(verified: false)
        XCTAssertTrue(f.begin(a))
        f.select("reader-B")
        f.select("reader-A")
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testNewGenerationForSameUIDRevokesWaitingConsent() {
        let f = Fixture()
        let a = f.select(verified: false)
        XCTAssertTrue(f.begin(a))
        f.select(verified: true, forceNewGeneration: true)
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testSameOwnerEmailChangeRevokesWithoutChangingCanonicalGeneration() {
        let f = Fixture()
        let a = f.select(verified: false)
        XCTAssertTrue(f.begin(a))
        let generation = f.canonical.snapshot.generation
        f.select(email: "other@example.invalid", verified: true)
        XCTAssertEqual(f.canonical.snapshot.generation, generation)
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testForeignCanonicalTicketAndStaleOwnerOrEmailAreRejected() {
        let f = Fixture(), other = Fixture()
        let a = f.select(), b = other.select()
        XCTAssertFalse(f.model.begin(session: a, context: other.canonical.contextTicket()))
        XCTAssertFalse(f.model.begin(session: ReaderAccountSession(uid: a.uid, email: "wrong@example.invalid", isEmailVerified: true), context: f.canonical.contextTicket()))
        let old = f.canonical.contextTicket()
        f.select("reader-B")
        XCTAssertFalse(f.model.begin(session: b, context: old))
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testMissingMalformedAndWhitespaceEmailsDoNotCreateRequests() {
        for email in ["", "no-at", "a@@example.invalid", "a@example..invalid", " a@example.invalid", "a@example.invalid\n", String(repeating: "a", count: 255) + "@example.invalid"] {
            let f = Fixture()
            XCTAssertFalse(f.begin(f.select(email: email)), email)
            XCTAssertNil(f.model.requestID)
            XCTAssertTrue(f.transport.requests.isEmpty)
        }
    }

    func testDuplicateBeginDuringSendAndAfterSuccessDoesNotSendAgain() async {
        let f = Fixture(), session = ReaderAccountSession(uid: "reader-A", email: "a@example.invalid", isEmailVerified: true)
        _ = f.canonical.adopt(session)
        XCTAssertTrue(f.begin(session))
        let requestID = f.model.requestID
        XCTAssertTrue(f.begin(session))
        await eventually { f.transport.requests.count == 1 }
        XCTAssertTrue(f.begin(session))
        XCTAssertFalse(f.model.retry())
        f.transport.finish(0)
        await eventually { f.model.status == .subscribed }
        XCTAssertTrue(f.begin(session))
        XCTAssertEqual(f.model.requestID, requestID)
        XCTAssertEqual(f.transport.requests.count, 1)
    }

    func testRetryAfterFailureUsesOriginalRequestAndNoRawTransportMessage() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        let original = f.transport.requests[0]
        f.transport.fail(0, error: NSError(domain: "secret-token@example.invalid", code: 1, userInfo: [NSLocalizedDescriptionKey: "private server payload"]))
        await eventually { f.model.status == .unavailable }
        XCTAssertTrue(f.model.canRetry)
        XCTAssertFalse(f.model.message?.contains("secret") ?? true)
        XCTAssertFalse(f.model.message?.contains("payload") ?? true)
        XCTAssertTrue(f.model.retry())
        XCTAssertFalse(f.model.retry())
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1], original)
        f.transport.finish(1, status: .alreadySubscribed)
        await eventually { f.model.status == .alreadySubscribed }
    }

    func testMismatchedResponseRequestIDCannotConfirmSubscription() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.transport.finish(0, requestID: UUID().uuidString)
        await eventually { f.model.status == .unavailable }
        XCTAssertTrue(f.model.canRetry)
    }

    func testCancelBeforeScheduledSendPreventsTransport() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        f.model.cancel()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
    }

    func testCancelDuringTransportDiscardsLateSuccess() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.model.cancel()
        f.transport.finish(0)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertFalse(f.model.retry())
    }

    func testAccountSwitchDuringTransportDiscardsLateFailure() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.select("reader-B")
        f.transport.fail(0)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.message)
        XCTAssertTrue(f.transport.requests.count == 1)
    }

    func testNewAcceptedBOptInWaitsForCancelledATransportToActuallyReturn() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        let oldRequest = f.transport.requests[0]
        let b = f.select("reader-B")
        XCTAssertTrue(f.begin(b))
        let newRequestID = f.model.requestID
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.transport.requests.count, 1)
        f.transport.finish(0)
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1].expectedUserID, b.uid)
        XCTAssertEqual(f.transport.requests[1].requestID, newRequestID)
        XCTAssertNotEqual(f.transport.requests[1].requestID, oldRequest.requestID)
        XCTAssertEqual(f.model.status, .submitting)
        f.transport.finish(1)
        await eventually { f.model.status == .subscribed }
    }

    func testCancelledTransportCannotReleaseNewerPhysicalSlotOrPublishReceipt() async {
        let f = Fixture()
        let a = f.select()
        XCTAssertTrue(f.begin(a))
        await eventually { f.transport.requests.count == 1 }
        f.model.cancel()
        XCTAssertTrue(f.begin(a))
        let newID = f.model.requestID
        f.transport.finish(0, status: .alreadySubscribed)
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.model.requestID, newID)
        XCTAssertEqual(f.model.status, .submitting)
        XCTAssertFalse(f.model.retry())
        f.transport.finish(1)
        await eventually { f.model.status == .subscribed }
    }

    func testServerVerificationRequirementDoesNotAutomaticallyLoopForVerifiedSession() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.transport.finish(0, status: .verificationRequired)
        await eventually { f.model.status == .verificationRequired }
        _ = f.canonical.reportUnavailableAction(context: f.canonical.contextTicket(), message: "Local fixture")
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.transport.requests.count, 1)
        XCTAssertTrue(f.model.canRetry)
        XCTAssertTrue(f.model.retry())
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1].requestID, f.transport.requests[0].requestID)
        f.transport.finish(1)
        await eventually { f.model.status == .subscribed }
    }

    func testRealVerificationChangeDuringSendPermitsOneFollowUpWhenServerNeedsIt() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.select(verified: false)
        f.select(verified: true)
        f.transport.finish(0, status: .verificationRequired)
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1], f.transport.requests[0])
        f.transport.finish(1, status: .verificationRequired)
        await eventually { f.model.status == .verificationRequired }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.transport.requests.count, 2)
    }

    func testVerificationRevokedBeforeTaskStartsWaitsForVerificationAgain() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        f.select(verified: false)
        await eventually { f.model.status == .verificationRequired }
        XCTAssertTrue(f.transport.requests.isEmpty)
        f.select(verified: true)
        await eventually { f.transport.requests.count == 1 }
        f.transport.finish(0)
        await eventually { f.model.status == .subscribed }
    }

    func testPendingIsNotSuccessAndItsRetryReusesOriginalID() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.transport.finish(0, status: .pending)
        await eventually { f.model.status == .pending }
        XCTAssertTrue(f.model.canRetry)
        XCTAssertTrue(f.model.retry())
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1], f.transport.requests[0])
        f.transport.finish(1)
        await eventually { f.model.status == .subscribed }
    }

    func testReconfirmationIsSeparateAndDoesNotBlindlyRetryOrRemoveOptOut() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.transport.finish(0, status: .reconfirmationRequired)
        await eventually { f.model.status == .reconfirmationRequired }
        XCTAssertFalse(f.model.canRetry)
        XCTAssertFalse(f.model.retry())
        XCTAssertTrue(f.model.message?.contains("tidligere afmeldt") == true)
        XCTAssertEqual(f.transport.requests.count, 1)
    }

    func testServerChallengeWaitsForExplicitSecondTapAndNetworkRetryKeepsExactPayload() async throws {
        let f = Fixture(), session = f.select()
        XCTAssertTrue(f.model.beginExplicitOptIn(session: session, context: f.canonical.contextTicket()))
        await eventually { f.transport.requests.count == 1 }
        let original = f.transport.requests[0], challenge = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        XCTAssertNil(original.reconfirmationChallenge)
        f.transport.finish(0, status: .reconfirmationRequired, challenge: challenge)
        await eventually { f.model.canReconfirm }
        XCTAssertFalse(f.model.canRetry); XCTAssertFalse(f.model.retry())
        _ = f.select()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.transport.requests.count, 1, "Receiving/observing a challenge never redeems it")
        XCTAssertTrue(f.model.reconfirm()); XCTAssertFalse(f.model.reconfirm())
        await eventually { f.transport.requests.count == 2 }
        let confirmed = f.transport.requests[1]
        XCTAssertEqual(confirmed.requestID, original.requestID)
        XCTAssertEqual(confirmed.reconfirmationChallenge, challenge)
        XCTAssertEqual(confirmed.expectedUserID, original.expectedUserID); XCTAssertEqual(confirmed.expectedEmail, original.expectedEmail)
        f.transport.fail(1)
        await eventually { f.model.status == .unavailable }
        XCTAssertTrue(f.model.retry())
        await eventually { f.transport.requests.count == 3 }
        XCTAssertEqual(f.transport.requests[2], confirmed, "Unknown response retries the same idempotent challenge request")
        f.transport.finish(2)
        await eventually { f.model.status == .subscribed }
        XCTAssertFalse(f.model.reconfirm())
    }

    func testSpentChallengeRequiresFreshCheckedChoiceWithNewIDRatherThanAutomaticRenewal() async {
        let f = Fixture(), session = f.select()
        XCTAssertTrue(f.model.beginExplicitOptIn(session: session, context: f.canonical.contextTicket()))
        await eventually { f.transport.requests.count == 1 }
        let firstID = f.model.requestID
        f.transport.finish(0, status: .reconfirmationRequired, challenge: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        await eventually { f.model.canReconfirm }
        XCTAssertTrue(f.model.reconfirm())
        await eventually { f.transport.requests.count == 2 }
        f.transport.finish(1, status: .reconfirmationRequired)
        await eventually { f.model.status == .reconfirmationRequired && !f.model.canReconfirm }
        XCTAssertFalse(f.model.retry()); XCTAssertFalse(f.model.reconfirm())
        XCTAssertTrue(f.begin(session)); XCTAssertEqual(f.model.requestID, firstID)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.transport.requests.count, 2)
        XCTAssertTrue(f.model.beginExplicitOptIn(session: session, context: f.canonical.contextTicket()))
        await eventually { f.transport.requests.count == 3 }
        XCTAssertNotEqual(f.model.requestID, firstID); XCTAssertNil(f.transport.requests[2].reconfirmationChallenge)
        f.transport.finish(2, status: .alreadySubscribed)
        await eventually { f.model.status == .alreadySubscribed }
        let completedID = f.model.requestID
        XCTAssertTrue(f.begin(session)); XCTAssertEqual(f.model.requestID, completedID)
        XCTAssertTrue(f.model.beginExplicitOptIn(session: session, context: f.canonical.contextTicket()))
        await eventually { f.transport.requests.count == 4 }
        XCTAssertNotEqual(f.model.requestID, completedID)
        f.transport.finish(3)
        await eventually { f.model.status == .subscribed }
    }

    func testChallengeCannotCrossAccountEpochOrChangedEmail() async {
        for changeEmail in [false, true] {
            let f = Fixture(), original = f.select()
            XCTAssertTrue(f.begin(original)); await eventually { f.transport.requests.count == 1 }
            f.transport.finish(0, status: .reconfirmationRequired, challenge: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
            await eventually { f.model.canReconfirm }
            f.select(email: changeEmail ? "changed@example.invalid" : nil, forceNewGeneration: !changeEmail)
            XCTAssertFalse(f.model.canReconfirm); XCTAssertFalse(f.model.reconfirm()); XCTAssertNil(f.model.requestID)
            XCTAssertFalse(f.model.beginExplicitOptIn(session: original, context: CanonicalSessionState().contextTicket()))
            XCTAssertEqual(f.transport.requests.count, 1)
        }
    }

    func testMalformedOrUnsolicitedChallengeCannotBecomeReconfirmationAuthority() async {
        for challenge in ["not-a-token", "dddddddd-dddd-4ddd-8ddd-dddddddddddd"] {
            let f = Fixture(); XCTAssertTrue(f.begin(f.select()))
            await eventually { f.transport.requests.count == 1 }
            f.transport.finish(0, status: challenge == "not-a-token" ? .reconfirmationRequired : .subscribed, challenge: challenge)
            await eventually { f.model.status == .unavailable }
            XCTAssertFalse(f.model.canReconfirm); XCTAssertFalse(f.model.reconfirm())
        }
    }

    func testTransportCancellationWithCurrentOwnerIsUnknownNotSuccessful() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        f.transport.fail(0, error: CancellationError())
        await eventually { f.model.status == .pending }
        XCTAssertTrue(f.model.canRetry)
    }

    func testCancelReenteredDuringBeginPublicationWins() async {
        let f = Fixture()
        let a = f.select()
        var armed = true
        let subscription = f.model.objectWillChange.sink {
            if armed { armed = false; f.model.cancel() }
        }
        XCTAssertFalse(f.begin(a))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertTrue(f.transport.requests.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testCanonicalSwitchReenteredDuringBeginPublicationWins() async {
        let f = Fixture()
        let a = f.select()
        var armed = true
        let subscription = f.model.objectWillChange.sink {
            if armed { armed = false; f.select("reader-B") }
        }
        XCTAssertFalse(f.begin(a))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.requestID)
        XCTAssertTrue(f.transport.requests.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testCanonicalSwitchReenteredDuringSuccessPublicationPreventsReceipt() async {
        let f = Fixture()
        XCTAssertTrue(f.begin(f.select()))
        await eventually { f.transport.requests.count == 1 }
        var armed = true
        let subscription = f.model.objectWillChange.sink {
            if armed { armed = false; f.select("reader-B") }
        }
        f.transport.finish(0)
        await eventually { f.canonical.snapshot.userID == "reader-B" }
        XCTAssertEqual(f.model.status, .idle)
        XCTAssertNil(f.model.message)
        XCTAssertNil(f.model.requestID)
        withExtendedLifetime(subscription) {}
    }

    func testWireRoundTripPreservesExplicitFieldsAndRejectsUnknownStatus() throws {
        let request = Model.Request(expectedUserID: "reader-A", expectedEmail: "a@example.invalid")
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(Model.Request.self, from: data), request)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["requestID", "expectedUserID", "expectedEmail", "consent", "consentVersion", "source", "reconfirmationChallenge"])
        XCTAssertTrue(fields["reconfirmationChallenge"] is NSNull)
        for status in Model.ResponseStatus.allCases {
            let response = Model.Response(status: status, requestID: request.requestID)
            XCTAssertEqual(try JSONDecoder().decode(Model.Response.self, from: JSONEncoder().encode(response)), response)
        }
        let unknown = Data("{\"status\":\"sentEmail\",\"requestID\":\"request\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Model.Response.self, from: unknown))
    }
}
