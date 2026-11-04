import Combine
import Foundation

/// The only platform bridge for functional reading history. Construction does
/// not open KVS, observe notifications, or start an account service.
@MainActor
final class ReadingHistoryRuntime {
    enum ExternalEvent: Equatable, Sendable {
        case changed(keys: Set<String>)
        case accountChanged
        case quotaViolation
    }
    struct Transport {
        let storage: ReadingHistoryModel.Storage
        let observe: @MainActor (@escaping @MainActor (ExternalEvent) -> Void) -> ReadingHistoryModel.Cancel
        let synchronize: @MainActor () -> Void
    }

    static let shared = ReadingHistoryRuntime(
        disabled: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled,
        transportFactory: { KVSBridge().transport },
        schedule: liveSchedule,
        markProfileRead: { articleID, expectedUID in
            UserManager.shared.markArticleAsRead(articleID, expectedUserID: expectedUID)
        },
        recovery: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
            ? nil : ReaderTransitionRecovery.application
    )
    static var model: ReadingHistoryModel { shared.model }
    static func localCleanupModel() -> ReadingHistoryModel? { shared.localCleanupModel() }
    /// Returns the same physical owner, without opening a KVS transport.
    func localCleanupModel() -> ReadingHistoryModel? { disabled ? nil : model }

    let model: ReadingHistoryModel
    private let disabled: Bool
    private let transportFactory: @MainActor () -> Transport
    private let markProfileRead: @MainActor (String, String) -> Void
    private let recovery: ReaderTransitionRecovery?
    private let box: StorageBox
    private var transport: Transport?
    private var prepared = false
    private var preparing = false
    private var canonicalUID: String?
    private var changeObservation: AnyCancellable?
    private var cancelExternal: ReadingHistoryModel.Cancel?
    private var observingTicket: ReadingHistoryModel.ExternalTicket?
    private var observerRevision = UUID()
    private var recoveryObservation: AnyCancellable?
    private var recoveryRevoked = false
    private var preparationAdmitted = false

    init(disabled: Bool, transportFactory: @escaping @MainActor () -> Transport,
         schedule: @escaping ReadingHistoryModel.Scheduler,
         markProfileRead: @escaping @MainActor (String, String) -> Void,
         recovery: ReaderTransitionRecovery? = nil,
         cleanupStorage: ReadingHistoryModel.Storage.Cleanup? = nil) {
        self.disabled = disabled
        self.transportFactory = transportFactory
        self.markProfileRead = markProfileRead
        self.recovery = recovery
        let box = StorageBox()
        self.box = box
        let admission = recovery?.admission
        model = ReadingHistoryModel(storage: .init(read: { namespace in
            guard admission?.isAllowed ?? true, let storage = box.value else { throw Failure.unprepared }
            return try storage.read(namespace)
        }, write: { namespace, data in
            guard admission?.isAllowed ?? true, let storage = box.value else { throw Failure.unprepared }
            try storage.write(namespace, data)
        }, cleanup: disabled ? nil : cleanupStorage), schedule: schedule, legacyAdmission: admission, recovery: recovery)
        recoveryObservation = recovery?.changes.sink { [weak self] in
            guard let self, self.preparationAdmitted, !self.permitsHistory else { return }
            self.revokeForRecovery()
        }
    }

    private var permitsHistory: Bool { !recoveryRevoked && (recovery?.admission.isAllowed ?? true) }

    func prepareIfNeeded() {
        guard !disabled, !prepared, !preparing, permitsHistory else { return }
        preparing = true
        preparationAdmitted = true
        defer { preparing = false }
        let bridge = transportFactory()
        guard permitsHistory else { revokeForRecovery(); return }
        box.value = bridge.storage
        transport = bridge
        prepared = true
        changeObservation = model.changes.sink { [weak self] _ in
            self?.refreshExternalObservation()
        }
        // This starts synchronization only in the normal app. Its return value
        // is never presented as a server acknowledgement or durable save.
        bridge.synchronize()
    }

    func changeAccountContext(userID: String?) {
        guard !disabled, prepared, permitsHistory else { return }
        canonicalUID = userID
        model.changeContext(to: .confirmed(userID: userID))
        refreshExternalObservation()
    }

    func suspendForAccountChange() {
        guard !disabled, prepared else { return }
        canonicalUID = nil
        model.changeContext(to: .unresolved)
        refreshExternalObservation()
    }

