import Combine
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseAppCheck

/// Firebase is the identity provider; one SDK-free committed state is the only
/// account projection used by UI and consumers. Construction starts no services.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    nonisolated let objectWillChange = ObservableObjectPublisher()
    let state = CanonicalSessionState()
    /// Auth-only projection. Reader observers must never subscribe here: they
    /// remain on `state` until the original observation is explicitly released.
    let bootstrapIdentity = CanonicalSessionState()
    private let startup: ReaderSDKStartupState
    private let identityPublication = CanonicalAccountPublication()
    private var identityIngress = UUID()
    private struct PendingReaderPublication {
        let id: UUID
        let ingress: UUID
        let context: CanonicalSessionState.ContextTicket
        let original: ReaderAccountSession?
        let currentUserID: () -> String?
        let publish: (@escaping () -> Bool) -> CanonicalSessionState.ContextTicket?
    }
    private var pendingReaderPublication: PendingReaderPublication?
    private var readerStartupCoordinator: ReaderStartupCoordinator?
    private var readerDeletionCoordinator: ReaderAccountDeletionCoordinator?
    private var readerDeletionComposition = UUID()
    private var recoveryPresentationObservations: Set<AnyCancellable> = []
    private var recoveryPresentationScheduled = false
    private var recoveryPreparation: UUID?
    private var retainedRecoveryFlow: RecoveryFlow?

    struct RecoveryTicket: Equatable {
        let context: CanonicalSessionState.ContextTicket
        let checkpoint: ReaderTransitionRecoveryStore.DeletionCheckpoint
    }
    enum AccountRecoveryPresentation: Equatable {
        case checking, unavailable, protected, deletion(RecoveryTicket)
    }
    typealias RecoveryProvider = ReaderReauthenticationMethod
    @MainActor struct RecoveryPrompts {
        let email: ReaderEmailReauthenticationPrompt
        let apple: ReaderAppleReauthenticationPrompt
        let google: ReaderGoogleReauthenticationPrompt
    }
    @MainActor struct RecoveryFlow {
        let id: UUID
        let ticket: RecoveryTicket
        let provider: RecoveryProvider
        let configuration: ReaderDeletionHTTPTransport.Configuration
        let coordinator: ReaderAccountDeletionCoordinator
        let prompts: RecoveryPrompts
    }
    typealias RecoveryFactory = @MainActor (RecoveryProvider, RecoveryPrompts) -> ReaderAccountDeletionCoordinator?

    /// Memory-only presentation. A verified local checkpoint describes unfinished
    /// work, never a server receipt or permission to start reader services.
    var accountRecoveryPresentation: AccountRecoveryPresentation {
        guard let recovery = startup.localRecovery else { return .checking }
        switch recovery.status {
        case .unresolved, .loading: return .checking
        case .unavailable: return .unavailable
        case .legacy: return .checking
        case .sealed(let marker):
            guard !recovery.isBusy, let checkpoint = recovery.deletionCheckpoint,
                  checkpoint.marker == marker,
                  bootstrapIdentity.snapshot.session?.uid == checkpoint.request.expectedUID else { return .protected }
            return .deletion(RecoveryTicket(context: bootstrapIdentity.contextTicket(), checkpoint: checkpoint))
        }
    }

    /// Keep the same prompts and physical coordinator across sheet reopenings.
    /// A different account/generation cannot inherit this presentation or retry.
    var accountRecoveryFlow: RecoveryFlow? {
        guard let flow = retainedRecoveryFlow, ownsRecoveryFlow(flow) else { return nil }
        return flow
    }
    private func ownsRecoveryFlow(_ flow: RecoveryFlow) -> Bool {
        guard retainedRecoveryFlow?.id == flow.id,
              readerDeletionCoordinator === flow.coordinator,
              state.snapshot.context == .unresolved,
              bootstrapIdentity.isCurrent(flow.ticket.context),
              let recovery = startup.localRecovery,
              startup.permitsAuthOnlyDeletionRecovery(recovery),
              let checkpoint = recovery.deletionCheckpoint else { return false }
        return flow.ticket.checkpoint.isSameFamily(as: checkpoint)
    }
    func canUseAccountRecoveryFlow(_ flow: RecoveryFlow,
                                  configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        configuration == flow.configuration && ownsRecoveryFlow(flow)
    }
    func canPrepareAccountRecovery(ticket: RecoveryTicket,
                                   configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard let configuration, recoveryPreparation == nil,
              state.snapshot.context == .unresolved, bootstrapIdentity.isCurrent(ticket.context),
              let recovery = startup.localRecovery,
              startup.permitsAuthOnlyDeletionRecovery(recovery),
              recovery.hasVerifiedSeal(binding: ticket.checkpoint.marker.binding),
              let checkpoint = recovery.deletionCheckpoint,
              ticket.checkpoint.isSameFamily(as: checkpoint),
              ticket.context.userID == checkpoint.request.expectedUID,
              checkpoint.configurationDigest == ReaderTransitionRecoveryStore.deletionConfigurationDigest(
                projectID: configuration.projectID, appID: configuration.appID, endpoint: configuration.endpointURL) else { return false }
        if let flow = retainedRecoveryFlow {
            return flow.ticket.context == ticket.context && canUseAccountRecoveryFlow(flow, configuration: configuration)
        }
        return readerDeletionCoordinator == nil
    }

    /// Explicit confirmed UI choice only. Factories are never evaluated by a
    /// rendering getter. Production supplies no endpoint until activation gates.
    func prepareAccountRecovery(ticket: RecoveryTicket, provider: RecoveryProvider,
                                configuration: ReaderDeletionHTTPTransport.Configuration?,
                                googleService: GoogleSignInService? = nil,
                                supportedProviders: (@MainActor (RecoveryTicket) -> Set<RecoveryProvider>)? = nil,
                                factory: RecoveryFactory? = nil) -> RecoveryFlow? {
        guard canPrepareAccountRecovery(ticket: ticket, configuration: configuration),
              let configuration else { return nil }
        if let flow = retainedRecoveryFlow { return flow.provider == provider ? flow : nil }
        let preparation = UUID()
        recoveryPreparation = preparation
        defer { if recoveryPreparation == preparation { recoveryPreparation = nil } }
        let supported = supportedProviders?(ticket) ?? resumedReaderReauthentication.supportedMethods(context: ticket.context)
        guard supported.contains(provider), recoveryPreparation == preparation,
              bootstrapIdentity.isCurrent(ticket.context), state.snapshot.context == .unresolved,
              retainedRecoveryFlow == nil, readerDeletionCoordinator == nil,
              let admittedRecovery = startup.localRecovery, startup.permitsAuthOnlyDeletionRecovery(admittedRecovery),
              admittedRecovery.hasVerifiedSeal(binding: ticket.checkpoint.marker.binding),
              let admittedCheckpoint = admittedRecovery.deletionCheckpoint,
              ticket.checkpoint.isSameFamily(as: admittedCheckpoint) else { return nil }
        let prompts = RecoveryPrompts(email: ReaderEmailReauthenticationPrompt(canonical: bootstrapIdentity),
            apple: ReaderAppleReauthenticationPrompt(canonical: bootstrapIdentity),
            google: ReaderGoogleReauthenticationPrompt(canonical: bootstrapIdentity, service: googleService ?? .shared))
        let coordinator: ReaderAccountDeletionCoordinator?
        if let factory { coordinator = factory(provider, prompts) }
        else {
            switch provider {
            case .email: coordinator = configureEmailReaderAccountDeletion(configuration: configuration,
                prompt: prompts.email, resumingAfterRestart: true)
            case .apple: coordinator = configureAppleReaderAccountDeletion(configuration: configuration,
                prompt: prompts.apple, resumingAfterRestart: true)
            case .google: coordinator = configureGoogleReaderAccountDeletion(configuration: configuration,
                prompt: prompts.google, resumingAfterRestart: true)
            }
        }
        guard let coordinator else { return nil }
        guard recoveryPreparation == preparation,
              readerDeletionCoordinator === coordinator, bootstrapIdentity.isCurrent(ticket.context),
              state.snapshot.context == .unresolved, let recovery = startup.localRecovery,
              startup.permitsAuthOnlyDeletionRecovery(recovery),
              recovery.hasVerifiedSeal(binding: ticket.checkpoint.marker.binding),
              let checkpoint = recovery.deletionCheckpoint,
              ticket.checkpoint.isSameFamily(as: checkpoint) else {
            // A factory hook may change identity before returning an inert
            // coordinator. It owns no intent/write/transport and must not strand
            // a later explicit choice. Never retire a started or replaced one.
            if recoveryPreparation == preparation { retireUnstartedRecovery(coordinator, flowID: nil) }
            return nil
        }
        let flow = RecoveryFlow(id: UUID(), ticket: ticket, provider: provider,
            configuration: configuration, coordinator: coordinator, prompts: prompts)
        retainedRecoveryFlow = flow
        objectWillChange.send()
        guard ownsRecoveryFlow(flow) else {
            retireUnstartedRecovery(coordinator, flowID: flow.id)
            return nil
        }
        return flow
    }

    private func retireUnstartedRecovery(_ coordinator: ReaderAccountDeletionCoordinator, flowID: UUID?) {
        guard retainedRecoveryFlow?.id == flowID, readerDeletionCoordinator === coordinator,
              coordinator.status == .idle, coordinator.requestID == nil,
              !coordinator.hasPhysicalFlight else { return }
        // Consume the exact idle owner before its cancellation can notify or
        // reenter. A started operation or a different replacement is preserved.
        retainedRecoveryFlow = nil
        readerDeletionCoordinator = nil
        readerDeletionComposition = UUID()
        coordinator.cancel()
    }

    @discardableResult
    func confirmAccountRecovery(_ flow: RecoveryFlow, configuration: ReaderDeletionHTTPTransport.Configuration?,
                                userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration),
              !flow.coordinator.hasPhysicalFlight else { return false }
        if flow.coordinator.canRetry { return flow.coordinator.retry(userConfirmed: true) }
        return flow.coordinator.beginResumption(context: flow.ticket.context, userConfirmed: true)
    }
    @discardableResult
    func confirmAccountRecoveryLedger(_ flow: RecoveryFlow, configuration: ReaderDeletionHTTPTransport.Configuration?,
                                      userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canBeginLedgerCleanup else { return false }
        return flow.coordinator.beginLedgerCleanup(userConfirmed: true)
    }
    @discardableResult
    func prepareAccountRecoveryLocalFavorites(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPrepareLocalFavoritesCleanup,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.prepareLocalFavoritesCleanup()
    }
    @discardableResult
    func confirmAccountRecoveryLocalFavorites(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.LocalFavoritesConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmLocalFavoritesCleanup(confirmation, userConfirmed: true)
    }
    @discardableResult
    func prepareAccountRecoveryLocalResume(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPrepareLocalResumeCleanup,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.prepareLocalResumeCleanup()
    }
    @discardableResult
    func confirmAccountRecoveryLocalResume(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.LocalResumeConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmLocalResumeCleanup(confirmation, userConfirmed: true)
    }
    func cancelAccountRecoveryLocalResume(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelLocalResumeCleanup()
    }
    @discardableResult
    func prepareAccountRecoveryLocalPodcast(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPrepareLocalPodcastCleanup,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.prepareLocalPodcastCleanup()
    }
    @discardableResult
    func confirmAccountRecoveryLocalPodcast(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.LocalPodcastConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmLocalPodcastCleanup(confirmation, userConfirmed: true)
    }
    func cancelAccountRecoveryLocalPodcast(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelLocalPodcastCleanup()
    }
    @discardableResult
    func prepareAccountRecoveryLocalIntroduction(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPrepareLocalIntroductionCleanup,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.prepareLocalIntroductionCleanup()
    }
    @discardableResult
    func confirmAccountRecoveryLocalIntroduction(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.LocalIntroductionConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmLocalIntroductionCleanup(confirmation, userConfirmed: true)
    }
    func cancelAccountRecoveryLocalIntroduction(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelLocalIntroductionCleanup()
    }
    @discardableResult
    func prepareAccountRecoveryLocalHistory(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPrepareLocalHistoryCleanup,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.prepareLocalHistoryCleanup()
    }
    @discardableResult
    func confirmAccountRecoveryLocalHistory(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.LocalHistoryConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmLocalHistoryCleanup(confirmation, userConfirmed: true)
    }
    func cancelAccountRecoveryLocalHistory(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelLocalHistoryCleanup()
    }
    func cancelAccountRecoveryLocalFavorites(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelLocalFavoritesCleanup()
    }
    @discardableResult
    func prepareAccountRecoveryPush(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?) -> Bool {
        guard canUseAccountRecoveryFlow(flow, configuration: configuration),
              flow.coordinator.canPreparePushRetirement,
              canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.preparePushRetirement()
    }
    @discardableResult
    func confirmAccountRecoveryPush(_ flow: RecoveryFlow,
        confirmation: ReaderAccountDeletionCoordinator.PushConfirmation,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.confirmPushRetirement(confirmation)
    }
    @discardableResult
    func retryAccountRecoveryPush(_ flow: RecoveryFlow,
        configuration: ReaderDeletionHTTPTransport.Configuration?, userConfirmed: Bool) -> Bool {
        guard userConfirmed, canUseAccountRecoveryFlow(flow, configuration: configuration) else { return false }
        return flow.coordinator.retryPushRetirement(userConfirmed: true)
    }
    func cancelAccountRecoveryPush(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancelPushRetirement()
    }
    func cancelAccountRecovery(_ flow: RecoveryFlow) {
        guard ownsRecoveryFlow(flow) else { return }
        flow.coordinator.cancel()
    }

    private func scheduleRecoveryPresentation() {
        guard !recoveryPresentationScheduled else { return }
        recoveryPresentationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.recoveryPresentationScheduled = false
            self.objectWillChange.send()
        }
    }
    var session: ReaderAccountSession? { state.snapshot.session }
    var verificationMessage: String? { state.snapshot.verificationMessage }
    var readerAccountActions: ReaderAccountActions {
        ReaderAccountActions(canonical: state, preferences: ReaderPreferencesService.shared.model,
            verify: { [weak self] in await self?.sendVerification(context: $0) },
            refresh: { [weak self] in try await self?.refreshSession(context: $0) })
    }
    private var observation: AnyCancellable?
    private var authListener: AuthStateDidChangeListenerHandle?
    private let canonicalPublication = CanonicalAccountPublication()
    private let disabled: Bool
    private lazy var operations = AuthOperationCoordinator(canonical: state, actualUserID: {
        Auth.auth().currentUser?.uid
    }, reauthenticationIdentity: bootstrapIdentity)

    /// Held-user reauthentication is distinct from login and token refresh. This
    /// adapter stays inert until a separately confirmed deletion action calls it.
    private lazy var readerReauthentication = makeReaderReauthentication(canonical: state)
    private lazy var resumedReaderReauthentication = makeReaderReauthentication(canonical: bootstrapIdentity)
    private func makeReaderReauthentication(canonical: CanonicalSessionState) -> ReaderAccountReauthentication<AuthCredential> {
        ReaderAccountReauthentication<AuthCredential>(
        canonical: canonical, operations: operations, captureUser: { [weak self] in
            guard let self, !self.disabled, let app = FirebaseApp.app() else { return nil }
            let provider = Auth.auth(app: app)
            guard let user = provider.currentUser else { return nil }
            return .init(uid: user.uid, isCurrent: { [weak self] in
                self?.disabled == false && provider.currentUser === user
            }, reauthenticate: { credential, stillCurrent in
                guard stillCurrent(), provider.currentUser === user else { throw CancellationError() }
                // The pinned SDK's async wrapper prefers result over error even
                // when the callback contains both. A mismatch must fail closed.
                let result: AuthDataResult = try await withCheckedThrowingContinuation { continuation in
                    user.reauthenticate(with: credential) { result, error in
                        continuation.resume(with: ReaderReauthenticationCallback.result(result, error: error))
                    }
                }
                guard stillCurrent(), provider.currentUser === user,
                      result.user.uid == user.uid else { throw CancellationError() }
                let token: AuthTokenResult = try await withCheckedThrowingContinuation { continuation in
                    user.getIDTokenResult(forcingRefresh: false) { result, error in
                        continuation.resume(with: ReaderReauthenticationCallback.result(result, error: error))
                    }
                }
                guard stillCurrent(), provider.currentUser === user,
                      token.claims["sub"] as? String == user.uid else { throw CancellationError() }
                let authTimeMs = token.authDate.timeIntervalSince1970 * 1_000
                guard authTimeMs.isFinite, authTimeMs >= 1,
                      authTimeMs <= Double(ReaderAccountDeletionContract.maximumSafeInteger) else {
                    throw ReaderReauthenticationCallback.MissingResult()
                }
                return .init(uid: user.uid, authTimeMs: Int64(authTimeMs))
            }, deletionCredentials: { proof, stillCurrent in
                guard stillCurrent(), !Task.isCancelled, provider.currentUser === user,
                      proof.authenticatedUID == user.uid,
                      let project = app.options.projectID else { throw CancellationError() }
                let token: AuthTokenResult = try await withCheckedThrowingContinuation { continuation in
                    user.getIDTokenResult(forcingRefresh: true) { result, error in
                        continuation.resume(with: ReaderReauthenticationCallback.result(result, error: error))
                    }
                }
                guard stillCurrent(), !Task.isCancelled, provider.currentUser === user,
                      token.claims["sub"] as? String == user.uid,
                      token.claims["aud"] as? String == project,
                      token.claims["iss"] as? String == "https://securetoken.google.com/" + project,
                      (token.claims["firebase"] as? [String: Any])?["tenant"] == nil,
                      Self.startupMilliseconds(token.authDate) == proof.authTimeMs else { throw CancellationError() }
                guard let checkProvider = AppCheck.appCheck(app: app), stillCurrent(),
                      provider.currentUser === user else { throw CancellationError() }
                let check = try await checkProvider.limitedUseToken()
                guard stillCurrent(), !Task.isCancelled, provider.currentUser === user else { throw CancellationError() }
                return .init(ownerUID: user.uid, projectID: project, appID: app.options.googleAppID,
                    idToken: token.token, appCheckToken: check.token, authTimeMs: Self.startupMilliseconds(token.authDate),
                    authValidUntilMs: Self.startupMilliseconds(token.expirationDate),
                    appCheckValidUntilMs: Self.startupMilliseconds(check.expirationDate))
            }, email: user.email, supportsPassword: user.providerData.contains { $0.providerID == "password" },
                appleSubject: user.providerData.first { $0.providerID == "apple.com" }?.uid,
                googleSubject: user.providerData.first { $0.providerID == "google.com" }?.uid)
        })
    }

    /// The credential provider must complete a new user challenge for this
    /// action (Apple/Google or password). It must never call Firebase signIn.
    /// No screen/endpoint is connected until reader membership and deletion
    /// scopes have separately passed their activation gates.
    func reauthenticateReaderAccount(
        action: ReaderAccountDeletionCoordinator.ActionTicket,
        obtainCredential: @MainActor (ReaderAccountDeletionCoordinator.ActionTicket) async throws -> AuthCredential
    ) async throws -> ReaderAccountDeletionCoordinator.ReauthenticationResult {
        guard !disabled else { throw CancellationError() }
        return try await readerReauthentication.reauthenticate(action: action, obtainCredential: obtainCredential)
    }

    /// Existing coordinator + actual reauth helper + explicit HTTP transport.
    /// Injected effects keep this composition hermetic without any SDK setup.
    func makeReaderAccountDeletion<Credential>(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        reauthentication: ReaderAccountReauthentication<Credential>,
        obtainCredential: @escaping @MainActor (ReaderAccountDeletionCoordinator.ActionTicket) async throws -> Credential,
        obtainHeldCredential: (@MainActor (ReaderAccountDeletionCoordinator.ActionTicket,
            ReaderAccountReauthentication<Credential>.HeldUser, @escaping @MainActor () -> Bool) async throws -> Credential)? = nil,
        reauthenticationFinished: (@MainActor (ReaderAccountDeletionCoordinator.ActionTicket, Error?) -> Void)? = nil,
        execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
        now: @escaping @MainActor () -> Int64,
        scheduleTimeout: ReaderAccountDeletionCoordinator.TimeoutScheduler? = nil,
        writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier? = nil,
        resumingAfterRestart: Bool = false,
        localJournalFactory: ReaderAccountDeletionCoordinator.LocalJournalFactory? = nil,
        localResumeStore: ReaderResumeStore? = nil,
        localPodcastStore: PodcastPlaybackProgressStore? = nil,
        localIntroductionModel: ReaderIntroductionModel? = nil,
        localHistoryModel: ReadingHistoryModel? = nil,
        pushInstallationVault: PushInstallationVault? = nil
    ) -> ReaderAccountDeletionCoordinator? {
        typealias Model = ReaderAccountDeletionCoordinator
        guard let configuration, readerDeletionCoordinator?.hasPhysicalFlight != true,
              readerDeletionCoordinator?.hasWriteBarrier != true else { return nil }
        let account = resumingAfterRestart ? bootstrapIdentity : state
        let digest = ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: configuration.projectID,
            appID: configuration.appID, endpoint: configuration.endpointURL)
        let resumption: Model.Resumption?
        if resumingAfterRestart {
            guard writeBarrier == nil, let recovery = startup.localRecovery,
                  startup.permitsAuthOnlyDeletionRecovery(recovery),
                  let checkpoint = recovery.deletionCheckpoint,
                  checkpoint.configurationDigest == digest,
                  recovery.hasVerifiedSeal(binding: checkpoint.marker.binding),
                  account.snapshot.session?.uid == checkpoint.request.expectedUID else { return nil }
            let original = account.contextTicket()
            resumption = .init(context: original, recovery: recovery, checkpoint: checkpoint,
                stillClosed: { [weak self, weak recovery] in
                    guard let self, let recovery else { return false }
                    return self.startup.permitsAuthOnlyDeletionRecovery(recovery)
                        && self.bootstrapIdentity.isCurrent(original)
                })
        } else {
            guard writeBarrier != nil, currentMembershipEpoch != nil else { return nil }
            resumption = nil
        }
        let composition = UUID()
        readerDeletionComposition = composition
        readerDeletionCoordinator?.cancel()
        guard readerDeletionComposition == composition, readerDeletionCoordinator?.hasPhysicalFlight != true,
              readerDeletionCoordinator?.hasWriteBarrier != true else { return nil }
        weak var owner: Model?
        var prepared: (proof: Model.ReauthenticationResult, transport: ReaderDeletionHTTPTransport,
                       stillCurrent: @MainActor () -> Bool, originalUserIsCurrent: @MainActor () -> Bool)?
        // Independent of the active action: explicit pre-submission abort must
        // still verify the original SDK object after logical cancellation.
        let originalUserCurrent: @MainActor (Model.ActionTicket, ReaderAccountReauthentication<Credential>.HeldUser) -> Bool = { [weak self] action, user in
            guard let self, let model = owner, self.readerDeletionComposition == composition,
                  self.readerDeletionCoordinator === model, account.isCurrent(action.context) else { return false }
            let held = user.isCurrent()
            return held && self.readerDeletionComposition == composition
                && self.readerDeletionCoordinator === model && account.isCurrent(action.context)
        }
        let current: @MainActor (Model.ActionTicket, ReaderAccountReauthentication<Credential>.HeldUser) -> Bool = { [weak self] action, user in
            guard let self, let model = owner, self.readerDeletionCoordinator === model,
                  account.isCurrent(action.context), model.permitsTransport(action: action) else { return false }
            let held = user.isCurrent()
            return held && self.readerDeletionCoordinator === model && account.isCurrent(action.context)
                && model.retainsTransport(action: action)
        }
        let take: @MainActor (Model.ReauthenticationResult) async throws -> ReaderDeletionHTTPTransport = { proof in
            guard let original = prepared, original.proof == proof, let model = owner else { throw CancellationError() }
            prepared = nil // Consume before any identity, journal, drain or credential hook.
            guard original.stillCurrent() else { throw CancellationError() }
            try await model.prepareWritesForDeletion(action: proof.action, stillCurrent: original.stillCurrent,
                                                     originalUserIsCurrent: original.originalUserIsCurrent)
            guard original.stillCurrent(), !Task.isCancelled else { throw CancellationError() }
            return original.transport
        }
        let coordinator = Model(canonical: account, currentMembershipEpoch: resumingAfterRestart ? nil : currentMembershipEpoch,
            reauthenticate: { [weak self] action in
                prepared = nil
                guard let self, let model = owner, self.readerDeletionCoordinator === model,
                      model.permitsTransport(action: action), self.readerDeletionCoordinator === model,
                      account.isCurrent(action.context) else { throw CancellationError() }
                var didFinishProvider = false
                let finishProvider: (Error?) -> Void = { error in
                    guard !didFinishProvider else { return }
                    didFinishProvider = true
                    reauthenticationFinished?(action, error)
                }
                do {
                    let held = try await reauthentication.reauthenticateHoldingUser(action: action,
                        obtainCredentialForUser: { action, user in
                            guard current(action, user) else { throw CancellationError() }
                            if let obtainHeldCredential {
                                return try await obtainHeldCredential(action, user, { current(action, user) })
                            }
                            return try await obtainCredential(action)
                        })
                    guard current(action, held.user), let credentials = held.user.deletionCredentials else { throw CancellationError() }
                    finishProvider(nil)
                    guard current(action, held.user), !Task.isCancelled else { throw CancellationError() }
                    let validateOriginal: (@MainActor () async throws -> Void)?
                    if action.phase == .pushPreparation || action.phase == .pushRetirement {
                        validateOriginal = {
                            guard current(action, held.user) else { throw CancellationError() }
                            try await model.validatePushStorage(action: action)
                            guard current(action, held.user) else { throw CancellationError() }
                        }
                    } else { validateOriginal = nil }
                    let transport = ReaderDeletionHTTPTransport(configuration: configuration, action: action, proof: held.proof,
                        credentials: { admitted in try await credentials(held.proof, admitted) },
                        isCurrent: { current(action, held.user) }, execute: execute, now: now,
                        validateOriginal: validateOriginal)
                    prepared = (held.proof, transport, { current(action, held.user) },
                                { originalUserCurrent(action, held.user) })
                    return held.proof
                } catch {
                    finishProvider(error)
                    throw error
                }
            }, send: { request, proof in
                let transport = try await take(proof)
                return try await transport.send(request)
            }, sendLedger: { request, proof in
                let transport = try await take(proof)
                return try await transport.sendLedger(request)
            }, sendPushPreparation: { request, proof in
                let transport = try await take(proof)
                return try await transport.sendPushPreparation(request)
            }, sendPushRetirement: { request, proof in
                let transport = try await take(proof)
                return try await transport.sendPushRetirement(request)
            }, pushInstallationVault: pushInstallationVault, pushAppID: configuration.appID, writeBarrier: writeBarrier, resumption: resumption, configurationDigest: digest,
            localJournalFactory: localJournalFactory ?? { FavoritesRuntime.makeJournalForClosedRecovery() },
            localResumeStore: localResumeStore, localPodcastStore: localPodcastStore, localIntroductionModel: localIntroductionModel, localHistoryModel: localHistoryModel,
            nowMilliseconds: now, scheduleTimeout: scheduleTimeout ?? Model.deadline)
        owner = coordinator
        readerDeletionCoordinator = coordinator
        return coordinator
    }

    /// The same provider form used by the configured SDK adapter and local
    /// integration fixture. It returns no session and cannot call signIn.
    func makeEmailReaderAccountDeletion<Credential>(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        reauthentication: ReaderAccountReauthentication<Credential>,
        prompt: ReaderEmailReauthenticationPrompt,
        makeCredential: @escaping @MainActor (String, String) throws -> Credential,
        execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
        now: @escaping @MainActor () -> Int64,
        scheduleTimeout: ReaderAccountDeletionCoordinator.TimeoutScheduler? = nil,
        writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier? = nil,
        resumingAfterRestart: Bool = false,
        localJournalFactory: ReaderAccountDeletionCoordinator.LocalJournalFactory? = nil,
        localResumeStore: ReaderResumeStore? = nil,
        localPodcastStore: PodcastPlaybackProgressStore? = nil,
        localIntroductionModel: ReaderIntroductionModel? = nil,
        localHistoryModel: ReadingHistoryModel? = nil,
        pushInstallationVault: PushInstallationVault? = nil
    ) -> ReaderAccountDeletionCoordinator? {
        let account = resumingAfterRestart ? bootstrapIdentity : state
        weak var owner: ReaderAccountDeletionCoordinator?
        let coordinator = makeReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: currentMembershipEpoch, reauthentication: reauthentication,
            obtainCredential: { _ in throw CancellationError() },
            obtainHeldCredential: { [weak self] action, user, current in
                guard user.supportsPassword, let email = user.email,
                      EmailAccountForm(email: email).validationMessage(for: .resetPassword) == nil,
                      current() else { throw CancellationError() }
                let password = try await prompt.request(action: action, email: email, isCurrent: current,
                    onCancel: { [weak self] in
                        guard let self, let owner, self.readerDeletionCoordinator === owner,
                              owner.retainsTransport(action: action) else { return }
                        owner.cancel()
                    }, onRetry: { [weak self] in
                        guard let self, let owner, self.readerDeletionCoordinator === owner,
                              account.isCurrent(action.context) else { return false }
                        return owner.retry(userConfirmed: true)
                    })
                guard current(), !Task.isCancelled else { throw CancellationError() }
                let credential = try makeCredential(email, password)
                guard current(), !Task.isCancelled else { throw CancellationError() }
                return credential
            }, reauthenticationFinished: { action, error in prompt.complete(action: action, error: error) },
            execute: execute, now: now, scheduleTimeout: scheduleTimeout, writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localJournalFactory: localJournalFactory, localResumeStore: localResumeStore, localPodcastStore: localPodcastStore, localIntroductionModel: localIntroductionModel, localHistoryModel: localHistoryModel, pushInstallationVault: pushInstallationVault)
        owner = coordinator
        return coordinator
    }

    /// The Apple provider returns only a credential. The same held SDK user
    /// must then reauthenticate; this path never calls signIn or publishes a session.
    func makeAppleReaderAccountDeletion<Credential>(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        reauthentication: ReaderAccountReauthentication<Credential>,
        prompt: ReaderAppleReauthenticationPrompt,
        makeCredential: @escaping @MainActor (String, String) throws -> Credential,
        execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
        now: @escaping @MainActor () -> Int64,
        scheduleTimeout: ReaderAccountDeletionCoordinator.TimeoutScheduler? = nil,
        writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier? = nil,
        resumingAfterRestart: Bool = false,
        localJournalFactory: ReaderAccountDeletionCoordinator.LocalJournalFactory? = nil,
        localResumeStore: ReaderResumeStore? = nil,
        localPodcastStore: PodcastPlaybackProgressStore? = nil,
        localIntroductionModel: ReaderIntroductionModel? = nil,
        localHistoryModel: ReadingHistoryModel? = nil,
        pushInstallationVault: PushInstallationVault? = nil
    ) -> ReaderAccountDeletionCoordinator? {
        weak var owner: ReaderAccountDeletionCoordinator?
        let coordinator = makeReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: currentMembershipEpoch, reauthentication: reauthentication,
            obtainCredential: { _ in throw CancellationError() },
            obtainHeldCredential: { [weak self] action, user, current in
                guard let subject = user.appleSubject, !subject.isEmpty, current() else { throw CancellationError() }
                let value = try await prompt.request(action: action, expectedAppleUserID: subject, isCurrent: current,
                    onCancel: { [weak self] in
                        guard let self, let owner, self.readerDeletionCoordinator === owner,
                              owner.retainsTransport(action: action) else { return }
                        owner.cancel()
                    })
                guard current(), !Task.isCancelled else { throw CancellationError() }
                let credential = try makeCredential(value.idToken, value.rawNonce)
                guard current(), !Task.isCancelled else { throw CancellationError() }
                return credential
            }, reauthenticationFinished: { action, error in prompt.complete(action: action, error: error) },
            execute: execute, now: now, scheduleTimeout: scheduleTimeout, writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localJournalFactory: localJournalFactory, localResumeStore: localResumeStore, localPodcastStore: localPodcastStore, localIntroductionModel: localIntroductionModel, localHistoryModel: localHistoryModel, pushInstallationVault: pushInstallationVault)
        owner = coordinator
        return coordinator
    }

    /// Explicitly configured only; no screen enables reader deletion yet.
    func configureAppleReaderAccountDeletion(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        prompt: ReaderAppleReauthenticationPrompt,
        resumingAfterRestart: Bool = false
    ) -> ReaderAccountDeletionCoordinator? {
        guard !disabled, let configuration, let app = FirebaseApp.app(),
              app.options.projectID == configuration.projectID, app.options.googleAppID == configuration.appID,
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.endpointURL]) else { return nil }
        let writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier?
        if resumingAfterRestart {
            // Cold Auth-only recovery must not construct a journal or start the
            // persistent SDK. The shared factory validates its original seal.
            writeBarrier = nil
        } else {
            guard currentMembershipEpoch != nil, let existing = existingReaderDeletionWriteBarrier() else { return nil }
            writeBarrier = existing
        }
        return makeAppleReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: resumingAfterRestart ? nil : currentMembershipEpoch,
            reauthentication: resumingAfterRestart ? resumedReaderReauthentication : readerReauthentication, prompt: prompt,
            makeCredential: { OAuthProvider.appleCredential(withIDToken: $0, rawNonce: $1, fullName: nil) },
            execute: { try await executor.performAwaitingPhysicalCompletion($0) }, now: { Self.startupMilliseconds(Date()) },
            writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localResumeStore: ReaderResumeRuntime.applicationStore,
            localPodcastStore: PodcastProgressRuntime.shared.localCleanupStore(),
            localIntroductionModel: ReaderIntroductionRuntime.localCleanupModel(),
            localHistoryModel: ReadingHistoryRuntime.localCleanupModel(),
            pushInstallationVault: PushInstallationVault(store: PushInstallationKeychainStore()))
    }

    /// Google returns only a credential for the same held Firebase user.
    /// No Firebase signIn or new app session is published. Interactive Google
    /// authorization still updates the provider SDK's own account/keychain.
    func makeGoogleReaderAccountDeletion<Credential>(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        reauthentication: ReaderAccountReauthentication<Credential>,
        prompt: ReaderGoogleReauthenticationPrompt,
        makeCredential: @escaping @MainActor (String, String) throws -> Credential,
        execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
        now: @escaping @MainActor () -> Int64,
        scheduleTimeout: ReaderAccountDeletionCoordinator.TimeoutScheduler? = nil,
        writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier? = nil,
        resumingAfterRestart: Bool = false,
        localJournalFactory: ReaderAccountDeletionCoordinator.LocalJournalFactory? = nil,
        localResumeStore: ReaderResumeStore? = nil,
        localPodcastStore: PodcastPlaybackProgressStore? = nil,
        localIntroductionModel: ReaderIntroductionModel? = nil,
        localHistoryModel: ReadingHistoryModel? = nil,
        pushInstallationVault: PushInstallationVault? = nil
    ) -> ReaderAccountDeletionCoordinator? {
        weak var owner: ReaderAccountDeletionCoordinator?
        let coordinator = makeReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: currentMembershipEpoch, reauthentication: reauthentication,
            obtainCredential: { _ in throw CancellationError() },
            obtainHeldCredential: { [weak self] action, user, current in
                guard let subject = user.googleSubject, !subject.isEmpty, current() else { throw CancellationError() }
                let value = try await prompt.request(action: action, expectedGoogleUserID: subject, isCurrent: current,
                    onCancel: { [weak self] in
                        guard let self, let owner, self.readerDeletionCoordinator === owner,
                              owner.retainsTransport(action: action) else { return }
                        owner.cancel()
                    })
                guard current(), !Task.isCancelled else { throw CancellationError() }
                let credential = try makeCredential(value.idToken, value.accessToken)
                guard current(), !Task.isCancelled else { throw CancellationError() }
                return credential
            }, reauthenticationFinished: { action, error in prompt.complete(action: action, error: error) },
            execute: execute, now: now, scheduleTimeout: scheduleTimeout, writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localJournalFactory: localJournalFactory, localResumeStore: localResumeStore, localPodcastStore: localPodcastStore, localIntroductionModel: localIntroductionModel, localHistoryModel: localHistoryModel, pushInstallationVault: pushInstallationVault)
        owner = coordinator
        return coordinator
    }

    /// Explicitly configured only; no screen enables reader deletion yet.
    func configureGoogleReaderAccountDeletion(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        prompt: ReaderGoogleReauthenticationPrompt,
        resumingAfterRestart: Bool = false
    ) -> ReaderAccountDeletionCoordinator? {
        guard !disabled, let configuration, let app = FirebaseApp.app(),
              app.options.projectID == configuration.projectID, app.options.googleAppID == configuration.appID,
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.endpointURL]) else { return nil }
        let writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier?
        if resumingAfterRestart {
            // Cold Auth-only recovery must not construct a journal or start the
            // persistent SDK. The shared factory validates its original seal.
            writeBarrier = nil
        } else {
            guard currentMembershipEpoch != nil, let existing = existingReaderDeletionWriteBarrier() else { return nil }
            writeBarrier = existing
        }
        return makeGoogleReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: resumingAfterRestart ? nil : currentMembershipEpoch,
            reauthentication: resumingAfterRestart ? resumedReaderReauthentication : readerReauthentication, prompt: prompt,
            makeCredential: { GoogleAuthProvider.credential(withIDToken: $0, accessToken: $1) },
            execute: { try await executor.performAwaitingPhysicalCompletion($0) }, now: { Self.startupMilliseconds(Date()) },
            writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localResumeStore: ReaderResumeRuntime.applicationStore,
            localPodcastStore: PodcastProgressRuntime.shared.localCleanupStore(),
            localIntroductionModel: ReaderIntroductionRuntime.localCleanupModel(),
            localHistoryModel: ReadingHistoryRuntime.localCleanupModel(),
            pushInstallationVault: PushInstallationVault(store: PushInstallationKeychainStore()))
    }

    /// Explicitly configured only; no screen enables reader deletion yet.
    func configureEmailReaderAccountDeletion(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: ReaderAccountDeletionCoordinator.EpochReader? = nil,
        prompt: ReaderEmailReauthenticationPrompt,
        resumingAfterRestart: Bool = false
    ) -> ReaderAccountDeletionCoordinator? {
        guard !disabled, let configuration, let app = FirebaseApp.app(),
              app.options.projectID == configuration.projectID, app.options.googleAppID == configuration.appID,
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.endpointURL]) else { return nil }
        let writeBarrier: ReaderAccountDeletionCoordinator.WriteBarrier?
        if resumingAfterRestart {
            // Cold Auth-only recovery must not construct a journal or start the
            // persistent SDK. The shared factory validates its original seal.
            writeBarrier = nil
        } else {
            guard currentMembershipEpoch != nil, let existing = existingReaderDeletionWriteBarrier() else { return nil }
            writeBarrier = existing
        }
        return makeEmailReaderAccountDeletion(configuration: configuration,
            currentMembershipEpoch: resumingAfterRestart ? nil : currentMembershipEpoch,
            reauthentication: resumingAfterRestart ? resumedReaderReauthentication : readerReauthentication, prompt: prompt,
            makeCredential: { EmailAuthProvider.credential(withEmail: $0, password: $1) },
            execute: { try await executor.performAwaitingPhysicalCompletion($0) }, now: { Self.startupMilliseconds(Date()) },
            writeBarrier: writeBarrier, resumingAfterRestart: resumingAfterRestart,
            localResumeStore: ReaderResumeRuntime.applicationStore,
            localPodcastStore: PodcastProgressRuntime.shared.localCleanupStore(),
            localIntroductionModel: ReaderIntroductionRuntime.localCleanupModel(),
            localHistoryModel: ReadingHistoryRuntime.localCleanupModel(),
            pushInstallationVault: PushInstallationVault(store: PushInstallationKeychainStore()))
    }

    /// No current screen calls this adapter. Missing configuration is inert;
    /// unit/smoke execution cannot reach Auth/App Check or URLSession here.
    func configureReaderAccountDeletion(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        currentMembershipEpoch: @escaping ReaderAccountDeletionCoordinator.EpochReader,
        obtainCredential: @escaping @MainActor (ReaderAccountDeletionCoordinator.ActionTicket) async throws -> AuthCredential
    ) -> ReaderAccountDeletionCoordinator? {
        guard !disabled, let configuration, let app = FirebaseApp.app(),
              app.options.projectID == configuration.projectID, app.options.googleAppID == configuration.appID,
              let writeBarrier = existingReaderDeletionWriteBarrier(),
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.endpointURL]) else { return nil }
        return makeReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: currentMembershipEpoch,
            reauthentication: readerReauthentication, obtainCredential: obtainCredential,
            execute: { try await executor.performAwaitingPhysicalCompletion($0) }, now: { Self.startupMilliseconds(Date()) },
            writeBarrier: writeBarrier, pushInstallationVault: PushInstallationVault(store: PushInstallationKeychainStore()))
    }

    /// Explicit Auth-only restart composition. No current screen activates it.
    /// The existing provider adapter must obtain a fresh credential for this
    /// bootstrapIdentity action; SDK/profile/journal preparation stays closed.
    func configureResumedReaderAccountDeletion(
        configuration: ReaderDeletionHTTPTransport.Configuration?,
        obtainCredential: @escaping @MainActor (ReaderAccountDeletionCoordinator.ActionTicket) async throws -> AuthCredential
    ) -> ReaderAccountDeletionCoordinator? {
        guard !disabled, let configuration, let app = FirebaseApp.app(),
              app.options.projectID == configuration.projectID, app.options.googleAppID == configuration.appID,
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.endpointURL]) else { return nil }
        return makeReaderAccountDeletion(configuration: configuration,
            reauthentication: resumedReaderReauthentication, obtainCredential: obtainCredential,
            execute: { try await executor.performAwaitingPhysicalCompletion($0) },
            now: { Self.startupMilliseconds(Date()) }, resumingAfterRestart: true,
            pushInstallationVault: PushInstallationVault(store: PushInstallationKeychainStore()))
    }

    private func existingReaderDeletionWriteBarrier() -> ReaderAccountDeletionCoordinator.WriteBarrier? {
        guard !disabled else { return nil }
        let original = state.contextTicket()
        guard let journal = FavoritesRuntime.existingJournalForTransition(context: original),
              state.isCurrent(original) else { return nil }
        let writers = ReaderWriterDrainRuntime.shared
        guard state.isCurrent(original) else { return nil }
        return .init(writers: writers, journal: journal, recovery: .application,
                     resumeStore: ReaderResumeRuntime.applicationStore, podcastStore: PodcastProgressRuntime.shared.localCleanupStore())
    }

    func captureLogin(_ kind: AuthOperationCoordinator.Kind, newsletterOptIn: Bool = false) throws -> AuthOperationCoordinator.Ticket {
        guard !disabled else { throw CancellationError() }
        return try operations.capture(kind, newsletterOptIn: newsletterOptIn)
    }
    func cancelLogin(_ ticket: AuthOperationCoordinator.Ticket) { guard !disabled else { return }; operations.cancel(ticket) }
    func loginFeedbackIsCurrent(_ ticket: AuthOperationCoordinator.Ticket) -> Bool {
        !disabled && operations.canPublishFeedback(ticket)
    }
    func acceptedLoginResult(_ ticket: AuthOperationCoordinator.Ticket,
                             session: ReaderAccountSession) -> ReaderLoginResult? {
        guard !disabled else { return nil }
        return operations.acceptedLoginResult(ticket, session: session)
    }
    func beginLoginProvider(_ ticket: AuthOperationCoordinator.Ticket) throws {
        guard !disabled else { throw CancellationError() }; try operations.beginProvider(ticket)
    }
    func loginProviderReturned(_ ticket: AuthOperationCoordinator.Ticket) throws {
        guard !disabled else { throw CancellationError() }; try operations.providerReturned(ticket)
    }
    func loginProviderFailed(_ ticket: AuthOperationCoordinator.Ticket) -> Bool {
        !disabled && operations.providerFailed(ticket)
    }
    func loginProvider<Value>(_ ticket: AuthOperationCoordinator.Ticket, perform: () async throws -> Value) async throws -> Value {
        guard !disabled else { throw CancellationError() }; return try await operations.provider(ticket, perform: perform)
    }
    private lazy var verification = ReaderAccountVerificationCoordinator(state: state, effects: .init(
        actualUserID: { Auth.auth().currentUser?.uid },
        send: { [weak self] ticket, stillCurrent in
            guard stillCurrent(), let user = Auth.auth().currentUser,
                  user.uid == ticket.userID, stillCurrent() else { throw CancellationError() }
            if user.isEmailVerified {
                _ = self?.state.adopt(Self.project(user), stillPermitted: stillCurrent)
                return
            }
            guard stillCurrent() else { throw CancellationError() }
            try await user.sendEmailVerification()
        }, refresh: { ticket, stillCurrent in
            guard stillCurrent(), let user = Auth.auth().currentUser,
                  user.uid == ticket.userID, stillCurrent() else { throw CancellationError() }
            try await user.reload()
            guard stillCurrent() else { throw CancellationError() }
            _ = try await user.getIDToken(forcingRefresh: true)
            guard stillCurrent() else { throw CancellationError() }
            return Self.project(user)
        }))

    init(startup: ReaderSDKStartupState? = nil) {
        self.startup = startup ?? .application
        disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
        observation = state.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        bootstrapIdentity.changes.sink { [weak self] _ in self?.scheduleRecoveryPresentation() }
            .store(in: &recoveryPresentationObservations)
        self.startup.localRecovery?.presentationChanges.sink { [weak self] in self?.scheduleRecoveryPresentation() }
            .store(in: &recoveryPresentationObservations)
    }

    func startObservingSession() {
        guard !disabled, authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.publishCanonicalSession(user) }
        }
        // Initial synchronous nil is unresolved; only the canonical callback
        // confirms a guest. A nonnil restored provider can publish immediately.
        if let current = Auth.auth().currentUser { publishCanonicalSession(current) }
    }

    @discardableResult
    func publishCanonicalSession(_ user: User?) -> CanonicalSessionState.ContextTicket? {
        publishCanonicalSession(user, restoringSuspension: nil)
    }

    private func publishCanonicalSession(_ user: User?, restoringSuspension: CanonicalSessionState.ContextTicket?) -> CanonicalSessionState.ContextTicket? {
        guard !disabled else { return nil }
        let original = user.map(Self.project)
        return observeIdentity(original, currentUserID: { Auth.auth().currentUser?.uid },
            revokeReader: { [weak self] in self?.suspendReaderProjection(stillCurrent: $0) ?? false }) { [weak self] permission in
            self?.publishReaderSession(user, restoringSuspension: restoringSuspension, permission: permission)
        }
    }

    /// Shared by the real Firebase ingress and service-free integration tests.
    /// Keep the held provider/profile closure; never reacquire today's account
    /// when a delayed startup decision releases this observation.
    @discardableResult
    func observeIdentity(_ original: ReaderAccountSession?, currentUserID: @escaping () -> String?,
                         revokeReader: @escaping (@escaping () -> Bool) -> Bool,
                         publishReader: @escaping (@escaping () -> Bool) -> CanonicalSessionState.ContextTicket?) -> CanonicalSessionState.ContextTicket? {
        // Reject stale provider callbacks before replacing an accepted pending
        // observation. The getter may reenter, so compare after reading it.
        let previousIngress = identityIngress
        let actual = currentUserID()
        guard identityIngress == previousIngress, actual == original?.uid else { return nil }
        let ingress = UUID(); identityIngress = ingress
        let stillCurrent = { [self] in
            let actual = currentUserID()
            return identityIngress == ingress && actual == original?.uid
        }
        var context: CanonicalSessionState.ContextTicket?
        var revoked = true
        let completed = identityPublication.perform(expectedUserID: original?.uid, currentUserID: currentUserID, steps: [
            { self.pendingReaderPublication = nil },
            {
                if (self.startup.requiresGuardedStartup || self.startup.localRecovery != nil) && self.state.snapshot.context != .unresolved &&
                   (self.state.snapshot.session != original || !self.startup.permitsReaderServices(identity: self.bootstrapIdentity)) {
                    revoked = revokeReader(stillCurrent)
                }
            },
            { context = self.bootstrapIdentity.adopt(original) }
        ], permission: { revoked && self.identityIngress == ingress })
        guard completed, let context, bootstrapIdentity.isCurrent(context),
              bootstrapIdentity.snapshot.session == original else { return nil }
        let pending = PendingReaderPublication(id: UUID(), ingress: ingress, context: context, original: original,
            currentUserID: currentUserID, publish: publishReader)
        pendingReaderPublication = pending
        return releaseReaderSession(context: context)
    }

    /// Release the held Auth observation, not a newly acquired provider user.
    /// No canonical logout is synthesized when the local marker later closes.
    @discardableResult
    func resumeReaderAfterLocalRecovery() -> Bool {
        guard let pending = pendingReaderPublication else { return false }
        return releaseReaderSession(context: pending.context) != nil
    }

    @discardableResult
    func releaseReaderSession(context: CanonicalSessionState.ContextTicket,
                              stillPermitted: @escaping () -> Bool = { true }) -> CanonicalSessionState.ContextTicket? {
        guard let pending = pendingReaderPublication, pending.context == context else { return nil }
        guard stillPermitted() else { return nil }
        let actual = pending.currentUserID() // May synchronously reenter.
        guard pendingReaderPublication?.id == pending.id,
              actual == pending.original?.uid, bootstrapIdentity.isCurrent(context),
              bootstrapIdentity.snapshot.session == pending.original,
              startup.permitsReaderPublication(identity: bootstrapIdentity) else { return nil }
        pendingReaderPublication = nil // Consume before arbitrary observer effects.
        let permission: () -> Bool = { [self] in
            guard stillPermitted() else { return false }
            let actual = pending.currentUserID()
            return identityIngress == pending.ingress && actual == pending.original?.uid
                && bootstrapIdentity.isCurrent(context) && bootstrapIdentity.snapshot.session == pending.original
                && startup.permitsReaderPublication(identity: bootstrapIdentity)
        }
        guard permission(), let released = pending.publish(permission) else { return nil }
        guard stillPermitted() else { return nil }
        let finalActual = pending.currentUserID()
        guard identityIngress == pending.ingress, finalActual == pending.original?.uid, bootstrapIdentity.isCurrent(context),
              bootstrapIdentity.snapshot.session == pending.original, state.isCurrent(released),
              state.snapshot.session == pending.original,
              startup.permitsReaderPublication(identity: bootstrapIdentity) else { return nil }
        return released
    }

    /// Explicit composition of the existing startup boundary. No application
    /// caller or default configuration enables guarded startup. The original
    /// pending provider publication is consumed only after actual start success.
    func startReaderSession(
        context: CanonicalSessionState.ContextTicket,
        configuration: ReaderStartupHTTPTransport.Configuration?,
        credentials: @escaping @MainActor (CanonicalSessionState.ContextTicket) async throws -> ReaderStartupHTTPTransport.Credentials,
        execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
        readMarker: @escaping @MainActor () async throws -> ReaderStartupCoordinator.Marker?,
        startSDK: @escaping @MainActor (ReaderStartupCoordinator.Receipt, @escaping ReaderStartupCoordinator.StartAdmission) async throws -> Void,
        now: @escaping @MainActor () -> Int64,
        schedule: ReaderStartupCoordinator.Schedule? = nil,
        providerIsCurrent: @escaping @MainActor () -> Bool = { true }
    ) async throws -> CanonicalSessionState.ContextTicket {
        typealias Failure = ReaderStartupCoordinator.Failure
        guard startup.requiresGuardedStartup, let configuration,
              let pending = pendingReaderPublication, pending.context == context,
              context.userID != nil else { throw Failure.unavailable }
        guard readerStartupCoordinator?.isBusy != true else { throw Failure.busy }
        var denied = false
        let identityCurrent: @MainActor () -> Bool = { [weak self] in
            guard !denied, let self else { return false }
            // Both hooks may reenter. All local ownership checks follow them.
            let providerCurrent = providerIsCurrent()
            let actual = pending.currentUserID()
            let accepted = providerCurrent && !denied
                && self.identityIngress == pending.ingress && self.bootstrapIdentity.isCurrent(context)
                && self.bootstrapIdentity.snapshot.session == pending.original && actual == pending.original?.uid
            if !accepted { denied = true }
            return accepted
        }
        let current: @MainActor () -> Bool = { [weak self] in
            guard self?.pendingReaderPublication?.id == pending.id, identityCurrent(),
                  self?.pendingReaderPublication?.id == pending.id else { denied = true; return false }
            return true
        }
        guard current(), !Task.isCancelled else { throw Failure.stale }
        weak var transportOwner: ReaderStartupCoordinator?
        let transport = ReaderStartupHTTPTransport(configuration: configuration, context: context,
            credentials: credentials, isCurrent: { [weak self] original in
                guard original == context, current(), let owner = transportOwner,
                      self?.readerStartupCoordinator === owner else { return false }
                return owner.permitsAuthorityTransport(context: context)
            }, execute: execute, now: now)
        let coordinator = ReaderStartupCoordinator(canonical: bootstrapIdentity, sdkState: startup,
            configuration: configuration.startup, readMarker: {
                guard current() else { throw Failure.stale }
                let result = try await readMarker()
                guard current() else { throw Failure.stale }
                return result
            }, readMembership: { try await transport.readMembership($0) },
            verify: { try await transport.verify($0) }, startSDK: { receipt, admission in
                guard current() else { throw Failure.stale }
                try await startSDK(receipt) {
                    guard current() else { throw Failure.stale }
                    try admission()
                    guard current() else { throw Failure.stale }
                }
                guard current() else { throw Failure.stale }
            }, now: {
                let time = now()
                return current() ? time : -1
            }, schedule: schedule)
        transportOwner = coordinator
        readerStartupCoordinator = coordinator
        defer {
            // A deadline/cancel may release the caller before the physical
            // operation. Keep that exact coordinator reserved until it returns.
            if readerStartupCoordinator === coordinator && !coordinator.isBusy { readerStartupCoordinator = nil }
        }
        do {
            _ = try await coordinator.start(context: context)
            guard !Task.isCancelled, current(), let released = releaseReaderSession(context: context, stillPermitted: identityCurrent) else {
                throw Failure.stale
            }
            return released
        } catch {
            startup.revokeReaderContext(context)
            throw error
        }
    }

    /// Captures the concrete Auth user synchronously before creating a Task.
    /// Inert without explicit trusted configuration; no Firestore dependency.
    /// Unit/smoke callers cannot reach the SDK or network through this adapter.
    func beginReaderStartup(
        context: CanonicalSessionState.ContextTicket,
        configuration: ReaderStartupHTTPTransport.Configuration?,
        readMarker: @escaping @MainActor () async throws -> ReaderStartupCoordinator.Marker?,
        startSDK: @escaping @MainActor (ReaderStartupCoordinator.Receipt, @escaping ReaderStartupCoordinator.StartAdmission) async throws -> Void
    ) -> Task<CanonicalSessionState.ContextTicket, Error>? {
        guard !disabled, startup.requiresGuardedStartup, let configuration,
              bootstrapIdentity.isCurrent(context), let app = FirebaseApp.app(),
              app.options.projectID == configuration.startup.projectID,
              app.options.googleAppID == configuration.startup.appID else { return nil }
        let provider = Auth.auth(app: app)
        guard let user = provider.currentUser, user.uid == context.userID,
              bootstrapIdentity.isCurrent(context),
              let executor = try? PushRegistrationURLSessionExecutor(allowedURLs: [configuration.membershipURL, configuration.attestationURL]) else { return nil }
        let providerCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return !self.disabled && provider.currentUser === user && self.bootstrapIdentity.isCurrent(context)
        }
        return Task { @MainActor [self] in
            try await startReaderSession(context: context, configuration: configuration, credentials: { original in
                guard original == context, providerCurrent(), !Task.isCancelled else { throw CancellationError() }
                let token: AuthTokenResult = try await withCheckedThrowingContinuation { continuation in
                    user.getIDTokenResult(forcingRefresh: true) { value, error in
                        continuation.resume(with: ReaderReauthenticationCallback.result(value, error: error))
                    }
                }
                guard providerCurrent(), !Task.isCancelled,
                      token.claims["sub"] as? String == user.uid,
                      token.claims["aud"] as? String == configuration.startup.projectID,
                      token.claims["iss"] as? String == "https://securetoken.google.com/" + configuration.startup.projectID,
                      (token.claims["firebase"] as? [String: Any])?["tenant"] == nil else { throw CancellationError() }
                guard let appCheck = AppCheck.appCheck(app: app), providerCurrent() else { throw CancellationError() }
                let check = try await appCheck.limitedUseToken()
                guard providerCurrent(), !Task.isCancelled else { throw CancellationError() }
                return .init(ownerUID: user.uid, projectID: configuration.startup.projectID,
                    appID: configuration.startup.appID, idToken: token.token, appCheckToken: check.token,
                    authValidUntilMs: Self.startupMilliseconds(token.expirationDate),
                    appCheckValidUntilMs: Self.startupMilliseconds(check.expirationDate))
            }, execute: { try await executor.perform($0) }, readMarker: readMarker, startSDK: startSDK,
                now: { Self.startupMilliseconds(Date()) }, providerIsCurrent: providerCurrent)
        }
    }

    private static func startupMilliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite, value > 0, value <= Double(ReaderAuthoritativeReadContract.maximumSafeInteger) else { return -1 }
        return Int64(value.rounded(.down))
    }

    func captureReaderWorkPermission() -> (@MainActor () -> Bool)? {
        guard !disabled else { return nil }
        return startup.captureReaderWork(identity: bootstrapIdentity, actualUserID: { Auth.auth().currentUser?.uid })
    }

    func bootstrapContextIsCurrent(_ context: CanonicalSessionState.ContextTicket) -> Bool {
        guard !disabled, bootstrapIdentity.isCurrent(context), context.context != .unresolved else { return false }
        let actual = Auth.auth().currentUser?.uid
        return bootstrapIdentity.isCurrent(context) && actual == context.userID
    }

    /// Guarded identity changes revoke old projections without starting new
    /// loads, unsubscribe cleanup or writer recovery for the incoming account.
    private func suspendReaderProjection(stillCurrent: @escaping () -> Bool) -> Bool {
        let steps: [() -> Void] = [
            { _ = UserManager.shared.state.changeContext(to: .unresolved) },
            { _ = ReaderPreferencesService.shared.model.changeContext(to: .unresolved) },
            { IncomingLinkRuntime.shared.suspendForAccountChange() },
            { FavoritesRuntime.shared.suspendForAccountChange() },
            { PodcastProgressRuntime.shared.suspendForAccountChange() },
            { ReadingHistoryRuntime.shared.suspendForAccountChange() },
            { _ = self.state.suspend(stillPermitted: stillCurrent) }
        ]
        for step in steps { guard stillCurrent() else { return false }; step() }
        return stillCurrent() && state.snapshot.context == .unresolved
    }

    private func publishReaderSession(_ user: User?, restoringSuspension: CanonicalSessionState.ContextTicket?, permission: @escaping () -> Bool) -> CanonicalSessionState.ContextTicket? {
        guard !disabled else { return nil }
        let original = user.map(Self.project)
        var accepted: CanonicalSessionState.ContextTicket?
        var profileContext: UserProfileState.ContextTicket?
        var preferencesContext: ReaderPreferencesModel.ContextTicket?
        // Failed signout already revoked both projections. Preserve the cached
        // profile suspension until canonical A has been accepted again; its
        // restore requires both actual and canonical identity to match.
        let restoreProfile = restoringSuspension.map {
            state.isCurrent($0) && $0.context == .unresolved && original != nil
        } ?? false
        let expectedProfileContext: UserProfileState.Context = restoreProfile ? .unresolved : .confirmed(userID: original?.uid)
        let revocationsCurrent: () -> Bool = {
            guard permission(), let profileContext, let preferencesContext else { return false }
            return profileContext.context == expectedProfileContext && UserManager.shared.state.isCurrent(profileContext)
                && preferencesContext.context == .confirmed(userID: original?.uid)
                && ReaderPreferencesService.shared.model.isCurrent(preferencesContext)
        }
        let completed = canonicalPublication.performReaderTransition(expectedUserID: original?.uid,
            currentUserID: { Auth.auth().currentUser?.uid },
            revokeProfile: {
                if !restoreProfile { UserManager.shared.changeAccountContext(userID: original?.uid) }
                let captured = UserManager.shared.state.contextTicket()
                guard captured.context == expectedProfileContext else { return false }
                profileContext = captured
                return UserManager.shared.state.isCurrent(captured)
            }, revokePreferences: {
                guard let profileContext, UserManager.shared.state.isCurrent(profileContext) else { return false }
                preferencesContext = ReaderPreferencesService.shared.changeAccountContext(userID: original?.uid)
                return revocationsCurrent()
            }, revocationsCurrent: revocationsCurrent, dependentSteps: [
                { IncomingLinkRuntime.shared.changeAccountContext(userID: original?.uid) },
                { FavoritesRuntime.shared.changeAccountContext(userID: original?.uid) },
                { TelemetryRuntime.shared.changeAccountContext(to: original?.uid) },
                { PodcastProgressRuntime.shared.changeAccountContext(userID: original?.uid) },
                { ReadingHistoryRuntime.shared.changeAccountContext(userID: original?.uid) }
            ], commitCanonical: {
                accepted = self.state.adopt(original, stillPermitted: revocationsCurrent)
                return accepted.map(self.state.isCurrent) ?? false
            }, startLoads: {
                guard permission(), let accepted, self.state.isCurrent(accepted) else { return }
                if restoreProfile {
                    _ = UserManager.shared.restoreAfterFailedSignOut()
                    guard permission(), self.state.isCurrent(accepted) else { return }
                    UserManager.shared.changeAccountContext(userID: original?.uid)
                }
                guard permission(), self.state.isCurrent(accepted) else { return }
                if let user {
                    UserManager.shared.loadUserProfileIfNeeded(for: user, stillCurrent: permission)
                } else { UserManager.shared.clearIfConfirmedGuest() }
                guard permission(), self.state.isCurrent(accepted), let preferencesContext else { return }
                Task { @MainActor in
                    guard permission(), self.state.isCurrent(accepted) else { return }
                    await ReaderPreferencesService.shared.loadCurrentContextIfNeeded(preferencesContext, stillCurrent: permission)
                }
            }, permission: permission)
        guard permission(), completed, let accepted else { return nil }
        let actual = Auth.auth().currentUser?.uid
        guard actual == original?.uid, state.isCurrent(accepted), state.snapshot.session == original else { return nil }
        return accepted
    }

    /// Identity getters can synchronously reenter publication. Always validate
    /// the original context after reading the provider, before the next effect.
    func isCurrent(_ context: CanonicalSessionState.ContextTicket) -> Bool {
        guard !disabled else { return false }
        let actual = Auth.auth().currentUser?.uid
        return actual == context.userID && state.isCurrent(context)
    }
    private static func project(_ user: User) -> ReaderAccountSession {
        ReaderAccountSession(uid: user.uid, email: user.email ?? "", isEmailVerified: user.isEmailVerified)
    }

    func perform(_ action: EmailAccountAction, form: EmailAccountForm,
                 ticket: AuthOperationCoordinator.Ticket? = nil) async throws -> ReaderAccountSession? {
        guard !disabled else { return nil }
        guard let ticket else { throw CancellationError() }
        let expected: AuthOperationCoordinator.Kind = action == .signIn ? .emailSignIn : action == .signUp ? .emailSignUp : .passwordReset
        guard ticket.kind == expected else { operations.cancel(ticket); throw CancellationError() }
        let accepted: ReaderAccountSession? = try await operations.exchange(ticket) { try await self.performEmail(action, form: form, ticket: ticket) }
        acceptNewsletterChoice(ticket, session: accepted)
        return accepted
    }

    private func performEmail(_ action: EmailAccountAction, form: EmailAccountForm,
                              ticket: AuthOperationCoordinator.Ticket) async throws -> ReaderAccountSession? {
        if action == .resetPassword {
            do { try await Auth.auth().sendPasswordReset(withEmail: form.normalizedEmail) }
            catch where (error as NSError).code == 17011 { /* Same public response for unknown accounts. */ }
            return nil
        }
        let result: AuthDataResult
        if action == .signIn { result = try await Auth.auth().signIn(withEmail: form.normalizedEmail, password: form.password) }
        else { result = try await Auth.auth().createUser(withEmail: form.normalizedEmail, password: form.password) }
        let original = Self.project(result.user)
        guard let context = publishCanonicalSession(result.user), isCurrent(context),
              state.acceptedSession(original, ticket: context) != nil,
              operations.acceptResult(ticket, context: context, isNewUser: action == .signUp) else { return nil }
        let originalProfilePermission = captureReaderWorkPermission()
        if action == .signUp {
            // Account creation succeeded. Follow-up failure must not encourage a
            // second createUser. Each effect retains the accepted original owner.
            let name = form.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let change = result.user.createProfileChangeRequest()
                guard isCurrent(context), operations.canPublishFeedback(ticket) else { return nil }
                change.displayName = name
                try? await change.commitChanges()
            }
            guard isCurrent(context), operations.canPublishFeedback(ticket) else { return nil }
            await sendVerification(context: context)
            guard isCurrent(context), operations.canPublishFeedback(ticket) else { return nil }
            if let originalProfilePermission, originalProfilePermission() {
                UserManager.shared.loadUserProfile(for: result.user, stillCurrent: originalProfilePermission)
            }
        }
        guard isCurrent(context), operations.canPublishFeedback(ticket) else { return nil }
        return state.acceptedSession(original, ticket: context)
    }

    func sendVerification(context: CanonicalSessionState.ContextTicket) async {
        guard !disabled else { return }
        await verification.sendVerification(context: context)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?,
                         ticket: AuthOperationCoordinator.Ticket? = nil) async throws -> ReaderAccountSession? {
        guard !disabled else { return nil }
        guard let ticket else { throw CancellationError() }
        guard ticket.kind == .apple else { operations.cancel(ticket); throw CancellationError() }
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        return try await signIn(credential: credential, ticket: ticket)
    }

    func signIn(credential: AuthCredential, ticket: AuthOperationCoordinator.Ticket) async throws -> ReaderAccountSession? {
        guard !disabled else { return nil }
        guard ticket.kind == .apple || ticket.kind == .google else { operations.cancel(ticket); throw CancellationError() }
        let accepted: ReaderAccountSession? = try await operations.exchange(ticket) {
            let result = try await Auth.auth().signIn(with: credential)
            let original = Self.project(result.user)
            guard let context = self.publishCanonicalSession(result.user), self.isCurrent(context),
                  self.operations.acceptResult(ticket, context: context,
                      isNewUser: result.additionalUserInfo?.isNewUser) else { return nil }
            return self.state.acceptedSession(original, ticket: context)
        }
        acceptNewsletterChoice(ticket, session: accepted)
        return accepted
    }

    private func acceptNewsletterChoice(_ ticket: AuthOperationCoordinator.Ticket, session: ReaderAccountSession?) {
        guard !disabled, ticket.newsletterOptIn, let session,
              operations.canPublishFeedback(ticket) else { return }
        let context = state.contextTicket()
        guard isCurrent(context), state.acceptedSession(session, ticket: context) != nil,
              operations.canPublishFeedback(ticket) else { return }
        ReaderNewsletterRuntime.model.begin(session: session, context: context)
    }

    func refreshSession(context: CanonicalSessionState.ContextTicket) async throws {
        guard !disabled else { return }
        try await verification.refreshSession(context: context)
    }

    func signOut() throws {
        guard !disabled else { throw CanonicalAccountSignOut.Failure.unconfirmed }
        try operations.signOut { try self.performSignOut() }
    }

    private func performSignOut() throws {
        let original = state.contextTicket()
        guard isCurrent(original), original.userID != nil else { throw CanonicalAccountSignOut.Failure.unconfirmed }
        var suspended: CanonicalReaderSuspension.Ticket?
        try CanonicalAccountSignOut.perform(suspend: {
            suspended = CanonicalReaderSuspension.perform(canonical: state, profile: UserManager.shared.state,
                preferences: ReaderPreferencesService.shared.model, context: original,
                currentUserID: { Auth.auth().currentUser?.uid },
                suspendProfile: { UserManager.shared.suspendForAccountChange() }, dependentSteps: [
                    { IncomingLinkRuntime.shared.suspendForAccountChange() },
                    { FavoritesRuntime.shared.suspendForAccountChange() },
                    { PodcastProgressRuntime.shared.suspendForAccountChange() },
                    { ReadingHistoryRuntime.shared.suspendForAccountChange() }
                ])
        }, signOut: {
            guard let suspended, CanonicalReaderSuspension.isCurrent(suspended, canonical: state,
                profile: UserManager.shared.state, preferences: ReaderPreferencesService.shared.model,
                currentUserID: { Auth.auth().currentUser?.uid }) else {
                throw CanonicalAccountSignOut.Failure.unconfirmed
            }
            try Auth.auth().signOut()
        }, isSignedOut: {
            Auth.auth().currentUser == nil
        }, republishCanonical: {
            let current = Auth.auth().currentUser
            let restoring = current?.uid == original.userID ? suspended?.canonical : nil
            _ = publishCanonicalSession(current, restoringSuspension: restoring)
        })
    }
}
