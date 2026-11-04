#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

/// Actual native UI and owner-bound models. All receipts and I/O are synthetic.
@MainActor
private final class LocalIntroductionFixture: ObservableObject {
    struct AccountPresentation: Identifiable {
        let id: UUID
        let entry: ReaderAccountEntry
        let ticket: ReaderIntroductionModel.AccountEntryTicket
        let form: EmailAccountFlowModel
    }
    let canonical: CanonicalSessionState
    let languagePreferences: PreferencesManager
    lazy var coordinator = ReaderLaunchCoordinator(presentationAllowed: { [weak self] in self?.model.permitsIntroduction == true })
    private let recovery: ReaderTransitionRecovery?
    private var oldIntroductionAction: (() -> Void)?
    private var rejectedOldActions = 0
    @Published private(set) var model: ReaderIntroductionModel
    @Published private(set) var modelID = UUID()
    @Published private(set) var topics: [Topic]
    @Published private(set) var isLoadingTopics: Bool
    @Published private(set) var topicsError: String?
    @Published private(set) var accountPresentation: AccountPresentation?
    @Published private(set) var accountDismissing = false
    @Published private(set) var accountInFlight = false
    @Published private(set) var accountRequests = 0
    @Published private(set) var accountVisits = 0
    @Published private(set) var acceptedLogins = 0
    @Published private(set) var lastLoginWasNew = false
    @Published private(set) var newsletterRequests = 0
    @Published private(set) var newsletterRequestStable = true
    @Published private(set) var newsletterPayload: ReaderNewsletterSignupModel.Request?
    @Published private(set) var deferrals = 0
    @Published private(set) var resumed = 0
    @Published private(set) var lastEntry: ReaderAccountEntry?
    @Published private(set) var generationChanges = 0
    @Published private(set) var providerActivations = 0
    private let memory: Memory
    private let scenario: String
    private var observations = Set<AnyCancellable>()
    private var modelObservation: AnyCancellable?
    private var started = false
    private var pendingPreferenceLoad: CheckedContinuation<Void, Never>?
    private var preferenceReadAttempts = 0
    private var signOutAttempts = 0

    private final class Memory {
        enum Failure: Error { case local }
        var introduction: Data?
        var preferences: [String: ReaderPreferences] = [:]
        var introductionReads = 0
        var introductionWrites = 0
        var preferenceWrites = 0
        var failNextIntroductionWrite = false
        var failNextPreferenceWrite = false
        func writeIntroduction(_ data: Data) throws {
            if failNextIntroductionWrite { failNextIntroductionWrite = false; throw Failure.local }
            introduction = data; introductionWrites += 1
        }
    }

