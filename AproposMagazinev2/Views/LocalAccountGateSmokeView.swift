#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalAccountGateFixture: ObservableObject {
    let canonical = CanonicalSessionState()
    lazy var gate = SavedArticleAccountGate(canonical: canonical)
    lazy var inbox = NotificationInboxModel(effects: .init(load: { nil }, save: { _ in },
        delivered: { $0([]) }, removeDelivered: { _ in }, clearBadge: { $0(true) }, open: { _ in false }))
    lazy var favorites = FavoritesModel(storage: .init(read: { _ in nil }, write: { [weak self] _, _ in self?.writes += 1 }))
    let article = Article(id: "gate-article", name: "En artikel til senere", slug: "gate-article",
        content: "<p>Lokalt testindhold.</p>", intro: "", topicID: "topic", contentRevision: "gate-v1")
    @Published var selectedTab = 3
    @Published var language: ArticleContentLanguage = .danish
    @Published private(set) var writes = 0
    @Published var emailAction = ""
    private var subscriptions = Set<AnyCancellable>()
    private let sheet = ProcessInfo.processInfo.arguments.contains("-GatingSheet")
    init() {
        canonical.adopt(nil)
        favorites.changeContext(to: .guest)
        if ProcessInfo.processInfo.arguments.contains("-GatingEnglish") { language = .english }
        selectedTab = sheet ? 0 : 3
        gate.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        canonical.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        favorites.changes.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        if !sheet { gate.present(language: language) }
    }
    func save() {
        // The English fixture uses an account-only prompt. English article
        // identity/filtering is exercised by the actual language fixture.
        gate.present(article: article, language: .danish)
    }
    func login() {
        let action = UUID(), original = canonical.contextTicket()
        guard gate.beginLogin(action) else { return }
        let session = ReaderAccountSession(uid: "local-reader", email: "reader@example.invalid", isEmailVerified: true)
        canonical.adopt(session)
        let accepted = ReaderLoginResult(originalContext: original, acceptedContext: canonical.contextTicket(),
            session: session, isNewUser: false, actionID: action)
        guard gate.accept(accepted, needsIntroduction: false) else { return }
        favorites.changeContext(to: .confirmed(userID: session.uid))
        gate.reconcile(language: language, favorites: favorites.snapshot, favoritesContext: favorites.context,
            canSave: favorites.canChangeSelection, currentArticle: { [self] _ in article },
            save: { [self] in favorites.setFavorite($0, enabled: true) != nil })
    }
    var report: String {
        let value: [String: Any] = ["firebaseStarted": FirebaseApp.allApps != nil,
            "saved": favorites.snapshot.articles.map(\.id), "writes": writes,
            "pending": gate.request != nil, "working": gate.isWorking, "language": language.rawValue]
        return String(data: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

/// Same shared Figma presentation and real gate/favorites models; only account
/// receipts and memory I/O are local. No AuthService or provider is constructed.
struct LocalAccountGateSmokeView: View {
    @StateObject private var fixture = LocalAccountGateFixture()
    @State private var settings = false
    @State private var email = false
    var body: some View {
        TabView(selection: $fixture.selectedTab) {
            NavigationStack {
                VStack(spacing: 24) {
                    Text("En artikel til senere").font(.title)
                    Button("Tilføj til min side", action: fixture.save)
                        .accessibilityIdentifier("guest.fixture.save")
                    Text(fixture.favorites.snapshot.articles.isEmpty ? "Ikke gemt" : "Gemt")
                }.navigationTitle("Artikel")
            }.tabItem { Label("Hjem", systemImage: "house.fill") }.tag(0)
            Color.clear.tabItem { Label("Artikler", systemImage: "text.document.fill") }.tag(1)
            Color.clear.tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }.tag(2)
            MinSidePages(model: fixture.inbox, coverDisplayURL: { _ in nil }, onSettings: { settings = true }) {
                if fixture.canonical.snapshot.userID == nil || fixture.gate.request != nil {
                    welcome(inline: true)
                } else { Text("Din samling").accessibilityIdentifier("guest.fixture.signedIn") }
            }.tabItem { Label("Min side", systemImage: "person.crop.circle.fill") }.tag(3)
        }
        .environment(\.locale, AppLocalization.locale(for: fixture.language))
        .preferredColorScheme(.dark)
        .background {
            Text("Lokalt kontokrav").font(.system(size: 1))
                .accessibilityIdentifier("guest.fixture.report").accessibilityValue(fixture.report)
        }
        .sheet(item: Binding(get: { fixture.gate.request?.isModal == true ? fixture.gate.request : nil },
            set: { if $0 == nil, fixture.gate.request != nil { fixture.gate.cancel() } }),
            onDismiss: { fixture.gate.presentationDidDismiss() }) { _ in
            welcome(inline: false).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $settings) {
            NavigationStack { Form {
                Picker("Appens sprog", selection: $fixture.language) {
                    Text("Dansk").tag(ArticleContentLanguage.danish)
                    Text("English").tag(ArticleContentLanguage.english)
                }
            }.navigationTitle("Indstillinger").toolbar { Button("Færdig") { settings = false } } }
        }
        .sheet(isPresented: $email) {
            NavigationStack { Text(LocalizedStringKey(fixture.emailAction))
                .accessibilityIdentifier("guest.fixture.emailAction")
                .toolbar { Button("Luk") { email = false } } }
        }
    }
    private func welcome(inline: Bool) -> some View {
        ZStack {
            ReaderIntroductionBackdrop(isPresented: false)
            GuestAccountWelcome(inline: inline, isWorking: fixture.gate.isWorking,
                onEmail: { fixture.emailAction = "Opret konto"; email = true },
                onSignIn: { fixture.emailAction = "Log ind"; email = true }) {
                ReaderIntroductionAppleButton(action: fixture.login)
                    .frame(height: 48).accessibilityIdentifier("guest.fixture.apple")
                Button(action: fixture.login) {
                    HStack(spacing: 12) {
                        Image("GoogleSignInMark").resizable().scaledToFit().frame(width: 20, height: 20)
                        Text("Fortsæt med Google").font(.headline)
                    }.foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("guest.fixture.google")
            }
        }.environment(\.locale, AppLocalization.locale(for: fixture.language))
    }
}
#endif
