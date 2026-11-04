import XCTest
@testable import Apropos

/// Real admission/canonical/introduction pipeline; provider and disk are local.
@MainActor
final class ReaderIntroductionLoginIntegrationTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var actualUID: String?
        var data: Data?
        var failWrite = false
        lazy var operations = AuthOperationCoordinator(canonical: canonical, actualUserID: { [unowned self] in actualUID })
        lazy var introduction = ReaderIntroductionModel(storage: .init(read: { [unowned self] in data }, write: { [unowned self] in
            if failWrite { throw CocoaError(.fileWriteUnknown) }
            data = $0
        }))
        init() {
            canonical.adopt(nil)
            introduction.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
            introduction.start()
        }
        func publish(_ uid: String) -> ReaderAccountSession {
            actualUID = uid
            let session = ReaderAccountSession(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
            canonical.adopt(session)
            introduction.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
            return session
        }
    }

    func testCanonicalPublicationKeepsWelcomeUntilItsRealFinishedReceiptRoutesNewOrExistingUser() async throws {
        for isNew in [true, false] {
            let fixture = Fixture()
            let operation = try fixture.operations.capture(.apple)
            let entry = try XCTUnwrap(fixture.introduction.beginAccountEntry(actionID: operation.actionID))
            try fixture.operations.beginProvider(operation)
            try fixture.operations.providerReturned(operation)
            let session = try await fixture.operations.exchange(operation) {
                let session = fixture.publish("reader")
                XCTAssertTrue(fixture.operations.acceptResult(operation, context: fixture.canonical.contextTicket(), isNewUser: isNew))
                await Task.yield() // The actual UI may render canonical state before result delivery.
                XCTAssertTrue(fixture.introduction.isPresented)
                XCTAssertEqual(fixture.introduction.step, .welcome)
                XCTAssertFalse(fixture.introduction.isCompleted)
                XCTAssertNil(fixture.operations.acceptedLoginResult(operation, session: session))
                return session
            }
            let receipt = try XCTUnwrap(fixture.operations.acceptedLoginResult(operation, session: session))
            XCTAssertTrue(fixture.introduction.acceptLogin(receipt, ticket: entry))
            XCTAssertEqual(fixture.introduction.isPresented, isNew)
            XCTAssertEqual(fixture.introduction.isCompleted, !isNew)
            XCTAssertEqual(fixture.introduction.step, isNew ? .interests : .welcome)
            XCTAssertFalse(fixture.introduction.acceptLogin(receipt, ticket: entry), "One accepted receipt cannot navigate twice")
        }
    }

    func testCompletedManualReplayKeepsExistingGoogleReaderInPersonalization() async throws {
        try await assertManualReplayKeepsExistingGoogleReader(completed: true)
    }

    func testIncompleteManualReplayKeepsExistingGoogleReaderInPersonalization() async throws {
        try await assertManualReplayKeepsExistingGoogleReader(completed: false)
    }

    private func assertManualReplayKeepsExistingGoogleReader(completed: Bool,
        file: StaticString = #filePath, line: UInt = #line) async throws {
        let fixture = Fixture()
        XCTAssertTrue(fixture.introduction.setSelectedTopicIDs(["guest-choice"]), file: file, line: line)
        XCTAssertTrue(fixture.introduction.advance(), file: file, line: line)
        if completed { XCTAssertTrue(fixture.introduction.complete(), file: file, line: line) }
        XCTAssertTrue(fixture.introduction.replay(), file: file, line: line)
        let operation = try fixture.operations.capture(.google)
        let entry = try XCTUnwrap(fixture.introduction.beginAccountEntry(actionID: operation.actionID), file: file, line: line)
        try fixture.operations.beginProvider(operation)
        try fixture.operations.providerReturned(operation)
        let session = try await fixture.operations.exchange(operation) {
            let session = fixture.publish("returning-reader")
            XCTAssertTrue(fixture.operations.acceptResult(operation, context: fixture.canonical.contextTicket(), isNewUser: false), file: file, line: line)
            await Task.yield()
            XCTAssertTrue(fixture.introduction.isPresented, file: file, line: line)
            XCTAssertEqual(fixture.introduction.step, .welcome, file: file, line: line)
            return session
        }
        let receipt = try XCTUnwrap(fixture.operations.acceptedLoginResult(operation, session: session), file: file, line: line)
        XCTAssertTrue(fixture.introduction.acceptLogin(receipt, ticket: entry), file: file, line: line)
        XCTAssertTrue(fixture.introduction.isPresented, "Explicit replay continues after an existing-account login", file: file, line: line)
        XCTAssertEqual(fixture.introduction.step, .interests, file: file, line: line)
        XCTAssertEqual(fixture.introduction.isCompleted, completed, "Replay does not rewrite prior completion", file: file, line: line)
        XCTAssertEqual(fixture.introduction.selectedTopicIDs, [], "An existing account must not inherit a guest draft", file: file, line: line)
        XCTAssertFalse(fixture.introduction.acceptLogin(receipt, ticket: entry), "The receipt remains single-use", file: file, line: line)
    }

    func testCancelledWelcomeDoesNotConsumeLaterAcceptedProviderResult() async throws {
        let fixture = Fixture()
        let operation = try fixture.operations.capture(.google)
        let entry = try XCTUnwrap(fixture.introduction.beginAccountEntry(actionID: operation.actionID))
        let session = try await fixture.operations.exchange(operation) {
            let session = fixture.publish("reader")
            XCTAssertTrue(fixture.operations.acceptResult(operation, context: fixture.canonical.contextTicket(), isNewUser: true))
            fixture.introduction.cancelAccountEntry(entry)
            await Task.yield()
            return session
        }
        let receipt = try XCTUnwrap(fixture.operations.acceptedLoginResult(operation, session: session))
        XCTAssertFalse(fixture.introduction.acceptLogin(receipt, ticket: entry))
        XCTAssertEqual(fixture.introduction.step, .welcome)
        XCTAssertFalse(fixture.introduction.isCompleted)
        XCTAssertNil(fixture.data)
    }

    func testReturningEmailUserRetriesOnlyLocalCompletionWithoutRepeatingAuthentication() async throws {
        let fixture = Fixture()
        let operation = try fixture.operations.capture(.emailSignIn)
        let entry = try XCTUnwrap(fixture.introduction.beginAccountEntry(actionID: operation.actionID))
        var providerCalls = 0
        let session = try await fixture.operations.exchange(operation) {
            providerCalls += 1
            let session = fixture.publish("reader")
            XCTAssertTrue(fixture.operations.acceptResult(operation, context: fixture.canonical.contextTicket(), isNewUser: false))
            return session
        }
        let receipt = try XCTUnwrap(fixture.operations.acceptedLoginResult(operation, session: session))
        fixture.failWrite = true
        XCTAssertFalse(fixture.introduction.acceptLogin(receipt, ticket: entry))
        XCTAssertNotNil(fixture.introduction.storageError)
        fixture.introduction.cancelAccountEntry(entry) // Original provider finishes; pending save must survive.
        fixture.failWrite = false
        XCTAssertTrue(fixture.introduction.retry())
        XCTAssertTrue(fixture.introduction.isCompleted)
        XCTAssertFalse(fixture.introduction.isPresented)
        XCTAssertEqual(providerCalls, 1)
    }
}
