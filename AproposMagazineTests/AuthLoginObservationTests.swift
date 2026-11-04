import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Subscribe to the publisher SwiftUI observes, not an individual property
/// wrapper: a stored objectWillChange does not wire @Published automatically.
@MainActor
final class AuthLoginObservationTests: XCTestCase {
    func testEmailInputsModeBusyAndResultReachTheActualObjectPublisherAfterCommit() async throws {
        let result = ReaderAccountSession(uid: "fixture", email: "reader@example.invalid", isEmailVerified: false)
        let model = EmailAccountFlowModel { _, _ in result }
        struct Observation {
            let email: String
            let password: String
            let action: EmailAccountAction
            let busy: Bool
            let session: ReaderAccountSession?
        }
        var observed: [Observation] = []
        let subscription = model.objectWillChange.sink {
            observed.append(.init(email: model.form.email, password: model.form.password,
                                  action: model.action, busy: model.isWorking, session: model.authenticatedSession))
        }
        model.form.email = result.email
        XCTAssertEqual(observed.last?.email, result.email)
        model.form.password = "original-password"
        XCTAssertEqual(observed.last?.password, "original-password")
        model.action = .resetPassword
        XCTAssertEqual(observed.last?.action, .resetPassword)
        model.action = .signIn
        XCTAssertEqual(observed.last?.action, .signIn)
        let original = try XCTUnwrap(model.captureSubmission())
        XCTAssertEqual(observed.last?.busy, true)
        await model.submit(original)
        XCTAssertTrue(observed.contains { $0.session == result })
        XCTAssertEqual(observed.last?.busy, false)
        XCTAssertEqual(observed.last?.password, "")
        XCTAssertEqual(observed.last?.session, result)
        withExtendedLifetime(subscription) {}
    }

    func testSuccessfulEmailCleanupCannotClearAReplacementDraftDuringPublication() async throws {
        let result = ReaderAccountSession(uid: "fixture", email: "reader@example.invalid", isEmailVerified: false)
        let model = EmailAccountFlowModel { _, _ in result }
        model.form = EmailAccountForm(email: result.email, password: "old-password", confirmation: "old-password", displayName: "Old")
        let original = try XCTUnwrap(model.captureSubmission())
        var replaced = false
        let subscription = model.objectWillChange.sink {
            guard !replaced, model.form.password.isEmpty else { return }
            replaced = true
            model.form = EmailAccountForm(email: "new@example.invalid", password: "new-password", confirmation: "new-confirmation", displayName: "New")
        }
        await model.submit(original)
        XCTAssertTrue(replaced)
        XCTAssertEqual(model.form.email, "new@example.invalid")
        XCTAssertEqual(model.form.password, "new-password")
        XCTAssertEqual(model.form.confirmation, "new-confirmation")
        XCTAssertFalse(model.isWorking)
        withExtendedLifetime(subscription) {}
    }

    func testCancelledEmailCleanupCannotClearAReplacementDraftDuringPublication() throws {
        let model = EmailAccountFlowModel { _, _ in nil }
        model.form = EmailAccountForm(email: "old@example.invalid", password: "old-password", confirmation: "old-password", displayName: "Old")
        _ = try XCTUnwrap(model.captureSubmission())
        var replaced = false
        let subscription = model.objectWillChange.sink {
            guard !replaced, model.form.password.isEmpty else { return }
            replaced = true
            model.cancel() // Idempotent even inside the secret-cleanup event.
            model.form = EmailAccountForm(email: "new@example.invalid", password: "new-password", confirmation: "new-confirmation", displayName: "New")
        }
        model.cancel()
        XCTAssertTrue(replaced)
        XCTAssertEqual(model.form.email, "new@example.invalid")
        XCTAssertEqual(model.form.password, "new-password")
        XCTAssertEqual(model.form.confirmation, "new-confirmation")
        XCTAssertFalse(model.isWorking)
        withExtendedLifetime(subscription) {}
    }

    func testAppleActualObjectPublisherTracksBusyUntilCallbackAndThenTheAcceptedResult() async throws {
        let result = ReaderAccountSession(uid: "fixture", email: "reader@example.invalid", isEmailVerified: true)
        let model = AppleAccountFlowModel { _, _, _ in result }
        var observed: [(busy: Bool, session: ReaderAccountSession?)] = []
        let subscription = model.objectWillChange.sink {
            observed.append((model.isWorking, model.authenticatedSession))
        }
        let first = try XCTUnwrap(model.begin())
        XCTAssertEqual(observed.last?.busy, true)
        model.cancel(ticketID: first.id)
        XCTAssertTrue(model.isWorking)
        model.providerCancelled(ticketID: first.id)
        XCTAssertEqual(observed.last?.busy, false)
        let next = try XCTUnwrap(model.begin())
        XCTAssertEqual(observed.last?.busy, true)
        await model.complete(ticketID: next.id,
            response: .init(identityToken: Data("fixture-token".utf8), state: next.state, fullName: nil))
        XCTAssertTrue(observed.contains { $0.session == result })
        XCTAssertEqual(observed.last?.busy, false)
        XCTAssertEqual(observed.last?.session, result)
        withExtendedLifetime(subscription) {}
    }

    func testInertGoogleAdapterUIPropertiesReachActualObjectPublisherWithoutStartingSDKs() throws {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            XCTFail("Hermetic host configuration is required"); return
        }
        XCTAssertNil(FirebaseApp.allApps)
        // Construction and ordinary UI properties are inert. No login, signout,
        // token, provider or Firebase operation is called by this test.
        let service = GoogleSignInService.shared
        let original = (service.isSignedIn, service.errorMessage, service.showErrorDialog)
        var observed: [(signedIn: Bool, message: String?, dialog: Bool)] = []
        let subscription = service.objectWillChange.sink {
            observed.append((service.isSignedIn, service.errorMessage, service.showErrorDialog))
        }
        defer {
            subscription.cancel()
            service.isSignedIn = original.0
            service.errorMessage = original.1
            service.showErrorDialog = original.2
        }
        service.isSignedIn = !original.0
        XCTAssertEqual(observed.last?.signedIn, !original.0)
        service.errorMessage = "Lokal testbesked"
        XCTAssertEqual(observed.last?.message, "Lokal testbesked")
        service.showErrorDialog = true
        XCTAssertEqual(observed.last?.dialog, true)
        service.clearError()
        XCTAssertEqual(observed.last?.dialog, false)
        XCTAssertNil(try XCTUnwrap(observed.last).message)
        XCTAssertNil(FirebaseApp.allApps)
    }
}
