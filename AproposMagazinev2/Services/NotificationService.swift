import Combine
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UserNotifications

@MainActor
class NotificationService: NSObject, ObservableObject {
    typealias OperationGuard = @MainActor () -> Bool
    typealias Completion = @MainActor (Error?) -> Void
    typealias AccountTokenWrite = @MainActor (String, String, @escaping OperationGuard,
        @escaping ReaderWriterDrainRuntime.Completion) -> Void
    struct BackendTokenTask {
        let resume: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }
    struct BackendTokenTransport {
        let endpoint: @MainActor () -> URL?
        let now: @MainActor () -> Date
        let makeTask: @MainActor (URLRequest, @escaping OperationGuard,
            @escaping ReaderWriterDrainRuntime.Completion) throws -> BackendTokenTask
    }
    enum TokenOwner: Equatable, Sendable { case guest, account(String) }
    enum Diagnostic: Equatable {
        case permissionFailed, tokenSaveFailed, tokenEncodeFailed, tokenSendFailed, tokenFetchFailed
        case topicFailed(String, Bool), topicSucceeded(String, Bool)
    }
    struct Effects {
        let resolveOwner: @MainActor () -> TokenOwner
        let authorizationStatus: @MainActor (@escaping OperationGuard) async -> UNAuthorizationStatus
        let requestAuthorization: @MainActor (@escaping OperationGuard) async throws -> Bool
        let register: @MainActor (@escaping OperationGuard) async -> Void
        let fetchToken: @MainActor (@escaping OperationGuard) async throws -> String?
        let setTopic: @MainActor (String, Bool, @escaping OperationGuard, @escaping Completion) -> Void
        let saveAccountToken: @MainActor (String, String, @escaping OperationGuard, @escaping Completion) -> Void
        let sendBackendToken: @MainActor (String, TokenOwner, @escaping OperationGuard, @escaping Completion) -> Void
        let loadSettings: @MainActor (@escaping OperationGuard) -> (NotificationPreferences, [String])
        let persistSettings: @MainActor (NotificationPreferences, [String], @escaping OperationGuard) -> Void
        let loadCategoryIDs: @MainActor (@escaping OperationGuard) -> [String]
        let persistCategoryIDs: @MainActor ([String], @escaping OperationGuard) -> Void
        let loadToken: @MainActor (@escaping OperationGuard) -> String?
        let persistToken: @MainActor (String, @escaping OperationGuard) -> Void
        let diagnostic: @MainActor (Diagnostic, @escaping OperationGuard) -> Void
    }

    private struct State {
        var isAuthorized = false
        var authorizationStatusDescription = "Ukendt"
        var fcmToken: String?
        var lastPushSyncSummary = "Ikke synkroniseret endnu"
        var subscribedTopicsDescription = "—"
        var lastPushSyncedAt: Date?
        var isResyncingPush = false
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private var state = State()
    private var publicationID = UUID()
    private var activationID: UUID?
    private var tokenRevision = UUID()
    private var pushResyncID: UUID?
    private let effects: Effects
    var isAuthorized: Bool { state.isAuthorized }
    var authorizationStatusDescription: String { state.authorizationStatusDescription }
    // AppDelegate's explicit token callback remains source compatible. Internal work uses guarded publication.
    var fcmToken: String? {
        get { state.fcmToken }
        set { publish(stillCurrent: { true }) { self.tokenRevision = UUID(); $0.fcmToken = newValue } }
    }
    var lastPushSyncSummary: String { state.lastPushSyncSummary }
    var subscribedTopicsDescription: String { state.subscribedTopicsDescription }
    var lastPushSyncedAt: Date? { state.lastPushSyncedAt }
    var isResyncingPush: Bool { state.isResyncingPush }
    static let shared = NotificationService()

    // Constructing either service does not touch Firebase, APNs, defaults or analytics.
    private override init() { effects = Self.liveEffects(); super.init() }
    init(effects: Effects) { self.effects = effects; super.init() }

    @MainActor private final class Permission {
        let source: OperationGuard
        var denied = false
        init(_ source: @escaping OperationGuard) { self.source = source }
        func check() -> Bool {
            guard !denied else { return false }
            let allowed = source()
            if !allowed { denied = true }
            return allowed && !denied
        }
    }
    private func latched(_ source: @escaping OperationGuard) -> OperationGuard {
        let permission = Permission(source)
        return { permission.check() }
    }
    private func beginActivation(_ source: @escaping OperationGuard) -> OperationGuard {
        let id = UUID()
        activationID = id // Reserve before invoking an injected permission/identity getter.
        return latched { [weak self] in
            guard let self, self.activationID == id, source() else { return false }
            return self.activationID == id
        }
    }
    @discardableResult
    private func publish(stillCurrent: @escaping OperationGuard, _ update: (inout State) -> Void) -> Bool {
        let id = UUID()
        publicationID = id
        guard stillCurrent(), publicationID == id else { return false }
        objectWillChange.send()
        guard stillCurrent(), publicationID == id else { return false }
        update(&state)
        return true
    }
    private func summary(_ text: String, _ stillCurrent: @escaping OperationGuard) {
        publish(stillCurrent: stillCurrent) { $0.lastPushSyncSummary = text }
    }
    private func diagnose(_ diagnostic: Diagnostic, _ stillCurrent: @escaping OperationGuard) {
        guard stillCurrent() else { return }
        effects.diagnostic(diagnostic, stillCurrent)
    }

