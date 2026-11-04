import AVFoundation
import Combine
import FirebaseCore
import FirebaseAppCheck
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import SwiftUI
import SDWebImage

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    
    private var injectedLinkEntry: IncomingLinkEntry?
    @MainActor private var linkEntry: IncomingLinkEntry { injectedLinkEntry ?? IncomingLinkEntryRuntime.entry }

    @MainActor convenience init(linkEntry: IncomingLinkEntry) {
        self.init()
        injectedLinkEntry = linkEntry
    }

    @MainActor private var injectedStartup: ReaderSDKStartupState?
    @MainActor private var injectedIdentity: CanonicalSessionState?
    @MainActor private var injectedActualUserID: (() -> String?)?
    @MainActor private var injectedBadgeClear: (() -> Void)?
    @MainActor private var startup: ReaderSDKStartupState { injectedStartup ?? .application }
    @MainActor private var identity: CanonicalSessionState { injectedIdentity ?? AuthService.shared.bootstrapIdentity }
    @MainActor private var readerServicesMayRun: Bool { startup.permitsReaderServices(identity: identity) }

    @MainActor convenience init(startup: ReaderSDKStartupState, identity: CanonicalSessionState,
                               actualUserID: (() -> String?)? = nil, badgeClear: (() -> Void)? = nil) {
        self.init()
        injectedStartup = startup; injectedIdentity = identity
        injectedActualUserID = actualUserID ?? { identity.snapshot.session?.uid }
        injectedBadgeClear = badgeClear
    }

    /// The actual launch call site supplies lazy effects. Closed startup does
    /// not construct any reader singleton; tests inject memory-only effects.
    @MainActor private var localStartupClaimed = false
    @MainActor private var localStartupTask: Task<Void, Never>?
    @MainActor @discardableResult
    func runAccountStartup(authOnly: @escaping () -> Void, readerSteps: [() -> Void],
                           observeAuth: @escaping () -> Void, releaseReader: @escaping () -> Void = {},
                           readyReader: @escaping () -> Void = {}) -> Task<Void, Never>? {
        guard startup.localRecovery != nil else {
            authOnly()
            _ = performReaderWork(readerSteps)
            observeAuth()
            releaseReader()
            observeReadyReaderServices(readyReader)
            return nil
        }
        // Claim before arbitrary auth hooks. A reentrant call cannot replace the
        // physical read or replay preparation, even after cancellation/failure.
        guard !localStartupClaimed else { return localStartupTask }
        localStartupClaimed = true
        authOnly()
        observeAuth() // Auth-only identity can arrive while reader work is closed.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.localStartupTask = nil }
            do {
                try await self.startup.prepareLocalRecovery()
                try Task.checkCancellation()
                guard self.performReaderWork(readerSteps), !Task.isCancelled else {
                    self.startup.closeLocalReadiness(); return
                }
                self.startup.finishLocalPreparation()
                // Capture after the asynchronous marker read, then preserve that
                // exact account through publication and any delayed service work.
                let original = self.identity.contextTicket()
                let permission = self.readerWorkGuard()
                guard self.readerServicesMayRun else { self.startup.closeLocalReadiness(); return }
                releaseReader()
                guard !Task.isCancelled, self.identity.isCurrent(original), self.readerServicesMayRun,
                      original.context == .unresolved || permission() else {
                    self.startup.closeLocalReadiness(); return
                }
                self.startup.publishLocalReadiness()
                self.observeReadyReaderServices(readyReader)
            } catch {
                self.startup.closeLocalReadiness()
            }
        }
        localStartupTask = task
        return task
    }

    @MainActor private var readerReadySubscriptions: Set<AnyCancellable> = []
    @MainActor private var readerReadyTask: Task<Void, Never>?
    @MainActor private var readerReadyContext: CanonicalSessionState.ContextTicket?

    /// The first Auth result may arrive after disk preparation. Every confirmed
    /// account gets its own delayed work; an old owner's job never borrows it.
    @MainActor private func observeReadyReaderServices(_ effect: @escaping () -> Void) {
        guard readerReadySubscriptions.isEmpty else { return }
        let schedule = { [weak self] in self?.scheduleReadyReaderServices(effect) }
        identity.changes.sink { _ in schedule() }.store(in: &readerReadySubscriptions)
        startup.changes.sink { schedule() }.store(in: &readerReadySubscriptions)
        scheduleReadyReaderServices(effect)
    }

    @MainActor private func scheduleReadyReaderServices(_ effect: @escaping () -> Void) {
        readerReadyTask?.cancel()
        guard identity.snapshot.context != .unresolved,
              startup.permitsReaderPublication(identity: identity) else { return }
        let original = identity.contextTicket(), current = readerWorkGuard()
        guard readerReadyContext != original, current() else { return }
        readerReadyTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, current(), self.identity.isCurrent(original),
                  self.startup.permitsReaderPublication(identity: self.identity) else { return }
            self.readerReadyContext = original // Reserve before an arbitrary effect.
            effect()
        }
    }

    @MainActor @discardableResult
    func performReaderWork(_ steps: [() -> Void]) -> Bool {
        let original = identity.contextTicket()
        // Legacy cold preparation predates the first Auth observation. Once an
        // identity is known, also detect provider changes before its callback.
        let providerGuard = readerWorkGuard()
        let allowed = {
            self.identity.isCurrent(original) && self.readerServicesMayRun
                && (original.context == .unresolved || providerGuard())
        }
        for step in steps {
            guard allowed() else { return false }
            step()
        }
        return allowed()
    }

    /// Capture when an operation begins, then pass through every async hop to
    /// the SDK write. UID equality alone cannot identify A → B → A.
    @MainActor func readerWorkGuard() -> @MainActor () -> Bool {
        let original = identity.contextTicket(), identity = identity, startup = startup
        let providerIsCurrent: () -> Bool
        if let actualUserID = injectedActualUserID {
            providerIsCurrent = {
                let actual = actualUserID()
                return identity.isCurrent(original) && actual == original.userID
            }
        } else {
            providerIsCurrent = { AuthService.shared.bootstrapContextIsCurrent(original) }
        }
        return {
            let providerMatches = providerIsCurrent() // May reenter; ticket check follows.
            return providerMatches && identity.isCurrent(original) && startup.permitsReaderServices(identity: identity)
        }
    }

    private var servicesAreDisabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
    }

    typealias PushGuard = @MainActor @Sendable () -> Bool
    typealias PushCompletion = @Sendable (String?, Error?) -> Void
    typealias PushDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    enum PushDiagnostic: Equatable, Sendable { case fetchFailed, registrationFailed }
    struct PushTokenEffects: Sendable {
        let assignAPNS: @MainActor @Sendable (Data, @escaping PushGuard) -> Void
        let fetchToken: @MainActor @Sendable (@escaping PushGuard, @escaping PushCompletion) -> Void
        let deliver: PushDelivery
        let acceptToken: @MainActor @Sendable (String, NotificationService.TokenOwner, @escaping PushGuard) -> Void
        let diagnostic: @MainActor @Sendable (PushDiagnostic, @escaping PushGuard) -> Void
    }
    @MainActor private var injectedPushTokenEffects: PushTokenEffects?
    @MainActor private var pushTokenID = UUID()
    @MainActor private var pushTokenEffects: PushTokenEffects { injectedPushTokenEffects ?? Self.livePushTokenEffects() }
    @MainActor private var pushTokenIngressEnabled: Bool { injectedPushTokenEffects != nil || !servicesAreDisabled }

    /// Full local composition for the actual delegate entries, with no SDK fallback.
    @MainActor convenience init(startup: ReaderSDKStartupState, identity: CanonicalSessionState,
                                 actualUserID: @escaping () -> String?, pushTokenEffects: PushTokenEffects) {
        self.init(startup: startup, identity: identity, actualUserID: actualUserID)
        injectedPushTokenEffects = pushTokenEffects
    }

    private struct PushAdmission: Sendable {
        let owner: NotificationService.TokenOwner
        let current: PushGuard
    }
    /// The permission and denial latch stay actor-isolated while SDK callbacks
    /// carry a Sendable check. This does not extend the delegate's lifetime.
    @MainActor private final class PushAdmissionState {
        weak var delegate: AppDelegate?
        let id: UUID
        let original: CanonicalSessionState.ContextTicket
        let permission: @MainActor () -> Bool
        var denied = false

        init(delegate: AppDelegate, id: UUID, original: CanonicalSessionState.ContextTicket,
             permission: @escaping @MainActor () -> Bool) {
            self.delegate = delegate; self.id = id; self.original = original; self.permission = permission
        }

        func check() -> Bool {
            guard !denied, let delegate, delegate.pushTokenID == id, delegate.identity.isCurrent(original),
                  permission(), !denied, delegate.pushTokenID == id, delegate.identity.isCurrent(original)
            else { denied = true; return false }
            return true
        }
    }
    @MainActor private func capturePushAdmission(replacingToken: Bool = true) -> PushAdmission? {
        guard pushTokenIngressEnabled, readerServicesMayRun else { return nil }
        let original = identity.contextTicket()
        guard original.context != .unresolved else { return nil }
        if replacingToken { pushTokenID = UUID() }
        let state = PushAdmissionState(delegate: self, id: pushTokenID, original: original,
                                       permission: readerWorkGuard())
        let current: PushGuard = { state.check() }
        guard current() else { return nil }
        return .init(owner: original.userID.map { .account($0) } ?? .guest, current: current)
    }

    /// SDK completion may arrive on any queue. Claim the first physical result
    /// before its MainActor hop, and defer every observable effect until admission.
    private final class PushReplyClaim: @unchecked Sendable {
        private let lock = NSLock()
        private var consumed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !consumed else { return false }
            consumed = true; return true
        }
    }

    @MainActor private static func livePushTokenEffects() -> PushTokenEffects {
        .init(assignAPNS: { token, current in
            guard current() else { return }
            let messaging = Messaging.messaging()
            guard current() else { return }
            messaging.apnsToken = token
        }, fetchToken: { current, completion in
            guard current() else { return }
            let messaging = Messaging.messaging()
            guard current() else { return }
            messaging.token(completion: completion)
        }, deliver: { action in
            Task { @MainActor in action() }
        }, acceptToken: { token, owner, current in
            guard current() else { return }
            // Preserve the existing profile eligibility without resolving a new owner.
            var registerAccount = false
            if case .account(let uid) = owner {
                let manager = UserManager.shared
                guard current() else { return }
                registerAccount = manager.currentUser?.uid == uid
            }
            guard current() else { return }
            let service = NotificationService.shared
            guard current() else { return }
            service.acceptRegistrationToken(token, owner: owner,
                registerAccountToken: registerAccount, stillCurrent: current)
        }, diagnostic: { diagnostic, current in
            guard current() else { return }
            switch diagnostic {
            case .fetchFailed: AppDiagnostics.recordOperational(.fcmFetchFailed)
            case .registrationFailed: AppDiagnostics.recordOperational(.apnsRegistrationFailed)
            }
        })
    }

    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Unit tests must remain hermetic: do not require GoogleService-Info.plist
        // and do not initialize Firebase, APNs, analytics, or background services.
        if servicesAreDisabled {
            return true
        }

        // Local badge/inbox effects must not wait for reader/server readiness.
        NotificationInboxRuntime.didBecomeActive()

        // Use a mixable ambient session by default so launch-time playback (the
        // splash video) never interrupts audio the user is already playing in
        // another app. The podcast player explicitly upgrades to `.playback`.
        configureDefaultAudioSession()
        UIScrollView.appearance().bounces = false

        runAccountStartup(authOnly: {
            // Local consent/buffer preparation must precede Firebase Core.
            TelemetryRuntime.shared.prepare()
            FirebaseConfiguration.shared.setLoggerLevel(.min)
            let newsletterEnabled = ReaderNewsletterConfiguration.endpoint(in: Bundle.main.infoDictionary ?? [:]) != nil
            AppCheck.setAppCheckProviderFactory(ReaderAppAttestProviderFactory(isEnabled: newsletterEnabled))
            FirebaseApp.configure()
            AppCheck.appCheck().isTokenAutoRefreshEnabled = false
        }, readerSteps: [
            { IncomingLinkRuntime.shared.prepareIfNeeded() },
            { TelemetryRuntime.shared.firebaseDidConfigure() },
            { PodcastProgressRuntime.shared.prepareIfNeeded() },
            { ReadingHistoryRuntime.shared.prepareIfNeeded() },
            { FavoritesRuntime.shared.prepareIfNeeded() },
            { FirestoreService.shared.configurePersistenceIfNeeded() },
            { UserManager.shared.startObservingSession() },
            { ReaderPreferencesService.shared.start() }
        ], observeAuth: { AuthService.shared.startObservingSession() }, releaseReader: {
            AuthService.shared.resumeReaderAfterLocalRecovery()
        }, readyReader: { [weak self] in self?.startDeferredReaderServices(application) })
        FeatureFlags.registerDefaults()
        configureGlobalImageCaching()
        application.beginReceivingRemoteControlEvents()
        AppDiagnostics.breadcrumb("app_launch")

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Configure Google Sign-In from Firebase / GoogleService-Info.plist
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else {
            AppDiagnostics.recordOperational(.appConfigurationMissing)
        }


        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let payload = NotificationNavigation.payload(from: remoteNotification) {
            UserDefaults.standard.set(true, forKey: NotificationNavigation.skipBootloaderKey)
            Task { @MainActor in
                NavigationCoordinator.shared.scheduleNotificationNavigation(payload)
            }
        }

        return true
    }

    /// Schedule the existing one-shot services after local disk readiness, so
    /// a slow read cannot silently drop them. Each hop retains its original owner.
    @MainActor private func startDeferredReaderServices(_ application: UIApplication) {
        guard readerServicesMayRun else { return }
        let stillCurrent = readerWorkGuard()
        Task { @MainActor in
            guard stillCurrent() else { return }
            PodcastLiveActivityService.shared.dismissUnsupportedActivitiesIfNeeded()
            guard stillCurrent() else { return }
            SubscriptionManager.shared.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard stillCurrent() else { return }
            SmartNotificationService.shared.setupNotificationCategories()
            guard stillCurrent() else { return }
            Messaging.messaging().isAutoInitEnabled = true
            guard stillCurrent() else { return }
            Messaging.messaging().delegate = self
        }

        // Register only if the user has already granted permission. The prompt is shown from Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard stillCurrent() else { return }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                guard authorized else { return }
                
                DispatchQueue.main.async {
                    guard stillCurrent() else { return }
                    application.registerForRemoteNotifications()
                    Task { @MainActor in
                        guard stillCurrent() else { return }
                        await NotificationService.shared.bootstrapPushNotifications(stillCurrent: stillCurrent)
                    }
                }
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TriggerTestNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                guard stillCurrent() else { return }
                Task { @MainActor in
                    guard stillCurrent() else { return }
                    await NotificationService.shared.sendTestLocalNotificationAfterAuthorization(delay: 2)
                }
            }
        }
        #endif
    }

    private func configureDefaultAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    private func configureGlobalImageCaching() {
        let cacheConfig = SDImageCache.shared.config
        cacheConfig.maxMemoryCost = 60 * 1024 * 1024
        cacheConfig.maxDiskSize = 350 * 1024 * 1024
        cacheConfig.maxDiskAge = 30 * 24 * 60 * 60
        cacheConfig.shouldUseWeakMemoryCache = true

        let downloaderConfig = SDWebImageDownloader.shared.config
        downloaderConfig.maxConcurrentDownloads = 4
        downloaderConfig.executionOrder = .lifoExecutionOrder
        downloaderConfig.downloadTimeout = 15
    }

    // APNs token -> FCM. This actual OS entry shares the injected production path.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard !deviceToken.isEmpty, let admission = capturePushAdmission() else { return }
        let effects = pushTokenEffects
        guard admission.current() else { return }
        effects.assignAPNS(deviceToken, admission.current)
        guard admission.current() else { return }
        let claim = PushReplyClaim(), deliver = effects.deliver
        effects.fetchToken(admission.current) { [weak self] token, error in
            guard claim.claim() else { return }
            deliver { [weak self] in
                guard self != nil, admission.current() else { return }
                if error != nil { effects.diagnostic(.fetchFailed, admission.current) }
                else if let token, !token.isEmpty {
                    effects.acceptToken(token, admission.owner, admission.current)
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        guard let admission = capturePushAdmission(replacingToken: false) else { return }
        let effects = pushTokenEffects
        guard admission.current() else { return }
        effects.diagnostic(.registrationFailed, admission.current)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        receivePushRegistrationToken(fcmToken)
    }

    /// The value entry used by the Messaging delegate needs no SDK object in tests.
    @MainActor func receivePushRegistrationToken(_ token: String?) {
        guard let token, !token.isEmpty, let admission = capturePushAdmission() else { return }
        let effects = pushTokenEffects
        guard admission.current() else { return }
        effects.deliver { [weak self] in
            guard self != nil, admission.current() else { return }
            effects.acceptToken(token, admission.owner, admission.current)
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard !servicesAreDisabled else { return [] }
        NotificationInboxRuntime.receive(notification, opened: false)
        guard readerServicesMayRun else { return [] }
        if notification.request.trigger is UNPushNotificationTrigger == false {
            NotificationDeliveryPolicy.recordLocalNotificationDelivered()
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        // The inbox owns the foreground unread badge projection. Showing a
        // banner does not acknowledge the corresponding article message.
        return [.banner, .sound]
    }
    
    // Handle notification tap when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard !servicesAreDisabled else { return }
        let userInfo = response.notification.request.content.userInfo
        await receiveNotificationResponse(actionIdentifier: response.actionIdentifier, userInfo: userInfo,
            effects: .init(receive: { opened in
                NotificationInboxRuntime.receive(response.notification, opened: opened)
            }, trackOpen: { articleID, type in
                AnalyticsService.shared.trackNotificationOpen(articleId: articleID, type: type)
            }, openArticle: { payload in
                await self.openArticleFromNotification(userInfo: userInfo, payload: payload)
            }))
    }

    /// Value entry shared with the actual delegate callback. Effects are supplied
    /// lazily so local routing tests never construct reader SDKs or OS lookups.
    struct NotificationResponseEffects {
        let receive: @MainActor (Bool) -> Void
        let trackOpen: @MainActor (String, String) -> Void
        let openArticle: @MainActor (NotificationNavigation.Payload) async -> Void
    }
    @MainActor
    func receiveNotificationResponse(actionIdentifier: String, userInfo: [AnyHashable: Any],
                                     effects: NotificationResponseEffects) async {
        effects.receive(actionIdentifier != UNNotificationDismissActionIdentifier)
        let payload = NotificationNavigation.payload(from: userInfo)
        // Preserve a typed tap in the existing readiness-aware ingress before
        // reader SDKs or analytics can gate it. Presentation remains guarded.
        if let payload, payload.isArticleNotification || payload.isPodcastNotification,
           [UNNotificationDefaultActionIdentifier, "READ_ACTION", "READ_BREAKING_NEWS"].contains(actionIdentifier) {
            await effects.openArticle(payload)
            if readerServicesMayRun {
                effects.trackOpen(payload.articleIdentifier, payload.type)
            }
            return
        }
        // Unknown/legacy/custom actions retain their existing reader boundary.
        guard readerServicesMayRun else { return }

        if let payload {
            let notificationType = payload.type
            effects.trackOpen(payload.articleIdentifier, notificationType)
        } else if let articleId = legacyNotificationArticleId(from: userInfo) {
            effects.trackOpen(articleId, legacyNotificationType(from: userInfo))
        }
        
        switch actionIdentifier {
        case "READ_ACTION", "READ_BREAKING_NEWS":
            if let payload { await effects.openArticle(payload) }
            
        case "VIEW_RECOMMENDATIONS":
            // "Se anbefalinger" action - navigate to recommendations
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRecommendations"),
                    object: nil
                )
            }
            
        case "VIEW_FESTIVAL_GUIDE":
            // "Se guide" action - navigate to festival guide
            if let festivalId = userInfo["festival_id"] as? String {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToFestivalGuide"),
                        object: nil,
                        userInfo: ["festivalId": festivalId]
                    )
                }
            }
            
        case UNNotificationDefaultActionIdentifier:
            if let name = legacyNotificationArticleName(from: userInfo), payload == nil {
                await AppReadiness.waitUntilUIReady()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenArticleFromNotification"),
                        object: nil,
                        userInfo: ["articleName": name]
                    )
                }
                return
            }

            if let payload { await effects.openArticle(payload) }
            
        default:
            // Other actions or dismissed
            break
        }
    }
    
    // Handle Google Sign-In URL and Deep Links
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        linkEntry.openURL(url)
    }
    
    // MARK: - Application Lifecycle
    func applicationDidEnterBackground(_ application: UIApplication) {
        guard !servicesAreDisabled, readerServicesMayRun else { return }
        ReadingHistoryRuntime.shared.flushAcceptedEdits()
        AppDiagnostics.breadcrumb("app_background")
        Task { @MainActor in
            PodcastPlayerManager.shared.persistPlaybackProgress(force: true)
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        guard !servicesAreDisabled, readerServicesMayRun else { return }
        AppDiagnostics.breadcrumb("app_foreground")
        let stillCurrent = readerWorkGuard()
        Task { @MainActor in
            guard stillCurrent() else { return }
            let categoryIds = NotificationService.shared.loadPersistedAllCategoryIds()
            await NotificationService.shared.bootstrapPushNotifications(allCategoryIds: categoryIds, stillCurrent: stillCurrent)
            guard stillCurrent() else { return }
            syncWidgetFeedIfNeeded()

            guard !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }

            await PodcastRepository.shared.refreshManifest()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // An injected local effect exercises this actual lifecycle entry without
        // permitting any OS notification lookup or reader work in the test host.
        if let injectedBadgeClear {
            injectedBadgeClear()
        } else {
            guard !servicesAreDisabled else { return }
            NotificationInboxRuntime.didBecomeActive()
        }
        guard !servicesAreDisabled, readerServicesMayRun else { return }
        Task { @MainActor in
            syncWidgetFeedIfNeeded()
        }
    }

    @MainActor
    private func syncWidgetFeedIfNeeded() {
        let cache = CacheManager.shared
        // The event owns these bytes before the Task hop; foreground/widget
        // startup joins the same bounded decode as the app's cold hydration.
        let original = cache.captureArticlesHydration()
        Task { @MainActor in await cache.syncCachedWidgetFeed(original) }
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        guard !servicesAreDisabled, readerServicesMayRun else { return }
        AppDiagnostics.breadcrumb("memory_warning")
        SDImageCache.shared.clearMemory()
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
    }

    private func legacyNotificationArticleId(from userInfo: [AnyHashable: Any]) -> String? {
        NotificationNavigation.payload(from: userInfo)?.articleIdentifier
    }

    private func legacyNotificationType(from userInfo: [AnyHashable: Any]) -> String {
        NotificationNavigation.payload(from: userInfo)?.type ?? "general"
    }

    private func legacyNotificationArticleName(from userInfo: [AnyHashable: Any]) -> String? {
        let normalized = NotificationNavigation.normalize(userInfo)
        if let name = normalized["article_name"] as? String, !name.isEmpty {
            return name
        }
        return nil
    }

    private func openArticleFromNotification(
        userInfo: [AnyHashable: Any],
        payload: NotificationNavigation.Payload?
    ) async {
        guard let payload else { return }

        await MainActor.run {
            NavigationCoordinator.shared.scheduleNotificationNavigation(payload)
        }
    }
    
    // MARK: - Additional UIApplicationDelegate Methods for Full Conformance
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        linkEntry.continueActivity(type: userActivity.activityType, webpageURL: userActivity.webpageURL)
    }
    
    func application(_ application: UIApplication, didUpdate userActivity: NSUserActivity) {
    }
    
    func application(_ application: UIApplication, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        AppDiagnostics.recordOperational(.activityResumeFailed)
    }
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !servicesAreDisabled, readerServicesMayRun,
              let permission = AuthService.shared.captureReaderWorkPermission() else {
            completionHandler(.noData); return
        }
        // Preserve the original owner through the silent-push SDK read, CMS
        // fallback and cache update. Stale work completes the OS callback once.
        refreshBackgroundFeed(stillCurrent: permission, fallbackFailure: .noData,
            onFailure: { AppDiagnostics.recordOperational(.backgroundRefreshFailed) },
            completion: completionHandler)
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !servicesAreDisabled, readerServicesMayRun,
              let permission = AuthService.shared.captureReaderWorkPermission() else {
            completionHandler(.noData); return
        }
        refreshBackgroundFeed(stillCurrent: permission, fallbackFailure: .failed,
            onFailure: { AppDiagnostics.recordOperational(.backgroundFetchFailed) },
            completion: completionHandler)
    }

    typealias BackgroundFeedFetch = @MainActor (@escaping @MainActor () -> Bool,
        @escaping (Result<[Article], Error>) -> Void) -> Void

    /// Shared by both actual OS callbacks and injected local tests. Closures are
    /// lazy: constructing the delegate/helper starts no SDK, network or cache.
    @MainActor
    func refreshBackgroundArticles(
        stillCurrent: @escaping @MainActor () -> Bool,
        fallbackFailure: UIBackgroundFetchResult,
        onFailure: @escaping @MainActor () -> Void,
        fetch: @escaping BackgroundFeedFetch = { permission, done in
            guard permission() else { done(.failure(CancellationError())); return }
            FirestoreArticleService.shared.fetchArticles(stillCurrent: permission, completion: done)
        },
        fallback: @escaping BackgroundFeedFetch = { permission, done in
            guard permission() else { done(.failure(CancellationError())); return }
            WebflowService.shared.fetchArticles(completion: done)
        },
        cache: @escaping @MainActor ([Article]) -> Void = { CacheManager.shared.cacheArticles($0) },
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        refreshBackgroundFeed(stillCurrent: stillCurrent, fallbackFailure: fallbackFailure, onFailure: onFailure,
            fetch: { permission, done in fetch(permission) { done($0.map(ArticleFeedSnapshot.Update.complete)) } },
            fallback: fallback, cache: { cache($0.articles) }, completion: completion)
    }

    @MainActor
    func refreshBackgroundFeed(
        stillCurrent: @escaping @MainActor () -> Bool,
        fallbackFailure: UIBackgroundFetchResult,
        onFailure: @escaping @MainActor () -> Void,
        fetch: @escaping ArticleFeedRefreshCoordinator.CatalogFetch = { permission, done in
            guard permission() else { done(.failure(CancellationError())); return }
            let cache = CacheManager.shared, original = cache.captureArticlesHydration()
            guard permission() else { done(.failure(CancellationError())); return }
            FirestoreArticleService.shared.fetchCatalog(stillCurrent: permission) { result in
                Task { @MainActor in
                    guard permission() else { done(.failure(CancellationError())); return }
                    do {
                        let update = try result.get()
                        let prepared = try await cache.prepareFeedUpdate(update, original: original, stillPermitted: permission)
                        done(permission() ? .success(prepared) : .failure(CancellationError()))
                    } catch { done(permission() ? .failure(error) : .failure(CancellationError())) }
                }
            }
        },
        fallback: @escaping BackgroundFeedFetch = { permission, done in
            guard permission() else { done(.failure(CancellationError())); return }
            WebflowService.shared.fetchArticles(completion: done)
        },
        cache: @escaping @MainActor (ArticleFeedSnapshot.Update) -> Void = { update in
            if let date = update.cacheTimestamp {
                CacheManager.shared.cacheArticles(update.articles, articlesAreSorted: true, timestamp: date)
            }
        },
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        var completed = false
        var primaryReturned = false
        var fallbackReturned = false
        let finish: @MainActor (UIBackgroundFetchResult) -> Void = { result in
            guard !completed else { return }
            completed = true // Reserve before the provider guard or OS callback can reenter.
            completion(stillCurrent() ? result : .noData)
        }
        let apply: @MainActor (Result<ArticleFeedSnapshot.Update, Error>, Bool) -> Void = { result, isFallback in
            guard !completed else { return }
            guard stillCurrent() else { finish(.noData); return }
            switch result {
            case .success(let update):
                guard update.baselineIsCurrent(), stillCurrent(), update.baselineIsCurrent() else { finish(.noData); return }
                guard update.hasAcceptedNamespace else { onFailure(); finish(.failed); return }
                if update.cacheTimestamp != nil { cache(update) }
                finish(update.cacheTimestamp != nil && update.didChange ? .newData : .noData)
            case .failure:
                if !isFallback || fallbackFailure == .failed { onFailure() }
                finish(isFallback ? fallbackFailure : .failed)
            }
        }
        let queryPermission: @MainActor () -> Bool = {
            guard !completed else { return false }
            let allowed = stillCurrent()
            return allowed && !completed
        }
        guard queryPermission() else { finish(.noData); return }
        fetch(queryPermission) { result in
            Task { @MainActor in
                guard !completed, !primaryReturned else { return }
                primaryReturned = true
                guard stillCurrent() else { finish(.noData); return }
                if case .failure(let error as FirestoreArticleError) = result, error.allowsCMSFallback {
                    fallback(queryPermission) { fallbackResult in
                        Task { @MainActor in
                            guard !completed, !fallbackReturned else { return }
                            fallbackReturned = true
                            apply(fallbackResult.map(ArticleFeedSnapshot.Update.complete), true)
                        }
                    }
                } else {
                    apply(result, false)
                }
            }
        }
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
