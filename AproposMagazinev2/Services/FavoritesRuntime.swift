import Combine
import Foundation

/// The process-lifetime composition for favorites. Factories are inert until
/// normal startup; no defaults, SDK, network monitor or cache opens in init.
@MainActor
final class FavoritesRuntime {
    typealias OfflineFactory = @MainActor (FavoritesModel) -> FavoritesOfflineCoordinator

    static let shared: FavoritesRuntime = FavoritesRuntime(
        disabled: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled,
        storageFactory: { makeJournalStorage() },
        capturePermission: { AuthService.shared.captureReaderWorkPermission() },
        drainPendingWrites: { uid, current in
            try await FirestoreService.shared.drainPendingFavoriteWrites(expectedUserID: uid, stillCurrent: current)
        },
        writeFavorite: { mutation, expectedUID, permission in
            let originalModel = FavoritesRuntime.shared.model
            try await FirestoreService.shared.setFavorite(mutation.article, enabled: mutation.enabled,
                expectedUserID: expectedUID, stillCurrent: {
                    permission() && originalModel.context == .confirmed(userID: expectedUID) && originalModel.isCurrent(mutation)
                })
        },
        offlineFactory: { OfflineManager.makeFavoritesCoordinator(model: $0) },
        profileSet: { ticket, expectedUID, originalModel, permission in
            try await UserManager.shared.setBookmark(ticket: ticket, expectedUserID: expectedUID, model: originalModel, stillCurrent: permission)
        },
        sanitize: { ArticleAvailabilityService.model.sanitized($0) }
    )
    static var model: FavoritesModel { shared.model }
    private static var activeFileJournal: FavoritesFileJournal?
    private static var closedRecoveryFileJournal: FavoritesFileJournal?

    /// Called only by an explicit, original-bound recovery action. This does
    /// not initialize `shared`, read defaults, start a model or open the SDK.
    /// A hot instance is reused; cold recovery keeps one queue across retries.
    static func makeJournalForClosedRecovery() -> FavoritesFileJournal? {
        if let activeFileJournal { return activeFileJournal }
        if let closedRecoveryFileJournal { return closedRecoveryFileJournal }
        guard let journal = makeFileJournal(admission: ReaderTransitionRecovery.application.admission) else { return nil }
        closedRecoveryFileJournal = journal
        return journal
    }

    /// Returns the already prepared source instance. Never opens another journal
    /// or adopts a different account for a transition. The caller must freeze
    /// this exact instance and recheck the original canonical context.
    static func existingJournalForTransition(context: CanonicalSessionState.ContextTicket) -> FavoritesFileJournal? {
        guard !shared.disabled, shared.prepared,
              let uid = context.userID, AuthService.shared.state.isCurrent(context),
              shared.canonicalUID == uid, shared.model.context == .confirmed(userID: uid) else { return nil }
        return activeFileJournal
    }

    let model: FavoritesModel
    private(set) var offline: FavoritesOfflineCoordinator?
    private var cloud: FavoritesCloudCoordinator?
    private let disabled: Bool
    private let requiresAccountForSaving: Bool
    private let storageFactory: @MainActor () -> FavoritesModel.Storage
    private let capturePermission: FavoritesCloudCoordinator.CapturePermission
    private let drainPendingWrites: FavoritesCloudCoordinator.GuardedDrain
    private let writeFavorite: FavoritesCloudCoordinator.GuardedWrite
    private let offlineFactory: OfflineFactory
    private let profileSet: FavoritesMutationTransport.GuardedProfileSet
    private let box: StorageBox
    private var prepared = false
    private var preparing = false
    private var canonicalUID: String?
    private var observation: AnyCancellable?

    /// Compatibility composition for fully injected local providers. The live
    /// singleton above must supply explicit original startup permission.
    convenience init(disabled: Bool, requiresAccountForSaving: Bool = true,
         storageFactory: @escaping @MainActor () -> FavoritesModel.Storage,
         drainPendingWrites: @escaping FavoritesCloudCoordinator.Drain,
         writeFavorite: @escaping FavoritesCloudCoordinator.Write,
         offlineFactory: @escaping OfflineFactory,
         profileSet: @escaping FavoritesMutationTransport.ProfileSet,
         sanitize: @escaping @MainActor (Article) -> Article? = { $0 }) {
        self.init(disabled: disabled, requiresAccountForSaving: requiresAccountForSaving, storageFactory: storageFactory, capturePermission: { { true } },
            drainPendingWrites: { uid, _ in try await drainPendingWrites(uid) },
            writeFavorite: { mutation, uid, _ in try await writeFavorite(mutation, uid) },
            offlineFactory: offlineFactory,
            profileSet: { ticket, uid, model, _ in try await profileSet(ticket, uid, model) }, sanitize: sanitize)
    }

