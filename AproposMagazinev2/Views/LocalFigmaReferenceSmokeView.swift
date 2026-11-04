#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

/// Native reference capture only. Product views are mounted directly; SDK reads,
/// remote artwork, account state and release-entry receipts are not supplied.
@MainActor
private final class LocalFigmaReferenceFixture: ObservableObject {
    let model: ArticleViewModel
    let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
    let author: Author
    let articles: [Article]
    let series: ContentSeries
    let whatsNew: [WhatsNewEntry]
    let notifications: NotificationService

    init() {
        notifications = Self.makeNotifications()
        model = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init())
        author = Author(id: "figma-reference-frederik", name: "Frederik Kragh", bio: nil,
            imageURL: nil, position: "", photoURL: "")
        func artwork(_ name: String) -> URL? {
            let url = URL(fileURLWithPath: "/tmp/apropos-figma-iphone-assets-png-20261031")
                .appendingPathComponent(name + ".png")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        articles = [
            Article(id: "figma-reference-terminal", name: "Anmeldelse: The Terminal List, sæson 1 på Prime Video",
                slug: "anmeldelse-the-terminal-list-saeson-1", content: "",
                intro: "Chris Pratt genopliver videobutikkens actionhelt i The Terminal List på Prime Video.",
                topicID: "reviews", authorID: author.id, mobileImageURL: artwork("terminal"),
                lastPublished: "2026-10-28T12:00:00Z"),
            Article(id: "figma-reference-deep-purple", name: "Anmeldelse: Deep Purple - Royal Arena",
                slug: "deep-purple---58-ar-senere-er-der-stadig-ild-i-orgelet", content: "",
                intro: "Deep Purple indtog Royal Arena med klassikere, rå energi og store orgelsoloer.",
                topicID: "reviews", authorID: "figma-reference-peter", mobileImageURL: artwork("deep-purple"),
                lastPublished: "2026-10-26T12:00:00Z"),
            Article(id: "figma-reference-nogen", name: "Boganmeldelse: Nogen der kender nogen",
                slug: "anmeldelse-nogen-der-kender-nogen-laura-ringo", content: "",
                intro: "Laura Ringo gør boligjagten til skarp og menneskelig litteratur, men stoler ikke altid på sine egne scener.",
                topicID: "reviews", authorID: "figma-reference-liv", mobileImageURL: artwork("nogen"),
                lastPublished: "2026-10-28T12:00:00Z")
        ]
        // A clearly labelled template is used because no real series metadata
        // or author portrait was obtained for this local design-reference task.
        series = ContentSeries(slug: "figma-reference-template", name: "Seriens navn",
            description: "Seriens beskrivelse", articleIds: articles.map(\.id), generatedAt: nil)
        model.authors = [author]
        model.topics = [Topic(id: "reviews", name: "Anmeldelser")]
        model.articles = articles
        whatsNew = WhatsNewManager.shared.entriesForDisplay()
        let args = ProcessInfo.processInfo.arguments
        let screen = args.firstIndex(of: "-FigmaReferenceScreen").flatMap {
            args.indices.contains($0 + 1) ? args[$0 + 1] : nil
        }
        if LocalSmokeMode.isEnabled,
           ["settings", "account-guest", "account-create", "account-signin", "account-reset"].contains(screen ?? "") {
            // Only the simulator capture host confirms a memory-only guest.
            // No provider publication, Auth listener or profile load is begun.
            _ = AuthService.shared.state.adopt(nil)
            UserManager.shared.changeAccountContext(userID: nil)
        }
    }

    private static func makeNotifications() -> NotificationService {
        NotificationService(effects: .init(
            resolveOwner: { .guest },
            authorizationStatus: { _ in .notDetermined },
            requestAuthorization: { _ in false },
            register: { _ in },
            fetchToken: { _ in nil },
            setTopic: { _, _, _, done in done(CancellationError()) },
            saveAccountToken: { _, _, _, done in done(CancellationError()) },
            sendBackendToken: { _, _, _, done in done(CancellationError()) },
            loadSettings: { _ in (NotificationPreferences(), []) },
            persistSettings: { _, _, _ in },
            loadCategoryIDs: { _ in [] },
            persistCategoryIDs: { _, _ in },
            loadToken: { _ in nil },
            persistToken: { _, _ in },
            diagnostic: { _, _ in }
        ))
    }
}

