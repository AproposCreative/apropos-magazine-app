#if DEBUG && targetEnvironment(simulator)
import AuthenticationServices
import Combine
import FirebaseCore
import SwiftUI
import UIKit

@MainActor
private final class LocalAppleReauthenticationFixture: ObservableObject {
    private typealias Coordinator = AppleAuthorizationButton.Coordinator
    @MainActor private final class Handle {
        let identity = NSObject()
        let challenge: AppleSignInChallenge
        weak var coordinator: Coordinator?
        init(challenge: AppleSignInChallenge, coordinator: Coordinator) {
            self.challenge = challenge; self.coordinator = coordinator
        }
        func success() {
            coordinator?.receive(identity: identity, response: .init(identityToken: Data("local.apple.token".utf8),
                state: challenge.state, fullName: nil, userID: "original-apple-subject"))
        }
        func fail() {
            coordinator?.receive(identity: identity,
                error: NSError(domain: "LocalAppleProvider", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE local provider detail"]))
        }
    }
    let lifetime = AccountLoginLifetime()
    @Published var showsButton = true
    private(set) var starts = 0 { didSet { schedulePublication() } }
    private(set) var cancellations = 0 { didSet { schedulePublication() } }
    private(set) var releases = 0 { didSet { schedulePublication() } }
    private(set) var exchanges = 0 { didSet { schedulePublication() } }
    private var handles: [Handle] = []
    private var observation: AnyCancellable?
    private var publicationScheduled = false
    lazy var flow = AppleAccountFlowModel(purpose: .reauthentication,
        makeChallenge: { .init(id: UUID(), rawNonce: UUID().uuidString, state: UUID().uuidString) },
        capture: { [unowned self] in
            .init(perform: { [unowned self] _, _, _ in exchanges += 1; return nil },
                expectedAppleUserID: "original-apple-subject")
        })
    init() {
        observation = flow.objectWillChange.sink { [weak self] in
            self?.schedulePublication()
        }
    }
    private func schedulePublication() {
        guard !publicationScheduled else { return }
        publicationScheduled = true
        // Provider cancellation remains synchronous during UIView dismantling.
        // Only test diagnostics are published after that SwiftUI update ends.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publicationScheduled = false
            self.objectWillChange.send()
        }
    }
    var providerFactory: AppleAuthorizationButton.Coordinator.ProviderFactory {
        { [unowned self] challenge, coordinator in
            let handle = Handle(challenge: challenge, coordinator: coordinator)
            handles.append(handle)
            return .init(identity: handle.identity,
                perform: { [weak self] in self?.starts += 1 },
                cancel: { [weak self] in self?.cancellations += 1 },
                release: { [weak self] in self?.releases += 1 })
        }
    }
    func succeed() { handles.last?.success() }
    func fail() { handles.last?.fail() }
    func stop() {
        lifetime.invalidate()
        handles.forEach { $0.fail() }
    }
    var report: String {
        let values: [String: Any] = ["starts": starts, "cancellations": cancellations,
            "releases": releases, "exchanges": exchanges, "working": flow.isWorking,
            "challengeIDs": handles.map { $0.challenge.id.uuidString },
            "lifetimeInvalidated": lifetime.isInvalidated,
            "hasSession": flow.authenticatedSession != nil, "firebaseStarted": FirebaseApp.allApps != nil,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}

/// Actual shared Apple button and native Coordinator, with a plain-object local
/// provider. This exercises presentation semantics, not Apple/Firebase login.
private struct LocalStandaloneAppleReauthenticationSmokeView: View {
    @StateObject private var fixture = LocalAppleReauthenticationFixture()
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bekræft din identitet").font(.headline)
                    if fixture.showsButton {
                        AppleAccountSignInButton(reauthenticationFlow: fixture.flow,
                            lifetime: fixture.lifetime, providerFactory: fixture.providerFactory)
                    } else {
                        Text("Den oprindelige knap er fjernet")
                            .font(.caption).accessibilityIdentifier("appleReauth.detached")
                    }
                }
                .padding(16)
                Divider()
                VStack(spacing: 12) {
                    Text("Kun lokal providertest; ingen Apple-konto eller netværkskald.").font(.footnote)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("appleReauth.firebase")
                    Button("Lokalt Apple-svar") { fixture.succeed() }
                        .accessibilityIdentifier("appleReauth.success")
                    Button("Lokalt Apple-afslag") { fixture.fail() }
                        .accessibilityIdentifier("appleReauth.failure")
                    Button(fixture.showsButton ? "Fjern Apple-knappen" : "Vis Apple-knappen") {
                        fixture.showsButton.toggle()
                    }.accessibilityIdentifier("appleReauth.toggle")
                    Text("Lokal teststatus").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("appleReauth.report").accessibilityValue(fixture.report)
                }
                .padding(.horizontal, 16)
                .tint(.primary)
                .dynamicTypeSize(.small ... .medium) // Test controls only; actual button follows the system.
                Spacer(minLength: 0)
            }
            .navigationTitle("Lokal Apple-bekræftelse")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { fixture.stop() }
    }
}

