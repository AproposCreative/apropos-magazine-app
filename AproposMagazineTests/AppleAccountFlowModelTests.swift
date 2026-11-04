import Combine
import XCTest
@testable import Apropos

final class AppleAccountFlowModelTests: XCTestCase {
    @MainActor
    func testRepeatedAlertDismissalPublishesOnlyTheActualErrorChange() throws {
        let model = AppleAccountFlowModel(purpose: .reauthentication, capture: {
            throw AppleAccountFlowError.randomUnavailable
        })
        XCTAssertNil(model.begin()); XCTAssertNotNil(model.errorMessage)
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        model.clearError(); model.clearError(); model.clearError()
        XCTAssertEqual(publications, 1); XCTAssertNil(model.errorMessage)
        withExtendedLifetime(observation) {}
    }
    private func challenge(_ state: String = "request-A") -> AppleSignInChallenge {
        AppleSignInChallenge(id: UUID(), rawNonce: "abc", state: state)
    }
    private func response(_ challenge: AppleSignInChallenge, token: Data? = Data("signed-token".utf8)) -> AppleIdentityResponse {
        AppleIdentityResponse(identityToken: token, state: challenge.state, fullName: nil)
    }
    private let session = ReaderAccountSession(uid: "reader-A", email: "reader@example.com", isEmailVerified: true)