    // MARK: - Authorization
    func refreshAuthorizationStatus() {
        let current = latched { true }
        Task { await refreshAuthorizationStatusFromSettings(stillCurrent: current) }
    }
    @discardableResult
    private func refreshAuthorizationStatusFromSettings(stillCurrent: @escaping OperationGuard) async -> Bool {
        guard stillCurrent(), !Task.isCancelled else { return false }
        let status = await effects.authorizationStatus(stillCurrent)
        guard stillCurrent(), !Task.isCancelled else { return false }
        let allowed = status == .authorized || status == .provisional
        let accepted = publish(stillCurrent: stillCurrent) {
            $0.isAuthorized = allowed
            $0.authorizationStatusDescription = Self.describe(status)
        }
        return accepted && stillCurrent() && allowed
    }
    func requestAuthorization(stillCurrent: @escaping OperationGuard = { true }) async -> Bool {
        let current = latched(stillCurrent)
        guard current(), await requestNotificationPermission(stillCurrent: current), current() else { return false }
        await registerForRemoteNotifications(stillCurrent: current)
        return current() && !Task.isCancelled
    }
    private func requestNotificationPermission(stillCurrent: @escaping OperationGuard) async -> Bool {
        guard stillCurrent(), !Task.isCancelled else { return false }
        do {
            let granted = try await effects.requestAuthorization(stillCurrent)
            guard stillCurrent(), !Task.isCancelled else { return false }
            _ = await refreshAuthorizationStatusFromSettings(stillCurrent: stillCurrent)
            guard stillCurrent(), !Task.isCancelled else { return false }
            if !granted { summary("Notifikationer er slået fra iOS-indstillinger.", stillCurrent) }
            return granted && stillCurrent()
        } catch {
            guard stillCurrent(), !Task.isCancelled else { return false }
            diagnose(.permissionFailed, stillCurrent)
            summary("Kunne ikke anmode om tilladelse.", stillCurrent)
            return false
        }
    }
    func activateArticlePushNotifications(preferences: NotificationPreferences, selectedCategoryIds: [String],
        allCategoryIds: [String], owner: TokenOwner? = nil, stillCurrent: @escaping OperationGuard = { true }) async {
        let current = beginActivation(stillCurrent)
        guard current(), !Task.isCancelled else { return }
        persistArticleNotificationSettings(preferences: preferences, selectedCategoryIds: selectedCategoryIds, stillCurrent: current)
        guard current() else { return }
        let enabled = pushNotificationsEnabled(preferences: preferences, selectedCategoryIds: selectedCategoryIds)
        if !enabled {
            updateArticleCategorySubscriptions(preferences: preferences, selectedCategoryIds: selectedCategoryIds,
                allCategoryIds: allCategoryIds, stillCurrent: current)
            summary("Notifikationer er slået fra.", current)
            return
        }
        let originalOwner = owner ?? effects.resolveOwner()
        guard current() else { return }
        let authorized = await refreshAuthorizationStatusFromSettings(stillCurrent: current)
        guard current(), !Task.isCancelled else { return }
        if !authorized { guard await requestAuthorization(stillCurrent: current), current() else { return } }
        await registerForRemoteNotifications(stillCurrent: current)
        guard current(), !Task.isCancelled else { return }
        restoreToken(stillCurrent: current)
        guard current() else { return }
        if fcmToken == nil { await refreshFCMToken(stillCurrent: current) }
        guard current(), !Task.isCancelled else { return }
        updateArticleCategorySubscriptions(preferences: preferences, selectedCategoryIds: selectedCategoryIds,
            allCategoryIds: allCategoryIds, stillCurrent: current)
        guard current() else { return }
        if fcmToken == nil { summary("Push aktiveret. Afventer FCM-token — tryk Synkroniser push igen om et øjeblik.", current) }
        else { updateFCMTokenOnServer(fcmToken, owner: originalOwner, stillCurrent: current) }
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Tilladt"
        case .denied: return "Afslået"
        case .notDetermined: return "Ikke valgt endnu"
        case .provisional: return "Foreløbig tilladelse"
        case .ephemeral: return "Midlertidig tilladelse"
        @unknown default: return "Ukendt"
        }
    }
    
    // MARK: - First Launch Onboarding
    
    /// v2 adds topic selection before the system notification prompt.
    private static let onboardingCompletedKey = "notification_onboarding_completed_v2"
    