    lazy var preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: { [weak self] in
        let uid = self?.canonical.snapshot.userID
        return .init(actualUID: uid, canonicalUID: uid)
    }, load: { [weak self] ticket, current in
        guard let self, let uid = ticket.userID, current() else { throw CancellationError() }
        preferenceReadAttempts += 1
        if ["preferences-loading", "manual-preferences-loading"].contains(scenario), preferenceReadAttempts == 1 {
            await withCheckedContinuation { self.pendingPreferenceLoad = $0 }
        }
        guard current() else { throw CancellationError() }
        if scenario == "preferences-retry", preferenceReadAttempts <= 2 { throw Memory.Failure.local }
        return .init(preferences: memory.preferences[uid], isFromCache: false)
    }, save: { [weak self] request, current in
        guard let self, current() else { throw CancellationError() }
        if memory.failNextPreferenceWrite { memory.failNextPreferenceWrite = false; throw Memory.Failure.local }
        memory.preferences[request.userID] = request.preferences
        memory.preferenceWrites += 1
    })
    lazy var accountActions = ReaderAccountActions(canonical: canonical, preferences: preferences,
        verify: { _ in }, refresh: { _ in })
    lazy var newsletter = ReaderNewsletterSignupModel(canonical: canonical) { [weak self] request, context in
        guard let self, canonical.isCurrent(context) else { throw CancellationError() }
        if let previous = newsletterPayload { newsletterRequestStable = previous.requestID == request.requestID }
        newsletterPayload = request; newsletterRequests += 1
        let attempt = newsletterRequests
        try await Task.sleep(for: .milliseconds(150))
        guard canonical.isCurrent(context) else { throw CancellationError() }
        if scenario.hasPrefix("newsletter-reconfirmation") {
            if request.reconfirmationChallenge == nil {
                return .init(status: .reconfirmationRequired, requestID: request.requestID,
                    reconfirmationChallenge: attempt == 1 ? "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" : "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
            }
            if scenario == "newsletter-reconfirmation-expired", attempt == 2 {
                return .init(status: .reconfirmationRequired, requestID: request.requestID)
            }
        }
        return .init(status: scenario == "newsletter-retry" && attempt == 1 ? .unavailable : .subscribed,
                     requestID: request.requestID)
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let scenario: String
        if let index = arguments.firstIndex(of: "-IntroductionSmokeScenario"), arguments.indices.contains(index + 1) {
            scenario = arguments[index + 1]
        } else { scenario = "first" }
        self.scenario = scenario
        // Actual preference persistence, isolated from the app's shared domain.
        let languageSuite = "local.introduction.language." + UUID().uuidString
        guard let languageDefaults = UserDefaults(suiteName: languageSuite) else {
            preconditionFailure("Cannot create the isolated introduction language suite")
        }
        languagePreferences = PreferencesManager(userDefaults: languageDefaults)
        let recoveryDirectory = scenario == "recovery" ? FileManager.default.temporaryDirectory.appendingPathComponent("intro-smoke-" + UUID().uuidString) : nil
        let recovery = recoveryDirectory.map { ReaderTransitionRecovery(store: .init(rootDirectory: $0)) }
        self.recovery = recovery
        let canonical = CanonicalSessionState()
        canonical.adopt(scenario.hasPrefix("restored") ? ReaderAccountSession(uid: "local-existing-reader", email: "reader@example.invalid", isEmailVerified: true) : nil)
        self.canonical = canonical
        let memory = Memory()
        if scenario == "corrupt" { memory.introduction = Data("unreadable introduction record".utf8) }
        memory.preferences["local-existing-reader"] = ReaderPreferences(interestTopicIDs: ["culture"], onboardingCompleted: true)
        if scenario.hasPrefix("restored") {
            let old = Self.makeModel(memory: memory, canonical: canonical)
            old.start(); old.advance(); old.setSelectedTopicIDs(["culture"])
            if scenario == "restored-active" { old.complete(); old.replay(); old.advance() }
            if let data = memory.introduction,
               var record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                record["schemaVersion"] = 2
                memory.introduction = try? JSONSerialization.data(withJSONObject: record)
            }
        }
        self.memory = memory
        model = Self.makeModel(memory: memory, canonical: canonical, recovery: recovery)
        topics = scenario == "late" ? [] : Self.availableTopics
        isLoadingTopics = scenario == "late"; topicsError = nil
        canonical.changes.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        coordinator.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        languagePreferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        observeModel()
    }
    private static let availableTopics = [
        Topic(id: "design", name: "Design"), Topic(id: "music", name: "Musik"),
        Topic(id: "culture", name: "Kultur"), Topic(id: "film", name: "Serier & Film")
    ]
    private static func makeModel(memory: Memory, canonical: CanonicalSessionState,
                                  recovery: ReaderTransitionRecovery? = nil) -> ReaderIntroductionModel {
        let model = ReaderIntroductionModel(storage: .init(read: {
            memory.introductionReads += 1
            return memory.introduction
        }, write: { try memory.writeIntroduction($0) }), recovery: recovery)
        model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        return model
    }
    private func observeModel() {
        modelObservation = model.changes.sink { [weak self] _ in
            guard let self else { return }
            if !model.permitsIntroduction { coordinator.suspend(); dismissAccount() }
            objectWillChange.send()
        }
    }
    func start() {
        guard !started else { return }; started = true
        if let recovery {
            Task { [weak self] in
                do { try await recovery.bootstrap() } catch { return }
                guard let self else { return }
                self.model.bindContext(self.canonical.contextTicket(), isCurrent: self.canonical.isCurrent)
                self.startReady()
            }
        } else { startReady() }
    }
    private func startReady() {
        model.start(); preferences.start()
        if let uid = canonical.snapshot.userID, let context = preferences.changeContext(to: .account(uid)) {
            Task { await preferences.load(context) }
        }
        preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        preferences.changes.sink { [weak self] _ in self?.seedCurrentSavedInterests() }.store(in: &observations)
        newsletter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        coordinator.start(needsIntroduction: model.isPresented, needsWhatsNew: false, blocked: false)
    }
    func replay() {
        guard model.permitsIntroduction, coordinator.isIdle else { return }
        if !model.hasLoaded, !model.start() {
            if model.storageError != nil { coordinator.replay() }; return
        }
        guard model.replay() else { if model.storageError != nil { coordinator.replay() }; return }
        newsletter.cancel(); coordinator.replay()
    }
    func recreateModel() {
        guard accountPresentation == nil else { return }
        let replacement = Self.makeModel(memory: memory, canonical: canonical, recovery: recovery); replacement.start()
        model = replacement; modelID = UUID(); observeModel(); resumed += 1
    }
    func releaseTopics() { topics = Self.availableTopics; isLoadingTopics = false; topicsError = nil }
    func failTopics() { topics = []; isLoadingTopics = false; topicsError = "Lokal emnefejl" }
    func failIntroductionWrite() { memory.failNextIntroductionWrite = true; objectWillChange.send() }
    func failPreferenceWrite() { memory.failNextPreferenceWrite = true; objectWillChange.send() }
    func releasePreferenceLoad() { pendingPreferenceLoad?.resume(); pendingPreferenceLoad = nil }
    func stopIntroductionForRecovery() {
        guard let recovery, let uid = canonical.snapshot.userID else { return }
        let originalModel = model
        oldIntroductionAction = { [weak self, originalModel] in
            guard let self else { return }
            let denied = [originalModel.toggleTopic("film"), originalModel.replay(), originalModel.retry()].allSatisfy { !$0 }
            if denied { rejectedOldActions += 1 }
            coordinator.replay()
            objectWillChange.send()
        }
        Task { [weak self] in
            _ = try? await recovery.seal(binding: .init(ownerUID: uid, epoch: 1))
            self?.objectWillChange.send()
        }
    }
    func deliverOldIntroductionAction() { oldIntroductionAction?() }
    func captureInterestCommit(_ ids: [String]) -> (@MainActor () async -> Bool)? {
        let original = canonical.contextTicket()
        guard let uid = original.userID, !model.isAwaitingSavedInterests else { return nil }
        return accountActions.captureInterestCommit(ids: ids, userID: uid, context: original)
    }
    var savedInterestsError: String? {
        let value = preferences.snapshot
        guard model.isAwaitingSavedInterests, value.userID == canonical.snapshot.userID,
              value.errorMessage != nil || (!value.isLoading && !value.loaded) else { return nil }
        return "Dine gemte interesser kunne ikke hentes. Prøv igen, eller vælg dem senere."
    }
    func seedCurrentSavedInterests() {
        guard model.isAwaitingSavedInterests else { return }
        let original = canonical.contextTicket(), value = preferences.snapshot
        guard canonical.isCurrent(original), let uid = original.userID,
              value.userID == uid, value.loaded, value.loadVersion != nil,
              !value.isLoading, !value.isSaving, value.errorMessage == nil else { return }
        _ = model.seedSavedInterests(value.preferences.interestTopicIDs, context: original) { [weak self] in
            guard let self else { return false }
            let current = preferences.snapshot
            return canonical.isCurrent(original) && current.userID == uid && current.loaded &&
                current.generation == value.generation && current.revision == value.revision &&
                current.loadVersion == value.loadVersion && !current.isLoading && !current.isSaving && current.errorMessage == nil
        }
    }
    func retrySavedInterests() {
        let original = canonical.contextTicket()
        guard model.isAwaitingSavedInterests, let uid = original.userID,
              let owner = accountActions.captureOwner(userID: uid, context: original) else { return }
        Task { @MainActor in
            guard canonical.isCurrent(original), model.isAwaitingSavedInterests else { return }
            _ = await accountActions.retry(owner)
            guard canonical.isCurrent(original) else { return }
            seedCurrentSavedInterests()
        }
    }
    func signOut() -> String? {
        let previous = canonical.snapshot.session
        signOutAttempts += 1
        let fails = scenario == "restored-signout-failure" && signOutAttempts == 1
        // Production explicitly keeps the chooser mounted while sign-out
        // revokes authority, then either confirms guest or restores the account.
        canonical.suspend()
        model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        preferences.changeContext(to: .unresolved)
        canonical.adopt(fails ? previous : nil)
        model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        if let context = preferences.changeContext(to: .confirmed(userID: canonical.snapshot.userID)) {
            Task { await preferences.load(context) }
        }
        generationChanges += 1
        model.replay()
        return fails ? "Du kunne ikke logges ud. Prøv igen." : nil
    }
    func finish() { coordinator.finishIntroduction() }
    func deferIntroduction() { deferrals += 1; coordinator.dismissCover() }
    func account(_ entry: ReaderAccountEntry) {
        guard accountPresentation == nil, !accountDismissing,
              let ticket = model.beginAccountEntry(actionID: UUID()) else { return }
        accountRequests += 1; lastEntry = entry
        let id = UUID()
        let form = EmailAccountFlowModel { [weak self] action, fields in
            guard let self, accountPresentation?.id == id else { throw CancellationError() }
            if action == .resetPassword { return nil }
            return await acceptLogin(ticket: ticket, isNewUser: action == .signUp,
                                     email: fields.normalizedEmail, verified: action != .signUp)
        }
        form.action = entry.initialEmailAction
        accountPresentation = AccountPresentation(id: id, entry: entry, ticket: ticket, form: form)
    }
    @discardableResult
    func acceptLogin(ticket: ReaderIntroductionModel.AccountEntryTicket, isNewUser: Bool,
                     email: String = "reader@example.invalid", verified: Bool = true) async -> ReaderAccountSession? {
        guard !accountInFlight, accountPresentation?.ticket == ticket, canonical.isCurrent(ticket.originalContext) else { return nil }
        accountInFlight = true
        let session = ReaderAccountSession(uid: isNewUser ? "local-new-reader" : "local-existing-reader", email: email, isEmailVerified: verified)
        guard let accepted = canonical.adopt(session) else { accountInFlight = false; return nil }
        model.bindContext(accepted, isCurrent: canonical.isCurrent)
        // Give SwiftUI a real render turn with canonical account published but
        // no accepted receipt, matching asynchronous provider completion.
        try? await Task.sleep(for: .milliseconds(150))
        guard accountPresentation?.ticket == ticket, canonical.isCurrent(accepted) else { accountInFlight = false; return nil }
        let result = ReaderLoginResult(originalContext: ticket.originalContext, acceptedContext: accepted,
            session: session, isNewUser: isNewUser, actionID: ticket.actionID)
        let saved = model.acceptLogin(result, ticket: ticket)
        accountInFlight = false
        guard saved || model.storageError != nil else { return nil }
        acceptedLogins += 1; lastLoginWasNew = isNewUser
        if let context = preferences.changeContext(to: .account(session.uid)) {
            Task { await preferences.load(context) }
        }
        seedCurrentSavedInterests()
        dismissAccount(cancelled: false)
        return session
    }
    func dismissAccount(cancelled: Bool = true) {
        guard let presentation = accountPresentation else { return }
        if cancelled { model.cancelAccountEntry(presentation.ticket); presentation.form.cancel(); presentation.form.clearPasswords() }
        accountDismissing = true; accountPresentation = nil
    }
    func accountDidDismiss() {
        accountDismissing = false
        if model.isCompleted && !model.isPresented { coordinator.finishIntroduction() }
    }
    func didOpenAccount() { accountVisits += 1 }
    func activateAccountEntry() { providerActivations += 1 }
    func subscribe() -> Bool {
        guard let session = canonical.snapshot.session else { return false }
        return newsletter.beginExplicitOptIn(session: session, context: canonical.contextTicket())
    }
    func replaceGuestGeneration() {
        if let presentation = accountPresentation { model.cancelAccountEntry(presentation.ticket) }
        canonical.adopt(nil, forceNewGeneration: true)
        model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        preferences.changeContext(to: .guest); generationChanges += 1
    }
    var status: String {
        let sheet = accountPresentation != nil || accountDismissing ? "account" : "none"
        let confirmed = newsletter.status == .subscribed || newsletter.status == .alreadySubscribed
        let saved = canonical.snapshot.userID.flatMap { memory.preferences[$0]?.interestTopicIDs } ?? []
        return "recoveryClosed=\(model.permitsIntroduction ? 0 : 1) oldActionsRejected=\(rejectedOldActions) preferenceReads=\(preferenceReadAttempts) preferencesLoading=\(preferences.snapshot.isLoading ? 1 : 0) systemReduceMotion=\(UIAccessibility.isReduceMotionEnabled ? 1 : 0) systemReduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled ? 1 : 0) firebase=\(FirebaseApp.allApps == nil ? "off" : "ON") loaded=\(model.hasLoaded ? 1 : 0) awaitingSavedInterests=\(model.isAwaitingSavedInterests ? 1 : 0) completed=\(model.isCompleted ? 1 : 0) step=\(model.step.rawValue) selected=\(model.selectedTopicIDs.joined(separator: ",")) saved=\(saved.joined(separator: ",")) preferenceWrites=\(memory.preferenceWrites) introWrites=\(memory.introductionWrites) cover=\(coordinator.cover == nil ? 0 : 1) sheet=\(sheet) awaiting=\(coordinator.isAwaitingDismissal || accountDismissing ? 1 : 0) accountRequests=\(accountRequests) accountVisits=\(accountVisits) acceptedLogins=\(acceptedLogins) newUser=\(lastLoginWasNew ? 1 : 0) newsletterRequests=\(newsletterRequests) newsletterConfirmed=\(confirmed ? 1 : 0) newsletterStatus=\(newsletter.status) newsletterChallengeSent=\(newsletterPayload?.reconfirmationChallenge != nil ? 1 : 0) newsletterConsent=\(newsletterPayload?.consent == true ? 1 : 0) newsletterSource=\(newsletterPayload?.source ?? "none") newsletterVersion=\(newsletterPayload?.consentVersion ?? "none") newsletterRequestStable=\(newsletterRequestStable ? 1 : 0) resumed=\(resumed) deferrals=\(deferrals) provider=\(lastEntry.map { String(describing: $0.provider) } ?? "none") generationChanges=\(generationChanges) providerActivations=\(providerActivations)"
    }
    func welcomeReport(isAccessibilitySize: Bool, colorScheme: ColorScheme) -> String {
        let value: [String: Any] = [
            "language": languagePreferences.articleLanguage.rawValue,
            "modelID": modelID.uuidString, "revision": model.snapshot.revision.uuidString,
            "step": model.step.rawValue, "selectedTopicIDs": model.selectedTopicIDs,
            "introductionReads": memory.introductionReads, "introductionWrites": memory.introductionWrites,
            "accountRequests": accountRequests, "newsletterRequests": newsletterRequests,
            "newsletterConsent": newsletterPayload?.consent == true, "firebaseStarted": FirebaseApp.allApps != nil,
            "dynamicTypeIsAccessibilitySize": isAccessibilitySize,
            "colorScheme": colorScheme == .dark ? "dark" : "light"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

struct LocalIntroductionSmokeView: View {
    @Environment(\.colorScheme) private var presentingColorScheme
    @StateObject private var fixture = LocalIntroductionFixture()
    @ScaledMetric(relativeTo: .headline) private var providerButtonHeight: CGFloat = 48
    private let visualOnly = ProcessInfo.processInfo.arguments.contains("-IntroductionVisualOnly")
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    status
                    Text("Magasinet").font(.largeTitle.bold()).accessibilityIdentifier("introduction.fixture.magazine")
                    Text("Kun lokale testdata. Ingen rigtig konto, e-mail, hjemmeside eller notifikationstjeneste åbnes.")
                    Button("Vis introduktion", action: fixture.replay).frame(minHeight: 44).accessibilityIdentifier("introduction.fixture.replay")
                    if ProcessInfo.processInfo.arguments.contains("recovery") {
                        Button("Aflever gammel introduktionshandling", action: fixture.deliverOldIntroductionAction)
                            .frame(minHeight: 44).accessibilityIdentifier("introduction.fixture.oldAction")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.accessibilityIdentifier("introduction.fixture.home")
        }
        .modifier(ReaderLaunchPresentation(coordinator: fixture.coordinator,
            introduction: { AnyView(introduction) },
            whatsNew: { AnyView(Text("Versionsnyheder · lokal test")) },
            account: { _ in AnyView(Text("Uventet separat kontodestination")) },
            newsletter: { AnyView(Text("Uventet ekstern nyhedsbrevsdestination")) }))
        .onAppear { fixture.start() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            fixture.objectWillChange.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceTransparencyStatusDidChangeNotification)) { _ in
            fixture.objectWillChange.send()
        }
    }
    private var introduction: some View {
        ReaderIntroductionView(model: fixture.model, topics: fixture.topics,
            isLoadingTopics: fixture.isLoadingTopics, topicsError: fixture.topicsError,
            isGuest: fixture.canonical.snapshot.context == .guest,
            language: Binding(get: { fixture.languagePreferences.articleLanguage },
                              set: { fixture.languagePreferences.updateArticleLanguage($0) }),
            welcomeColorScheme: presentingColorScheme,
            accountContextGeneration: fixture.canonical.snapshot.generation,
            onRetryTopics: fixture.releaseTopics, onCaptureInterests: fixture.captureInterestCommit,
            onFinish: fixture.finish, onDefer: fixture.deferIntroduction, onAccount: fixture.account,
            accountButtons: { AnyView(providerButtons) },
            accountIsWorking: fixture.accountPresentation != nil || fixture.accountDismissing || fixture.accountInFlight,
            signedInEmail: fixture.canonical.snapshot.session?.email, onSignOut: fixture.signOut,
            newsletterStatus: fixture.newsletter.status, newsletterMessage: fixture.newsletter.message,
            onNewsletterSignup: fixture.subscribe, onNewsletterRetry: fixture.newsletter.retry,
            savedInterestsError: fixture.savedInterestsError, onRetrySavedInterests: fixture.retrySavedInterests,
            newsletterCanReconfirm: fixture.newsletter.canReconfirm, onNewsletterReconfirm: fixture.newsletter.reconfirm)
            .id(fixture.modelID)
            .environment(\.locale, AppLocalization.locale(for: fixture.languagePreferences.articleLanguage))
            .overlay(alignment: .topLeading) {
                LocalWelcomeFixtureReport(fixture: fixture)
            }
            .onChange(of: fixture.model.snapshot.revision) { _, _ in fixture.seedCurrentSavedInterests() }
            .safeAreaInset(edge: .top, spacing: 0) { if !visualOnly { controls } }
            .sheet(item: Binding(get: { fixture.accountPresentation }, set: {
                if $0 == nil { fixture.dismissAccount() }
            }), onDismiss: fixture.accountDidDismiss) { presentation in
                LocalIntroductionAccountSheet(fixture: fixture, presentation: presentation)
            }
    }
    /// Copies only the production providers' idle appearance. No auth SDK,
    /// provider service or real credential is initialized by these controls.
    private var providerButtons: some View {
        VStack(spacing: 10) {
            ReaderIntroductionAppleButton {
                fixture.account(ReaderAccountEntry(topicIDs: fixture.model.selectedTopicIDs, provider: .apple))
            }
            .frame(maxWidth: .infinity).frame(height: max(48, providerButtonHeight))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
            Button {
                fixture.account(ReaderAccountEntry(topicIDs: fixture.model.selectedTopicIDs, provider: .google))
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleSignInMark").resizable().scaledToFit().frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text("Fortsæt med Google")
                        .font(.headline).foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity).frame(minHeight: 48)
                .background(Color.white).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .accessibilityIdentifier("introduction.account.google")
        }
    }
    private var status: some View {
        Text(FirebaseApp.allApps == nil ? "Simuleret introtest · Firebase ikke startet" : "FEJL: Firebase startet")
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("introduction.fixture.state").accessibilityValue(fixture.status)
    }
    private var controls: some View {
        HStack(spacing: 8) {
            status.frame(maxWidth: .infinity, alignment: .leading)
            Menu("Testdata") {
                if ProcessInfo.processInfo.arguments.contains("recovery") {
                    Button("Stop lokal konto", action: fixture.stopIntroductionForRecovery).accessibilityIdentifier("introduction.fixture.stop")
                }
                Button("Indlæs emner", action: fixture.releaseTopics).accessibilityIdentifier("introduction.fixture.topics.release")
                Button("Emner fejler", action: fixture.failTopics).accessibilityIdentifier("introduction.fixture.topics.fail")
                Button("Genopret lokal model", action: fixture.recreateModel).accessibilityIdentifier("introduction.fixture.resume")
                Button("Næste introvalg fejler", action: fixture.failIntroductionWrite).accessibilityIdentifier("introduction.fixture.intro.fail")
                Button("Næste interessegemning fejler", action: fixture.failPreferenceWrite).accessibilityIdentifier("introduction.fixture.preferences.fail")
                Button("Skift lokal kontogeneration", action: fixture.replaceGuestGeneration).accessibilityIdentifier("introduction.fixture.generation")
                Button("Afslut kontohentning", action: fixture.releasePreferenceLoad).accessibilityIdentifier("introduction.fixture.preferences.release")
            }.frame(minHeight: 44).accessibilityIdentifier("introduction.fixture.controls")
        }
        .padding(.horizontal, 16).dynamicTypeSize(.large).background(Color(uiColor: .secondarySystemBackground))
    }
}