    func flushAcceptedEdits() {
        guard !disabled, prepared, permitsHistory else { return }
        model.flushPending()
    }

    /// The immutable article ticket is checked again after publishing history:
    /// an observer may have changed accounts during that publication.
    func markRead(_ ticket: ReadingHistoryModel.ArticleTicket) {
        guard !disabled, prepared, permitsHistory, model.isCurrent(ticket) else { return }
        let expectedUID = canonicalUID
        model.markRead(ticket)
        guard permitsHistory, let expectedUID, canonicalUID == expectedUID,
              model.context == .confirmed(userID: expectedUID),
              model.isCurrent(ticket) else { return }
        markProfileRead(ticket.articleID, expectedUID)
    }

    private func refreshExternalObservation() {
        guard prepared, !disabled, permitsHistory else { return }
        let ticket = model.externalTicket()
        guard ticket != observingTicket else { return }
        observingTicket = ticket
        observerRevision = UUID()
        let revision = observerRevision
        let oldCancel = cancelExternal
        cancelExternal = nil
        oldCancel?()
        guard permitsHistory, revision == observerRevision, let ticket, let transport,
              model.externalTicket() == ticket else { return }
        let cancel = transport.observe { [weak self] event in
            self?.receive(event, ticket: ticket, observerRevision: revision)
        }
        guard permitsHistory, revision == observerRevision, model.externalTicket() == ticket else {
            cancel()
            return
        }
        cancelExternal = cancel
    }

    private func receive(_ event: ExternalEvent, ticket: ReadingHistoryModel.ExternalTicket,
                         observerRevision: UUID) {
        guard !disabled, prepared, permitsHistory, self.observerRevision == observerRevision,
              model.externalTicket() == ticket else { return }
        switch event {
        case .changed(let keys):
            guard let key = model.context.namespace?.storageKey, keys.contains(key) else { return }
            model.reloadExternal(ticket: ticket)
        case .accountChanged:
            // Invalidate readers, timers and the old observer before reading the
            // current platform store. Old captured observer closures stay stale.
            model.storageIdentityChanged()
            refreshExternalObservation()
        case .quotaViolation:
            model.reportQuotaViolation(ticket: ticket)
        }
    }

    private func revokeForRecovery() {
        guard !recoveryRevoked else { return }
        recoveryRevoked = true
        canonicalUID = nil
        // Retire callbacks before model publication or arbitrary cancellation
        // hooks can reenter. No unrelated account/guest data is removed.
        observerRevision = UUID()
        observingTicket = nil
        let oldCancel = cancelExternal
        cancelExternal = nil
        model.revokeForRecovery()
        oldCancel?()
    }

    private static func liveSchedule(delay: TimeInterval,
                                     action: @escaping @MainActor () -> Void) -> ReadingHistoryModel.Cancel {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    private final class StorageBox { var value: ReadingHistoryModel.Storage? }
    private enum Failure: Error { case unprepared, invalidValue, unconfirmedWrite }

    // Intentionally no Cleanup capability: even a local KVS set may propagate.
    // A separately reviewed cloud cleanup protocol is required before wiring it.
    private final class KVSBridge {
        private let store = NSUbiquitousKeyValueStore.default
        var transport: Transport {
            Transport(storage: .init(read: { [self] namespace in
                let value = store.object(forKey: namespace.storageKey)
                guard value == nil || value is Data else { throw Failure.invalidValue }
                return value as? Data
            }, write: { [self] namespace, data in
                store.set(data, forKey: namespace.storageKey)
                guard store.data(forKey: namespace.storageKey) == data else { throw Failure.unconfirmedWrite }
                // Local readback only. synchronize is asynchronous with respect
                // to physical disk/server durability and conflict resolution.
                _ = store.synchronize()
            }), observe: { [self] receive in
                let token = NotificationCenter.default.addObserver(
                    forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                    object: store, queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard let reason = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue else { return }
                        switch reason {
                        case NSUbiquitousKeyValueStoreAccountChange: receive(.accountChanged)
                        case NSUbiquitousKeyValueStoreQuotaViolationChange: receive(.quotaViolation)
                        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
                            guard let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
                            receive(.changed(keys: Set(keys)))
                        default: break
                        }
                    }
                }
                return { NotificationCenter.default.removeObserver(token) }
            }, synchronize: { [self] in _ = store.synchronize() })
        }
    }
}
