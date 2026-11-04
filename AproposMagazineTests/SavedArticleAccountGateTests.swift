import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Exact feature-login receipts and the real in-memory library/introduction
/// models. No SDK startup, provider, disk, network or shared runtime is used.
@MainActor
final class SavedArticleAccountGateTests: XCTestCase {
    private let sourceID = "0123456789abcdef01234567"

    private func article(language: ArticleContentLanguage = .danish, revision: String = "r1") -> Article {
        Article(id: language == .danish ? sourceID : "en_" + sourceID,
            name: "Saved article", slug: "shared-story", content: "<p>Body</p>", intro: "", topicID: "topic",
            isDraft: false, lastPublished: "2026-10-31T12:00:00Z", contentRevision: revision,
            contentLanguage: language, sourceArticleID: language == .english ? sourceID : nil,
            cmsLocaleId: language == .english ? ArticleContentLanguage.englishCMSLocaleID : nil)
    }

    @MainActor private final class Fixture {
        typealias ReadCompletion = @MainActor (Result<FavoritesRecord?, Error>) -> Void
        let canonical = CanonicalSessionState()
        lazy var gate = SavedArticleAccountGate(canonical: canonical)
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var heldReads: [(FavoritesNamespace, ReadCompletion)] = []
        var holdReads = false
        var current: Article?
        var saves: [Article] = []
        var saveSucceeds = true
        var onSave: (() -> Void)?
        lazy var library = FavoritesModel(storage: .init(read: { [unowned self] namespace, complete in
            if holdReads { heldReads.append((namespace, complete)) }
            else { complete(.success(records[namespace])) }
        }, write: { [unowned self] namespace, record, _, complete in
            records[namespace] = record
            complete(.success(()))
        }))

        init() {
            canonical.adopt(nil)
            library.changeContext(to: .guest)
        }

        func present(_ article: Article? = nil, language: ArticleContentLanguage = .danish) throws -> UUID {
            current = article
            XCTAssertTrue(gate.present(article: article, language: language))
            let id = UUID()
            XCTAssertTrue(gate.beginLogin(id))
            return id
        }

        func publish(_ actionID: UUID, uid: String = "reader-A", isNew: Bool = false) throws -> ReaderLoginResult {
            let original = try XCTUnwrap(gate.request).originalContext
            let session = ReaderAccountSession(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
            canonical.adopt(session)
            return ReaderLoginResult(originalContext: original, acceptedContext: canonical.contextTicket(),
                session: session, isNewUser: isNew, actionID: actionID)
        }

        func loadLibrary(_ uid: String, existing: [Article] = [], hold: Bool = false) throws {
            let context = FavoritesContext.confirmed(userID: uid)
            records[try XCTUnwrap(context.namespace)] = FavoritesRecord(articles: existing)
            holdReads = hold
            library.changeContext(to: context)
        }

        func finishRead() throws {
            let (namespace, complete) = try XCTUnwrap(heldReads.first)
            heldReads.removeFirst()
            complete(.success(records[namespace]))
        }

        func reconcile(language: ArticleContentLanguage = .danish) {
            gate.reconcile(language: language, favorites: library.snapshot,
                favoritesContext: library.context, canSave: library.canChangeSelection,
                currentArticle: { [unowned self] _ in current }, save: { [unowned self] value in
                    saves.append(value)
                    onSave?()
                    guard saveSucceeds else { return false }
                    return library.setFavorite(value, enabled: true) != nil
                })
        }
    }

    func testUnresolvedAndSignedInReadersCannotCreateGuestRequestAndInvalidLanguageIsRejected() {
        let canonical = CanonicalSessionState()
        let gate = SavedArticleAccountGate(canonical: canonical)
        XCTAssertTrue(gate.isUnresolved)
        XCTAssertFalse(gate.present(article: article(), language: .danish))
        canonical.adopt(nil)
        XCTAssertTrue(gate.isGuest)
        XCTAssertFalse(gate.present(article: article(), language: .english))
        canonical.adopt(ReaderAccountSession(uid: "A", email: "a@example.invalid", isEmailVerified: true))
        XCTAssertFalse(gate.present(language: .danish))
        XCTAssertNil(gate.request)
        XCTAssertNil(FirebaseApp.app())
    }

