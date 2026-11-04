import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Canonical Auth alone owns transitions. Construction performs no provider or
/// SDK work; both production and tests use this same guarded adapter/model.
@MainActor
final class ReaderPreferencesService {
    typealias Model = ReaderPreferencesModel
    typealias Guard = Model.Guard
    struct Effects {
        let capturePermission: @MainActor () -> Guard?
        let identity: @MainActor () -> Model.Identity
        let load: Model.Load
        let save: Model.Save
    }
    static let shared = ReaderPreferencesService()
    private let disabled: Bool
    private let injectedEffects: Effects?
    private let injectedSchedule: Model.Schedule?
    private lazy var db = Firestore.firestore()
    private(set) lazy var model = makeModel()

    private init() {
        disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
        injectedEffects = nil; injectedSchedule = nil
    }
    /// All service boundaries are required, so a local fixture cannot partially
    /// inject a transport and then fall through to Auth, Firestore or messaging.
    init(effects: Effects, schedule: Model.Schedule? = nil) {
        disabled = false; injectedEffects = effects; injectedSchedule = schedule
    }
    func start() { guard !disabled else { return }; model.start() }
    @discardableResult func changeAccountContext(userID: String?) -> Model.ContextTicket? {
        model.changeContext(to: .confirmed(userID: userID))
    }
    func loadCurrentContext(_ original: Model.ContextTicket, stillCurrent: @escaping Guard) async {
        guard !disabled, stillCurrent() else { return }
        await model.load(original, stillCurrent: stillCurrent)
    }
    /// Fresh Auth admission replaces an unloaded old request, whose parent
    /// permission can already be revoked even while its physical read remains.
    func loadCurrentContextIfNeeded(_ original: Model.ContextTicket, stillCurrent: @escaping Guard) async {
        guard !disabled, stillCurrent(), model.isCurrent(original), !model.snapshot.loaded,
              stillCurrent(), model.isCurrent(original), !model.snapshot.loaded else { return }
        // The model captures its revision before invoking the original parent
        // again. Do not insert a callback before that capture via another shim.
        await model.load(original, stillCurrent: stillCurrent)
    }
    /// Foreground/reconnect is best effort: capture the original account and
    /// startup permission synchronously, before the task can be delayed.
    /// The model coalesces refreshes and gives local writes priority.
    @discardableResult
    func refreshAfterInterruption() -> Task<Void, Never>? {
        guard !disabled,
              let request = model.captureRefresh(context: model.contextTicket()) else { return nil }
        let originalModel = model
        return Task { await originalModel.refresh(request) }
    }
    private func identity() -> Model.Identity {
        if let injectedEffects { return injectedEffects.identity() }
        guard !disabled else { return .init(actualUID: nil, canonicalUID: nil) }
        return .init(actualUID: Auth.auth().currentUser?.uid, canonicalUID: AuthService.shared.session?.uid)
    }
    private func capturePermission() -> Guard? {
        guard !disabled else { return nil }
        if let injectedEffects { return injectedEffects.capturePermission() }
        return AuthService.shared.captureReaderWorkPermission()
    }
    private func admission(userID: String, original: @escaping Guard) -> Guard {
        var denied = false
        return { [weak self] in
            guard !denied, let self, !self.disabled else { denied = true; return false }
            guard original(), !denied else { denied = true; return false }
            let identity = self.identity()
            guard original(), !denied, identity.actualUID == userID, identity.canonicalUID == userID else {
                denied = true; return false
            }
            return true
        }
    }
    private func makeModel() -> Model {
        Model(capturePermission: { [weak self] in self?.capturePermission() },
            identity: { [weak self] in self?.identity() ?? .init(actualUID: nil, canonicalUID: nil) },
            load: { [weak self] ticket, stillCurrent in
                guard let self, let uid = ticket.userID else { throw CancellationError() }
                let admitted = self.admission(userID: uid, original: stillCurrent)
                guard admitted() else { throw CancellationError() }
                if let effects = self.injectedEffects {
                    let result = try await effects.load(ticket, admitted)
                    guard admitted() else { throw CancellationError() }
                    return result
                }
                let reference = try self.reference(userID: uid, admitted: admitted)
                guard admitted() else { throw CancellationError() }
                let doc = try await reference.getDocument()
                guard admitted() else { throw CancellationError() }
                if !doc.exists { return .init(preferences: nil, isFromCache: doc.metadata.isFromCache) }
                let data = doc.data() ?? [:]
                guard let version = data["schemaVersion"] as? Int, version == 1,
                      let ids = data["interestTopicIDs"] as? [String], ids.count <= 20,
                      let completed = data["onboardingCompleted"] as? Bool else { throw CocoaError(.coderReadCorrupt) }
                let result = Model.ReadResult(preferences: ReaderPreferences(interestTopicIDs: ids, onboardingCompleted: completed),
                                              isFromCache: doc.metadata.isFromCache)
                guard admitted() else { throw CancellationError() }
                return result
            }, save: { [weak self] request, stillCurrent in
                guard let self else { throw CancellationError() }
                let admitted = self.admission(userID: request.userID, original: stillCurrent)
                guard admitted() else { throw CancellationError() }
                if let effects = self.injectedEffects {
                    try await effects.save(request, admitted)
                    guard admitted() else { throw CancellationError() }
                    return
                }
                // The model's deadline only ends UI waiting. This await retains
                // the physical slot until the real SDK callback returns.
                let runtime = ReaderWriterDrainRuntime.shared
                guard admitted() else { throw CancellationError() }
                try await runtime.performWrite(expectedUserID: request.userID, stillCurrent: admitted) { [weak self] stillAdmitted, completion in
                    guard let self, stillAdmitted() else { completion(CancellationError()); return }
                    do {
                        let reference = try self.reference(userID: request.userID, admitted: stillAdmitted)
                        let fields: [String: Any] = [
                            "schemaVersion": 1, "interestTopicIDs": request.preferences.interestTopicIDs,
                            "onboardingCompleted": request.preferences.onboardingCompleted,
                            "updatedAt": FieldValue.serverTimestamp()
                        ]
                        guard stillAdmitted() else { completion(CancellationError()); return }
                        reference.setData(fields, completion: completion)
                    } catch { completion(error) }
                }
                guard admitted() else { throw CancellationError() }
            }, schedule: injectedSchedule)
    }
    private func reference(userID: String, admitted: Guard) throws -> DocumentReference {
        guard admitted() else { throw CancellationError() }
        let client = db
        guard admitted() else { throw CancellationError() }
        let users = client.collection("users")
        guard admitted() else { throw CancellationError() }
        let user = users.document(userID)
        guard admitted() else { throw CancellationError() }
        let preferences = user.collection("preferences")
        guard admitted() else { throw CancellationError() }
        let reference = preferences.document("reader")
        guard admitted() else { throw CancellationError() }
        return reference
    }
}