struct LocalFigmaReferenceSmokeView: View {
    @StateObject private var fixture = LocalFigmaReferenceFixture()
    @State private var presented = false
    @State private var pushed = false
    private let screen: String = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-FigmaReferenceScreen"), args.indices.contains(index + 1)
        else { return "help" }
        return args[index + 1]
    }()

    private var isNavigation: Bool { screen == "author" || screen == "series" }
    private var report: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let data: [String: Any] = ["screen": screen, "firebaseStarted": FirebaseApp.allApps != nil,
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "", "presented": presented || pushed,
            "artworkSource": "existing-local-public-png-or-placeholder",
            "authorPortraitAvailable": false, "seriesMetadata": "explicit-template",
            "notificationEffects": "injected-memory-only",
            "accountContext": AuthService.shared.state.snapshot.userID == nil ? "no-account" : "local-account",
            "whatsNewVersions": fixture.whatsNew.map(\.version)]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }

    var body: some View {
        if ["home", "articles", "search", "categories", "category-detail", "minside", "podcasts", "reader"].contains(screen) {
            LocalFigmaEditorialReferenceSmokeView(screen: screen)
        } else {
        NavigationStack {
            Button("Åbn reference") {
                if isNavigation { pushed = true } else { presented = true }
            }
            .accessibilityIdentifier("figma.reference.open")
            .navigationTitle("Lokal reference")
            .navigationDestination(isPresented: $pushed) {
                if screen == "author" {
                    AuthorDetailView(author: fixture.author)
                        .environmentObject(fixture.model)
                } else if screen == "series" {
                    SeriesDetailView(series: fixture.series, articles: fixture.articles)
                }
            }
        }
        .environment(\.navigationCoordinator, fixture.navigation)
        .sheet(isPresented: $presented) {
            sheetContent
                .presentationDetents([.large])
                .overlay(alignment: .bottomLeading) { metadata }
        }
        .overlay(alignment: .bottomLeading) { metadata }
        .tint(.primary)
        }
    }

    @ViewBuilder private var sheetContent: some View {
        switch screen {
        case "help": HelpSupportView()
        case "contact": ContactUsView()
        case "theme": DarkModeOptionsView()
        case "whatsnew": WhatsNewView(entries: fixture.whatsNew, onDismiss: { presented = false })
        case "settings":
            SettingsView(notificationService: fixture.notifications)
                .environmentObject(fixture.model)
        case "account-signedin":
            LocalFigmaAccountReferenceView(screen: .signedIn, onClose: { presented = false })
        case "newsletter-manual":
            LocalFigmaAccountReferenceView(screen: .newsletter, onClose: { presented = false })
        case "account-guest":
            LoginSheetView(isPresented: $presented)
                .environmentObject(fixture.model)
        case "account-create":
            LoginSheetView(isPresented: $presented,
                accountEntry: ReaderAccountEntry(topicIDs: [], provider: .emailSignUp),
                showsNewsletterChoice: false, showsProviderButtons: false)
                .environmentObject(fixture.model)
        case "account-signin", "account-reset":
            // The reset reference taps the actual "Glemt adgangskode?" action
            // after this exact sign-in form appears; there is no copied form.
            LoginSheetView(isPresented: $presented,
                accountEntry: ReaderAccountEntry(topicIDs: [], provider: .emailSignIn),
                showsNewsletterChoice: false, showsProviderButtons: false)
                .environmentObject(fixture.model)
        default: Text("Ukendt lokal reference")
        }
    }

    private var metadata: some View {
        Text("Reference")
            .font(.system(size: 1)).foregroundStyle(.clear)
            .frame(width: 1, height: 1).clipped()
            .accessibilityIdentifier("figma.reference.metadata")
            .accessibilityLabel("Lokal native reference")
            .accessibilityValue(report)
            .allowsHitTesting(false)
    }
}
#endif
