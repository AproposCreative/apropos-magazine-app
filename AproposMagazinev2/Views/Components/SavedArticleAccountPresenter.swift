import SwiftUI

struct SavedArticleAccountPresenter: ViewModifier {
    @ObservedObject var gate: SavedArticleAccountGate
    @State private var presentedIDs: [UUID] = []
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { gate.request?.isModal == true ? gate.request : nil },
            set: { if $0 == nil, let id = gate.request?.id, id == presentedIDs.first { gate.cancel() } }), onDismiss: {
                if !presentedIDs.isEmpty { gate.presentationDidDismiss(requestID: presentedIDs.removeFirst()) }
            }) { original in
            SavedArticleAccountEntry(gate: gate, inline: false)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .onAppear { if !presentedIDs.contains(original.id) { presentedIDs.append(original.id) } }
        }
    }
}

/// Live composition of existing provider buttons and email flow; no new auth
/// service, automatic email consent or account-linking behavior is introduced.
struct SavedArticleAccountEntry: View {
    @ObservedObject var gate: SavedArticleAccountGate
    var inline: Bool
    @EnvironmentObject private var articles: ArticleViewModel
    @ObservedObject private var canonical = AuthService.shared.state
    @ObservedObject private var favorites = FavoritesRuntime.model
    @State private var lifetime = AccountLoginLifetime()
    @State private var lifetimeID = UUID()
    @State private var introTicket: ReaderIntroductionModel.AccountEntryTicket?
    @State private var email: EmailEntry?
    @State private var originalPresentationID: UUID?
    private struct EmailEntry: Identifiable { let id = UUID(); let entry: ReaderAccountEntry }

    var body: some View {
        ZStack {
            ReaderIntroductionBackdrop(isPresented: false)
            GuestAccountWelcome(inline: inline, isWorking: gate.isWorking, message: gate.message,
                onEmail: { openEmail(.emailSignUp) }, onSignIn: { openEmail(.emailSignIn) }) {
                Group {
                AppleAccountSignInButton(lifetime: lifetime, onLoginStarted: begin,
                    onAuthenticated: accepted, onLoginFinished: finished, introductionStyle: true)
                GoogleSignInButton(lifetime: lifetime, onLoginStarted: begin,
                    onAuthenticated: accepted, onLoginFinished: finished, introductionStyle: true)
                }.id(lifetimeID)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            prepareInlineEntry()
            originalPresentationID = gate.request?.id
        }
        .onDisappear {
            cancelProvider()
            if inline, let id = originalPresentationID { gate.presentationDidDismiss(requestID: id) }
        }
        .onReceive(canonical.changes) { _ in articles.reconcileAccountSave() }
        .onReceive(favorites.changes) { _ in articles.reconcileAccountSave() }
        .onChange(of: articles.articleLanguage) { _, _ in
            cancelProvider(); email = nil; gate.cancel(); prepareInlineEntry()
        }
        .onChange(of: gate.request?.id) { _, id in
            if id == nil { prepareInlineEntry() }
        }
        .sheet(item: $email, onDismiss: { cancelEntry() }) { original in
            LoginSheetView(isPresented: Binding(get: { email?.id == original.id },
                set: { if !$0 { email = nil } }), accountEntry: original.entry,
                showsNewsletterChoice: false, showsProviderButtons: false, lifetime: lifetime,
                onLoginStarted: begin, onAuthenticated: accepted, onLoginFinished: finished,
                onCancelled: cancelEntry)
                .environmentObject(articles)
        }
    }

    private func openEmail(_ provider: ReaderAccountEntry.Provider) {
        guard !gate.isWorking, email == nil else { return }
        email = EmailEntry(entry: ReaderAccountEntry(topicIDs: [], provider: provider))
    }
    private func begin(_ id: UUID) {
        prepareInlineEntry()
        guard gate.beginLogin(id) else { lifetime.invalidate(); return }
        let model = ReaderIntroductionRuntime.introduction, original = canonical.contextTicket()
        guard model.bindContext(original, isCurrent: canonical.isCurrent), model.start() else {
            gate.loginFinished(id); lifetime.invalidate(); return
        }
        introTicket = model.beginAccountEntry(actionID: id, fromFeature: true)
        if introTicket == nil { gate.loginFinished(id); lifetime.invalidate() }
    }
    private func accepted(_ result: ReaderLoginResult) {
        let model = ReaderIntroductionRuntime.introduction
        guard let original = introTicket, original.actionID == result.actionID,
              canonical.acceptedSession(result.session, ticket: result.acceptedContext) != nil,
              model.bindContext(result.acceptedContext, isCurrent: canonical.isCurrent),
              gate.accept(result, needsIntroduction: result.isNewUser) else { return }
        _ = model.acceptLogin(result, ticket: original)
        introTicket = nil; email = nil
        articles.reconcileAccountSave()
    }
    private func finished(_ id: UUID) {
        gate.loginFinished(id)
        if introTicket?.actionID == id { cancelEntry() }
    }
    private func cancelEntry() {
        let original = introTicket
        introTicket = nil
        if let original { ReaderIntroductionRuntime.introduction.cancelAccountEntry(original) }
    }
    private func cancelProvider() { cancelEntry(); lifetime.invalidate() }

    private func prepareInlineEntry() {
        guard inline, gate.isGuest, gate.request == nil else { return }
        // A cancelled language/context-specific attempt must not leave the
        // still-visible inline page holding a permanently retired provider.
        // Recreate only its local presentation; no provider starts here.
        cancelProvider()
        lifetime = AccountLoginLifetime(); lifetimeID = UUID()
        _ = gate.present(language: articles.articleLanguage)
        originalPresentationID = gate.request?.id
    }
}
