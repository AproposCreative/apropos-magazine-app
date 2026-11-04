#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

@MainActor
private final class LocalGoogleReauthenticationFixture: ObservableObject {
    @MainActor private final class User { let uid = "local-reader-A" }
    @MainActor private final class Provider {
        typealias Callback = @Sendable (GoogleSignInService.ReauthenticationIdentity?, Error?) -> Void
        var callbacks: [Callback] = []
        var changed: (() -> Void)?
        func begin(current: @escaping @MainActor () -> Bool, callback: @escaping Callback) throws {
            guard current() else { throw CancellationError() }
            callbacks.append(callback); changed?()
        }
        func succeed() {
            callbacks.last?(.init(idToken: "local.google.identity", accessToken: "local.google.access", userID: "original-google-subject"), nil)
        }
        func fail() {
            callbacks.last?(nil, NSError(domain: "LocalGoogleProvider", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PRIVATE local provider failure"]))
        }
        func drain() { callbacks.forEach { $0(nil, CancellationError()) } }
    }
    let isResuming = ProcessInfo.processInfo.arguments.contains("-AproposDeletionResume")
    let auth: AuthService
    private let recovery: ReaderTransitionRecovery
    private let startup: ReaderSDKStartupState
    private let recoveryRoot: URL
    private var restartPreparationStarted = false
    private(set) var restartReady = false
    private var startupDelegate: AppDelegate?
    private var readerEffects = 0
    private var readerPublications = 0
    private var epochReads = 0
    private var drainFactories = 0
    private var sentBodies: [String] = []
    private var originalParentBody = ""
    private var originalContext: CanonicalSessionState.ContextTicket?
    private var account: CanonicalSessionState { isResuming ? auth.bootstrapIdentity : auth.state }
    private let journal = FavoritesFileJournal(rootDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("local-google-deletion-journal-" + UUID().uuidString, isDirectory: true))
    private lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
        actualUID: { [unowned self] in user.uid },
        makeDrain: { [unowned self] in drainFactories += 1; return .init(wait: { completion in completion(nil) }) })
    let service: GoogleSignInService
    let prompt: ReaderGoogleReauthenticationPrompt
    private let provider: Provider
    private let user = User()
    private let now: Int64 = 1_800_000_000_123
    private(set) var sdkCalls = 0 { didSet { schedulePublication() } }
    private(set) var httpCalls = 0 { didSet { schedulePublication() } }
    private(set) var sdkHeld = false { didSet { schedulePublication() } }
    private(set) var httpHeld = false { didSet { schedulePublication() } }
    private(set) var rejectedStarts = 0 { didSet { schedulePublication() } }
    private var sdkWait: CheckedContinuation<Void, Never>?
    private var httpWait: CheckedContinuation<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var publicationScheduled = false
    private var actions: [UUID] = []
    private lazy var operations = AuthOperationCoordinator(canonical: auth.state, actualUserID: { [unowned self] in user.uid },
        reauthenticationIdentity: isResuming ? auth.bootstrapIdentity : nil)
    private lazy var bridge = ReaderAccountReauthentication<String>(canonical: account, operations: operations,
        captureUser: { [unowned self] in
            let original = user
            return .init(uid: original.uid, isCurrent: { [unowned self] in user === original },
                reauthenticate: { [unowned self] _, admitted in
                    guard admitted() else { throw CancellationError() }
                    sdkCalls += 1
                    await withCheckedContinuation { sdkWait = $0; sdkHeld = true }
                    guard admitted() else { throw CancellationError() }
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, admitted in
                    guard admitted() else { throw CancellationError() }
                    return .init(ownerUID: original.uid, projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString, authTimeMs: proof.authTimeMs,
                        authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                }, googleSubject: "original-google-subject")
        }, nowMilliseconds: { [unowned self] in now })
    private(set) var coordinator: ReaderAccountDeletionCoordinator?
    private func makeCoordinator() -> ReaderAccountDeletionCoordinator? {
        let config = try? ReaderDeletionHTTPTransport.Configuration(projectID: "local-deletion",
            appID: "1:123456789:ios:abcdef123456", endpointURL: URL(string: "https://reauth.example.invalid/reader")!)
        return auth.makeGoogleReaderAccountDeletion(configuration: config, currentMembershipEpoch: { [unowned self] _ in epochReads += 1; return 7 },
            reauthentication: bridge, prompt: prompt, makeCredential: { token, access in token + ":" + access },
            execute: { [unowned self] request in
                httpCalls += 1
                sentBodies.append(request.httpBody?.base64EncodedString() ?? "")
                await withCheckedContinuation { httpWait = $0; httpHeld = true }
                guard let bytes = request.httpBody,
                      let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let uid = value["expectedUID"] as? String, let epoch = value["membershipEpoch"] as? Int64,
                      let url = request.url else { throw URLError(.cannotParseResponse) }
                let original = try ReaderAccountDeletionContract.Request(expectedUID: uid, membershipEpoch: epoch)
                let reply: [String: Any] = ["requestID": original.requestID, "scope": ReaderAccountDeletionContract.scope,
                    "status": "scopedCloudDataRemoved", "accountDeletionComplete": false,
                    "unresolved": ReaderAccountDeletionContract.unresolved, "removedFavoriteDocuments": 0]
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
                return (try JSONSerialization.data(withJSONObject: reply), response)
            }, now: { [unowned self] in now }, scheduleTimeout: { _, _ in {} },
            writeBarrier: isResuming ? nil : .init(writers: writers, journal: journal, recovery: recovery),
            resumingAfterRestart: isResuming)
    }
    init() {
        let resume = ProcessInfo.processInfo.arguments.contains("-AproposDeletionResume")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-deletion-recovery-" + UUID().uuidString, isDirectory: true)
        recoveryRoot = root
        let localRecovery = ReaderTransitionRecovery(store: .init(rootDirectory: root))
        recovery = localRecovery
        let localStartup = ReaderSDKStartupState(legacyRecovery: localRecovery)
        startup = localStartup
        auth = resume ? AuthService(startup: localStartup) : AuthService()
        let localProvider = Provider()
        provider = localProvider
        service = GoogleSignInService(reauthenticationProvider: { current, callback in
            try localProvider.begin(current: current, callback: callback)
        })
        prompt = ReaderGoogleReauthenticationPrompt(canonical: resume ? auth.bootstrapIdentity : auth.state, service: service)
        if !isResuming { auth.state.adopt(.init(uid: user.uid, email: "local@example.invalid", isEmailVerified: true)) }
        provider.changed = { [weak self] in self?.schedulePublication() }
        prompt.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
        if !isResuming { installCoordinator() }
    }
    private func schedulePublication() {
        guard !publicationScheduled else { return }
        publicationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publicationScheduled = false
            if let id = self.prompt.presentation?.id, !self.actions.contains(id) { self.actions.append(id) }
            self.objectWillChange.send()
        }
    }
    private func installCoordinator() {
        coordinator = makeCoordinator()
        coordinator?.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
    }

