import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class AccountServiceHermeticStartupTests: XCTestCase {
    func testDisabledRealAccountAdaptersRemainInertAcrossStartAndAccountActions() async throws {
        // Never try these production entry points outside the native hermetic
        // host. A missing test guard must fail before any SDK could be touched.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            XCTFail("Hermetic host configuration is required"); return
        }
        XCTAssertNil(FirebaseApp.allApps)
        let auth = AuthService.shared, preferences = ReaderPreferencesService.shared
        _ = ReaderWriterDrainRuntime.shared
        let newsletter = ReaderNewsletterRuntime.model
        XCTAssertEqual(newsletter.status, .idle)
        let canonicalBefore = auth.state.snapshot, preferencesBefore = preferences.model.snapshot
        let context = auth.state.contextTicket()
        XCTAssertNil(FavoritesRuntime.existingJournalForTransition(context: context))
        auth.startObservingSession()
        preferences.start()
        XCTAssertNil(preferences.refreshAfterInterruption())
        _ = auth.readerAccountActions
        await auth.sendVerification(context: context)
        try await auth.refreshSession(context: context)
        let email = try await auth.perform(.signIn, form: EmailAccountForm())
        let apple = try await auth.signInWithApple(idToken: "local-fixture", rawNonce: "local-fixture", fullName: nil)
        XCTAssertNil(email); XCTAssertNil(apple)
        XCTAssertNil(preferences.model.captureSave(ids: ["music"], context: preferences.model.contextTicket()))
        XCTAssertThrowsError(try auth.signOut())
        XCTAssertEqual(auth.state.snapshot, canonicalBefore)
        XCTAssertEqual(preferences.model.snapshot, preferencesBefore)
        XCTAssertNil(FirebaseApp.allApps)
    }
    func testConfiguredProviderResumeAdaptersCannotEscapeHermeticHost() throws {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            XCTFail("Hermetic host configuration is required"); return
        }
        XCTAssertNil(FirebaseApp.allApps)
        let auth = AuthService()
        let before = auth.state.snapshot, identityBefore = auth.bootstrapIdentity.snapshot
        let configuration = try ReaderDeletionHTTPTransport.Configuration(projectID: "local-deletion",
            appID: "1:123456789:ios:abcdef123456", endpointURL: XCTUnwrap(URL(string: "https://deletion.example.invalid/reader")))
        let google = GoogleSignInService(reauthenticationProvider: { _, _ in
            XCTFail("A disabled configure adapter must never start the provider"); throw CancellationError()
        })
        for resumed in [false, true] {
            let identity = resumed ? auth.bootstrapIdentity : auth.state
            let epoch: ReaderAccountDeletionCoordinator.EpochReader = { _ in
                XCTFail("A disabled configure adapter must never read membership"); return nil
            }
            XCTAssertNil(auth.configureEmailReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: epoch,
                prompt: ReaderEmailReauthenticationPrompt(canonical: identity), resumingAfterRestart: resumed))
            XCTAssertNil(auth.configureAppleReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: epoch,
                prompt: ReaderAppleReauthenticationPrompt(canonical: identity), resumingAfterRestart: resumed))
            XCTAssertNil(auth.configureGoogleReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: epoch,
                prompt: ReaderGoogleReauthenticationPrompt(canonical: identity, service: google), resumingAfterRestart: resumed))
        }
        XCTAssertEqual(auth.state.snapshot, before); XCTAssertEqual(auth.bootstrapIdentity.snapshot, identityBefore)
        XCTAssertNil(FirebaseApp.allApps)
    }

}
