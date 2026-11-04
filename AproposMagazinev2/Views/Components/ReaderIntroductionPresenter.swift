import SwiftUI

/// Production dependencies live here; the shared modal coordinator and views
/// remain injectable in the offline native fixture.
struct ReaderIntroductionPresenter: ViewModifier {
    @Environment(\.colorScheme) private var presentingColorScheme
    let automatic: Bool
    var startupBlocked = false
    @Binding var replayRequested: Bool
    var featureSetupRequested = false
    var canOpenFeatureSetup: () -> Bool = { false }
    var didOpenFeatureSetup: () -> Void = {}
    @EnvironmentObject private var articles: ArticleViewModel
    @ObservedObject private var canonical = AuthService.shared.state
    @ObservedObject private var model = ReaderIntroductionRuntime.introduction
    @ObservedObject private var incomingLinks = IncomingLinkRuntime.shared
    @StateObject private var coordinator = ReaderLaunchCoordinator(presentationAllowed: {
        ReaderIntroductionRuntime.introduction.permitsIntroduction
    })
    @State private var newsletterContext: CanonicalSessionState.ContextTicket?
    @State private var newsletterEmail = ""
    @ObservedObject private var newsletterModel = ReaderNewsletterRuntime.model
    @ObservedObject private var preferencesModel = ReaderPreferencesService.shared.model
    @ObservedObject private var languagePreferences = PreferencesManager.shared
    @State private var accountEntryTicket: ReaderIntroductionModel.AccountEntryTicket?
    @State private var loginLifetime = AccountLoginLifetime()
    @State private var appleWorking = false
    @State private var googleWorking = false
    @State private var accountInFlight = false
    @State private var accountSwitchInProgress = false
    @State private var emailEntry: EmailEntry?
    private struct EmailEntry: Identifiable {
        let id = UUID()
        let entry: ReaderAccountEntry
    }

    func body(content: Content) -> some View {
        content.modifier(ReaderLaunchPresentation(coordinator: coordinator,
            introduction: { AnyView(introduction) },
            whatsNew: {
                let original = canonical.contextTicket()
                guard introductionActionIsCurrent(original) else { return AnyView(EmptyView()) }
                return AnyView(WhatsNewView(entries: WhatsNewManager.shared.entriesForDisplay()) {
                    guard introductionActionIsCurrent(original) else { return }
                    markCurrentNewsSeen()
                    coordinator.dismissSheet()
                }.interactiveDismissDisabled())
            },
            account: { entry in
                guard model.permitsIntroduction else { return AnyView(EmptyView()) }
                return AnyView(LoginSheetView(isPresented: Binding(
                get: { coordinator.sheet?.kind == .account },
                set: { if !$0 { coordinator.dismissSheet() } }), suggestedInterestTopicIDs: entry.topicIDs, accountEntry: entry)
                .environmentObject(articles)
                .onAppear { coordinator.accountDidAppear() }) },
            newsletter: {
                guard model.permitsIntroduction else { return AnyView(EmptyView()) }
                return AnyView(NewsletterSignupView(email: newsletterContext.map { introductionActionIsCurrent($0) } == true
                    ? newsletterEmail : ""))
            }))
        .task { synchronize() }
        .onReceive(model.changes) { _ in
            if !model.permitsIntroduction { suspendDeniedIntroduction() }
        }
        .onReceive(preferencesModel.changes) { _ in seedCurrentSavedInterests() }
        .onChange(of: model.snapshot.revision) { _, _ in seedCurrentSavedInterests() }
        .onReceive(canonical.changes) { _ in
            // Until the sheet appears, the intro owns this proposal. Afterwards
            // the sheet's continuously observed proposal owns account changes.
            coordinator.reconcileAccountHandoff(with: canonical)
            if let original = newsletterContext, !canonical.isCurrent(original) {
                newsletterContext = nil; newsletterEmail = ""
                coordinator.suspend()
            }
            synchronize()
        }
        .onChange(of: replayRequested) { _, requested in
            if requested { replay() }
        }
        .onChange(of: featureSetupRequested) { _, requested in
            if requested { presentFeatureSetup() }
        }
        .onChange(of: incomingLinks.acceptedIntentRevision) { _, _ in
            coordinator.suspend()
        }
        .onChange(of: coordinator.isIdle) { _, idle in
            if idle {
                newsletterContext = nil; newsletterEmail = ""
                if featureSetupRequested { presentFeatureSetup() }
                if replayRequested { replay() }
            }
        }
        .onChange(of: coordinator.cover?.id) { _, id in
            if id == nil { cancelAccountEntry(); loginLifetime.invalidate(); emailEntry = nil }
        }
    }