    init(disabled: Bool, requiresAccountForSaving: Bool = true,
         storageFactory: @escaping @MainActor () -> FavoritesModel.Storage,
         capturePermission: @escaping FavoritesCloudCoordinator.CapturePermission,
         drainPendingWrites: @escaping FavoritesCloudCoordinator.GuardedDrain,
         writeFavorite: @escaping FavoritesCloudCoordinator.GuardedWrite,
         offlineFactory: @escaping OfflineFactory,
         profileSet: @escaping FavoritesMutationTransport.GuardedProfileSet,
         sanitize: @escaping @MainActor (Article) -> Article? = { $0 }) {
        self.disabled = disabled
        self.requiresAccountForSaving = requiresAccountForSaving
        self.storageFactory = storageFactory
        self.capturePermission = capturePermission
        self.drainPendingWrites = drainPendingWrites
        self.writeFavorite = writeFavorite
        self.offlineFactory = offlineFactory
        self.profileSet = profileSet
        let box = StorageBox()
        self.box = box
        model = FavoritesModel(storage: .init(read: { namespace, completion in
            guard let storage = box.value else { completion(.failure(FavoritesJournalFailure.readFailed)); return }
            storage.read(namespace, completion)
        }, write: { namespace, record, expectedRevision, completion in
            guard let storage = box.value else { completion(.failure(FavoritesJournalFailure.writeFailed)); return }
            storage.write(namespace, record, expectedRevision, completion)
        }), sanitize: sanitize)
    }

    func prepareIfNeeded() {
        guard !disabled, !prepared, !preparing else { return }
        preparing = true
        box.value = storageFactory()
        let write = writeFavorite, profile = profileSet, core = model
        cloud = FavoritesCloudCoordinator(model: core, capturePermission: { [weak self] in
            self?.captureCloudPermission()
        }, drainPendingWrites: drainPendingWrites) { ticket, uid, permission in
            try await FavoritesMutationTransport.perform(model: core, ticket: ticket, expectedUserID: uid,
                stillCurrent: permission, writeFavorite: write, setBookmark: profile)
        }
        offline = offlineFactory(model)
        prepared = true
        preparing = false
        observation = model.changes.sink { [weak self] snapshot in
            guard let self, snapshot.generation == self.model.snapshot.generation,
                  snapshot.revision == self.model.snapshot.revision else { return }
            self.offline?.synchronizeCurrentMembership()
            self.refreshCloud()
        }
    }

    func changeAccountContext(userID: String?) {
        guard !disabled, prepared else { return }
        canonicalUID = userID
        model.changeContext(to: .confirmed(userID: userID))
        refreshCloud()
        offline?.synchronizeCurrentMembership()
    }

    func suspendForAccountChange() {
        guard !disabled, prepared else { return }
        canonicalUID = nil
        model.changeContext(to: .unresolved)
        refreshCloud()
        offline?.synchronizeCurrentMembership()
    }

    @discardableResult
    func setFavorite(_ article: Article, enabled: Bool) -> FavoritesModel.Mutation? {
        guard !disabled, prepared else { return nil }
        let expectedUID = canonicalUID
        if enabled && requiresAccountForSaving {
            let generation = model.snapshot.generation
            guard let expectedUID, model.context == .confirmed(userID: expectedUID),
                  let permission = capturePermission(),
                  canonicalUID == expectedUID, model.context == .confirmed(userID: expectedUID),
                  model.snapshot.generation == generation, permission(),
                  canonicalUID == expectedUID, model.context == .confirmed(userID: expectedUID),
                  model.snapshot.generation == generation else { return nil }
        }
        let original = model.snapshot
        let originalOffline = offline
        let removal = enabled ? nil : originalOffline?.captureDownloadRemoval(articleID: article.id)
        // Resolving the exact asset can reenter. Never apply an old tap to a
        // different owner or a newer selection published during that lookup.
        guard canonicalUID == expectedUID, model.snapshot.generation == original.generation,
              model.snapshot.revision == original.revision else { return nil }
        guard let mutation = model.setFavorite(article, enabled: enabled) else { return nil }
        if let removal { _ = originalOffline?.discardDownloads(removal, mutation: mutation) }
        deliver(mutation, expectedUID: expectedUID)
        return mutation
    }

