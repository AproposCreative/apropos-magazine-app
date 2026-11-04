#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalContentLanguageFixture: ObservableObject {
    static let suite = "apropos.local.content-language-smoke"
    let preferences: PreferencesManager
    let viewModel: ArticleViewModel
    let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
    @Published private(set) var loadState = "waiting"
    @Published private(set) var sourceLanguages: [String] = []
    private var initialLoadStarted = false
    private var mirrorDocuments: [(id: String, data: [String: Any])] = []
    private var decodedFailureCount = 0
    private var observation: AnyCancellable?

    init() {
        let defaults = UserDefaults(suiteName: Self.suite)!
        if ProcessInfo.processInfo.arguments.contains("-ResetContentLanguageFixture") {
            defaults.removePersistentDomain(forName: Self.suite)
        }
        let preferences = PreferencesManager(userDefaults: defaults)
        self.preferences = preferences
        viewModel = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init(), languagePreferences: preferences)
        viewModel.topics = [Topic(id: "music", name: "Musik")]
        observation = Publishers.Merge(viewModel.objectWillChange, navigation.objectWillChange)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    func loadInitialCatalog() async {
        guard !initialLoadStarted else { return }
        initialLoadStarted = true
        await loadCatalog(emptyEnglish: false)
    }

    func removeEnglishFromCatalog() {
        Task { await loadCatalog(emptyEnglish: true) }
    }

    private func loadCatalog(emptyEnglish: Bool) async {
        loadState = "loading"; sourceLanguages = []
        do {
            let enabled = ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:])
            let sources = try await ArticleMirrorCatalog.load(englishEnabled: enabled, stillCurrent: { true }) { language in
                self.sourceLanguages.append(language.rawValue)
                let sourceID = "0123456789abcdef01234567"
                let english = language == .english
                let readerID = english ? "en_" + sourceID : sourceID
                var document: [String: Any] = ["id": readerID, "isDraft": false, "isArchived": false,
                    "lastPublished": "2026-11-03T10:00:00Z", "contentRevision": language.rawValue + "-fixture-current",
                    "fieldData": ["name": english ? "An English culture story" : "En dansk kulturfortælling",
                        "slug": "culture-story", "intro": english ? "A story in English." : "En fortælling på dansk.",
                        "topic": "music", "content": english ? "This is the English article body." : "Dette er den danske artikeltekst."]]
                if english {
                    document["contentLanguage"] = "en"; document["sourceArticleID"] = sourceID
                    document["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
                }
                return .init(language: language, documents: english && emptyEnglish ? [] : [(readerID, document)],
                             isFromCache: false, hasPendingWrites: false)
            }
            let documents = sources.flatMap(\.documents)
            let decoded = try CMSArticleDocumentCodec.decodeFeed(documents)
            try Task.checkCancellation()
            mirrorDocuments = documents; decodedFailureCount = decoded.failures.count
            viewModel.articles = decoded.articles
            loadState = "loaded"
        } catch { loadState = "failed" }
    }

    func articleBody(for article: Article) -> String {
        guard let document = mirrorDocuments.first(where: { $0.id == article.id }),
              let full = try? CMSArticleDocumentCodec.decodeArticle(from: document.data, expectedID: article.id) else { return "" }
        return full.content ?? ""
    }

    var report: String {
        let data: [String: Any] = ["firebaseStarted": FirebaseApp.allApps != nil,
            "language": viewModel.articleLanguage.rawValue,
            "storedLanguage": preferences.articleLanguage.rawValue,
            "englishSourceEnabled": ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:]),
            "sourceLanguages": sourceLanguages, "loadState": loadState,
            "decodedFailureCount": decodedFailureCount,
            "transport": "injected-local-mirror", "realCMSRead": false,
            "catalogIDs": viewModel.articles.map(\.id),
            "visibleIDs": viewModel.visibleArticles.map(\.id),
            "accessibilityText": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory]
        return String(data: (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])) ?? Data(),
            encoding: .utf8) ?? "{}"
    }
}

/// Actual bundle gate, shared mirror loader/decoder, Settings and Search screen.
/// The mirror transport and point-decoded body destination are local; this does
/// not exercise Firestore, the full reader, an account, audio or a live CMS.
struct LocalContentLanguageSmokeView: View {
    @StateObject private var fixture = LocalContentLanguageFixture()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Lokalt artikelsprog")
                .font(.caption).dynamicTypeSize(.large)
                .accessibilityIdentifier("language.fixture.report")
                .accessibilityValue(fixture.report)
            NavigationStack(path: fixture.navigation.path(for: .search)) {
                SearchView_Enhanced()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Indstillinger") { showSettings = true }
                                .accessibilityIdentifier("language.fixture.settings")
                        }
                    }
                    .navigationDestination(for: Article.self) { article in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(article.name ?? "").font(.title)
                                Text(fixture.articleBody(for: article))
                                    .accessibilityIdentifier("language.fixture.body")
                            }.padding()
                        }
                        .navigationTitle("Artikel").navigationBarTitleDisplayMode(.inline)
                    }
            }
            .environment(\.locale, AppLocalization.locale(for: fixture.viewModel.articleLanguage))
        }
        .environmentObject(fixture.viewModel)
        .environment(\.locale, AppLocalization.locale(for: fixture.viewModel.articleLanguage))
        .environment(\.navigationCoordinator, fixture.navigation)
        .environment(\.homeImagePolicy, .placeholder)
        .task { await fixture.loadInitialCatalog() }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    ContentLanguageSection(preferences: fixture.preferences)
                    Section("Lokal prøvestyring") {
                        Button("Fjern engelsk prøveartikel", action: fixture.removeEnglishFromCatalog)
                            .accessibilityIdentifier("language.fixture.removeEnglish")
                    }
                }
                .navigationTitle("Indstillinger")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Luk") { showSettings = false }
                            .accessibilityIdentifier("language.fixture.closeSettings")
                    }
                }
            }
            .environment(\.locale, AppLocalization.locale(for: fixture.viewModel.articleLanguage))
        }
    }
}
#endif
