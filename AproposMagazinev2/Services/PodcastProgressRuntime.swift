import Combine
import Foundation

/// Canonical auth publishes context here. This bridge never creates an audio
/// player or an auth listener, and constructs no storage before preparation.
@MainActor
final class PodcastProgressRuntime {
    static let shared = PodcastProgressRuntime(
        disabled: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled,
        storageFactory: { DefaultsBridge().storage },
        recovery: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
            ? nil : ReaderTransitionRecovery.application
    )
    static var store: PodcastPlaybackProgressStore { shared.model }

    let model: PodcastPlaybackProgressStore
    private let disabled: Bool
    private let storageFactory: @MainActor () -> PodcastPlaybackProgressStore.Storage
    private let box: StorageBox
    private let recovery: ReaderTransitionRecovery?
    private var recoveryObservation: AnyCancellable?
    private var preparationAdmitted = false
    private var recoveryRevoked = false
    private var preparing = false
    private var prepared = false

    init(disabled: Bool, storageFactory: @escaping @MainActor () -> PodcastPlaybackProgressStore.Storage,
         recovery: ReaderTransitionRecovery? = nil) {
        self.disabled = disabled
        self.storageFactory = storageFactory
        self.recovery = recovery
        let box = StorageBox()
        self.box = box
        let admission = recovery?.admission
        model = PodcastPlaybackProgressStore(storage: .init(read: { namespace in
            guard admission?.isAllowed ?? true, let storage = box.value else { throw Failure.unprepared }
            return try storage.read(namespace)
        }, write: { namespace, data in
            guard admission?.isAllowed ?? true, let storage = box.value else { throw Failure.unprepared }
            try storage.write(namespace, data)
        }), legacyAdmission: admission, cleanupStorageProvider: { checkpoint, stillCurrent in
            // This is only reached by explicit original-bound cleanup. Ordinary
            // startup/rendering and the getter below never construct storage.
            @MainActor func authorized() -> Bool {
                guard !disabled, let recovery, !recovery.admission.isAllowed,
                      recovery.hasVerifiedSeal(binding: checkpoint.marker.binding),
                      recovery.deletionCheckpoint?.phase == .ledger,
                      recovery.deletionCheckpoint?.isSameFamily(as: checkpoint) == true,
                      checkpoint.phase == .ledger else { return false }
                guard stillCurrent() else { return false }
                return !recovery.admission.isAllowed
                    && recovery.hasVerifiedSeal(binding: checkpoint.marker.binding)
                    && recovery.deletionCheckpoint?.phase == .ledger
                    && recovery.deletionCheckpoint?.isSameFamily(as: checkpoint) == true
            }
            guard authorized(), !box.constructing,
                  let namespace = PodcastProgressContext.confirmed(userID: checkpoint.request.expectedUID).namespace,
                  namespace != .guest else { throw Failure.unprepared }
            if box.value == nil {
                box.constructing = true
                defer { box.constructing = false }
                let storage = storageFactory()
                guard authorized() else { throw Failure.unprepared }
                box.value = storage
            }
            guard authorized(), let storage = box.value else { throw Failure.unprepared }
            return .init(read: { requested in
                guard requested == namespace else { throw Failure.unprepared }
                return try storage.read(requested)
            }, write: { requested, data in
                guard requested == namespace else { throw Failure.unprepared }
                try storage.write(requested, data)
            })
        })
        recoveryObservation = recovery?.changes.sink { [weak self] in
            guard let self, self.preparationAdmitted, !self.permitsProgress else { return }
            self.revokeForRecovery()
        }
    }

    private var permitsProgress: Bool { !recoveryRevoked && (recovery?.admission.isAllowed ?? true) }

    /// Inert access to the existing physical owner. Raw storage is only resolved
    /// by its explicitly scoped cleanup provider after original closed proof.
    func localCleanupStore() -> PodcastPlaybackProgressStore? { disabled ? nil : model }

    /// Before Firebase configuration; no SDK or defaults read occurs here.
    func prepareIfNeeded() {
        guard !disabled, !prepared, !preparing, permitsProgress else { return }
        guard !box.constructing else { return }
        preparing = true
        box.constructing = true
        preparationAdmitted = true
        defer { preparing = false; box.constructing = false }
        let storage = storageFactory()
        guard permitsProgress else { revokeForRecovery(); return }
        box.value = storage
        prepared = true
    }

    func changeAccountContext(userID: String?) {
        guard !disabled, prepared, permitsProgress else { return }
        model.changeContext(to: .confirmed(userID: userID))
    }

    /// Stop old callbacks/player before logout cleanup. A failed logout restores
    /// its canonical account through the same publish path, with a fresh epoch.
    func suspendForAccountChange() {
        guard !disabled, prepared else { return }
        model.changeContext(to: .unresolved)
    }

    private func revokeForRecovery() {
        guard !recoveryRevoked else { return }
        recoveryRevoked = true
        model.revokeForRecovery()
    }

    private final class StorageBox {
        var value: PodcastPlaybackProgressStore.Storage?
        var constructing = false
    }
    private enum Failure: Error { case unprepared, invalidStoredValue, unconfirmedWrite }

    private final class DefaultsBridge {
        private let defaults = UserDefaults.standard
        var storage: PodcastPlaybackProgressStore.Storage {
            .init(read: { [self] namespace in
                let key = namespace.storageKey
                if defaults.object(forKey: key) != nil, defaults.data(forKey: key) == nil {
                    throw Failure.invalidStoredValue
                }
                return defaults.data(forKey: key)
            }, write: { [self] namespace, data in
                let key = namespace.storageKey
                defaults.set(data, forKey: key)
                // Process-visible readback, not a promise of crash durability.
                guard defaults.data(forKey: key) == data else { throw Failure.unconfirmedWrite }
            })
        }
    }
}