    func testCanonicalPublicationAloneCannotSaveAndOnlyOneExactReceiptConsumesTheIntention() throws {
        let f = Fixture(), requested = article()
        let action = try f.present(requested)
        XCTAssertTrue(try XCTUnwrap(f.gate.request).isModal)
        let receipt = try f.publish(action)
        try f.loadLibrary("reader-A")
        f.reconcile()
        XCTAssertTrue(f.saves.isEmpty, "Canonical account publication is not this feature's login receipt")
        XCTAssertNotNil(f.gate.request)
        let wrong = ReaderLoginResult(originalContext: receipt.originalContext, acceptedContext: receipt.acceptedContext,
            session: receipt.session, isNewUser: false, actionID: UUID())
        XCTAssertFalse(f.gate.accept(wrong, needsIntroduction: false))
        let foreignCanonical = CanonicalSessionState()
        foreignCanonical.adopt(nil)
        let foreignOrigin = ReaderLoginResult(originalContext: foreignCanonical.contextTicket(),
            acceptedContext: receipt.acceptedContext, session: receipt.session, isNewUser: false, actionID: action)
        XCTAssertFalse(f.gate.accept(foreignOrigin, needsIntroduction: false))
        XCTAssertTrue(f.gate.accept(receipt, needsIntroduction: false))
        XCTAssertFalse(f.gate.accept(receipt, needsIntroduction: false))
        f.onSave = { f.reconcile() }
        f.reconcile()
        f.reconcile()
        XCTAssertEqual(f.saves, [requested])
        XCTAssertEqual(f.library.snapshot.articles.map(\.id), [requested.id])
        XCTAssertNil(f.gate.request)
        XCTAssertFalse(f.gate.isWorking)
    }

    func testAcceptedReceiptWaitsForTheSameAccountsActuallyLoadedLibrary() throws {
        let f = Fixture(), requested = article()
        let action = try f.present(requested), receipt = try f.publish(action)
        XCTAssertTrue(f.gate.accept(receipt, needsIntroduction: false))
        try f.loadLibrary("reader-B")
        f.reconcile()
        XCTAssertTrue(f.saves.isEmpty)
        XCTAssertNotNil(f.gate.request)
        try f.loadLibrary("reader-A", hold: true)
        XCTAssertFalse(f.library.canChangeSelection)
        f.reconcile()
        XCTAssertTrue(f.saves.isEmpty)
        XCTAssertNotNil(f.gate.request)
        try f.finishRead()
        XCTAssertTrue(f.library.canChangeSelection)
        f.reconcile()
        XCTAssertEqual(f.saves, [requested])
    }

    func testExistingSavedArticleCompletesWithoutTogglingOrWritingAgain() throws {
        let f = Fixture(), requested = article()
        let action = try f.present(requested), receipt = try f.publish(action)
        try f.loadLibrary("reader-A", existing: [requested])
        let bytesBefore = f.records
        XCTAssertTrue(f.gate.accept(receipt, needsIntroduction: false))
        f.reconcile()
        XCTAssertNil(f.gate.request)
        XCTAssertTrue(f.saves.isEmpty)
        XCTAssertEqual(f.records, bytesBefore)
        XCTAssertEqual(f.library.snapshot.articles.map(\.id), [requested.id])
    }

    func testCancelledOrReplacedRequestCannotAcceptItsLateReceipt() throws {
        let f = Fixture()
        let oldAction = try f.present(article()), old = try f.publish(oldAction)
        f.gate.cancel()
        XCTAssertFalse(f.gate.accept(old, needsIntroduction: true))
        f.canonical.adopt(nil)
        let newAction = try f.present(article())
        f.gate.loginFinished(oldAction)
        XCTAssertTrue(f.gate.isWorking, "An old completion cannot finish the new login action")
        XCTAssertFalse(f.gate.accept(old, needsIntroduction: true))
        let replacement = try f.publish(newAction)
        try f.loadLibrary("reader-A")
        XCTAssertTrue(f.gate.accept(replacement, needsIntroduction: false))
        f.reconcile()
        XCTAssertEqual(f.saves.count, 1)
        f.gate.presentationDidDismiss()
        XCTAssertFalse(f.gate.needsSetup, "Cancelled old new-user status cannot leak into the replacement")
    }

