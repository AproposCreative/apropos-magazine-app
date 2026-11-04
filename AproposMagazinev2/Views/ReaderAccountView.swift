import SwiftUI

/// Tasks are created after the button captures its original owner and payload.
/// The local fixture can hold this exact closure before execution.
typealias ReaderAccountSchedule = (@escaping @MainActor () async -> Void) -> Void

struct LoginSheetView: View {
    @Binding var isPresented: Bool
    var suggestedInterestTopicIDs: [String]? = nil
    @EnvironmentObject private var articles: ArticleViewModel
    @ObservedObject private var auth = AuthService.shared
    @State private var googleWorking = false
    @State private var appleWorking = false
    @State private var entryActivation: UUID?
    @State private var loginLifetime: AccountLoginLifetime
    private let ownsLoginLifetime: Bool
    @State private var completion: Completion
    @StateObject private var newsletterDraft: ReaderNewsletterOptInDraft
    @ObservedObject private var newsletterModel = ReaderNewsletterRuntime.model
    @StateObject private var form: EmailAccountFlowModel
    var accountEntry: ReaderAccountEntry? = nil
    var showsNewsletterChoice = true
    var showsProviderButtons = true
    var onLoginStarted: (UUID) -> Void = { _ in }
    var onAuthenticated: (ReaderLoginResult) -> Void = { _ in }
    var onLoginFinished: (UUID) -> Void = { _ in }
    var onCancelled: () -> Void = {}

    @MainActor private final class Completion {
        private(set) var authenticated = false
        private(set) var cancelled = false
        func deliver(_ result: ReaderLoginResult, to callback: (ReaderLoginResult) -> Void) {
            guard !authenticated, !cancelled else { return }
            authenticated = true
            callback(result)
        }
        func cancel(_ callback: () -> Void) {
            guard !cancelled else { return }
            cancelled = true
            if !authenticated { callback() }
        }
    }

    init(isPresented: Binding<Bool>, suggestedInterestTopicIDs: [String]? = nil,
         accountEntry: ReaderAccountEntry? = nil,
         showsNewsletterChoice: Bool = true, showsProviderButtons: Bool = true,
         lifetime: AccountLoginLifetime? = nil,
         onLoginStarted: @escaping (UUID) -> Void = { _ in },
         onAuthenticated: @escaping (ReaderLoginResult) -> Void = { _ in },
         onLoginFinished: @escaping (UUID) -> Void = { _ in },
         onCancelled: @escaping () -> Void = {}) {
        _isPresented = isPresented
        self.suggestedInterestTopicIDs = suggestedInterestTopicIDs
        self.accountEntry = accountEntry
        self.showsNewsletterChoice = showsNewsletterChoice
        self.showsProviderButtons = showsProviderButtons
        self.onLoginStarted = onLoginStarted
        self.onAuthenticated = onAuthenticated
        self.onLoginFinished = onLoginFinished
        self.onCancelled = onCancelled
        ownsLoginLifetime = lifetime == nil
        let loginLifetime = lifetime ?? AccountLoginLifetime()
        _loginLifetime = State(initialValue: loginLifetime)
        let completion = Completion()
        _completion = State(initialValue: completion)
        let draft = ReaderNewsletterOptInDraft(canonical: AuthService.shared.state,
                                              selected: accountEntry?.newsletterOptIn ?? false)
        _newsletterDraft = StateObject(wrappedValue: draft)
        _form = StateObject(wrappedValue: EmailAccountFlowModel(capture: { action, fields in
            try loginLifetime.captureEmailOperation {
            guard !completion.cancelled, !completion.authenticated else { throw CancellationError() }
            let auth = AuthService.shared
            let kind: AuthOperationCoordinator.Kind = action == .signIn ? .emailSignIn : action == .signUp ? .emailSignUp : .passwordReset
            let ticket = try auth.captureLogin(kind, newsletterOptIn: showsNewsletterChoice && draft.isSelected(for: auth.state.contextTicket()))
            if action != .resetPassword { onLoginStarted(ticket.actionID) }
            guard !completion.cancelled, !loginLifetime.isInvalidated else {
                auth.cancelLogin(ticket)
                if action != .resetPassword { onLoginFinished(ticket.actionID) }
                throw CancellationError()
            }
            return .init(perform: {
                defer { if action != .resetPassword { onLoginFinished(ticket.actionID) } }
                guard !loginLifetime.isInvalidated else { throw CancellationError() }
                let session = try await auth.perform(action, form: fields, ticket: ticket)
                guard !loginLifetime.isInvalidated else { throw CancellationError() }
                if let session, let result = auth.acceptedLoginResult(ticket, session: session),
                   !loginLifetime.isInvalidated {
                    completion.deliver(result, to: onAuthenticated)
                }
                return session
            },
                cancel: { auth.cancelLogin(ticket) }, feedbackIsCurrent: { auth.loginFeedbackIsCurrent(ticket) })
            }
        }))
    }