    func retryMutation(articleID: String) {
        guard !disabled, prepared else { return }
        let expectedUID = canonicalUID
        guard let mutation = model.retryMutation(articleID: articleID) else { return }
        deliver(mutation, expectedUID: expectedUID)
    }

    func retryCurrentChanges(generation: UUID) {
        guard !disabled, prepared, model.snapshot.generation == generation else { return }
        model.retryStorage()
        cloud?.retryRecovery(generation: generation)
        guard model.snapshot.generation == generation else { return }
        for id in model.snapshot.pendingArticleIDs.sorted() {
            guard model.snapshot.generation == generation else { return }
            retryMutation(articleID: id)
        }
    }

    private func deliver(_ mutation: FavoritesModel.Mutation, expectedUID: String?) {
        // setFavorite publishes synchronously. An observer can switch accounts or
        // supersede this exact intent before it returns to this bridge.
        // Both provider effects execute serially inside the coordinator slot.
        guard let expectedUID, owns(mutation, uid: expectedUID) else { return }
        cloud?.submit(mutation, expectedUserID: expectedUID)
    }

    private func owns(_ mutation: FavoritesModel.Mutation, uid: String) -> Bool {
        canonicalUID == uid && model.context == .confirmed(userID: uid) && model.isCurrent(mutation)
    }

    /// Captured synchronously by the coordinator before any provider Task. A
    /// model owner can change reentrantly during the auth/startup lookup.
    private func captureCloudPermission() -> FavoritesCloudCoordinator.Guard? {
        guard !disabled, prepared, let uid = canonicalUID,
              model.context == .confirmed(userID: uid) else { return nil }
        let generation = model.snapshot.generation
        guard let source = capturePermission(), canonicalUID == uid,
              model.context == .confirmed(userID: uid), model.snapshot.generation == generation else { return nil }
        var denied = false
        let current: FavoritesCloudCoordinator.Guard = { [weak self] in
            guard !denied, let self, self.canonicalUID == uid,
                  self.model.context == .confirmed(userID: uid), self.model.snapshot.generation == generation,
                  source(), !denied, self.canonicalUID == uid,
                  self.model.context == .confirmed(userID: uid), self.model.snapshot.generation == generation
            else { denied = true; return false }
            return true
        }
        return current() ? current : nil
    }

    private func refreshCloud() {
        cloud?.setOwner(expectedUserID: canonicalUID, generation: model.snapshot.generation)
    }

    private final class StorageBox { var value: FavoritesModel.Storage? }
    /// The journal is created only by guarded normal preparation. Its typed
    /// callback storage performs codec and atomic file I/O away from MainActor.
    private static func makeJournalStorage() -> FavoritesModel.Storage {
        guard let journal = activeFileJournal ?? closedRecoveryFileJournal
                ?? makeFileJournal(admission: shared.disabled ? nil : ReaderTransitionRecovery.application.admission) else {
            return .init(read: { _, completion in completion(.failure(FavoritesJournalFailure.readFailed)) },
                         write: { _, _, _, completion in completion(.failure(FavoritesJournalFailure.writeFailed)) })
        }
        activeFileJournal = journal
        return journal.storage
    }

    private static func makeFileJournal(admission: ReaderLegacyWriteAdmission?) -> FavoritesFileJournal? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return FavoritesFileJournal(rootDirectory: base.appendingPathComponent("AproposMagazine/favorites-journal", isDirectory: true),
            legacyRead: { namespace in
                // Only the existing owner-bound V1 key is eligible. No global
                // legacy favorite or pending-action record is adopted.
                let value = UserDefaults.standard.object(forKey: namespace.storageKey)
                guard value == nil || value is Data else { throw FavoritesJournalFailure.readFailed }
                return value as? Data
            }, legacyAdmission: admission, legacyDelete: { namespace, expected in
                guard namespace != .guest else { throw FavoritesFileJournal.CleanupFailure.differentOriginal }
                let defaults = UserDefaults.standard
                // Exact existing owner key only. An unexpected type or changed
                // value is preserved, never treated as a missing legacy record.
                let original = defaults.object(forKey: namespace.storageKey)
                guard let original = original as? Data, original == expected else {
                    throw FavoritesFileJournal.CleanupFailure.changedSource
                }
                defaults.removeObject(forKey: namespace.storageKey)
                guard defaults.object(forKey: namespace.storageKey) == nil else {
                    throw FavoritesFileJournal.CleanupFailure.unconfirmed
                }
            })
    }
}