    func testFailedLoginCanRetryButTheRetiredActionCannotOwnTheNewReceipt() throws {
        let f = Fixture()
        let first = try f.present(article())
        f.gate.loginFinished(first)
        XCTAssertFalse(f.gate.isWorking)
        XCTAssertNotNil(f.gate.request)
        let second = UUID()
        XCTAssertTrue(f.gate.beginLogin(second))
        let result = try f.publish(second)
        let stale = ReaderLoginResult(originalContext: result.originalContext, acceptedContext: result.acceptedContext,
            session: result.session, isNewUser: false, actionID: first)
        XCTAssertFalse(f.gate.accept(stale, needsIntroduction: false))
        XCTAssertTrue(f.gate.accept(result, needsIntroduction: false))
        try f.loadLibrary("reader-A")
        f.reconcile()
        XCTAssertEqual(f.saves.count, 1)
    }

    func testAcceptedAccountSwitchAndRoundTripRevokeTheOriginalSave() throws {
        for roundTrip in [false, true] {
            let f = Fixture()
            let action = try f.present(article()), result = try f.publish(action)
            XCTAssertTrue(f.gate.accept(result, needsIntroduction: true))
            try f.loadLibrary("reader-A", hold: true)
            f.canonical.adopt(ReaderAccountSession(uid: "reader-B", email: "b@example.invalid", isEmailVerified: true))
            if roundTrip { f.canonical.adopt(result.session) }
            try f.finishRead()
            f.reconcile()
            XCTAssertTrue(f.saves.isEmpty)
            XCTAssertNil(f.gate.request)
            f.gate.presentationDidDismiss()
            XCTAssertFalse(f.gate.needsSetup)
        }
    }

    func testLanguageChangeBeforeOrAfterReceiptCancelsWithoutSaving() throws {
        for acceptsFirst in [false, true] {
            let f = Fixture()
            let action = try f.present(article()), result = try f.publish(action)
            if acceptsFirst { XCTAssertTrue(f.gate.accept(result, needsIntroduction: false)) }
            f.reconcile(language: .english)
            XCTAssertNil(f.gate.request)
            XCTAssertFalse(f.gate.accept(result, needsIntroduction: false))
            XCTAssertTrue(f.saves.isEmpty)
        }
    }

    func testWithdrawnChangedRevisionWrongIdentityAndWrongLanguageCannotConsumeSave() throws {
        let wrongIdentity = Article(id: "different-id", name: "Other", slug: "other", content: "body",
            intro: "", topicID: "topic", contentRevision: "r1")
        let invalidIdentity = Article(id: "en_" + sourceID, name: "Invalid", slug: "shared-story", content: "body",
            intro: "", topicID: "topic", contentRevision: "r1", contentLanguage: .english)
        let replacements: [Article?] = [nil, article(revision: "r2"), wrongIdentity, article(language: .english), invalidIdentity]
        for replacement in replacements {
            let f = Fixture()
            let action = try f.present(article()), result = try f.publish(action)
            XCTAssertTrue(f.gate.accept(result, needsIntroduction: false))
            try f.loadLibrary("reader-A")
            f.current = replacement // nil is the caller's authoritative withdrawal projection.
            f.reconcile()
            XCTAssertTrue(f.saves.isEmpty)
            XCTAssertNil(f.gate.request)
        }
    }

    func testInlineAccountEntryFinishesWithoutAnArticleOrLibraryWriteAndDefersNewSetupUntilDismissal() throws {
        for newUser in [false, true] {
            let f = Fixture()
            let action = try f.present(), result = try f.publish(action, isNew: newUser)
            XCTAssertFalse(try XCTUnwrap(f.gate.request).isModal)
            XCTAssertTrue(f.gate.accept(result, needsIntroduction: newUser))
            XCTAssertFalse(f.gate.needsSetup)
            f.reconcile()
            XCTAssertNil(f.gate.request)
            XCTAssertTrue(f.saves.isEmpty)
            f.gate.presentationDidDismiss()
            XCTAssertEqual(f.gate.needsSetup, newUser)
            f.gate.acknowledgeSetup()
            XCTAssertFalse(f.gate.needsSetup)
        }
    }