    func testNonceHashUsesSHA256WithoutSendingRawNonceToApple() {
        XCTAssertEqual(challenge().hashedNonce, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testProductionChallengesHaveIndependentRandomNonceAndState() throws {
        let a = try AppleSignInChallenge.generate(), b = try AppleSignInChallenge.generate()
        XCTAssertEqual(a.rawNonce.count, 64)
        XCTAssertEqual(a.state.count, 64)
        XCTAssertEqual(a.hashedNonce.count, 64)
        XCTAssertNotEqual(a.rawNonce, a.state)
        XCTAssertNotEqual(a.rawNonce, b.rawNonce)
        XCTAssertNotEqual(a.state, b.state)
    }

    @MainActor
    func testEntropyFailureDoesNotStartAnExchange() {
        let model = AppleAccountFlowModel(makeChallenge: { throw AppleAccountFlowError.randomUnavailable }) { _, _, _ in
            XCTFail("Must not authenticate"); return nil
        }
        XCTAssertNil(model.begin())
        XCTAssertFalse(model.isWorking)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testRepeatedBeginDoesNotReplaceAnActiveChallenge() throws {
        let expected = challenge()
        var generations = 0
        let model = AppleAccountFlowModel(makeChallenge: { generations += 1; return expected }) { _, _, _ in nil }
        XCTAssertEqual(try XCTUnwrap(model.begin()).id, expected.id)
        XCTAssertNil(model.begin())
        XCTAssertEqual(generations, 1)
        XCTAssertTrue(model.isWorking)
    }

    @MainActor
    func testMismatchedStateNeverReachesFirebaseTransportAndAllowsRetry() async throws {
        let expected = challenge()
        let model = AppleAccountFlowModel(makeChallenge: { expected }) { _, _, _ in
            XCTFail("Wrong state must not authenticate"); return nil
        }
        _ = try XCTUnwrap(model.begin())
        await model.complete(ticketID: expected.id, response: AppleIdentityResponse(identityToken: Data("token".utf8), state: "foreign", fullName: nil))
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.authenticatedSession)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNotNil(model.begin())
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testMissingEmptyAndNonUTF8TokensNeverReachTransport() async throws {
        for token: Data? in [nil, Data(), Data([0xff, 0xfe])] {
            let expected = challenge()
            let model = AppleAccountFlowModel(makeChallenge: { expected }) { _, _, _ in
                XCTFail("Invalid identity must not authenticate"); return nil
            }
            _ = try XCTUnwrap(model.begin())
            await model.complete(ticketID: expected.id, response: response(expected, token: token))
            XCTAssertFalse(model.isWorking)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertNil(model.authenticatedSession)
        }
    }

    @MainActor
    func testSuccessfulExchangePassesOriginalNonceAndFirstSignInName() async throws {
        let expected = challenge()
        var name = PersonNameComponents()
        name.givenName = "Reader"
        var received: (String, String, PersonNameComponents?)?
        let result = session
        let model = AppleAccountFlowModel(makeChallenge: { expected }) { token, nonce, fullName in
            received = (token, nonce, fullName); return result
        }
        _ = try XCTUnwrap(model.begin())
        await model.complete(ticketID: expected.id, response: AppleIdentityResponse(identityToken: Data("signed-token".utf8), state: expected.state, fullName: name))
        XCTAssertEqual(received?.0, "signed-token")
        XCTAssertEqual(received?.1, expected.rawNonce)
        XCTAssertEqual(received?.2?.givenName, "Reader")
        XCTAssertEqual(model.authenticatedSession, session)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testCancellationIsSilentAndLateOldCallbackCannotFinishNewAttempt() async throws {
        let a = challenge(), b = challenge("request-B")
        var requests = [a, b]
        var exchanges = 0
        let result = session
        let model = AppleAccountFlowModel(makeChallenge: { requests.removeFirst() }) { _, _, _ in exchanges += 1; return result }
        _ = try XCTUnwrap(model.begin())
        model.cancel(ticketID: a.id)
        XCTAssertTrue(model.isWorking)
        XCTAssertNil(model.begin())
        model.providerCancelled(ticketID: a.id)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage)
        _ = try XCTUnwrap(model.begin())
        await model.complete(ticketID: a.id, response: response(a))
        model.fail(ticketID: a.id, error: AppleAccountFlowError.invalidIdentity)
        XCTAssertTrue(model.isWorking)
        XCTAssertEqual(exchanges, 0)
        await model.complete(ticketID: b.id, response: response(b))
        XCTAssertEqual(exchanges, 1)
        XCTAssertEqual(model.authenticatedSession, session)
    }

    @MainActor
    func testDuplicateCallbacksConsumeNonceOnlyOnceDuringExchange() async throws {
        let expected = challenge(), fixture = AppleExchangeFixture()
        let model = AppleAccountFlowModel(makeChallenge: { expected }) { _, _, _ in try await fixture.exchange() }
        _ = try XCTUnwrap(model.begin())
        let pending = Task { await model.complete(ticketID: expected.id, response: response(expected)) }
        await fixture.waitForStart()
        await model.complete(ticketID: expected.id, response: response(expected))
        model.fail(ticketID: expected.id, error: AppleAccountFlowError.invalidIdentity)
        let calls = await fixture.calls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.isWorking)
        XCTAssertNil(model.errorMessage)
        await fixture.succeed(session)
        await pending.value
        XCTAssertEqual(model.authenticatedSession, session)
    }

    @MainActor
    func testTransportFailureDoesNotClaimLoginAndAllowsFreshRetry() async throws {
        let expected = challenge()
        let model = AppleAccountFlowModel(makeChallenge: { expected }) { _, _, _ in throw URLError(.notConnectedToInternet) }
        _ = try XCTUnwrap(model.begin())
        await model.complete(ticketID: expected.id, response: response(expected))
        XCTAssertNil(model.authenticatedSession)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.errorMessage, "Ingen forbindelse. Prøv igen, når du er online.")
        XCTAssertNotNil(model.begin())
    }

    @MainActor
    func testUnconfirmedTransportSessionDoesNotClaimLogin() async throws {
        let expected = challenge()
        let model = AppleAccountFlowModel(makeChallenge: { expected }) { _, _, _ in nil }
        _ = try XCTUnwrap(model.begin())
        await model.complete(ticketID: expected.id, response: response(expected))
        XCTAssertNil(model.authenticatedSession)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    @MainActor
    func testCancelledExchangeKeepsSlotUntilActualReturnAndCannotPublish() async throws {
        let a = challenge(), b = challenge("request-B"), fixture = AppleExchangeFixture()
        var requests = [a, b]
        let model = AppleAccountFlowModel(makeChallenge: { requests.removeFirst() }) { _, _, _ in try await fixture.exchange() }
        _ = try XCTUnwrap(model.begin())
        let pending = Task { await model.complete(ticketID: a.id, response: response(a)) }
        await fixture.waitForStart()
        model.cancel(ticketID: a.id)
        XCTAssertNil(model.begin())
        XCTAssertTrue(model.isWorking)
        await fixture.succeed(session)
        await pending.value
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.authenticatedSession)
        XCTAssertNil(model.errorMessage)
        _ = try XCTUnwrap(model.begin())
        model.providerCancelled(ticketID: b.id)
    }
}

private actor AppleExchangeFixture {
    private(set) var calls = 0
    private var operation: CheckedContinuation<ReaderAccountSession?, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    func exchange() async throws -> ReaderAccountSession? {
        calls += 1
        return try await withCheckedThrowingContinuation {
            operation = $0
            observer?.resume()
            observer = nil
        }
    }
    func waitForStart() async {
        if calls > 0 { return }
        await withCheckedContinuation { observer = $0 }
    }
    func succeed(_ session: ReaderAccountSession) {
        operation?.resume(returning: session)
        operation = nil
    }
}