    private var introduction: some View {
        let renderedContext = canonical.contextTicket()
        return ReaderIntroductionView(model: model, topics: articles.topics,
            isLoadingTopics: articles.isLoadingTopics,
            topicsError: articles.topicsError.map { _ in "Emnerne kunne ikke hentes. Du kan prøve igen eller fortsætte uden." },
            isGuest: canonical.snapshot.context == .guest,
            language: Binding(get: { languagePreferences.articleLanguage },
                set: { languagePreferences.updateArticleLanguage($0) }),
            welcomeColorScheme: presentingColorScheme,
            accountContextGeneration: canonical.snapshot.generation,
            onRetryTopics: { if introductionActionIsCurrent(renderedContext) { articles.fetchTopics() } },
            onCaptureInterests: { ids in
                let original = renderedContext
                guard introductionActionIsCurrent(original), !model.isAwaitingSavedInterests else { return nil }
                if original.context == .guest {
                    return {
                        guard introductionActionIsCurrent(original) else { return false }
                        guard !ids.isEmpty else { return true }
                        let store = ReaderIntroductionRuntime.guestInterests
                        guard store.start(), introductionActionIsCurrent(original) else { return false }
                        return store.save(ids, context: original, isCurrent: introductionActionIsCurrent)
                    }
                }
                guard let uid = original.userID else { return nil }
                let actions = AuthService.shared.readerAccountActions
                guard let commit = actions.captureInterestCommit(ids: ids, userID: uid, context: original),
                      introductionActionIsCurrent(original) else { return nil }
                return {
                    guard introductionActionIsCurrent(original) else { return false }
                    let accepted = await commit()
                    return introductionActionIsCurrent(original) && accepted
                }
            }, onFinish: { if introductionActionIsCurrent(renderedContext) { finish() } },
            onDefer: { if introductionActionIsCurrent(renderedContext) { coordinator.dismissCover() } },
            onAccount: { entry in
                let original = renderedContext
                guard original.context == .guest, introductionActionIsCurrent(original), emailEntry == nil else { return }
                emailEntry = EmailEntry(entry: entry)
            }, accountButtons: { AnyView(providerButtons) },
            accountIsWorking: accountInFlight || appleWorking || googleWorking,
            signedInEmail: canonical.snapshot.session?.email,
            onSignOut: {
                guard introductionActionIsCurrent(renderedContext), renderedContext.userID != nil else {
                    return "Kontoen har ændret sig. Prøv igen."
                }
                // Keep this explicit account chooser mounted across the
                // synchronous unresolved→guest/restored-account transition.
                // Failed sign-out must retain its visible error and retry.
                accountSwitchInProgress = true
                defer { accountSwitchInProgress = false }
                do {
                    try AuthService.shared.signOut()
                    restoreAccountWelcome()
                    return nil
                } catch {
                    restoreAccountWelcome()
                    return "Du kunne ikke logges ud. Prøv igen."
                }
            },
            newsletterStatus: newsletterModel.status, newsletterMessage: newsletterModel.message,
            onNewsletterSignup: {
                guard introductionActionIsCurrent(renderedContext), let session = canonical.snapshot.session,
                      canonical.acceptedSession(session, ticket: renderedContext) != nil,
                      introductionActionIsCurrent(renderedContext) else { return false }
                return newsletterModel.beginExplicitOptIn(session: session, context: renderedContext)
            }, onNewsletterRetry: {
                guard introductionActionIsCurrent(renderedContext) else { return false }
                return newsletterModel.retry()
            }, savedInterestsError: savedInterestsError, onRetrySavedInterests: retrySavedInterests,
            newsletterCanReconfirm: newsletterModel.canReconfirm, onNewsletterReconfirm: {
                guard introductionActionIsCurrent(renderedContext) else { return false }
                return newsletterModel.reconfirm()
            })
            .environment(\.locale, AppLocalization.locale(for: languagePreferences.articleLanguage))
            .onAppear {
                guard model.permitsIntroduction else { suspendDeniedIntroduction(); return }
                if loginLifetime.isInvalidated { loginLifetime = AccountLoginLifetime() }
            }
            .sheet(item: $emailEntry, onDismiss: { cancelAccountEntry() }) { presentation in
                LoginSheetView(isPresented: Binding(get: { emailEntry?.id == presentation.id },
                    set: { if !$0 { emailEntry = nil } }),
                    accountEntry: presentation.entry,
                    showsNewsletterChoice: false, showsProviderButtons: false,
                    lifetime: loginLifetime,
                    onLoginStarted: beginAccountEntry, onAuthenticated: acceptedLogin,
                    onLoginFinished: loginFinished, onCancelled: cancelAccountEntry)
                    .environmentObject(articles)
            }
    }