    func testFailedSaveIsNotAutomaticallyRepeatedAndItsMessageCanBeCleared() throws {
        let f = Fixture()
        let action = try f.present(article()), result = try f.publish(action)
        XCTAssertTrue(f.gate.accept(result, needsIntroduction: false))
        try f.loadLibrary("reader-A")
        f.saveSucceeds = false
        f.reconcile()
        f.reconcile()
        XCTAssertEqual(f.saves.count, 1)
        XCTAssertNil(f.gate.request)
        XCTAssertNotNil(f.gate.message)
        XCTAssertTrue(f.library.snapshot.articles.isEmpty)
        f.gate.clearMessage()
        XCTAssertNil(f.gate.message)
    }

    func testReentrantNewGuestIntentionSurvivesTheOldSaveFailureWithoutItsMessage() throws {
        let f = Fixture(), requested = article()
        let action = try f.present(requested), result = try f.publish(action)
        XCTAssertTrue(f.gate.accept(result, needsIntroduction: true))
        try f.loadLibrary("reader-A")
        f.saveSucceeds = false
        f.onSave = {
            f.canonical.adopt(nil)
            XCTAssertTrue(f.gate.present(article: requested, language: .danish))
        }
        f.reconcile()
        XCTAssertEqual(f.saves.count, 1)
        XCTAssertNotNil(f.gate.request)
        XCTAssertNil(f.gate.message, "Old failed work cannot publish into the new request")
        XCTAssertFalse(f.gate.isWorking)
        f.gate.presentationDidDismiss()
        XCTAssertFalse(f.gate.needsSetup, "The old request's setup intent was cancelled")
    }

    func testCancellationDuringLoginPublicationCannotLeaveWorkingStateOrProviderAdmission() {
        let canonical = CanonicalSessionState()
        canonical.adopt(nil)
        let gate = SavedArticleAccountGate(canonical: canonical)
        XCTAssertTrue(gate.present(article: article(), language: .danish))
        var armed = true
        let observation = gate.objectWillChange.sink {
            guard armed else { return }
            armed = false
            gate.cancel()
        }
        XCTAssertFalse(gate.beginLogin(UUID()))
        XCTAssertNil(gate.request)
        XCTAssertFalse(gate.isWorking)
        withExtendedLifetime(observation) {}
    }

    func testAccountSwitchDuringAcceptedReceiptPublicationRevokesTheOriginalRequest() throws {
        let f = Fixture()
        let action = try f.present(article()), result = try f.publish(action)
        var armed = true
        let observation = f.gate.objectWillChange.sink {
            guard armed else { return }
            armed = false
            f.canonical.adopt(ReaderAccountSession(uid: "reader-B", email: "b@example.invalid", isEmailVerified: true))
        }
        XCTAssertFalse(f.gate.accept(result, needsIntroduction: true))
        XCTAssertNil(f.gate.request)
        XCTAssertFalse(f.gate.isWorking)
        f.reconcile()
        XCTAssertTrue(f.saves.isEmpty)
        f.gate.presentationDidDismiss()
        XCTAssertFalse(f.gate.needsSetup)
        withExtendedLifetime(observation) {}
    }

