import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
final class UserManager: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    static let shared = UserManager()
    let state: UserProfileState
    var profileSnapshot: UserProfileState.Snapshot { state.snapshot }
    var profileChanges: AnyPublisher<UserProfileState.Snapshot, Never> { state.changes }
    var currentUser: UserProfile? { state.snapshot.profile }
    var isLoading: Bool { state.snapshot.isLoading }
    var errorMessage: String? { state.snapshot.errorMessage }
    private lazy var db = Firestore.firestore()
    private lazy var coordinator = makeCoordinator()
    private var observation: AnyCancellable?
    private var prepared = false
    private let disabled: Bool
    private let injectedEffects: UserProfileCoordinator.Effects?
    private let injectedProfileSeed: (@MainActor () -> UserProfile?)?
    private let injectedBookmarkEffects: BookmarkEffects?
    private let injectedProfileWriteEffects: ProfileWriteEffects?
    private var profileEntry = UUID()
    private var notificationChoiceID = UUID()
    typealias Guard = UserProfileCoordinator.Guard

    /// No SDK, timer, auth listener or service singleton is constructed here.
    private init() {
        state = UserProfileState()
        injectedEffects = nil; injectedProfileSeed = nil; injectedBookmarkEffects = nil
        injectedProfileWriteEffects = nil
        disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
        observation = state.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    /// Complete local composition: no partially injected path can fall back to
    /// live identity, Firestore, topics or messaging during a test.
    init(state: UserProfileState, effects: UserProfileCoordinator.Effects,
         currentProfileSeed: @escaping @MainActor () -> UserProfile?, bookmarkEffects: BookmarkEffects? = nil,
         profileWriteEffects: ProfileWriteEffects? = nil) {
        self.state = state; injectedEffects = effects; injectedProfileSeed = currentProfileSeed
        injectedBookmarkEffects = bookmarkEffects; injectedProfileWriteEffects = profileWriteEffects
        disabled = false
        observation = state.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    private func profileIdentity() -> UserProfileCoordinator.Identity {
        if let injectedEffects { return injectedEffects.identity() }
        return .init(actualUID: Auth.auth().currentUser?.uid, canonicalUID: AuthService.shared.session?.uid)
    }

    private func captureProfilePermission(parent: Guard? = nil) -> Guard? {
        guard prepared, !disabled else { return nil }
        let context = state.contextTicket()
        guard parent?() != false, state.isCurrent(context) else { return nil }
        let captured: Guard?
        if let injectedEffects { captured = injectedEffects.capturePermission() }
        else { captured = AuthService.shared.captureReaderWorkPermission() }
        guard let captured, state.isCurrent(context) else { return nil }
        var revoked = false
        let permission: Guard = { [weak self] in
            guard !revoked, let self, self.state.isCurrent(context) else { revoked = true; return false }
            guard parent?() != false, !revoked, captured(), !revoked,
                  self.state.isCurrent(context) else { revoked = true; return false }
            return true
        }
        return permission() ? permission : nil
    }

    private struct ProfileRequest {
        let context: UserProfileState.ContextTicket
        let revision: UInt64
        let permission: Guard
    }
    private func prepareProfileRequest(parent: Guard? = nil) -> ProfileRequest? {
        guard prepared, !disabled else { return nil }
        let entry = UUID(); profileEntry = entry
        let context = state.contextTicket(), revision = state.snapshot.revision
        guard let captured = captureProfilePermission(parent: parent), profileEntry == entry,
              state.isCurrent(context), state.snapshot.revision == revision else { return nil }
        let permission: Guard = { [weak self] in
            guard let self, self.profileEntry == entry, captured() else { return false }
            return self.profileEntry == entry && self.state.isCurrent(context)
        }
        guard permission() else { return nil }
        return .init(context: context, revision: revision, permission: permission)
    }
    private func enqueueProfileLoad(_ seed: UserProfile, request: ProfileRequest) {
        guard request.permission() else { return }
        let identity = profileIdentity()
        guard request.permission(), state.isCurrent(request.context), state.snapshot.revision == request.revision,
              identity.actualUID == seed.uid, identity.canonicalUID == seed.uid,
              request.context.userID == seed.uid else { return }
        coordinator.load(seed, stillCurrent: request.permission)
    }

    /// Canonical AuthService owns identity publication; no second auth listener.
    func startObservingSession() {
        guard !disabled, !prepared else { return }
        prepared = true; coordinator.start()
    }
    func changeAccountContext(userID: String?) {
        if state.snapshot.context != .confirmed(userID: userID) { profileEntry = UUID() }
        if disabled { _ = state.changeContext(to: .confirmed(userID: userID)); return }
        coordinator.changeAccountContext(userID: userID)
    }
    func suspendForAccountChange() {
        profileEntry = UUID()
        guard !disabled else { return }; coordinator.suspendForAccountChange()
    }
    @discardableResult func restoreAfterFailedSignOut() -> Bool {
        guard !disabled else { return false }; return coordinator.restoreAfterFailedSignOut()
    }
    func clearIfConfirmedGuest() {
        guard !disabled else { return }; coordinator.clearIfConfirmedGuest()
    }
    /// A fresh canonical observation owns fresh permission even for the same UID.
    /// An older in-flight load may already be revoked, so it cannot suppress this
    /// replacement. Coordinator tickets still bound callbacks and physical slots.
    func loadUserProfileIfNeeded(for user: User, stillCurrent: @escaping Guard) {
        loadUserProfileIfNeeded(UserProfile(firebaseUser: user), stillCurrent: stillCurrent)
    }
    func loadUserProfileIfNeeded(_ seed: UserProfile, stillCurrent: @escaping Guard) {
        guard !state.snapshot.loaded, let request = prepareProfileRequest(parent: stillCurrent),
              !state.snapshot.loaded else { return }
        enqueueProfileLoad(seed, request: request)
    }
    func loadUserProfile(for user: User, stillCurrent: @escaping Guard) {
        guard let request = prepareProfileRequest(parent: stillCurrent) else { return }
        enqueueProfileLoad(UserProfile(firebaseUser: user), request: request)
    }
    /// Shared value entry used by the native provider projection and local tests.
    func loadUserProfile(_ seed: UserProfile, stillCurrent: Guard? = nil) {
        guard let request = prepareProfileRequest(parent: stillCurrent) else { return }
        enqueueProfileLoad(seed, request: request)
    }
    func retryProfileLoad() {
        guard !state.snapshot.loaded, let request = prepareProfileRequest(),
              request.context.userID != nil else { return }
        let seed: UserProfile?
        if let injectedProfileSeed { seed = injectedProfileSeed() }
        else { seed = Auth.auth().currentUser.map { UserProfile(firebaseUser: $0) } }
        guard let seed, request.permission() else { return }
        enqueueProfileLoad(seed, request: request)
    }
    @discardableResult func saveUserProfile(_ profile: UserProfile, stillCurrent: Guard? = nil) -> UserProfileState.SaveTicket? {
        guard let request = prepareProfileRequest(parent: stillCurrent), request.permission(),
              state.snapshot.revision == request.revision else { return nil }
        return coordinator.save(profile, stillCurrent: request.permission)
    }
    /// The actual Settings event boundary: capture before Task and retain that
    /// choice through profile publication, OS authorization and push effects.
    /// A replacement choice invalidates the older one before either Task runs.
    func captureNotificationChoices(preferences: NotificationPreferences, categoryIDs: [String],
                                    allCategoryIDs: [String], context: UserProfileState.ContextTicket,
                                    service: NotificationService) -> (@MainActor () async -> Void)? {
        guard prepared, !disabled, state.isCurrent(context), context.context != .unresolved,
              context.userID == nil || state.snapshot.writeReady else { return nil }
        let choiceID = UUID(); notificationChoiceID = choiceID
        let revision = state.snapshot.revision, loadVersion = state.acceptedLoadVersion
        guard let captured = captureProfilePermission(), notificationChoiceID == choiceID,
              state.isCurrent(context), state.snapshot.revision == revision else { return nil }
        let cancellation = NotificationChoiceCancellation()
        var denied = false
        let original: Guard = { [weak self] in
            guard !denied, !cancellation.isCancelled, let self,
                  self.notificationChoiceID == choiceID, self.state.isCurrent(context),
                  captured(), !denied, !cancellation.isCancelled,
                  self.notificationChoiceID == choiceID, self.isCurrent(context),
                  captured(), !denied, !cancellation.isCancelled,
                  self.notificationChoiceID == choiceID, self.state.isCurrent(context),
                  self.state.acceptedLoadVersion == loadVersion else { denied = true; return false }
            return true
        }
        guard original(), state.snapshot.revision == revision else { return nil }
        let owner: NotificationService.TokenOwner = context.userID.map { .account($0) } ?? .guest
        var consumed = false
        return { [weak self, weak service] in
            guard !consumed else { return }
            consumed = true
            if Task.isCancelled { cancellation.cancel() }
            guard let self, let service, original() else { return }
            await withTaskCancellationHandler(operation: {
                guard original() else { return }
                var saveTicket: UserProfileState.SaveTicket?
                if var profile = self.currentUser {
                    guard profile.uid == context.userID else { return }
                    profile.notificationPreferences = preferences
                    guard let ticket = self.saveUserProfile(profile, stillCurrent: original), original() else { return }
                    saveTicket = ticket
                } else if context.userID != nil { return }
                let save = saveTicket
                var retired = false
                let admitted: Guard = { [weak self] in
                    guard !retired, let self, original(),
                          save.map({ self.isCurrent($0) }) ?? true,
                          original(), !retired else { retired = true; return false }
                    return true
                }
                guard admitted() else { return }
                service.persistAllCategoryIds(allCategoryIDs, stillCurrent: admitted)
                guard admitted() else { return }
                await service.activateArticlePushNotifications(preferences: preferences,
                    selectedCategoryIds: categoryIDs, allCategoryIds: allCategoryIDs,
                    owner: owner, stillCurrent: admitted)
                guard admitted() else { return }
                service.refreshPushDiagnostics(preferences: preferences,
                    selectedCategoryIds: categoryIDs, stillCurrent: admitted)
            }, onCancel: { cancellation.cancel() })
        }
    }

    func isCurrent(_ ticket: UserProfileState.SaveTicket) -> Bool {
        guard prepared, !disabled else { return false }; return owns(ticket)
    }
    func isCurrent(_ ticket: UserProfileState.ContextTicket) -> Bool {
        guard prepared, !disabled else { return false }
        let identity = profileIdentity()
        return identity.actualUID == ticket.userID && identity.canonicalUID == ticket.userID && state.isCurrent(ticket)
    }
    private func owns(_ ticket: UserProfileState.LoadTicket) -> Bool {
        let identity = profileIdentity()
        return identity.actualUID == ticket.userID && identity.canonicalUID == ticket.userID && state.isCurrent(ticket)
    }
    private func owns(_ ticket: UserProfileState.SaveTicket) -> Bool {
        let identity = profileIdentity()
        return identity.actualUID == ticket.userID && identity.canonicalUID == ticket.userID && state.isCurrent(ticket)
    }
    private enum Failure: Error { case stale }
    private func makeCoordinator() -> UserProfileCoordinator {
        UserProfileCoordinator(state: state, effects: .init(capturePermission: { [weak self] in
            self?.captureProfilePermission()
        }, identity: { [weak self] in self?.profileIdentity() ?? .init(actualUID: nil, canonicalUID: nil)
        }, read: { [weak self] seed, source, ticket, stillCurrent in
            guard let self else { throw Failure.stale }
            let original: Guard = { [weak self] in
                guard let self, stillCurrent(), self.owns(ticket), stillCurrent() else { return false }
                return self.state.isCurrent(ticket)
            }
            guard original() else { throw Failure.stale }
            if let injectedEffects = self.injectedEffects {
                let result = try await injectedEffects.read(seed, source, ticket, original)
                guard original() else { throw Failure.stale }
                return result
            }
            let client = self.db
            guard original() else { throw Failure.stale }
            let users = client.collection("users")
            guard original() else { throw Failure.stale }
            let reference = users.document(ticket.userID)
            guard original() else { throw Failure.stale }
            let document: DocumentSnapshot
            if source == .server { document = try await reference.getDocument(source: .server) }
            else { document = try await reference.getDocument() }
            guard original() else { throw Failure.stale }
            guard document.exists else { return .init(profile: nil, isFromCache: document.metadata.isFromCache) }
            let fields = (document.data() ?? [:]).mapValues(Self.convertTimestamps)
            let profile = try UserProfileDocumentCodec.decode(fields, userID: ticket.userID,
                fallbackCreatedAt: seed.createdAt, fallbackLastLoginAt: seed.lastLoginAt)
            guard original() else { throw Failure.stale }
            return .init(profile: profile, isFromCache: document.metadata.isFromCache)
        }, write: { [weak self] profile, ticket, stillCurrent in
            guard let self else { throw Failure.stale }
            let original: Guard = { [weak self] in
                guard let self, stillCurrent(), self.owns(ticket), stillCurrent() else { return false }
                return self.state.isCurrent(ticket)
            }
            guard original(), profile.uid == ticket.userID else { throw Failure.stale }
            if let injectedEffects = self.injectedEffects, self.injectedProfileWriteEffects == nil {
                // Existing complete local compositions keep their explicit
                // provider; omitting the new seam can never select a live SDK.
                try await injectedEffects.write(profile, ticket, original)
                guard original() else { throw Failure.stale }
                return
            }
            let data = try Self.fields(profile)
            guard original() else { throw Failure.stale }
            let effects = try self.profileWriteEffects()
            guard original() else { throw Failure.stale }
            // The runtime reserves admission before the merge adapter can
            // obtain its first SDK reference. Cancellation/account changes do
            // not free either physical slot before the real callback returns.
            try await effects.performWrite(ticket.userID, original) { stillAdmitted, completion in
                guard original(), stillAdmitted() else { completion(CancellationError()); return }
                effects.merge(ticket.userID, data, { original() && stillAdmitted() }, completion)
            }
            guard original() else { throw Failure.stale }
        }, subscribe: { [weak self] profile, stillCurrent in
            guard let self, stillCurrent() else { return }
            if let injectedEffects = self.injectedEffects { injectedEffects.subscribe(profile, stillCurrent); return }
            let service = NotificationService.shared
            guard stillCurrent() else { return }
            service.subscribeToTopics(for: profile, stillCurrent: stillCurrent)
        }, unsubscribe: { [weak self] profile, stillCurrent in
            guard let self, stillCurrent() else { return }
            if let injectedEffects = self.injectedEffects { injectedEffects.unsubscribe(profile, stillCurrent); return }
            let service = NotificationService.shared
            guard stillCurrent() else { return }
            service.unsubscribeFromTopics(for: profile, stillCurrent: stillCurrent)
        }, updateFCM: { [weak self] uid, stillCurrent in
            guard let self, stillCurrent() else { return }
            if let injectedEffects = self.injectedEffects { injectedEffects.updateFCM(uid, stillCurrent); return }
            let service = NotificationService.shared
            guard stillCurrent() else { return }
            service.updateFCMTokenOnServer(service.fcmToken, expectedUserID: uid, stillCurrent: stillCurrent)
        }))
    }
    /// Callback seam for the ordinary profile merge. Fixtures inject both
    /// runtime admission and the SDK boundary; production uses the same path.
    struct ProfileWriteEffects {
        let performWrite: @MainActor (String, @escaping Guard,
            @escaping ReaderWriterDrainRuntime.Start) async throws -> Void
        let merge: @MainActor (String, [String: Any], @escaping Guard,
            @escaping ReaderWriterDrainRuntime.Completion) -> Void
    }

    private func profileWriteEffects() throws -> ProfileWriteEffects {
        if let injectedProfileWriteEffects { return injectedProfileWriteEffects }
        guard injectedEffects == nil, !disabled else { throw Failure.stale }
        return .init(performWrite: { uid, current, start in
            guard current() else { throw CancellationError() }
            let runtime = ReaderWriterDrainRuntime.shared
            guard current() else { throw CancellationError() }
            try await runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
        }, merge: { [self] uid, fields, stillAdmitted, completion in
            guard stillAdmitted() else { completion(CancellationError()); return }
            let client = self.db
            guard stillAdmitted() else { completion(CancellationError()); return }
            let users = client.collection("users")
            guard stillAdmitted() else { completion(CancellationError()); return }
            let reference = users.document(uid)
            guard stillAdmitted() else { completion(CancellationError()); return }
            reference.setData(fields, merge: true, completion: completion)
        })
    }

    private static func convertTimestamps(_ value: Any) -> Any {
        if let value = value as? Timestamp { return value.dateValue() }
        if let value = value as? [String: Any] { return value.mapValues(convertTimestamps) }
        if let value = value as? [Any] { return value.map(convertTimestamps) }
        return value
    }
    private static func fields(_ profile: UserProfile) throws -> [String: Any] {
        let now = Date()
        var fields: [String: Any] = [
            "uid": profile.uid, "email": profile.email, "displayName": profile.displayName,
            "createdAt": Timestamp(date: profile.createdAt.timeIntervalSince1970 > 0 ? profile.createdAt : now),
            "lastLoginAt": Timestamp(date: profile.lastLoginAt.timeIntervalSince1970 > 0 ? profile.lastLoginAt : now),
            "favoriteCategories": profile.favoriteCategories, "favoriteAuthors": profile.favoriteAuthors,
            "readArticles": profile.readArticles, "readingProgress": profile.readingProgress,
            "notificationPreferences": try UserProfileDocumentCodec.encodePreferences(profile.notificationPreferences),
            "readingPreferences": try UserProfileDocumentCodec.encodePreferences(profile.readingPreferences)
        ]
        if let photo = profile.photoURL { fields["photoURL"] = photo }
        // FavoritesModel/outbox alone owns the bookmark compatibility field.
        return fields
    }
    func markArticleAsRead(_ articleID: String, expectedUserID: String) {
        guard Auth.auth().currentUser?.uid == expectedUserID, AuthService.shared.session?.uid == expectedUserID,
              state.snapshot.writeReady, var profile = currentUser, profile.uid == expectedUserID else { return }
        if !profile.readArticles.contains(articleID) { profile.readArticles.append(articleID); saveUserProfile(profile) }
    }

    /// The durable dispatch owns this compatibility mirror independently of
    /// local profile loading. updateData cannot create a bookmark-only profile.
    /// Cached legacy bookmark fields refresh on ordinary profile reload; they
    /// never replace FavoritesModel as visible membership authority.
    struct BookmarkEffects {
        let identity: @MainActor () -> FavoritesProfileMirror.Identity
        let performWrite: @MainActor (String, @escaping Guard,
            @escaping ReaderWriterDrainRuntime.Start) async throws -> Void
        let updateExisting: @MainActor (String, String, Bool, @escaping Guard,
            @escaping ReaderWriterDrainRuntime.Completion) -> Void
        let diagnostic: @MainActor (@escaping Guard) -> Void
    }

    private func bookmarkEffects() throws -> BookmarkEffects {
        if let injectedBookmarkEffects { return injectedBookmarkEffects }
        // A locally injected profile manager never falls through to live
        // bookmark services merely because its bookmark effects were omitted.
        guard injectedEffects == nil, !disabled else { throw FavoritesProfileMirror.Failure.stale }
        return .init(identity: {
            .init(actualUID: Auth.auth().currentUser?.uid, canonicalUID: AuthService.shared.session?.uid)
        }, performWrite: { uid, current, start in
            guard current() else { throw CancellationError() }
            let runtime = ReaderWriterDrainRuntime.shared
            guard current() else { throw CancellationError() }
            try await runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
        }, updateExisting: { [self] uid, articleID, saved, current, completion in
            guard current() else { completion(CancellationError()); return }
            let client = self.db
            guard current() else { completion(CancellationError()); return }
            let users = client.collection("users")
            guard current() else { completion(CancellationError()); return }
            let reference = users.document(uid)
            let operation = saved ? FieldValue.arrayUnion([articleID]) : FieldValue.arrayRemove([articleID])
            guard current() else { completion(CancellationError()); return }
            reference.updateData(["bookmarkedArticles": operation], completion: completion)
        }, diagnostic: { current in
            guard current() else { return }
            AppDiagnostics.recordOperational(.profileSaveFailed)
        })
    }

    func setBookmark(ticket: FavoritesModel.DispatchTicket, expectedUserID: String,
                     model: FavoritesModel, stillCurrent: @escaping Guard) async throws {
        guard stillCurrent(), !Task.isCancelled else { throw FavoritesProfileMirror.Failure.stale }
        let effects = try bookmarkEffects()
        var denied = false
        let original: Guard = {
            guard !denied, !Task.isCancelled, stillCurrent(), !denied,
                  model.context == .confirmed(userID: expectedUserID), model.isCurrent(ticket) else {
                denied = true; return false
            }
            let identity = effects.identity()
            guard stillCurrent(), !denied, !Task.isCancelled,
                  identity.actualUID == expectedUserID, identity.canonicalUID == expectedUserID,
                  model.context == .confirmed(userID: expectedUserID), model.isCurrent(ticket) else {
                denied = true; return false
            }
            return true
        }
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: ticket, expectedUserID: expectedUserID,
                stillCurrent: original, effects: .init(identity: effects.identity,
                guardedUpdateExisting: { uid, articleID, saved, mirrorGuard in
                    guard mirrorGuard() else { throw FavoritesProfileMirror.Failure.stale }
                    try await effects.performWrite(uid, mirrorGuard) { stillAdmitted, completion in
                        guard mirrorGuard(), stillAdmitted() else { completion(CancellationError()); return }
                        effects.updateExisting(uid, articleID, saved, {
                            mirrorGuard() && stillAdmitted()
                        }, completion)
                    }
                }))
        } catch {
            if original() { effects.diagnostic(original) }
            throw error
        }
    }

    func updateReadingProgress(_ progress: Double, for articleId: String) {
        guard var user = currentUser else { return }
        user.readingProgress[articleId] = progress
        saveUserProfile(user)
    }
    
    func isArticleBookmarked(_ articleId: String) -> Bool {
        return currentUser?.bookmarkedArticles.contains(articleId) ?? false
    }
    
    func getReadingProgress(for articleId: String) -> Double {
        return currentUser?.readingProgress[articleId] ?? 0.0
    }
    
    // MARK: - Preferences
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        guard var user = currentUser else { return }
        user.notificationPreferences = preferences
        saveUserProfile(user)
    }
    
    func updateReadingPreferences(_ preferences: ReadingPreferences) {
        guard var user = currentUser else { return }
        user.readingPreferences = preferences
        saveUserProfile(user)
    }
    
    func toggleFavoriteCategory(_ categoryId: String) {
        guard var user = currentUser else { return }
        
        if user.favoriteCategories.contains(categoryId) {
            user.favoriteCategories.removeAll { $0 == categoryId }
        } else {
            user.favoriteCategories.append(categoryId)
        }
        
        saveUserProfile(user)
    }
    
    func toggleFavoriteAuthor(_ authorId: String) {
        guard var user = currentUser else { return }
        
        if user.favoriteAuthors.contains(authorId) {
            user.favoriteAuthors.removeAll { $0 == authorId }
        } else {
            user.favoriteAuthors.append(authorId)
        }
        
        saveUserProfile(user)
    }
    
    // MARK: - Analytics
    
    func getReadingStats() -> ReadingStats {
        guard let user = currentUser else { return ReadingStats() }
        
        return ReadingStats(
            totalArticlesRead: user.readArticles.count,
            totalBookmarks: user.bookmarkedArticles.count,
            averageReadingProgress: user.readingProgress.values.reduce(0, +) / Double(max(user.readingProgress.count, 1)),
            favoriteCategories: user.favoriteCategories.count,
            favoriteAuthors: user.favoriteAuthors.count
        )
    }
}

struct ReadingStats {
    let totalArticlesRead: Int
    let totalBookmarks: Int
    let averageReadingProgress: Double
    let favoriteCategories: Int
    let favoriteAuthors: Int
    
    init(totalArticlesRead: Int = 0, totalBookmarks: Int = 0, averageReadingProgress: Double = 0.0, favoriteCategories: Int = 0, favoriteAuthors: Int = 0) {
        self.totalArticlesRead = totalArticlesRead
        self.totalBookmarks = totalBookmarks
        self.averageReadingProgress = averageReadingProgress
        self.favoriteCategories = favoriteCategories
        self.favoriteAuthors = favoriteAuthors
    }
}

/// Shared with task cancellation without an actor-hop admission window.
private final class NotificationChoiceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