    private var providerButtons: some View {
        VStack(spacing: 10) {
            AppleAccountSignInButton(onBusyChanged: { appleWorking = $0 },
                lifetime: loginLifetime,
                onLoginStarted: beginAccountEntry, onAuthenticated: acceptedLogin,
                onLoginFinished: loginFinished, introductionStyle: true)
                .accessibilityIdentifier("introduction.account.apple")
            GoogleSignInButton(onBusyChanged: { googleWorking = $0 },
                lifetime: loginLifetime,
                onLoginStarted: beginAccountEntry, onAuthenticated: acceptedLogin,
                onLoginFinished: loginFinished, introductionStyle: true)
                .accessibilityIdentifier("introduction.account.google")
        }
    }

    private func beginAccountEntry(_ actionID: UUID) {
        guard model.permitsIntroduction, coordinator.cover != nil else { suspendDeniedIntroduction(); return }
        cancelAccountEntry()
        accountEntryTicket = model.beginAccountEntry(actionID: actionID)
        accountInFlight = accountEntryTicket != nil
        if !model.permitsIntroduction || accountEntryTicket == nil { loginLifetime.invalidate() }
    }

    private func cancelAccountEntry() {
        if let original = accountEntryTicket { model.cancelAccountEntry(original) }
        accountEntryTicket = nil
        accountInFlight = false
        appleWorking = false
        googleWorking = false
    }

    private func loginFinished(_ actionID: UUID) {
        guard accountEntryTicket?.actionID == actionID else { return }
        cancelAccountEntry()
    }

    private func acceptedLogin(_ result: ReaderLoginResult) {
        guard model.permitsIntroduction, coordinator.cover != nil, let original = accountEntryTicket,
              result.actionID == original.actionID, result.originalContext == original.originalContext,
              canonical.acceptedSession(result.session, ticket: result.acceptedContext) != nil else { return }
        guard model.bindContext(result.acceptedContext, isCurrent: canonical.isCurrent) else { return }
        let accepted = model.acceptLogin(result, ticket: original)
        guard model.permitsIntroduction else { suspendDeniedIntroduction(); return }
        if accepted || model.storageError != nil {
            accountEntryTicket = nil
            accountInFlight = false
            appleWorking = false
            googleWorking = false
            emailEntry = nil
            seedCurrentSavedInterests()
            if model.isCompleted && !model.isPresented { finish() }
        }
    }

