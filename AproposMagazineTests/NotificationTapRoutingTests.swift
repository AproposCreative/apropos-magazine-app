import FirebaseCore
import UserNotifications
import XCTest
@testable import Apropos

/// Exercises the actual delegate value entry and VM route commit with local
/// ingress/navigation/presentation effects. No OS response, SDK or player starts.
@MainActor
final class NotificationTapRoutingTests: XCTestCase {
    private let articleID = "6ae8aff199edb6a5b1f8c9f9"
    private let slug = "behemoth-og-dimmu-borgir-i-kb-hallen"

    private var payload: [AnyHashable: Any] {
        ["type": "new_article", "article_id": articleID,
         "article_slug": slug, "click_action": "OPEN_ARTICLE"]
    }

    private func article() -> Article {
        Article(id: articleID, name: "Lokal artikel", slug: slug,
                content: "<p>Lokalt artikelindhold.</p>", intro: "", topicID: "music",
                isDraft: false, lastPublished: "2026-11-02T16:31:32.090Z",
                contentRevision: "local-public-revision")
    }

    func testActualDelegateQueuesCanonicalTapBeforeReaderStartupAndOpensAfterReadiness() async {
        XCTAssertNil(FirebaseApp.allApps)
        let closedStartup = ReaderSDKStartupState(), identity = CanonicalSessionState()
        _ = identity.adopt(nil)
        let delegate = AppDelegate(startup: closedStartup, identity: identity, actualUserID: { nil })
        var startupReady = false
        let runtime = IncomingLinkRuntime(disabled: false, startupReady: { startupReady })
        var delivered: [IncomingLinkCoordinator.Request] = []
        var received: [Bool] = [], analyticsOpens = 0
        let routed = expectation(description: "Original canonical tap survives reader startup")
        runtime.bindResolver({ request in
            delivered.append(request)
            routed.fulfill()
        }, cancelPendingSeek: { XCTFail("An article tap must not start or cancel player work") })

        await delegate.receiveNotificationResponse(actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: payload, effects: .init(receive: { received.append($0) },
                trackOpen: { _, _ in analyticsOpens += 1 }, openArticle: { value in
                    XCTAssertTrue(runtime.acceptNotification(value))
                }))
        XCTAssertEqual(received, [true], "Inbox receipt is independent of reader-service admission")
        XCTAssertEqual(analyticsOpens, 0, "Closed reader startup cannot initialize analytics")
        XCTAssertTrue(delivered.isEmpty)

        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: nil)
        runtime.setUIReady(true)
        XCTAssertTrue(delivered.isEmpty, "The accepted tap still waits for actual startup")
        startupReady = true
        runtime.refreshStartupReadiness()
        await fulfillment(of: [routed], timeout: 3)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.link, .article(id: articleID))
        XCTAssertEqual(delivered.first?.fallbackIdentifier, slug)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testActualIncomingArticleCommitDismissesFullPlayerButPreservesPlayingEpisode() async {
        XCTAssertNil(FirebaseApp.allApps)
        let identity = CanonicalSessionState()
        _ = identity.adopt(nil)
        let availability = ArticleAvailabilityModel()
        let value = article()
        availability.recordPublications([value], ticket: availability.beginRead())
        let vm = ArticleViewModel(startup: ReaderSDKStartupState(), identity: identity,
            actualUserID: { nil }, readEffects: .init(), availabilityModel: availability)
        let runtime = IncomingLinkRuntime(disabled: false)
        let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
        navigation.selectedTab = .favorites
        navigation.navigateToArticle(value, in: .favorites)
        var presentation = PodcastPlayerPresentation(activeEpisodeID: "existing-playing-episode",
            preparationID: nil, preparationTitle: nil, isFullPlayerPresented: true,
            offlinePlaybackMessage: nil)
        let originalEpisodeID = presentation.activeEpisodeID
        var dismissals = 0
        let routed = expectation(description: "Actual VM commits the incoming canonical article")
        runtime.bindResolver({ request in
            vm.openIncomingArticle(value, ticket: request.ticket, stillCurrent: { true },
                runtime: runtime, navigation: navigation,
                permitsBody: { availability.permitsBody($0) }, dismissFullPlayer: {
                    dismissals += 1
                    presentation.isFullPlayerPresented = false
                })
            routed.fulfill()
        }, cancelPendingSeek: { XCTFail("An article route must preserve ordinary playback") })
        runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: nil)
        runtime.setUIReady(true)
        XCTAssertTrue(runtime.acceptNotification(NotificationNavigation.payload(from: payload)!))
        await fulfillment(of: [routed], timeout: 3)

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertEqual(navigation.homePath.count, 1)
        XCTAssertEqual(navigation.favoritesPath.count, 1, "An unrelated tab's path is retained")
        XCTAssertEqual(dismissals, 1, "The ready article must not remain hidden behind the existing full-player sheet")
        XCTAssertFalse(presentation.isFullPlayerPresented)
        XCTAssertEqual(presentation.activeEpisodeID, originalEpisodeID,
                       "Only presentation is dismissed; playback/session/progress are not closed")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testClosedReaderAdmitsTypedArticleAndAudioTapsButNotDismissedOrUnknownActions() async {
        let cases: [(String, String, DeepLink?)] = [
            (UNNotificationDefaultActionIdentifier, "new_article", .article(id: articleID)),
            ("READ_ACTION", "new_article", .article(id: articleID)),
            ("READ_BREAKING_NEWS", "breaking_news", .article(id: articleID)),
            (UNNotificationDefaultActionIdentifier, "new_podcast", .podcast(id: articleID, startSeconds: nil)),
            (UNNotificationDefaultActionIdentifier, "new_narration", .podcast(id: articleID, startSeconds: nil)),
            (UNNotificationDismissActionIdentifier, "new_article", nil),
            (UNNotificationDefaultActionIdentifier, "unknown_kind", nil),
            ("UNKNOWN_ACTION", "new_article", nil)
        ]
        for (action, type, expected) in cases {
            let identity = CanonicalSessionState()
            _ = identity.adopt(nil)
            let delegate = AppDelegate(startup: ReaderSDKStartupState(), identity: identity, actualUserID: { nil })
            var ready = false
            let runtime = IncomingLinkRuntime(disabled: false, startupReady: { ready })
            var requests: [IncomingLinkCoordinator.Request] = []
            var receipts: [Bool] = [], analytics = 0, forwarded = 0
            let delivered = expectation(description: "Typed \(type) \(action)")
            delivered.isInverted = expected == nil
            runtime.bindResolver({ request in requests.append(request); delivered.fulfill() }, cancelPendingSeek: {})
            var info = payload
            info["type"] = type
            if type == "new_narration" { info["podcast_title"] = "Explicit local audio announcement" }
            await delegate.receiveNotificationResponse(actionIdentifier: action, userInfo: info,
                effects: .init(receive: { receipts.append($0) }, trackOpen: { _, _ in analytics += 1 },
                    openArticle: { value in forwarded += 1; XCTAssertTrue(runtime.acceptNotification(value)) }))
            XCTAssertTrue(requests.isEmpty)
            runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: nil); runtime.setUIReady(true)
            ready = true; runtime.refreshStartupReadiness()
            await fulfillment(of: [delivered], timeout: expected == nil ? 0.05 : 3)
            XCTAssertEqual(forwarded, expected == nil ? 0 : 1)
            XCTAssertEqual(requests.first?.link, expected)
            XCTAssertEqual(requests.count, expected == nil ? 0 : 1)
            XCTAssertEqual(receipts, [action != UNNotificationDismissActionIdentifier])
            XCTAssertEqual(analytics, 0)
        }
        XCTAssertNil(FirebaseApp.allApps)
    }

    @MainActor private final class RouteFixture {
        let article: Article
        let identity = CanonicalSessionState()
        let availability = ArticleAvailabilityModel()
        let runtime = IncomingLinkRuntime(disabled: false)
        let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
        var current = true
        var dismissals = 0
        var onPermission: (() -> Void)?
        var onDismiss: (() -> Void)?
        var presentation = PodcastPlayerPresentation(activeEpisodeID: "ordinary-playing-episode",
            preparationID: nil, preparationTitle: nil, isFullPlayerPresented: true, offlinePlaybackMessage: nil)
        lazy var vm = ArticleViewModel(startup: ReaderSDKStartupState(), identity: identity,
            actualUserID: { nil }, readEffects: .init(), availabilityModel: availability)
        init(article: Article) {
            self.article = article
            _ = identity.adopt(nil)
            availability.recordPublications([article], ticket: availability.beginRead())
            navigation.selectedTab = .favorites
            navigation.navigateToArticle(article, in: .favorites)
        }
        func commit(_ request: IncomingLinkCoordinator.Request) {
            vm.openIncomingArticle(article, ticket: request.ticket, stillCurrent: { self.current },
                runtime: runtime, navigation: navigation, permitsBody: { article in
                    let observed = self.availability.permitsBody(article)
                    let hook = self.onPermission; self.onPermission = nil; hook?()
                    return observed
                }, dismissFullPlayer: {
                    self.dismissals += 1
                    self.presentation.isFullPlayerPresented = false
                    let hook = self.onDismiss; self.onDismiss = nil; hook?()
                })
        }
    }

    private func admittedRequest(_ fixture: RouteFixture) async -> IncomingLinkCoordinator.Request? {
        let admitted = expectation(description: "Local original route ticket")
        var request: IncomingLinkCoordinator.Request?
        fixture.runtime.bindResolver({ value in request = value; admitted.fulfill() }, cancelPendingSeek: {})
        fixture.runtime.prepareIfNeeded(); fixture.runtime.changeAccountContext(userID: nil)
        fixture.runtime.setUIReady(true)
        XCTAssertTrue(fixture.runtime.accept(.article(id: articleID)))
        await fulfillment(of: [admitted], timeout: 3)
        return request
    }

    private func assertNoNavigation(_ fixture: RouteFixture, dismissals: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.navigation.selectedTab, .favorites, file: file, line: line)
        XCTAssertEqual(fixture.navigation.homePath.count, 0, file: file, line: line)
        XCTAssertEqual(fixture.navigation.favoritesPath.count, 1, file: file, line: line)
        XCTAssertEqual(fixture.dismissals, dismissals, file: file, line: line)
        XCTAssertEqual(fixture.presentation.activeEpisodeID, "ordinary-playing-episode", file: file, line: line)
        XCTAssertNil(FirebaseApp.allApps, file: file, line: line)
    }

    func testStaleOrWithdrawnIncomingArticleDoesNotDismissOrNavigate() async {
        for withdrawn in [false, true] {
            let fixture = RouteFixture(article: article())
            guard let request = await admittedRequest(fixture) else { return }
            if withdrawn {
                fixture.availability.recordWithdrawals([articleID], ticket: fixture.availability.beginRead())
            } else {
                fixture.current = false
            }
            fixture.commit(request)
            assertNoNavigation(fixture, dismissals: 0)
            XCTAssertTrue(fixture.presentation.isFullPlayerPresented)
        }
    }

    func testPublicationPermissionReentryCannotDismissOldRoute() async {
        let fixture = RouteFixture(article: article())
        guard let request = await admittedRequest(fixture) else { return }
        fixture.onPermission = { fixture.runtime.suspendForAccountChange() }
        fixture.commit(request)
        assertNoNavigation(fixture, dismissals: 0)
        XCTAssertTrue(fixture.presentation.isFullPlayerPresented)
    }

    func testDismissalReentryCannotCommitOldRouteUnderAnotherAccount() async {
        let fixture = RouteFixture(article: article())
        guard let request = await admittedRequest(fixture) else { return }
        fixture.onDismiss = {
            fixture.runtime.suspendForAccountChange()
            fixture.runtime.changeAccountContext(userID: "different-local-owner")
        }
        fixture.commit(request)
        assertNoNavigation(fixture, dismissals: 1)
        XCTAssertFalse(fixture.presentation.isFullPlayerPresented)
    }

    func testWithdrawalDuringDismissalRejectsNavigationWithoutClosingPlayback() async {
        let fixture = RouteFixture(article: article())
        guard let request = await admittedRequest(fixture) else { return }
        fixture.onDismiss = {
            fixture.availability.recordWithdrawals([self.articleID], ticket: fixture.availability.beginRead())
        }
        fixture.commit(request)
        assertNoNavigation(fixture, dismissals: 1)
        XCTAssertFalse(fixture.presentation.isFullPlayerPresented)
    }

    func testClosedIncomingReadinessNeverCallsTheSDKPermissionProvider() {
        let identity = CanonicalSessionState()
        _ = identity.adopt(nil)
        var permissionReads = 0
        for startup in [ReaderSDKStartupState(), ReaderSDKStartupState(alreadyInitialized: true)] {
            XCTAssertFalse(IncomingLinkRuntime.readerStartupReady(startup: startup, identity: identity,
                permission: { permissionReads += 1; return true }))
        }
        XCTAssertEqual(permissionReads, 0, "Closed or uncertain startup must not construct Auth or another SDK permission provider")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testReadyIncomingReadinessKeepsTheActualProviderBindingAndDenial() {
        let identity = CanonicalSessionState()
        let session = ReaderAccountSession(uid: "local-owner", email: "local@example.invalid", isEmailVerified: true)
        _ = identity.adopt(session)
        let startup = ReaderSDKStartupState.application
        var actualUID: String? = session.uid
        var permissionReads = 0
        let check = {
            IncomingLinkRuntime.readerStartupReady(startup: startup, identity: identity, permission: {
                permissionReads += 1
                return startup.captureReaderWork(identity: identity, actualUserID: { actualUID }) != nil
            })
        }
        XCTAssertTrue(check())
        XCTAssertEqual(permissionReads, 1)
        actualUID = "another-local-owner"
        XCTAssertFalse(check(), "A ready startup cannot borrow a different provider's identity")
        XCTAssertEqual(permissionReads, 2)
        XCTAssertFalse(IncomingLinkRuntime.readerStartupReady(startup: startup, identity: identity,
            permission: { permissionReads += 1; return false }))
        XCTAssertEqual(permissionReads, 3)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testIncomingReadinessPermissionReentryCannotBorrowTheSameUIDAfterRoundTrip() {
        let identity = CanonicalSessionState()
        let session = ReaderAccountSession(uid: "local-owner", email: "local@example.invalid", isEmailVerified: true)
        _ = identity.adopt(session)
        let original = identity.contextTicket()
        var permissionReads = 0
        XCTAssertFalse(IncomingLinkRuntime.readerStartupReady(startup: .application, identity: identity,
            permission: {
                permissionReads += 1
                _ = identity.adopt(nil)
                _ = identity.adopt(session)
                return true
            }))
        XCTAssertEqual(permissionReads, 1)
        XCTAssertFalse(identity.isCurrent(original))
        XCTAssertEqual(identity.snapshot.session?.uid, session.uid)
        XCTAssertNil(FirebaseApp.allApps)
    }
}