    /// Two distinct recovery instances: seed the prior process on disk, then
    /// start the actual new AppDelegate/Auth composition against those bytes.
    func prepareRestart() async {
        guard isResuming, !restartPreparationStarted else { return }
        restartPreparationStarted = true
        do {
            let seed = ReaderTransitionRecovery(store: .init(rootDirectory: recoveryRoot))
            try await seed.bootstrap()
            _ = try await seed.seal(binding: .init(ownerUID: "local-reader-A", epoch: 7))
            let request = try ReaderAccountDeletionContract.Request(expectedUID: "local-reader-A", membershipEpoch: 7)
            let digest = ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: "local-deletion",
                appID: "1:123456789:ios:abcdef123456", endpoint: URL(string: "https://reauth.example.invalid/reader")!)
            _ = try await seed.recordDeletion(request: request, phase: .parent, configurationDigest: digest)
            _ = try await seed.recordDeletion(request: request, phase: .ledger, configurationDigest: digest)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            originalParentBody = try encoder.encode(request).base64EncodedString()
            let delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
                actualUserID: { [unowned self] in user.uid })
            startupDelegate = delegate
            if let task = delegate.runAccountStartup(authOnly: {},
                readerSteps: [{ [unowned self] in readerEffects += 1 }],
                observeAuth: { [unowned self] in
                    let session = ReaderAccountSession(uid: "local-reader-A", email: "canonical@example.invalid", isEmailVerified: true)
                    _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user.uid },
                        revokeReader: { [unowned self] current in auth.state.suspend(stillPermitted: current) != nil },
                        publishReader: { [unowned self] current in
                            readerPublications += 1
                            return auth.state.adopt(session, stillPermitted: current)
                        })
                }, releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() }) {
                await task.value
            }
            guard !Task.isCancelled else { return }
            originalContext = auth.bootstrapIdentity.contextTicket()
            installCoordinator()
            restartReady = coordinator != nil
            schedulePublication()
        } catch { schedulePublication() }
    }
    func begin() {
        Task { @MainActor in
            guard !isResuming || restartReady else { return }
            if recovery.status == .unresolved {
                do { try await recovery.bootstrap() } catch { rejectedStarts += 1; return }
            }

            let accepted = isResuming
                ? coordinator?.beginResumption(context: auth.bootstrapIdentity.contextTicket(), userConfirmed: true)
                : coordinator?.begin(context: auth.state.contextTicket(), membershipEpoch: 7, userConfirmed: true)
            if accepted != true { rejectedStarts += 1 }
        }
    }
    func retry() { if coordinator?.retry(userConfirmed: true) != true { rejectedStarts += 1 } }
    func providerSuccess() { provider.succeed() }
    func providerFailure() { provider.fail() }
    func releaseSDK() { let old = sdkWait; sdkWait = nil; sdkHeld = false; old?.resume() }
    func releaseHTTP() { let old = httpWait; httpWait = nil; httpHeld = false; old?.resume() }
    func stop() { prompt.cancel(); coordinator?.cancel(); provider.drain(); releaseSDK(); releaseHTTP() }
    var report: String {
        let values: [String: Any] = ["providerCalls": provider.callbacks.count,
            "sdkCalls": sdkCalls, "httpCalls": httpCalls, "sdkHeld": sdkHeld, "httpHeld": httpHeld,
            "promptID": prompt.presentation?.id.uuidString ?? "", "working": prompt.presentation?.isWorking ?? false,
            "actionIDs": actions.map(\.uuidString), "rejectedStarts": rejectedStarts,
            "physicalFlight": coordinator?.hasPhysicalFlight ?? false,
            "status": coordinator.map { String(describing: $0.status) } ?? "unavailable",
            "uid": auth.state.snapshot.session?.uid ?? "", "serviceSignedIn": service.isSignedIn,
            "serviceHasUser": service.user != nil, "resuming": isResuming, "restartReady": restartReady,
            "readerUnresolved": auth.state.snapshot.context == .unresolved,
            "bootstrapUID": auth.bootstrapIdentity.snapshot.session?.uid ?? "",
            "originalContextCurrent": originalContext.map { auth.bootstrapIdentity.isCurrent($0) } ?? false,
            "readerEffects": readerEffects, "readerPublications": readerPublications,
            "epochReads": epochReads, "drainFactories": drainFactories,
            "checkpointPhase": recovery.deletionCheckpoint?.phase.rawValue ?? "",
            "canBeginLedger": coordinator?.canBeginLedgerCleanup ?? false,
            "hasParentReceipt": coordinator?.receipt != nil,
            "sentBodies": sentBodies, "originalParentBody": originalParentBody,
            "firebaseStarted": FirebaseApp.allApps != nil,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}

/// Actual Auth/prompt/provider/held-user/HTTP composition, entirely local.
/// No GID presentation, Firebase initialization or transport reaches a service.
struct LocalGoogleReauthenticationSmokeView: View {
    @StateObject private var fixture = LocalGoogleReauthenticationFixture()
    private var loginRender: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-GoogleReauthenticationScenario"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "loginRender"
    }
    var body: some View {
        if loginRender {
            NavigationStack {
                VStack(spacing: 24) {
                    GoogleSignInButton().disabled(true)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .font(.caption).accessibilityIdentifier("googleReauth.firebase")
                    controls.dynamicTypeSize(.small ... .medium)
                }.padding(16).tint(.primary)
                .navigationTitle("Eksisterende Google-knap")
                .navigationBarTitleDisplayMode(.inline)
            }
        } else { composedContent }
    }
    private var composedContent: some View {
        let presented = fixture.prompt.presentation
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .font(.caption).accessibilityIdentifier("googleReauth.firebase")
                    Button("Start identitetsbekræftelse") { fixture.begin() }
                        .accessibilityIdentifier("googleReauth.begin")
                        .disabled(fixture.isResuming && !fixture.restartReady)
                        .dynamicTypeSize(.small ... .medium)
                    if fixture.prompt.presentation == nil {
                        if let message = fixture.coordinator?.message {
                            Text(message).accessibilityIdentifier("googleReauth.message")
                        }
                        if fixture.coordinator?.canRetry == true {
                            Button("Prøv igen") { fixture.retry() }.accessibilityIdentifier("googleReauth.retry")
                        }
                        controls.dynamicTypeSize(.small ... .medium)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Lokal Google-bekræftelse")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
        }
        .sheet(item: Binding(get: { fixture.prompt.presentation }, set: { value in
            guard value == nil, let original = presented?.action else { return }
            fixture.prompt.cancel(action: original)
        })) { presentation in
            VStack(spacing: 0) {
                ReaderGoogleReauthenticationSheet(prompt: fixture.prompt, presentation: presentation)
                    .frame(maxHeight: .infinity)
                controls.padding(8).background(.regularMaterial).dynamicTypeSize(.small ... .medium)
            }
        }
        .task { await fixture.prepareRestart() }
        .onDisappear { fixture.stop() }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            Button("Lokalt Google-svar") { fixture.providerSuccess() }.accessibilityIdentifier("googleReauth.success")
            Button("Lokalt Google-afslag") { fixture.providerFailure() }.accessibilityIdentifier("googleReauth.failure")
            Button("Frigiv lokalt SDK-svar") { fixture.releaseSDK() }.accessibilityIdentifier("googleReauth.releaseSDK")
            Button("Frigiv lokalt HTTP-svar") { fixture.releaseHTTP() }.accessibilityIdentifier("googleReauth.releaseHTTP")
            Text("Lokal teststatus").font(.caption)
                .accessibilityIdentifier("googleReauth.report").accessibilityValue(fixture.report)
        }
        .font(.footnote).tint(.primary)
        .accessibilityElement(children: .contain).accessibilityIdentifier("googleReauth.fixtureControls")
    }
}
#endif