    func testViewModelFeatureGateUsesFeatureIdentityRatherThanTheIndependentReadIdentity() throws {
        let readIdentity = CanonicalSessionState(), featureIdentity = CanonicalSessionState()
        readIdentity.adopt(nil)
        featureIdentity.adopt(nil)
        let readOrigin = readIdentity.contextTicket(), featureOrigin = featureIdentity.contextTicket()
        var actualUID: String?
        let vm = ArticleViewModel(startup: ReaderSDKStartupState(), identity: readIdentity,
            featureIdentity: featureIdentity, actualUserID: { actualUID }, readEffects: .init())
        let gate = vm.accountSaveGate
        XCTAssertTrue(gate.present(language: .danish))
        XCTAssertEqual(try XCTUnwrap(gate.request).originalContext, featureOrigin)
        XCTAssertNotEqual(gate.request?.originalContext, readOrigin)
        let action = UUID()
        XCTAssertTrue(gate.beginLogin(action))
        let session = ReaderAccountSession(uid: "feature-reader", email: "reader@example.invalid", isEmailVerified: true)
        actualUID = session.uid
        featureIdentity.adopt(session)
        XCTAssertEqual(readIdentity.snapshot.context, .guest, "Read bootstrap identity remains independently injected")
        let wrongOrigin = ReaderLoginResult(originalContext: readOrigin,
            acceptedContext: featureIdentity.contextTicket(), session: session, isNewUser: false, actionID: action)
        XCTAssertFalse(gate.accept(wrongOrigin, needsIntroduction: false))
        let accepted = ReaderLoginResult(originalContext: featureOrigin,
            acceptedContext: featureIdentity.contextTicket(), session: session, isNewUser: false, actionID: action)
        XCTAssertTrue(gate.accept(accepted, needsIntroduction: false))
        let snapshot = FavoritesSnapshot(generation: UUID(), revision: 0, articles: [],
            pendingArticleIDs: [], serverConfirmed: false, state: .unresolved)
        gate.reconcile(language: .danish, favorites: snapshot, favoritesContext: .unresolved, canSave: false,
            currentArticle: { _ in XCTFail("Inline entry has no article"); return nil },
            save: { _ in XCTFail("Inline entry has no save"); return false })
        XCTAssertNil(gate.request)
        XCTAssertTrue(gate.hasAccount)
        XCTAssertNil(FirebaseApp.app())
        withExtendedLifetime(vm) {}
    }

    func testNewAccountsDeferredOrVisibleSetupIsRevokedWhenAccountChangesAfterSuccessfulSave() throws {
        for dismissedBeforeSwitch in [false, true] {
            let f = Fixture(), requested = article()
            let action = try f.present(requested), result = try f.publish(action, isNew: true)
            XCTAssertTrue(f.gate.accept(result, needsIntroduction: true))
            try f.loadLibrary("reader-A")
            f.reconcile()
            XCTAssertNil(f.gate.request)
            XCTAssertEqual(f.saves, [requested])
            XCTAssertTrue(f.gate.permitsSetup)
            XCTAssertFalse(f.gate.needsSetup)
            if dismissedBeforeSwitch {
                f.gate.presentationDidDismiss()
                XCTAssertTrue(f.gate.needsSetup)
            }
            f.canonical.adopt(ReaderAccountSession(uid: "reader-B", email: "b@example.invalid", isEmailVerified: true))
            XCTAssertFalse(f.gate.permitsSetup)
            XCTAssertFalse(f.gate.needsSetup)
            f.gate.presentationDidDismiss()
            XCTAssertFalse(f.gate.needsSetup, "A's deferred setup must not open for B after sheet dismissal")
            f.canonical.adopt(result.session)
            f.gate.presentationDidDismiss()
            XCTAssertFalse(f.gate.permitsSetup, "Returning to A does not resurrect its retired setup authority")
            XCTAssertFalse(f.gate.needsSetup)
            XCTAssertEqual(f.saves, [requested])
        }
    }

    func testInvalidCurrentArticleCallbackCannotCancelItsReentrantReplacementRequest() throws {
        let f = Fixture(), requested = article(), replacement = article(revision: "r2")
        let action = try f.present(requested), result = try f.publish(action)
        let oldID = try XCTUnwrap(f.gate.request).id
        XCTAssertTrue(f.gate.accept(result, needsIntroduction: true))
        try f.loadLibrary("reader-A")
        var replacementID: UUID?
        f.gate.reconcile(language: .danish, favorites: f.library.snapshot,
            favoritesContext: f.library.context, canSave: f.library.canChangeSelection,
            currentArticle: { id in
                XCTAssertEqual(id, requested.id)
                f.canonical.adopt(nil)
                XCTAssertTrue(f.gate.present(article: replacement, language: .danish))
                replacementID = f.gate.request?.id
                return nil
            }, save: { _ in XCTFail("The old invalidated article must not save"); return false })
        let current = try XCTUnwrap(f.gate.request)
        XCTAssertEqual(current.id, try XCTUnwrap(replacementID))
        XCTAssertNotEqual(current.id, oldID)
        XCTAssertEqual(current.article, replacement)
        XCTAssertTrue(f.gate.isGuest)
        XCTAssertFalse(f.gate.isWorking)
        XCTAssertFalse(f.gate.permitsSetup)
        XCTAssertFalse(f.gate.needsSetup)
        XCTAssertTrue(f.saves.isEmpty)
    }