/// Read the actual cover's environment, not the underlying magazine window.
/// Metadata reserves no layout/safe area and invokes no action or storage read.
private struct LocalWelcomeFixtureReport: View {
    @ObservedObject var fixture: LocalIntroductionFixture
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text("Lokal velkomststatus").font(.system(size: 1)).frame(width: 1, height: 1)
            .opacity(0.01).allowsHitTesting(false)
            .accessibilityIdentifier("introduction.welcome.fixture.report")
            .accessibilityValue(fixture.welcomeReport(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                                      colorScheme: colorScheme))
    }
}

private struct LocalIntroductionAccountSheet: View {
    @ObservedObject var fixture: LocalIntroductionFixture
    let presentation: LocalIntroductionFixture.AccountPresentation
    @ObservedObject private var form: EmailAccountFlowModel
    init(fixture: LocalIntroductionFixture, presentation: LocalIntroductionFixture.AccountPresentation) {
        self.fixture = fixture; self.presentation = presentation; form = presentation.form
    }
    private var showsEmail: Bool {
        presentation.entry.provider == .emailSignUp || presentation.entry.provider == .emailSignIn
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Kun simulerede resultater") {
                    Text("Ingen rigtig konto oprettes. Resultatknapperne afprøver den samme onboardingmodel med lokale kvitteringer.")
                        .font(.footnote).accessibilityIdentifier("introduction.fixture.account")
                    Text("Lokal konto · Firebase ikke startet")
                        .accessibilityIdentifier("introduction.fixture.state").accessibilityValue(fixture.status)
                    Text(String(describing: presentation.entry.provider)).accessibilityIdentifier("introduction.fixture.account.provider")
                }
                if showsEmail {
                    Section {
                        Text(form.action == .signUp ? "Opret med e-mail" : form.action == .signIn ? "Log ind med e-mail" : "Nulstil adgangskode")
                            .accessibilityIdentifier("introduction.fixture.account.mode")
                    }
                    EmailAccountFormSections(form: form)
                }
                Section("Simuleret providerkvittering") {
                    Button("Simulér eksisterende bruger") {
                        Task { await fixture.acceptLogin(ticket: presentation.ticket, isNewUser: false) }
                    }.accessibilityIdentifier("introduction.fixture.account.existing")
                    Button("Simulér ny bruger") {
                        Task { await fixture.acceptLogin(ticket: presentation.ticket, isNewUser: true) }
                    }.accessibilityIdentifier("introduction.fixture.account.new")
                }.disabled(fixture.accountInFlight)
            }
            .accessibilityIdentifier("introduction.fixture.account.form")
            .navigationTitle("Lokal loginprøve").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annullér") { fixture.dismissAccount() }.accessibilityIdentifier("introduction.fixture.destination.close")
                }
            }
        }
        .interactiveDismissDisabled().onAppear(perform: fixture.didOpenAccount)
        .background { AccountEntryActivation(onReady: fixture.activateAccountEntry).frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}
#endif