    var body: some View {
        let renderedContext = auth.state.contextTicket()
        return NavigationStack {
            Group {
            if !showsProviderButtons && !showsNewsletterChoice {
                // The onboarding email operation owns this presentation until
                // its accepted receipt arrives; canonical publication alone
                // must not replace a pending form with account settings.
                Form {
                    EmailAccountFormSections(form: form, providersWorking: false)
                }
                .accessibilityIdentifier("reader.account.form")
                .navigationTitle(LocalizedStringKey(form.action == .signUp ? "Opret konto" : form.action == .resetPassword ? "Nulstil adgangskode" : "Log ind"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
            ReaderAccountSheetContent(canonical: auth.state,
                preferences: ReaderPreferencesService.shared.model, actions: auth.readerAccountActions,
                topics: articles.topics, onDone: close,
                newsletter: { AnyView(NewsletterSignupView(email: $0)) },
                suggestedInterestTopicIDs: suggestedInterestTopicIDs,
                recoveryContent: { AnyView(ReaderAccountRecoverySection(auth: auth)) },
                recoveryPresentation: { AnyView(ReaderAccountRecoveryPresentation(auth: auth)) }) {
                    if showsProviderButtons { Section {
                        Text("Gem artikler og vælg dine interesser. Du kan fortsat læse magasinet uden en konto.")
                            .foregroundStyle(.secondary)
                        GoogleSignInButton(onBusyChanged: { googleWorking = $0; if $0 { entryActivation = nil } },
                            lifetime: loginLifetime, newsletterOptIn: { showsNewsletterChoice && newsletterDraft.selected },
                            activation: accountEntry?.provider == .google ? entryActivation : nil,
                            activationIsCurrent: { isPresented && newsletterDraft.initialEntryIsCurrent },
                            onLoginStarted: onLoginStarted,
                            onAuthenticated: { completion.deliver($0, to: onAuthenticated) },
                            onLoginFinished: onLoginFinished)
                            .disabled(form.isWorking || appleWorking)
                        AppleAccountSignInButton(onBusyChanged: { appleWorking = $0; if $0 { entryActivation = nil } },
                            lifetime: loginLifetime, newsletterOptIn: { showsNewsletterChoice && newsletterDraft.selected },
                            activation: accountEntry?.provider == .apple ? entryActivation : nil,
                            activationIsCurrent: { isPresented && newsletterDraft.initialEntryIsCurrent },
                            onLoginStarted: onLoginStarted,
                            onAuthenticated: { completion.deliver($0, to: onAuthenticated) },
                            onLoginFinished: onLoginFinished)
                            .disabled(form.isWorking || googleWorking)
                    } }
                    if showsNewsletterChoice { Section {
                        Toggle("Ja tak til Apropos’ nyhedsbrev", isOn: Binding(
                            get: { newsletterDraft.isSelected(for: renderedContext) },
                            set: { newsletterDraft.setSelected($0, context: renderedContext) }))
                            .disabled(form.isWorking || googleWorking || appleWorking)
                            .accessibilityIdentifier("account.newsletter.optin")
                        Text("Historier og anbefalinger på e-mail. Du kan altid afmelde dig.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } }
                    EmailAccountFormSections(form: form, providersWorking: googleWorking || appleWorking)
                } extraContent: {
                    if auth.session != nil, newsletterModel.status != .idle {
                        ReaderNewsletterStatusSection(model: newsletterModel)
                    }
                }
            }
            }
            .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Luk", action: close)
                    }
                }
        }
        .background(AccountEntryActivation {
            guard isPresented, let entry = accountEntry,
                  let original = newsletterDraft.consumeInitialEntryContext() else { return }
            switch entry.provider {
            case .apple, .google:
                guard original.context == .guest else { return }
                entryActivation = UUID()
            case .account:
                guard showsNewsletterChoice, newsletterDraft.isSelected(for: original),
                      let session = auth.state.snapshot.session,
                      auth.state.acceptedSession(session, ticket: original) != nil else { return }
                // A checked introduction can also belong to an already signed-in
                // reader. This explicit original handoff is not an auth listener.
                newsletterModel.begin(session: session, context: original)
            case .email, .emailSignIn, .emailSignUp:
                break
            }
        }.frame(width: 0, height: 0))
        .tint(.primary)
        .task {
            auth.startObservingSession()
            form.action = accountEntry?.initialEmailAction ?? .signIn
        }
        .onChange(of: auth.state.snapshot.generation) { _, _ in
            form.clearPasswords()
            entryActivation = nil
        }
        .onChange(of: isPresented) { _, presented in if !presented { cancelLoginIntents() } }
        .onDisappear { if !isPresented { cancelLoginIntents() } }
        .presentationDetents([.large])
    }
    private func cancelLoginIntents() {
        // An intro email sheet owns its form, while the parent still owns its
        // Apple/Google buttons. Child dismissal must not retire that lifetime.
        if ownsLoginLifetime { loginLifetime.invalidate() }
        form.cancel(); completion.cancel(onCancelled)
    }
    private func close() { cancelLoginIntents(); isPresented = false }
}

/// Shared by the actual login sheet and service-free fixture. Construction does
/// not select a service or begin I/O; every production dependency is explicit.
@MainActor
struct ReaderAccountSheetContent<GuestContent: View, ExtraContent: View>: View {
    @ObservedObject var canonical: CanonicalSessionState
    @ObservedObject var preferences: ReaderPreferencesModel
    let actions: ReaderAccountActions
    let topics: [Topic]
    var schedule: ReaderAccountSchedule = { work in Task { await work() } }
    let onDone: () -> Void
    let newsletter: (String) -> AnyView
    let recoveryContent: (() -> AnyView)?
    let recoveryPresentation: (() -> AnyView)?
    @ViewBuilder let guestContent: () -> GuestContent
    @ViewBuilder let extraContent: () -> ExtraContent
    @StateObject private var introductionProposal: ReaderIntroductionInterestProposal

    init(canonical: CanonicalSessionState, preferences: ReaderPreferencesModel,
         actions: ReaderAccountActions, topics: [Topic],
         schedule: @escaping ReaderAccountSchedule = { work in Task { await work() } },
         onDone: @escaping () -> Void, newsletter: @escaping (String) -> AnyView,
         suggestedInterestTopicIDs: [String]? = nil,
         recoveryContent: (() -> AnyView)? = nil,
         recoveryPresentation: (() -> AnyView)? = nil,
         @ViewBuilder guestContent: @escaping () -> GuestContent,
         @ViewBuilder extraContent: @escaping () -> ExtraContent) {
        self.canonical = canonical; self.preferences = preferences
        self.actions = actions; self.topics = topics; self.schedule = schedule
        self.onDone = onDone; self.newsletter = newsletter
        self.recoveryContent = recoveryContent
        self.recoveryPresentation = recoveryPresentation
        self.guestContent = guestContent; self.extraContent = extraContent
        _introductionProposal = StateObject(wrappedValue: ReaderIntroductionInterestProposal(
            canonical: canonical, suggestedInterestTopicIDs: suggestedInterestTopicIDs))
    }

    var body: some View {
        // Resolve the sheet-owned observer even before a signed-in form exists.
        // A → B between two renders must not reassign A's proposal to B.
        let proposal = introductionProposal
        Group {
            if let session = canonical.snapshot.session {
                ReaderAccountSetupForm(canonical: canonical, preferences: preferences,
                    actions: actions, context: canonical.contextTicket(), session: session,
                    topics: topics, schedule: schedule, onDone: onDone, newsletter: newsletter,
                    introductionProposal: proposal,
                    extraContent: extraContent)
                    .id(canonical.snapshot.generation)
            } else {
                Form {
                    extraContent()
                    if canonical.snapshot.context == .unresolved {
                        if let recoveryContent {
                            recoveryContent()
                        } else {
                            Section {
                                ProgressView("Kontrollerer din konto…")
                                    .accessibilityIdentifier("reader.account.unresolved")
                            }
                        }
                    } else {
                        guestContent()
                    }
                }
                .accessibilityIdentifier("reader.account.form")
            }
        }
        // The modal host stays outside lazy Form rows when their recovery
        // content changes from confirmation to an Auth-owned running flow.
        .background {
            if let recoveryPresentation { recoveryPresentation() }
        }
        .navigationTitle(LocalizedStringKey(canonical.snapshot.session != nil ? "Dine læservalg"
            : canonical.snapshot.context == .unresolved && recoveryContent != nil ? "Din konto" : "Log ind eller opret"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct ReaderAccountSetupForm<ExtraContent: View>: View {
    @Environment(\.locale) private var locale
    @ObservedObject var canonical: CanonicalSessionState
    @ObservedObject var preferences: ReaderPreferencesModel
    let actions: ReaderAccountActions
    let context: CanonicalSessionState.ContextTicket
    let session: ReaderAccountSession
    let topics: [Topic]
    let schedule: ReaderAccountSchedule
    let onDone: () -> Void
    let newsletter: (String) -> AnyView
    @ObservedObject var introductionProposal: ReaderIntroductionInterestProposal
    @ViewBuilder let extraContent: () -> ExtraContent
    @State private var interestDraft = ReaderInterestDraft()
    @State private var isWorking = false
    @State private var message: String?
    @State private var savedReceipt: ReaderAccountActions.SaveAction?
    @State private var newsletterRequest: NewsletterRequest?

    private struct NewsletterRequest: Identifiable {
        let id = UUID()
        let owner: ReaderAccountActions.OwnerAction
        let email: String
    }
    private var ownerMatches: Bool {
        canonical.isCurrent(context) && preferences.snapshot.userID == session.uid
    }
    private var ready: Bool { ownerMatches && preferences.snapshot.loaded && !preferences.snapshot.isLoading }
    private var selected: Set<String> { interestDraft.selected }
    private var savedAlertBinding: Binding<Bool> {
        Binding(get: {
            guard let original = savedReceipt else { return false }
            return actions.isCurrentReceipt(original)
        }, set: { if !$0 { savedReceipt = nil } })
    }

    var body: some View {
        Form {
            extraContent()
            setupSections
        }
        .accessibilityIdentifier("reader.account.form")
        .onAppear { adopt(preferences.snapshot) }
        .onReceive(preferences.changes) {
            adopt($0)
            revokeStaleFeedback()
        }
        .onReceive(canonical.changes) { _ in revokeStaleFeedback() }
        .sheet(item: $newsletterRequest) { request in
            if actions.isCurrent(request.owner) { newsletter(request.email) }
        }
        .alert("Dine valg er gemt", isPresented: savedAlertBinding, presenting: savedReceipt) { original in
            Button("Færdig") {
                guard actions.isCurrentReceipt(original) else { return }
                onDone()
            }
        } message: { _ in Text("Dine interesser er gemt. Du kan ændre dem under Indstillinger.") }
    }

    private var setupSections: some View {
        Group {
            Section {
                Text(session.email).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reader.account.email")
                if !session.isEmailVerified {
                    Text("Bekræft din e-mail for at sikre din konto. Du kan gemme interesser allerede nu.")
                    Button("Send bekræftelsesmail igen") { verify(resend: true) }
                        .accessibilityIdentifier("reader.account.verification.send")
                    Button("Jeg har bekræftet min e-mail") { verify(resend: false) }
                        .accessibilityIdentifier("reader.account.verification.refresh")
                    if let status = canonical.snapshot.verificationMessage {
                        Text(LocalizedStringKey(status)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reader.account.verification.message")
                    }
                } else {
                    Text("Din e-mail er bekræftet.").font(.footnote)
                        .accessibilityIdentifier("reader.account.verification.verified")
                }
            } header: { Text("Din konto") }

            Section {
                Text("Vælg de emner, du gerne vil læse mere om. Dine valg ændrer ikke dine pushnotifikationer.")
                    .font(.footnote).foregroundStyle(.secondary)
                if preferences.snapshot.isLoading { ProgressView("Henter dine valg…") }
                if let error = ownerMatches ? preferences.snapshot.errorMessage : nil {
                    Text(LocalizedStringKey(error)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reader.account.interests.error")
                    if !preferences.snapshot.loaded {
                        Button("Prøv igen", action: retry)
                            .accessibilityIdentifier("reader.account.interests.retry")
                    }
                }
                if topics.isEmpty {
                    Text("Emnerne er ikke hentet endnu. Du kan vælge dem senere i Indstillinger.")
                        .foregroundStyle(.secondary)
                }
                if !introductionProposal.topicIDs(context: context, topics: topics).isEmpty {
                    Button("Brug emner fra introduktionen", action: useIntroductionTopics)
                        .accessibilityIdentifier("reader.account.introduction.interests")
                        .disabled(!ready || preferences.snapshot.isSaving)
                    Text("Forslaget ændrer kun dine valg her. Tryk Gem og fortsæt for at gemme dem på kontoen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(topics.filter(\.isActive)) { topic in
                    Button {
                        guard ready, canonical.isCurrent(context) else { return }
                        interestDraft.toggle(topic.id)
                    } label: {
                        HStack {
                            LocalizedArticleTaxonomy(topic.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if selected.contains(topic.id) { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityIdentifier("reader.account.topic." + topic.id)
                    .accessibilityValue(Text(LocalizedStringKey(selected.contains(topic.id) ? "Valgt" : "Ikke valgt")))
                    .disabled(!ready)
                }
            } header: { Text("Dine interesser (valgfrit)") }

            Section {
                Button("Tilmeld nyhedsbrevet") {
                    guard let owner = actions.captureOwner(userID: session.uid, context: context) else { return }
                    newsletterRequest = NewsletterRequest(owner: owner, email: session.email)
                }
                .accessibilityIdentifier("reader.account.newsletter")
                Text("Få historier og anbefalinger på e-mail. Tilmelding er valgfri, og du kan altid afmelde dig.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let url = NewsletterSignupPolicy.termsURL(for: AppLocalization.language(for: locale)) {
                    Link("Vilkår og privatliv", destination: url)
                }
            } header: { Text("Nyhedsbrev") }

            Section {
                if let message {
                    Text(LocalizedStringKey(message)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reader.account.message")
                }
                Button(action: save) {
                    HStack {
                        Text("Gem og fortsæt")
                        if isWorking || preferences.snapshot.isSaving { Spacer(); ProgressView() }
                    }
                }
                .accessibilityIdentifier("reader.account.save")
                .disabled(isWorking || !ready)
                Button("Vælg senere") {
                    guard let owner = actions.captureOwner(userID: session.uid, context: context), actions.isCurrent(owner) else { return }
                    onDone()
                }
                .accessibilityIdentifier("reader.account.later")
                .disabled(isWorking)
            }
        }
        .disabled(isWorking)
    }

    private func revokeStaleFeedback() {
        if !canonical.isCurrent(context) { interestDraft = ReaderInterestDraft() }
        if let original = savedReceipt, !actions.isCurrentReceipt(original) { savedReceipt = nil }
        if let request = newsletterRequest, !actions.isCurrent(request.owner) { newsletterRequest = nil }
    }

    private func adopt(_ snapshot: ReaderPreferencesModel.Snapshot) {
        guard canonical.isCurrent(context), snapshot.userID == session.uid else { return }
        interestDraft.adopt(generation: snapshot.generation, loadVersion: snapshot.loadVersion,
                            loaded: snapshot.loaded, interestTopicIDs: snapshot.preferences.interestTopicIDs)
    }

    private func retry() {
        guard !isWorking, let original = actions.captureOwner(userID: session.uid, context: context) else { return }
        isWorking = true; message = nil
        schedule {
            _ = await actions.retry(original)
            guard actions.isCurrent(original) else { return }
            isWorking = false
        }
    }

    private func verify(resend: Bool) {
        guard !isWorking, let original = actions.captureOwner(userID: session.uid, context: context) else { return }
        isWorking = true; message = nil
        schedule {
            do {
                if resend { _ = await actions.sendVerification(original) }
                else { _ = try await actions.refresh(original) }
            } catch {
                guard actions.isCurrent(original) else { return }
                message = "Kunne ikke kontrollere e-mailen. Prøv igen, når du er online."
            }
            guard actions.isCurrent(original) else { return }
            isWorking = false
        }
    }

    private func save() {
        guard !isWorking,
              let original = actions.captureSave(ids: Array(selected), userID: session.uid, context: context) else { return }
        isWorking = true; message = nil
        schedule {
            let saved = await actions.save(original)
            guard actions.isCurrent(original) else { return }
            isWorking = false
            if saved, actions.isCurrentReceipt(original) { savedReceipt = original }
        }
    }

    private func useIntroductionTopics() {
        guard !isWorking,
              let owner = actions.captureOwner(userID: session.uid, context: context),
              let ids = introductionProposal.draftTopicIDs(context: context, topics: topics,
                preferences: preferences.snapshot, adoptedGeneration: interestDraft.generation,
                adoptedLoadVersion: interestDraft.loadVersion), actions.isCurrent(owner) else { return }
        interestDraft.replaceSelection(with: ids)
        savedReceipt = nil
    }
}