@MainActor
private final class LocalComposedAppleReauthenticationFixture: ObservableObject {
    @MainActor private final class HeldUser { let uid = "local-reader-A" }
    @MainActor private final class Handle {
        let identity = NSObject()
        let challenge: AppleSignInChallenge
        weak var coordinator: AppleAuthorizationButton.Coordinator?
        init(_ challenge: AppleSignInChallenge, _ coordinator: AppleAuthorizationButton.Coordinator) {
            self.challenge = challenge; self.coordinator = coordinator
        }
        func succeed() {
            coordinator?.receive(identity: identity, response: .init(identityToken: Data("local.apple.token".utf8),
                state: challenge.state, fullName: nil, userID: "original-apple-subject"))
        }
        func fail() { coordinator?.receive(identity: identity, error: CancellationError()) }
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
        .appendingPathComponent("local-apple-deletion-journal-" + UUID().uuidString, isDirectory: true))
    private lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
        actualUID: { [unowned self] in user.uid },
        makeDrain: { [unowned self] in drainFactories += 1; return .init(wait: { completion in completion(nil) }) })
    let prompt: ReaderAppleReauthenticationPrompt
    private let user = HeldUser()
    private let now: Int64 = 1_800_000_000_123
    private(set) var starts = 0 { didSet { schedulePublication() } }
    private(set) var cancellations = 0 { didSet { schedulePublication() } }
    private(set) var sdkCalls = 0 { didSet { schedulePublication() } }
    private(set) var httpCalls = 0 { didSet { schedulePublication() } }
    private(set) var sdkHeld = false { didSet { schedulePublication() } }
    private(set) var httpHeld = false { didSet { schedulePublication() } }
    private(set) var rejectedStarts = 0
    private var handles: [Handle] = []
    private var flows: [AppleAccountFlowModel] = []
    private var sdkWait: CheckedContinuation<Void, Never>?
    private var httpWait: CheckedContinuation<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var publicationScheduled = false
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
                }, appleSubject: "original-apple-subject")
        }, nowMilliseconds: { [unowned self] in now })
    private(set) var coordinator: ReaderAccountDeletionCoordinator?
    private func makeCoordinator() -> ReaderAccountDeletionCoordinator? {
        let config = try? ReaderDeletionHTTPTransport.Configuration(projectID: "local-deletion",
            appID: "1:123456789:ios:abcdef123456", endpointURL: URL(string: "https://reauth.example.invalid/reader")!)
        return auth.makeAppleReaderAccountDeletion(configuration: config, currentMembershipEpoch: { [unowned self] _ in epochReads += 1; return 7 },
            reauthentication: bridge, prompt: prompt, makeCredential: { token, nonce in token + ":" + nonce },
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
        prompt = ReaderAppleReauthenticationPrompt(canonical: resume ? auth.bootstrapIdentity : auth.state)
        if !isResuming { auth.state.adopt(.init(uid: user.uid, email: "local@example.invalid", isEmailVerified: true)) }
        prompt.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
        if !isResuming { installCoordinator() }
    }
    private func schedulePublication() {
        guard !publicationScheduled else { return }
        publicationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publicationScheduled = false
            if let flow = self.prompt.presentation?.flow, !self.flows.contains(where: { $0 === flow }) {
                self.flows.append(flow)
                flow.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &self.subscriptions)
            }
            self.objectWillChange.send()
        }
    }
    var providerFactory: AppleAuthorizationButton.Coordinator.ProviderFactory {
        { [unowned self] challenge, owner in
            let handle = Handle(challenge, owner); handles.append(handle)
            return .init(identity: handle.identity, perform: { [weak self] in self?.starts += 1 },
                cancel: { [weak self] in self?.cancellations += 1 }, release: {})
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
                do { try await recovery.bootstrap() } catch { return }
            }
            let accepted = isResuming
                ? coordinator?.beginResumption(context: auth.bootstrapIdentity.contextTicket(), userConfirmed: true)
                : coordinator?.begin(context: auth.state.contextTicket(), membershipEpoch: 7, userConfirmed: true)
            if accepted != true { rejectedStarts += 1; schedulePublication() }
        }
    }
    func providerSuccess() { handles.last?.succeed() }
    func releaseSDK() { let old = sdkWait; sdkWait = nil; sdkHeld = false; old?.resume() }
    func releaseHTTP() { let old = httpWait; httpWait = nil; httpHeld = false; old?.resume() }
    func stop() { prompt.cancel(); coordinator?.cancel(); handles.forEach { $0.fail() }; releaseSDK(); releaseHTTP() }
    var report: String {
        let values: [String: Any] = ["starts": starts, "cancellations": cancellations, "rejectedStarts": rejectedStarts,
            "sdkCalls": sdkCalls, "httpCalls": httpCalls, "sdkHeld": sdkHeld, "httpHeld": httpHeld,
            "promptID": prompt.presentation?.id.uuidString ?? "", "working": prompt.presentation?.flow.isWorking ?? false,
            "physicalFlight": coordinator?.hasPhysicalFlight ?? false,
            "status": coordinator.map { String(describing: $0.status) } ?? "unavailable",
            "uid": auth.state.snapshot.session?.uid ?? "", "hasNewSession": flows.contains { $0.authenticatedSession != nil },
            "resuming": isResuming, "restartReady": restartReady,
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

private struct LocalComposedAppleReauthenticationSmokeView: View {
    @StateObject private var fixture = LocalComposedAppleReauthenticationFixture()
    var body: some View {
        let presented = fixture.prompt.presentation
        return NavigationStack {
            VStack(spacing: 20) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                    .accessibilityIdentifier("appleReauth.firebase")
                Button("Start identitetsbekræftelse") { fixture.begin() }
                    .tint(.primary)
                    .accessibilityIdentifier("appleReauth.begin")
                        .disabled(fixture.isResuming && !fixture.restartReady)
                if fixture.prompt.presentation == nil { controls }
            }
            .padding(16)
            .dynamicTypeSize(.small ... .medium)
            .navigationTitle("Lokal samlet Apple-test")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: Binding(get: { fixture.prompt.presentation }, set: { value in
            guard value == nil, let original = presented?.action else { return }
            fixture.prompt.cancel(action: original)
        })) { presentation in
            VStack(spacing: 0) {
                ReaderAppleReauthenticationSheet(prompt: fixture.prompt, presentation: presentation,
                    providerFactory: fixture.providerFactory)
                    .frame(maxHeight: .infinity)
                controls.padding(8).background(.regularMaterial).dynamicTypeSize(.small ... .medium)
            }
        }
        .task { await fixture.prepareRestart() }
        .onDisappear { fixture.stop() }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            Button("Lokalt Apple-svar") { fixture.providerSuccess() }
                .accessibilityIdentifier("appleReauth.success")
            Button("Frigiv lokalt SDK-svar") { fixture.releaseSDK() }
                .accessibilityIdentifier("appleReauth.releaseSDK")
            Button("Frigiv lokalt HTTP-svar") { fixture.releaseHTTP() }
                .accessibilityIdentifier("appleReauth.releaseHTTP")
            Text("Lokal teststatus").font(.caption)
                .accessibilityIdentifier("appleReauth.report").accessibilityValue(fixture.report)
        }
        .font(.footnote)
        .tint(.primary)
        .accessibilityElement(children: .contain).accessibilityIdentifier("appleReauth.fixtureControls")
    }
}

struct LocalAppleReauthenticationSmokeView: View {
    private var composed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AppleReauthenticationScenario"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "composed"
    }
    var body: some View {
        if composed { LocalComposedAppleReauthenticationSmokeView() }
        else { LocalStandaloneAppleReauthenticationSmokeView() }
    }
}
#endif