    func shouldPresentOnboarding() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) else {
            return false
        }
        
        let settings = await currentNotificationSettings()
        return settings.authorizationStatus == .notDetermined
    }
    
    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        // Keep legacy key in sync so older builds don't re-prompt.
        UserDefaults.standard.set(true, forKey: "notification_onboarding_completed_v1")
    }
    
    func completeOnboarding(
        allowNotifications: Bool,
        selectedCategoryIds: [String],
        allCategoryIds: [String]
    ) async {
        markOnboardingCompleted()
        
        let choices = NotificationOnboardingPolicy.choices(
            allowNotifications: allowNotifications,
            selectedCategoryIds: selectedCategoryIds
        )
        
        await activateArticlePushNotifications(
            preferences: choices.preferences,
            selectedCategoryIds: choices.selectedCategoryIds,
            allCategoryIds: allCategoryIds
        )
    }
    
    private func currentNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
    
    private func registerForRemoteNotifications(stillCurrent: @escaping OperationGuard) async {
        guard stillCurrent(), !Task.isCancelled else { return }
        await effects.register(stillCurrent)
    }

    // MARK: - FCM Token Management
    /// Accept one delegate token for its original owner. A token revision, rather than
    /// token-string equality, owns every queued topic operation and physical callback.
    /// Guest callbacks retain local caching/topic behavior without account/backend registration.
    func acceptRegistrationToken(_ token: String, owner: TokenOwner, registerAccountToken: Bool, stillCurrent: @escaping OperationGuard) {
        let previousRevision = tokenRevision
        let original = latched(stillCurrent)
        let beforePublication = latched { [weak self] in
            guard let self, original() else { return false }
            return self.tokenRevision == previousRevision
        }
        guard beforePublication() else { return }
        let acceptedRevision = UUID()
        guard publish(stillCurrent: beforePublication, {
            self.tokenRevision = acceptedRevision
            $0.fcmToken = token
        }) else { return }
        let current = latched { [weak self] in
            guard let self, original() else { return false }
            return self.tokenRevision == acceptedRevision
        }
        guard current() else { return }
        effects.persistToken(token, current)
        guard current() else { return }
        syncPersistedArticleNotificationSubscriptions(stillCurrent: current)
        guard current() else { return }
        if registerAccountToken, case .account = owner {
            updateFCMTokenOnServer(token, owner: owner, stillCurrent: current)
        }
    }

    func updateFCMTokenOnServer(_ token: String?, expectedUserID: String? = nil,
        stillCurrent: @escaping OperationGuard = { true }) {
        let current = latched(stillCurrent)
        guard current(), let token else { return }
        let owner = expectedUserID.map(TokenOwner.account) ?? effects.resolveOwner()
        guard current() else { return }
        updateFCMTokenOnServer(token, owner: owner, stillCurrent: current)
    }
    private func updateFCMTokenOnServer(_ token: String?, owner: TokenOwner, stillCurrent: @escaping OperationGuard) {
        guard stillCurrent(), let token else { return }
        if case .account(let uid) = owner {
            guard !uid.isEmpty, !uid.contains("/"), stillCurrent() else { return }
            effects.saveAccountToken(token, uid, stillCurrent) { [weak self] error in
                guard stillCurrent() else { return }
                if error != nil { self?.diagnose(.tokenSaveFailed, stillCurrent) }
            }
        }
        guard stillCurrent() else { return }
        effects.sendBackendToken(token, owner, stillCurrent) { [weak self] error in
            guard stillCurrent() else { return }
            if error != nil { self?.diagnose(.tokenSendFailed, stillCurrent) }
        }
    }

    /// Shared by the live effect and fully local tests. Capture the original
    /// account generation before scheduling the callback API's async bridge.
    /// Only the physical SDK callback releases the runtime's write slot.
    @discardableResult
    static func saveAccountToken(_ token: String, userID: String,
        stillCurrent: @escaping OperationGuard, runtime: ReaderWriterDrainRuntime,
        write: @escaping AccountTokenWrite, completion: @escaping Completion) -> Task<Void, Never>? {
        guard let captured = runtime.captureWrite(expectedUserID: userID, stillCurrent: stillCurrent,
            start: { current, returned in
                guard current() else { returned(CancellationError()); return }
                write(token, userID, current, returned)
            }) else { return nil }
        return Task { @MainActor in
            do {
                try await captured()
                guard !Task.isCancelled, captured.isCurrent() else { return }
                completion(nil)
            } catch {
                guard !Task.isCancelled, captured.isCurrent() else { return }
                completion(error)
            }
        }
    }

    @MainActor private final class AccountTokenClientLifetime {
        private let client: Firestore
        init(_ client: Firestore) { self.client = client }
    }

    private static func writeAccountToken(_ token: String, userID: String,
        stillCurrent: @escaping OperationGuard,
        completion: @escaping ReaderWriterDrainRuntime.Completion) {
        guard stillCurrent() else { completion(CancellationError()); return }
        let db = Firestore.firestore()
        guard stillCurrent() else { completion(CancellationError()); return }
        let users = db.collection("users")
        guard stillCurrent() else { completion(CancellationError()); return }
        let reference = users.document(userID)
        let lifetime = AccountTokenClientLifetime(db)
        guard stillCurrent() else { completion(CancellationError()); return }
        reference.updateData(["fcmToken": token, "lastTokenUpdate": Date()]) { error in
            withExtendedLifetime(lifetime) { completion(error) }
        }
    }

    /// The optional runtime is required for an account and is never replaced
    /// by a shared fallback. Explicit guests retain their anonymous HTTP route.
    @discardableResult
    static func sendBackendToken(_ token: String, owner: TokenOwner,
        stillCurrent: @escaping OperationGuard, runtime: ReaderWriterDrainRuntime?,
        transport: BackendTokenTransport, completion: @escaping Completion) -> Task<Void, Never>? {
        var preparedRequest: URLRequest?
        let operation: @MainActor () async throws -> Void
        let feedback: OperationGuard
        switch owner {
        case .account(let uid):
            // This must precede endpoint/date hooks and the async bridge.
            guard let runtime,
                  let captured = runtime.captureWrite(expectedUserID: uid, stillCurrent: stillCurrent,
                    start: { admitted, returned in
                        guard let request = preparedRequest else { returned(CancellationError()); return }
                        Self.startBackendTask(request, stillCurrent: admitted, transport: transport, completion: returned)
                    }) else { return nil }
            operation = { try await captured() }
            feedback = { captured.isCurrent() }
        case .guest:
            let permission = Permission(stillCurrent)
            feedback = { permission.check() }
            operation = {
                guard feedback(), !Task.isCancelled, let request = preparedRequest else { throw CancellationError() }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Self.startBackendTask(request, stillCurrent: feedback, transport: transport) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
            }
        }

        do {
            guard feedback() else { return nil }
            let endpoint = transport.endpoint()
            guard feedback() else { return nil }
            // A missing configured endpoint remains a synchronous no-op: no
            // write registration, URLSession, suspended task or async bridge.
            guard let endpoint else { completion(nil); return nil }
            let date = transport.now()
            guard feedback() else { return nil }
            let uid: String
            switch owner { case .guest: uid = "anonymous"; case .account(let original): uid = original }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 30; request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("AproposMagazine-iOS/1.0", forHTTPHeaderField: "User-Agent")
            let payload: [String: Any] = ["fcmToken": token, "userId": uid, "platform": "ios", "timestamp": date.timeIntervalSince1970]
            do { request.httpBody = try JSONSerialization.data(withJSONObject: payload) }
            catch { throw BackendTokenEncodingFailure(underlying: error) }
            guard feedback() else { return nil }
            preparedRequest = request
        } catch {
            guard feedback() else { return nil }
            completion(error)
            return nil
        }
        return Task { @MainActor in
            do {
                try await operation()
                guard !Task.isCancelled, feedback() else { return }
                completion(nil)
            } catch {
                guard !Task.isCancelled, feedback() else { return }
                completion(error)
            }
        }
    }

    private struct BackendTokenEncodingFailure: Error { let underlying: Error }
    @MainActor private final class BackendTaskLifetime { var task: BackendTokenTask? }

    /// Owns the first physical callback, including a cancellation callback from
    /// a never-started task. A premature injected callback cannot claim success.
    private final class BackendReply: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        private var finished = false
        private let completion: ReaderWriterDrainRuntime.Completion
        init(_ completion: @escaping ReaderWriterDrainRuntime.Completion) { self.completion = completion }
        func begin() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !started, !finished else { return false }
            started = true
            return true
        }
        func receive(_ error: Error?) { finish(error, requiresStart: true) }
        func reject(_ error: Error) { finish(error, requiresStart: false) }
        private func finish(_ error: Error?, requiresStart: Bool) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let result = !requiresStart || started ? error : CancellationError()
            lock.unlock()
            completion(result)
        }
    }

    private static func startBackendTask(_ request: URLRequest,
        stillCurrent: @escaping OperationGuard, transport: BackendTokenTransport,
        completion: @escaping ReaderWriterDrainRuntime.Completion) {
        let held = BackendTaskLifetime()
        let reply = BackendReply { error in
            Task { @MainActor in
                // The resumed task stays retained through its real callback,
                // even when the caller is cancelled or its account is replaced.
                held.task = nil
                completion(error)
            }
        }
        guard stillCurrent(), !Task.isCancelled else { reply.reject(CancellationError()); return }
        do {
            let task = try transport.makeTask(request, stillCurrent, { reply.receive($0) })
            held.task = task
            guard stillCurrent(), !Task.isCancelled, reply.begin() else {
                task.cancel()
                reply.reject(CancellationError())
                return
            }
            task.resume()
        } catch { reply.reject(error) }
    }

    // MARK: - Topic Subscriptions
    
    private enum StorageKey {
        static let preferences = "article_notification_preferences_v1"
        static let categoryIds = "article_notification_category_ids_v1"
        static let allCategoryIds = "article_notification_all_category_ids_v1"
        static let podcastPreferenceMigrated = "notification_podcast_pref_migrated_v1"
    }

    func persistAllCategoryIds(_ ids: [String], stillCurrent: @escaping OperationGuard = { true }) {
        let current = latched(stillCurrent)
        guard current() else { return }
        effects.persistCategoryIDs(ids, current)
    }
    func loadPersistedAllCategoryIds(stillCurrent: @escaping OperationGuard = { true }) -> [String] {
        let current = latched(stillCurrent)
        guard current() else { return [] }
        let ids = effects.loadCategoryIDs(current)
        return current() ? ids : []
    }

    func expectedActiveTopics(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> [String] {
        var topics: [String] = []
        if preferences.newPodcasts {
            topics.append("new_podcasts")
        }
        if articleNotificationsEnabled(preferences: preferences, selectedCategoryIds: selectedCategoryIds) {
            if preferences.newArticles && selectedCategoryIds.isEmpty {
                topics.append("new_articles")
            }
            for categoryId in selectedCategoryIds {
                topics.append(topicIdentifier(prefix: "category", rawValue: categoryId))
            }
        }
        if preferences.festivalReminders { topics.append("festival_reminders") }
        if preferences.breakingNews { topics.append("breaking_news") }
        if preferences.weeklyDigest { topics.append("weekly_digest") }
        return topics
    }

    func refreshPushDiagnostics(
        preferences: NotificationPreferences? = nil,
        selectedCategoryIds: [String]? = nil,
        stillCurrent: @escaping OperationGuard = { true }
    ) {
        guard stillCurrent() else { return }
        let (resolvedPreferences, resolvedCategoryIds) = if let preferences, let selectedCategoryIds {
            (preferences, selectedCategoryIds)
        } else {
            loadPersistedArticleNotificationSettings(stillCurrent: stillCurrent)
        }

        let topics = expectedActiveTopics(
            preferences: resolvedPreferences,
            selectedCategoryIds: resolvedCategoryIds
        )
        guard stillCurrent() else { return }
        publish(stillCurrent: stillCurrent) { $0.subscribedTopicsDescription = topics.isEmpty ? "Ingen emner" : topics.joined(separator: ", ") }
    }
    
    func articleNotificationsEnabled(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> Bool {
        if !selectedCategoryIds.isEmpty {
            return true
        }
        return preferences.newArticles
    }

    func pushNotificationsEnabled(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> Bool {
        articleNotificationsEnabled(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        ) || preferences.newPodcasts
    }
    
    func persistArticleNotificationSettings(preferences: NotificationPreferences, selectedCategoryIds: [String],
        stillCurrent: @escaping OperationGuard = { true }) {
        let current = latched(stillCurrent)
        guard current() else { return }
        effects.persistSettings(preferences, selectedCategoryIds, current)
    }
    func loadPersistedArticleNotificationSettings(stillCurrent: @escaping OperationGuard = { true }) -> (NotificationPreferences, [String]) {
        let current = latched(stillCurrent)
        guard current() else { return (NotificationPreferences(), []) }
        let settings = effects.loadSettings(current)
        return current() ? settings : (NotificationPreferences(), [])
    }
    func syncPersistedArticleNotificationSubscriptions(allCategoryIds: [String] = [], stillCurrent: @escaping OperationGuard = { true }) {
        let current = latched(stillCurrent)
        guard current() else { return }
        Task {
            guard current(), !Task.isCancelled else { return }
            await synchronizePersistedArticleNotificationSubscriptions(allCategoryIds: allCategoryIds, stillCurrent: current)
        }
    }
    private func synchronizePersistedArticleNotificationSubscriptions(allCategoryIds: [String], stillCurrent: @escaping OperationGuard) async {
        guard stillCurrent(), !Task.isCancelled else { return }
        guard await refreshAuthorizationStatusFromSettings(stillCurrent: stillCurrent) else {
            summary("Push kræver tilladelse iOS-indstillinger.", stillCurrent)
            refreshPushDiagnostics(stillCurrent: stillCurrent)
            return
        }
        guard stillCurrent(), !Task.isCancelled else { return }
        let resolvedCategoryIds = allCategoryIds.isEmpty ? loadPersistedAllCategoryIds(stillCurrent: stillCurrent) : allCategoryIds
        if !allCategoryIds.isEmpty { persistAllCategoryIds(allCategoryIds, stillCurrent: stillCurrent) }
        guard stillCurrent() else { return }
        let (preferences, categoryIds) = loadPersistedArticleNotificationSettings(stillCurrent: stillCurrent)
        updateArticleCategorySubscriptions(preferences: preferences, selectedCategoryIds: categoryIds,
            allCategoryIds: resolvedCategoryIds, stillCurrent: stillCurrent)
        toggleTopic(preferences.festivalReminders, topic: "festival_reminders", stillCurrent: stillCurrent)
        toggleTopic(preferences.breakingNews, topic: "breaking_news", stillCurrent: stillCurrent)
        toggleTopic(preferences.weeklyDigest, topic: "weekly_digest", stillCurrent: stillCurrent)
        publish(stillCurrent: stillCurrent) { $0.lastPushSyncedAt = Date() }
        refreshPushDiagnostics(preferences: preferences, selectedCategoryIds: categoryIds, stillCurrent: stillCurrent)
    }
    func resyncPushSubscriptions(allCategoryIds: [String] = [], stillCurrent: @escaping OperationGuard = { true }) async {
        let current = beginActivation(stillCurrent)
        guard current(), !Task.isCancelled else { return }
        let operation = UUID()
        pushResyncID = operation
        defer {
            if pushResyncID == operation {
                // Only retire this UI operation; do not update a replacement operation.
                publish(stillCurrent: { self.pushResyncID == operation }) {
                    self.pushResyncID = nil
                    $0.isResyncingPush = false
                }
            }
        }
        guard publish(stillCurrent: current, { $0.isResyncingPush = true }), current() else { return }
        let owner = effects.resolveOwner()
        guard current() else { return }
        guard await refreshAuthorizationStatusFromSettings(stillCurrent: current) else {
            summary("Slå notifikationer til under iOS-indstillinger → Apropos Magazine.", current)
            refreshPushDiagnostics(stillCurrent: current)
            return
        }
        guard current(), !Task.isCancelled else { return }
        if !allCategoryIds.isEmpty { persistAllCategoryIds(allCategoryIds, stillCurrent: current) }
        await registerForRemoteNotifications(stillCurrent: current)
        guard current(), !Task.isCancelled else { return }
        restoreToken(stillCurrent: current)
        guard current() else { return }
        if fcmToken == nil { await refreshFCMToken(stillCurrent: current) }
        guard current(), !Task.isCancelled else { return }
        await synchronizePersistedArticleNotificationSubscriptions(allCategoryIds: allCategoryIds, stillCurrent: current)
        guard current(), !Task.isCancelled else { return }
        if fcmToken == nil { summary("Tilmelding sendt. Afventer FCM-token — prøv igen om et øjeblik.", current) }
        else { updateFCMTokenOnServer(fcmToken, owner: owner, stillCurrent: current) }
    }
    private func restoreToken(stillCurrent: @escaping OperationGuard) {
        guard stillCurrent(), fcmToken == nil else { return }
        let revision = tokenRevision
        let token = effects.loadToken(stillCurrent)
        guard stillCurrent(), tokenRevision == revision, let token else { return }
        publish(stillCurrent: { stillCurrent() && self.tokenRevision == revision }) {
            self.tokenRevision = UUID()
            $0.fcmToken = token
        }
    }
    private func refreshFCMToken(stillCurrent: @escaping OperationGuard) async {
        guard stillCurrent(), !Task.isCancelled else { return }
        let revision = tokenRevision
        do {
            let token = try await effects.fetchToken(stillCurrent)
            guard stillCurrent(), !Task.isCancelled, tokenRevision == revision, let token else { return }
            let accepted = publish(stillCurrent: { stillCurrent() && self.tokenRevision == revision }) {
                self.tokenRevision = UUID()
                $0.fcmToken = token
            }
            guard accepted, stillCurrent(), fcmToken == token else { return }
            effects.persistToken(token, stillCurrent)
        } catch {
            guard stillCurrent(), !Task.isCancelled, tokenRevision == revision else { return }
            diagnose(.tokenFetchFailed, stillCurrent)
        }
    }
    func bootstrapPushNotifications(allCategoryIds: [String] = [], stillCurrent: @escaping OperationGuard = { true }) async {
        // The guarded loader already supplies/migrates the profile fallback used by resync.
        // No defaults/profile work occurs at construction or after the original permission is denied.
        await resyncPushSubscriptions(allCategoryIds: allCategoryIds, stillCurrent: stillCurrent)
    }

    func subscribeToTopics(for user: UserProfile, stillCurrent: @escaping OperationGuard = { true }) {
        guard stillCurrent() else { return }
        let (_, categories) = loadPersistedArticleNotificationSettings(stillCurrent: stillCurrent)
        persistArticleNotificationSettings(preferences: user.notificationPreferences, selectedCategoryIds: categories, stillCurrent: stillCurrent)
        syncArticleTopicSubscriptions(preferences: user.notificationPreferences, selectedCategoryIds: categories, stillCurrent: stillCurrent)
        toggleTopic(user.notificationPreferences.festivalReminders, topic: "festival_reminders", stillCurrent: stillCurrent)
        toggleTopic(user.notificationPreferences.breakingNews, topic: "breaking_news", stillCurrent: stillCurrent)
        toggleTopic(user.notificationPreferences.weeklyDigest, topic: "weekly_digest", stillCurrent: stillCurrent)
    }
    func unsubscribeFromTopics(for user: UserProfile, stillCurrent: @escaping OperationGuard = { true }) {
        for topic in ["all_users", "new_articles", "new_podcasts"] {
            unsubscribeFromTopic(topic, stillCurrent: stillCurrent)
        }
        for id in user.favoriteCategories { unsubscribeFromTopic(topicIdentifier(prefix: "category", rawValue: id), stillCurrent: stillCurrent) }
        for id in user.favoriteAuthors { unsubscribeFromTopic(topicIdentifier(prefix: "author", rawValue: id), stillCurrent: stillCurrent) }
        for topic in ["festival_reminders", "breaking_news", "weekly_digest"] { toggleTopic(false, topic: topic, stillCurrent: stillCurrent) }
    }
    func unsubscribeFromAllArticleTopics(allCategoryIds: [String] = [], stillCurrent: @escaping OperationGuard = { true }) {
        for topic in ["all_users", "new_articles"] { unsubscribeFromTopic(topic, stillCurrent: stillCurrent) }
        for id in allCategoryIds { unsubscribeFromTopic(topicIdentifier(prefix: "category", rawValue: id), stillCurrent: stillCurrent) }
        guard stillCurrent() else { return }
        let (_, storedCategories) = loadPersistedArticleNotificationSettings(stillCurrent: stillCurrent)
        for id in storedCategories {
            unsubscribeFromTopic(topicIdentifier(prefix: "category", rawValue: id), stillCurrent: stillCurrent)
        }
    }

    
    // MARK: - Local Notifications
    
    func scheduleLocalNotification(title: String, body: String, timeInterval: TimeInterval, threadIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Add thread identifier for grouping
        if let threadId = threadIdentifier {
            content.threadIdentifier = threadId
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                AppDiagnostics.recordOperational(.notificationScheduleFailed)
            }
        }
    }
    
    func scheduleFestivalReminder(festivalName: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Festival Reminder"
        content.body = "\(festivalName) starter snart!"
        content.sound = .default
        
        let reminderDate = date.addingTimeInterval(-24 * 60 * 60)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(identifier: "festival_\(festivalName)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                AppDiagnostics.recordOperational(.notificationFestivalScheduleFailed)
            }
        }
    }
    
    // MARK: - Notification Preferences
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        let (_, categoryIds) = loadPersistedArticleNotificationSettings()
        syncArticleTopicSubscriptions(
            preferences: preferences,
            selectedCategoryIds: categoryIds
        )
        toggleTopic(preferences.festivalReminders, topic: "festival_reminders")
        toggleTopic(preferences.breakingNews, topic: "breaking_news")
        toggleTopic(preferences.weeklyDigest, topic: "weekly_digest")
    }

    func updateArticleCategorySubscriptions(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String],
        allCategoryIds: [String], stillCurrent: @escaping OperationGuard = { true }
    ) {
        syncArticleTopicSubscriptions(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds,
            allCategoryIds: allCategoryIds, stillCurrent: stillCurrent
        )
    }
    
    private func toggleTopic(_ enabled: Bool, topic: String, stillCurrent: @escaping OperationGuard = { true }) {
        if enabled { subscribeToTopic(topic, stillCurrent: stillCurrent) }
        else { unsubscribeFromTopic(topic, stillCurrent: stillCurrent) }
    }
    private func subscribeToTopic(_ topic: String, stillCurrent: @escaping OperationGuard = { true }) {
        changeTopic(topic, enabled: true, stillCurrent: stillCurrent)
    }
    private func unsubscribeFromTopic(_ topic: String, stillCurrent: @escaping OperationGuard = { true }) {
        changeTopic(topic, enabled: false, stillCurrent: stillCurrent)
    }
    private func changeTopic(_ topic: String, enabled: Bool, stillCurrent: @escaping OperationGuard) {
        guard stillCurrent() else { return }
        var completed = false
        effects.setTopic(topic, enabled, stillCurrent) { [weak self] error in
            guard !completed else { return }
            completed = true
            guard let self, stillCurrent() else { return }
            if error != nil {
                self.diagnose(.topicFailed(topic, enabled), stillCurrent)
                if enabled { self.summary("Kunne ikke tilmelde \(topic).", stillCurrent) }
            } else { self.diagnose(.topicSucceeded(topic, enabled), stillCurrent) }
        }
    }
    private func syncArticleTopicSubscriptions(preferences: NotificationPreferences, selectedCategoryIds: [String],
        allCategoryIds: [String] = [], stillCurrent: @escaping OperationGuard = { true }) {
        guard stillCurrent() else { return }
        let selected = Set(selectedCategoryIds.map { topicIdentifier(prefix: "category", rawValue: $0) })
        let articles = articleNotificationsEnabled(preferences: preferences, selectedCategoryIds: selectedCategoryIds)
        toggleTopic(preferences.newPodcasts, topic: "new_podcasts", stillCurrent: stillCurrent)
        if articles {
            toggleTopic(preferences.newArticles && selected.isEmpty, topic: "new_articles", stillCurrent: stillCurrent)
            for topic in selected { subscribeToTopic(topic, stillCurrent: stillCurrent) }
            for id in allCategoryIds where !selectedCategoryIds.contains(id) {
                unsubscribeFromTopic(topicIdentifier(prefix: "category", rawValue: id), stillCurrent: stillCurrent)
            }
        } else { unsubscribeFromAllArticleTopics(allCategoryIds: allCategoryIds, stillCurrent: stillCurrent) }
        guard stillCurrent() else { return }
        summary(pushSyncSummary(preferences: preferences, selectedCategoryIds: selectedCategoryIds), stillCurrent)
        guard stillCurrent() else { return }
        refreshPushDiagnostics(preferences: preferences, selectedCategoryIds: selectedCategoryIds, stillCurrent: stillCurrent)
    }


    private func pushSyncSummary(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> String {
        let topics = expectedActiveTopics(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        guard !topics.isEmpty else {
            return "Notifikationer er slået fra."
        }
        return "Tilmeldt: \(topics.joined(separator: ", "))"
    }
    
    // MARK: - Article Notifications (Rich Notifications Support)
    
    /// Send a notification about a new article with thumbnail support
    /// The thumbnail will be added by NotificationServiceExtension if available
    func sendArticleNotification(article: Article, title: String? = nil, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title ?? "Ny artikel: \(article.name ?? "Ukendt")"
        content.body = body ?? article.intro ?? ""
        content.sound = .default
        content.categoryIdentifier = "NEW_ARTICLE"
        content.threadIdentifier = "new_articles" // Group all new article notifications
        
        // Add article data to userInfo for NotificationServiceExtension
        // The extension will download the thumbnail and add it as an attachment
        var userInfo: [String: Any] = [
            "type": "new_article",
            "article_id": article.id
        ]
        
        // Add mobile image URL first so rich notifications use the lightweight image when available.
        if let mobileImageURL = article.mobileImageURL {
            userInfo["thumbnail_url"] = mobileImageURL.absoluteString
        } else if let thumbnailURL = article.thumbURL {
            userInfo["thumbnail_url"] = thumbnailURL.absoluteString
        }
        
        // Add cover URL as fallback
        if let coverURL = article.coverURL {
            userInfo["cover_url"] = coverURL.absoluteString
        }
        
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "article_\(article.id)_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                AppDiagnostics.recordOperational(.notificationSendFailed)
            }
        }
    }
    
    // MARK: - Test Local Notification
    
    func sendTestLocalNotification(delay: TimeInterval = 2) {
        let content = UNMutableNotificationContent()
        content.title = "Apropos Magazine"
        content.body = "Lokal test — viser, at notifikationer er tilladt på denne enhed."
        content.sound = .default
        // A permission test must preserve the editorial unread badge.
        content.badge = nil
        content.threadIdentifier = "test_notifications"
        
        content.userInfo = ["type": "test"]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(
            identifier: "test_notification_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                AppDiagnostics.recordOperational(.notificationTestSendFailed)
            } else {
                AppDiagnostics.recordOperational(.notificationTestScheduled)
            }
        }
    }
    
    func sendTestLocalNotificationAfterAuthorization(delay: TimeInterval = 2) async {
        let authorized = await requestNotificationPermission(stillCurrent: { true })
        guard authorized else { return }
        sendTestLocalNotification(delay: delay)
    }

    // MARK: - Comprehensive Debug
    
    func debugNotificationSystem() {
        if UserManager.shared.currentUser != nil {
            Messaging.messaging().subscribe(toTopic: "new_articles") { error in
                if error != nil {
                    AppDiagnostics.recordOperational(.notificationSubscribeFailed)
                }
            }
            
            Messaging.messaging().subscribe(toTopic: "all_users") { error in
                if error != nil {
                    AppDiagnostics.recordOperational(.notificationSubscribeFailed)
                }
            }
        }
    }
    
    func forceSubscribeToNewArticles() {
        Messaging.messaging().subscribe(toTopic: "new_articles") { error in
            if error != nil {
                AppDiagnostics.recordOperational(.notificationSubscribeFailed)
                return
            }

            Task {
                let token = await MainActor.run { self.fcmToken }
                if let token {
                    await MainActor.run {
                        self.updateFCMTokenOnServer(token)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func topicIdentifier(prefix: String, rawValue: String) -> String {
        let sanitized = rawValue
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return "\(prefix)_\(sanitized)"
    }
    // All live references are created inside guarded effects, never by either initializer.
    private static func liveEffects() -> Effects {
        Effects(
            resolveOwner: { UserManager.shared.currentUser.map { .account($0.uid) } ?? .guest },
            authorizationStatus: { current in
                guard current() else { return .notDetermined }
                let center = UNUserNotificationCenter.current()
                guard current() else { return .notDetermined }
                return await withCheckedContinuation { continuation in
                    guard current() else { continuation.resume(returning: .notDetermined); return }
                    center.getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
                }
            },
            requestAuthorization: { current in
                guard current() else { throw CancellationError() }
                let center = UNUserNotificationCenter.current()
                guard current() else { throw CancellationError() }
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            },
            register: { current in
                guard current() else { return }
                let app = UIApplication.shared
                guard current() else { return }
                app.registerForRemoteNotifications()
            },
            fetchToken: { current in
                guard current() else { throw CancellationError() }
                let messaging = Messaging.messaging()
                guard current() else { throw CancellationError() }
                return try await withCheckedThrowingContinuation { continuation in
                    guard current() else { continuation.resume(throwing: CancellationError()); return }
                    messaging.token { token, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: token) }
                    }
                }
            },
            setTopic: { topic, enabled, current, completion in
                guard current() else { completion(CancellationError()); return }
                let messaging = Messaging.messaging()
                guard current() else { completion(CancellationError()); return }
                let callback: @Sendable (Error?) -> Void = { error in Task { @MainActor in completion(error) } }
                if enabled { messaging.subscribe(toTopic: topic, completion: callback) }
                else { messaging.unsubscribe(fromTopic: topic, completion: callback) }
            },
            saveAccountToken: { token, uid, current, completion in
                guard current() else { completion(CancellationError()); return }
                Self.saveAccountToken(token, userID: uid, stillCurrent: current,
                    runtime: .shared, write: Self.writeAccountToken, completion: completion)
            },
            sendBackendToken: { token, owner, current, completion in
                guard current() else { completion(CancellationError()); return }
                let runtime: ReaderWriterDrainRuntime?
                switch owner { case .account: runtime = .shared; case .guest: runtime = nil }
                Self.sendBackendToken(token, owner: owner, stillCurrent: current, runtime: runtime,
                    transport: .init(endpoint: { SecureConfig.shared.fcmBackendURL }, now: { Date() },
                        makeTask: { request, admitted, returned in
                            guard admitted() else { throw CancellationError() }
                            let session = URLSession.shared
                            guard admitted() else { throw CancellationError() }
                            let task = session.dataTask(with: request) { _, _, error in returned(error) }
                            return BackendTokenTask(resume: { task.resume() }, cancel: { task.cancel() })
                        }), completion: { error in
                            guard current() else { return }
                            if error is BackendTokenEncodingFailure {
                                AppDiagnostics.recordOperational(.notificationTokenEncodeFailed)
                            }
                            guard current() else { return }
                            completion(error)
                        })
            },
            loadSettings: { current in
                guard current() else { return (NotificationPreferences(), []) }
                let defaults = UserDefaults.standard
                guard current() else { return (NotificationPreferences(), []) }
                let storedData = defaults.data(forKey: StorageKey.preferences)
                var preferences: NotificationPreferences
                var missingProfileFallback = false
                if let data = storedData,
                   let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
                    preferences = decoded
                } else {
                    guard current() else { return (NotificationPreferences(), []) }
                    let user = UserManager.shared.currentUser
                    guard current() else { return (NotificationPreferences(), []) }
                    preferences = user?.notificationPreferences ?? NotificationPreferences()
                    missingProfileFallback = storedData == nil && user != nil
                }
                guard current() else { return (NotificationPreferences(), []) }
                let ids = defaults.stringArray(forKey: StorageKey.categoryIds) ?? []
                guard current() else { return (NotificationPreferences(), []) }
                let alreadyMigrated = defaults.bool(forKey: StorageKey.podcastPreferenceMigrated)
                if !alreadyMigrated {
                    preferences.newPodcasts = !ids.isEmpty || preferences.newArticles
                    guard current() else { return (NotificationPreferences(), []) }
                    defaults.set(true, forKey: StorageKey.podcastPreferenceMigrated)
                    guard current() else { return (NotificationPreferences(), []) }
                    if let data = try? JSONEncoder().encode(preferences), current() {
                        defaults.set(data, forKey: StorageKey.preferences)
                    }
                }
                // Preserve bootstrap's original missing-data profile fallback even after the
                // podcast migration already ran. A corrupt existing blob is not silently replaced.
                if alreadyMigrated && missingProfileFallback {
                    guard current() else { return (NotificationPreferences(), []) }
                    if let data = try? JSONEncoder().encode(preferences), current() {
                        defaults.set(data, forKey: StorageKey.preferences)
                    }
                }
                return (preferences, ids)
            },
            persistSettings: { preferences, ids, current in
                guard current() else { return }
                let defaults = UserDefaults.standard
                guard current() else { return }
                if let data = try? JSONEncoder().encode(preferences), current() { defaults.set(data, forKey: StorageKey.preferences) }
                guard current() else { return }
                defaults.set(ids, forKey: StorageKey.categoryIds)
            },
            loadCategoryIDs: { current in
                guard current() else { return [] }
                let defaults = UserDefaults.standard
                guard current() else { return [] }
                return defaults.stringArray(forKey: StorageKey.allCategoryIds) ?? []
            },
            persistCategoryIDs: { ids, current in
                guard current() else { return }
                let defaults = UserDefaults.standard
                guard current() else { return }
                defaults.set(ids, forKey: StorageKey.allCategoryIds)
            },
            loadToken: { current in
                guard current() else { return nil }
                let defaults = UserDefaults.standard
                guard current() else { return nil }
                return defaults.string(forKey: "FCMRegistrationToken")
            },
            persistToken: { token, current in
                guard current() else { return }
                let defaults = UserDefaults.standard
                guard current() else { return }
                defaults.set(token, forKey: "FCMRegistrationToken")
            },
            diagnostic: { diagnostic, current in
                guard current() else { return }
                switch diagnostic {
                case .permissionFailed: AppDiagnostics.recordOperational(.notificationPermissionFailed)
                case .tokenSaveFailed: AppDiagnostics.recordOperational(.notificationTokenSaveFailed)
                case .tokenEncodeFailed: AppDiagnostics.recordOperational(.notificationTokenEncodeFailed)
                case .tokenSendFailed: AppDiagnostics.recordOperational(.notificationTokenSendFailed)
                case .tokenFetchFailed: AppDiagnostics.recordOperational(.fcmFetchFailed)
                case .topicFailed(_, let enabled):
                    if enabled { AppDiagnostics.recordOperational(.notificationSubscribeFailed) }
                    else { AppDiagnostics.recordOperational(.notificationUnsubscribeFailed) }
                case .topicSucceeded(let topic, let enabled):
                    if enabled { AppDiagnostics.breadcrumb("push_subscribed_\(topic)") }
                }
            }
        )
    }

}
