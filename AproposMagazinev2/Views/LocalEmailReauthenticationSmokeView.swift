#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

@MainActor
private final class LocalEmailReauthenticationFixture: ObservableObject {
    enum Scenario: String { case normal, wrongPassword, held }
    private final class User {
        let uid: String
        let email = "original.reader@example.invalid"
        init(_ uid: String) { self.uid = uid }
    }
    let scenario: Scenario
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
        .appendingPathComponent("local-email-deletion-journal-" + UUID().uuidString, isDirectory: true))
    private lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
        actualUID: { [unowned self] in user?.uid },
        makeDrain: { [unowned self] in drainFactories += 1; return .init(wait: { completion in completion(nil) }) })
    let prompt: ReaderEmailReauthenticationPrompt
    private var user: User? = User("local-reader-A")
    private var now: Int64 = 1_800_000_000_123
    @Published private(set) var sdkCalls = 0
    @Published private(set) var httpCalls = 0
    @Published private(set) var credentialEmails: [String] = []
    @Published private(set) var actions: [ReaderAccountDeletionCoordinator.ActionTicket] = []
    @Published private(set) var sdkHeld = false
    @Published private(set) var rejectedStarts = 0
    private var held: CheckedContinuation<Void, Never>?
    private var forms: [EmailAccountFlowModel] = []
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var operations = AuthOperationCoordinator(canonical: auth.state, actualUserID: { [unowned self] in user?.uid },
        reauthenticationIdentity: isResuming ? auth.bootstrapIdentity : nil)
    private lazy var bridge = ReaderAccountReauthentication<String>(canonical: account, operations: operations,
        captureUser: { [unowned self] in
            guard let original = user else { return nil }
            return .init(uid: original.uid, isCurrent: { [unowned self] in user === original },
                reauthenticate: { [unowned self] _, admitted in
                    guard admitted() else { throw CancellationError() }
                    sdkCalls += 1
                    let attempt = sdkCalls
                    if scenario == .held && attempt == 1 {
                        await withCheckedContinuation { held = $0; sdkHeld = true }
                    }
                    guard admitted() else { throw CancellationError() }
                    if scenario == .wrongPassword && attempt == 1 {
                        throw NSError(domain: "FIRAuthErrorDomain", code: 17009,
                            userInfo: [NSLocalizedDescriptionKey: "PRIVATE fixture wrong password detail"])
                    }
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, admitted in
                    guard admitted() else { throw CancellationError() }
                    return .init(ownerUID: original.uid, projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString, authTimeMs: proof.authTimeMs,
                        authValidUntilMs: now + 60000, appCheckValidUntilMs: now + 60000)
                }, email: original.email, supportsPassword: true)
        }, nowMilliseconds: { [unowned self] in now })
    private(set) var coordinator: ReaderAccountDeletionCoordinator?
    private func makeCoordinator() -> ReaderAccountDeletionCoordinator? {
        let configuration = try? ReaderDeletionHTTPTransport.Configuration(projectID: "local-deletion",
            appID: "1:123456789:ios:abcdef123456", endpointURL: URL(string: "https://reauth.example.invalid/reader")!)
        return auth.makeEmailReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: { [unowned self] _ in epochReads += 1; return 7 },
            reauthentication: bridge, prompt: prompt, makeCredential: { [unowned self] email, password in
                credentialEmails.append(email)
                return password // Local credential only; never persisted or reported.
            }, execute: { [unowned self] request in
                httpCalls += 1
                sentBodies.append(request.httpBody?.base64EncodedString() ?? "")
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
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-EmailReauthenticationScenario"), args.indices.contains(index + 1) {
            scenario = Scenario(rawValue: args[index + 1]) ?? .normal
        } else { scenario = .normal }
        prompt = ReaderEmailReauthenticationPrompt(canonical: resume ? auth.bootstrapIdentity : auth.state)
        if !isResuming { select("local-reader-A") }
        prompt.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.rememberPresentation(); self?.objectWillChange.send() }
        }.store(in: &subscriptions)
        if !isResuming { installCoordinator() }
    }
    private func select(_ uid: String) {
        if user?.uid != uid { user = User(uid) }
        // Intentionally differs from the held SDK email. The real composition
        // must present that held email, not this potentially older projection.
        auth.state.adopt(.init(uid: uid, email: "canonical@example.invalid", isEmailVerified: true))
    }
    private func rememberPresentation() {
        guard let presentation = prompt.presentation, !actions.contains(where: { $0.actionID == presentation.action.actionID }) else { return }
        actions.append(presentation.action); forms.append(presentation.form)
        presentation.form.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }.store(in: &subscriptions)
    }
    private func installCoordinator() {
        coordinator = makeCoordinator()
        coordinator?.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }.store(in: &subscriptions)
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
                actualUserID: { [unowned self] in user?.uid })
            startupDelegate = delegate
            if let task = delegate.runAccountStartup(authOnly: {},
                readerSteps: [{ [unowned self] in readerEffects += 1 }],
                observeAuth: { [unowned self] in
                    let session = ReaderAccountSession(uid: "local-reader-A", email: "canonical@example.invalid", isEmailVerified: true)
                    _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user?.uid },
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
            objectWillChange.send()
        } catch { objectWillChange.send() }
    }
    func begin() {
        Task { @MainActor in
            guard !isResuming || restartReady else { return }
            if recovery.status == .unresolved {
                do { try await recovery.bootstrap() } catch { rejectedStarts += 1; return }
            }
            now += 1_000
            let accepted = isResuming
                ? coordinator?.beginResumption(context: auth.bootstrapIdentity.contextTicket(), userConfirmed: true)
                : coordinator?.begin(context: auth.state.contextTicket(), membershipEpoch: 7, userConfirmed: true)
            if accepted != true { rejectedStarts += 1 }
        }
    }
    func releaseSDK() { let old = held; held = nil; sdkHeld = false; old?.resume() }
    func roundTrip() { select("local-reader-B"); select("local-reader-A") }
    func oldPromptCallback() { if let original = actions.first { prompt.complete(action: original, error: nil) } }
    func stop() { prompt.cancel(); coordinator?.cancel(); releaseSDK() }
    var report: String {
        let fields: [String: Any] = ["resuming": isResuming, "restartReady": restartReady,
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
            "sdkCalls": sdkCalls, "httpCalls": httpCalls, "credentialEmails": credentialEmails,
            "actionIDs": actions.map { $0.actionID.uuidString },
            "activeID": prompt.presentation?.id.uuidString ?? "",
            "promptState": prompt.presentation.map { String(describing: $0.state) } ?? "closed",
            "status": coordinator.map { String(describing: $0.status) } ?? "unavailable",
            "physicalFlight": coordinator?.hasPhysicalFlight ?? false, "sdkHeld": sdkHeld,
            "passwordsCleared": forms.allSatisfy { $0.form.password.isEmpty && $0.form.confirmation.isEmpty },
            "rejectedStarts": rejectedStarts,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// The production form and sheet run through the actual Auth composition,
/// original held-user reauthentication and HTTP adapter, with local effects.
struct LocalEmailReauthenticationSmokeView: View {
    @StateObject private var fixture = LocalEmailReauthenticationFixture()

    var body: some View {
        let presented = fixture.prompt.presentation
        return NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Ingen rigtig kontoændring eller netværkskald. Resultatet er simuleret.")
                        .font(.footnote)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("emailReauth.firebase")
                }
                Section {
                    Button("Start identitetsbekræftelse") { fixture.begin() }
                        .accessibilityIdentifier("emailReauth.begin")
                        .disabled(fixture.isResuming && !fixture.restartReady)
                    if fixture.scenario == .held {
                        Button("Frigiv SDK-svar") { fixture.releaseSDK() }
                            .accessibilityIdentifier("emailReauth.release")
                    }
                }
            }
            .dynamicTypeSize(.small ... .medium) // Fixture controls only; the presented production form uses system text.
            .navigationTitle("Lokal identitetstest")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom) {
            diagnostics.padding(8).background(.regularMaterial)
                .dynamicTypeSize(.small ... .medium)
        }
        .sheet(item: Binding(get: { fixture.prompt.presentation }, set: { value in
            guard value == nil, let original = presented?.action else { return }
            fixture.prompt.cancel(action: original)
        })) { presentation in
            VStack(spacing: 0) {
                ReaderEmailReauthenticationSheet(prompt: fixture.prompt, presentation: presentation)
                    .frame(maxHeight: .infinity)
                VStack(spacing: 4) {
                        if fixture.scenario == .held {
                            HStack {
                                Button("Kontoskift A → B → A") { fixture.roundTrip() }
                                    .accessibilityIdentifier("emailReauth.roundTrip")
                                Button("Gammelt prompt-svar") { fixture.oldPromptCallback() }
                                    .accessibilityIdentifier("emailReauth.oldPrompt")
                            }.font(.caption)
                        }
                        diagnostics
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .tint(.primary)
                    .dynamicTypeSize(.small ... .medium) // Test diagnostics only; actual form follows system text.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("emailReauth.fixtureControls")
            }
        }
        .task { await fixture.prepareRestart() }
        .onDisappear { fixture.stop() }
    }
    private var diagnostics: some View {
        Text("Lokal teststatus")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("emailReauth.report")
            .accessibilityValue(fixture.report)
    }
}
#endif