    func testLateDismissalForOldRequestCannotCancelTheReplacementLogin() throws {
        let f = Fixture()
        _ = try f.present(article())
        let oldID = try XCTUnwrap(f.gate.request).id
        f.gate.cancel()
        let replacement = article(revision: "r2")
        XCTAssertTrue(f.gate.present(article: replacement, language: .danish))
        let newID = try XCTUnwrap(f.gate.request).id
        XCTAssertTrue(f.gate.beginLogin(UUID()))
        f.gate.presentationDidDismiss(requestID: oldID)
        XCTAssertEqual(f.gate.request?.id, newID)
        XCTAssertEqual(f.gate.request?.article, replacement)
        XCTAssertTrue(f.gate.isWorking)
        XCTAssertFalse(f.gate.needsSetup)
        f.gate.presentationDidDismiss(requestID: newID)
        XCTAssertNil(f.gate.request)
        XCTAssertFalse(f.gate.isWorking)
        XCTAssertTrue(f.saves.isEmpty)
    }

    func testCompletedIntroductionFeatureEntryRoutesNewAccountToInterestsAndReturningAccountPastSetup() async throws {
        for newUser in [false, true] {
            let canonical = CanonicalSessionState()
            canonical.adopt(nil)
            var stored: Data?
            var actualUID: String?
            let introduction = ReaderIntroductionModel(storage: .init(read: { stored }, write: { stored = $0 }))
            XCTAssertTrue(introduction.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
            XCTAssertTrue(introduction.start())
            XCTAssertTrue(introduction.setSelectedTopicIDs(["old-guest-choice"]))
            XCTAssertTrue(introduction.complete())
            XCTAssertFalse(introduction.isPresented)
            let operations = AuthOperationCoordinator(canonical: canonical, actualUserID: { actualUID })
            let operation = try operations.capture(.google)
            let entry = try XCTUnwrap(introduction.beginAccountEntry(actionID: operation.actionID, fromFeature: true))
            let gate = SavedArticleAccountGate(canonical: canonical)
            XCTAssertTrue(gate.present(language: .danish))
            XCTAssertTrue(gate.beginLogin(operation.actionID))
            try operations.beginProvider(operation)
            try operations.providerReturned(operation)
            let session = try await operations.exchange(operation) {
                actualUID = "feature-reader"
                let session = ReaderAccountSession(uid: "feature-reader", email: "reader@example.invalid", isEmailVerified: true)
                canonical.adopt(session)
                XCTAssertTrue(introduction.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
                XCTAssertTrue(operations.acceptResult(operation, context: canonical.contextTicket(), isNewUser: newUser))
                XCTAssertNotNil(gate.request, "A canonical publication does not finish the feature login")
                XCTAssertNil(operations.acceptedLoginResult(operation, session: session))
                return session
            }
            let result = try XCTUnwrap(operations.acceptedLoginResult(operation, session: session))
            XCTAssertTrue(introduction.acceptLogin(result, ticket: entry))
            XCTAssertEqual(introduction.isPresented, newUser)
            if newUser { XCTAssertEqual(introduction.step, .interests) }
            XCTAssertTrue(introduction.selectedTopicIDs.isEmpty, "Feature signup never adopts the previous guest draft")
            XCTAssertTrue(gate.accept(result, needsIntroduction: introduction.isPresented))
            let snapshot = FavoritesSnapshot(generation: UUID(), revision: 0, articles: [],
                pendingArticleIDs: [], serverConfirmed: false, state: .unresolved)
            gate.reconcile(language: .danish, favorites: snapshot, favoritesContext: .unresolved, canSave: false,
                currentArticle: { _ in XCTFail("Inline login has no article lookup"); return nil },
                save: { _ in XCTFail("Inline login has no article save"); return false })
            gate.presentationDidDismiss()
            XCTAssertEqual(gate.needsSetup, newUser)
            XCTAssertFalse(introduction.acceptLogin(result, ticket: entry))
            XCTAssertNil(FirebaseApp.app())
        }
    }
}