    private func synchronize() {
        guard model.permitsIntroduction else { suspendDeniedIntroduction(); return }
        let original = canonical.contextTicket()
        guard model.bindContext(original, isCurrent: canonical.isCurrent) else { return }
        guard original.context != .unresolved else {
            if coordinator.cover != nil && !accountSwitchInProgress { coordinator.suspend() }
            return
        }
        model.start()
        guard introductionActionIsCurrent(original) else { return }
        if coordinator.cover != nil && !model.isPresented && accountEntryTicket == nil && !accountSwitchInProgress { coordinator.suspend() }
        if replayRequested { replay(); return }
        if automatic {
            coordinator.start(needsIntroduction: model.isPresented,
                needsWhatsNew: WhatsNewManager.shared.shouldShowWhatsNew(),
                blocked: startupBlocked || incomingLinks.hasAcceptedIncomingLink)
        }
    }
    private func restoreAccountWelcome() {
        let current = canonical.contextTicket()
        guard current.context != .unresolved, introductionActionIsCurrent(current),
              model.bindContext(current, isCurrent: canonical.isCurrent) else { return }
        if model.start(), introductionActionIsCurrent(current) { model.replay() }
    }
    private var savedInterestsError: String? {
        let value = preferencesModel.snapshot
        guard model.isAwaitingSavedInterests, value.userID == canonical.snapshot.userID,
              value.errorMessage != nil || (!value.isLoading && !value.loaded) else { return nil }
        return "Dine gemte interesser kunne ikke hentes. Prøv igen, eller vælg dem senere."
    }
    private func seedCurrentSavedInterests() {
        guard model.isAwaitingSavedInterests else { return }
        let original = canonical.contextTicket(), value = preferencesModel.snapshot
        guard introductionActionIsCurrent(original), let uid = original.userID,
              value.userID == uid, value.loaded, value.loadVersion != nil,
              !value.isLoading, !value.isSaving, value.errorMessage == nil else { return }
        _ = model.seedSavedInterests(value.preferences.interestTopicIDs, context: original) {
            let current = preferencesModel.snapshot
            return introductionActionIsCurrent(original) && current.userID == uid && current.loaded &&
                current.generation == value.generation && current.revision == value.revision &&
                current.loadVersion == value.loadVersion && !current.isLoading && !current.isSaving && current.errorMessage == nil
        }
    }
    private func retrySavedInterests() {
        let original = canonical.contextTicket()
        guard model.isAwaitingSavedInterests, introductionActionIsCurrent(original), let uid = original.userID else { return }
        let actions = AuthService.shared.readerAccountActions
        guard let owner = actions.captureOwner(userID: uid, context: original) else { return }
        Task { @MainActor in
            guard introductionActionIsCurrent(original), model.isAwaitingSavedInterests else { return }
            _ = await actions.retry(owner)
            guard introductionActionIsCurrent(original) else { return }
            seedCurrentSavedInterests()
        }
    }
    private func replay() {
        guard model.permitsIntroduction else { suspendDeniedIntroduction(); return }
        guard canonical.snapshot.context != .unresolved, coordinator.isIdle else { return }
        replayRequested = false
        let original = canonical.contextTicket()
        guard model.bindContext(original, isCurrent: canonical.isCurrent) else { return }
        guard model.start() else { coordinator.replay(); return }
        guard model.replay() else { coordinator.replay(); return }
        let preferences = ReaderPreferencesService.shared.model.snapshot
        if original.userID != nil, introductionActionIsCurrent(original), preferences.loaded,
           preferences.userID == original.userID {
            _ = model.setSelectedTopicIDs(preferences.preferences.interestTopicIDs)
        }
        if introductionActionIsCurrent(original) { coordinator.replay() }
    }
    private func presentFeatureSetup() {
        guard featureSetupRequested, canOpenFeatureSetup(), model.permitsIntroduction, model.isPresented,
              canonical.snapshot.userID != nil, coordinator.isIdle else { return }
        // The original feature-login receipt already advanced the real model.
        // Present those interests without replaying Welcome or resetting drafts.
        coordinator.replay()
        didOpenFeatureSetup()
    }
    private func finish(then next: ReaderLaunchCoordinator.FollowUp? = nil) {
        guard model.permitsIntroduction, model.isCompleted else { return }
        markCurrentNewsSeen()
        if model.permitsIntroduction { coordinator.finishIntroduction(then: next) }
    }
    private func markCurrentNewsSeen() {
        guard model.permitsIntroduction else { return }
        if let newest = WhatsNewManager.shared.entriesForDisplay().first, model.permitsIntroduction {
            WhatsNewManager.shared.markEntryAsSeen(newest)
        }
    }
    private func introductionActionIsCurrent(_ context: CanonicalSessionState.ContextTicket) -> Bool {
        guard model.permitsIntroduction, canonical.isCurrent(context) else { return false }
        return model.permitsIntroduction
    }
    private func suspendDeniedIntroduction() {
        // Retire local ownership before cancelling provider callbacks. This
        // cleanup may also run while the cold recovery read is still closed.
        cancelAccountEntry()
        loginLifetime.invalidate()
        emailEntry = nil
        newsletterContext = nil; newsletterEmail = ""
        coordinator.suspend()
    }
}
