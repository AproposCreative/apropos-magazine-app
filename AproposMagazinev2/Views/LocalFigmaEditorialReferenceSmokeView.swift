#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI
import UIKit

/// The product's real phone shell and editorial bodies, with local data only.
/// Reader construction permits ordinary local image/cache work but never opens
/// startup permission or supplies remotely loadable HTML/media to that reader.
@MainActor
private final class LocalFigmaEditorialFixture: ObservableObject {
    let model: ArticleViewModel
    let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
    let home: HomeFeedPreparationModel
    let progress: PodcastPlaybackProgressStore
    let presentation = PodcastPlayerPresentationModel(read: { .empty })
    let articles: [Article]
    let episodes: [PodcastEpisode]
    private let owner = UUID()
    private let availability = UUID()
    private let now = Date(timeIntervalSince1970: 1_793_448_000)
    private var prepared = false

    init() {
        let receiver = HomeFeedInputReceiver()
        // Keep the same receiver whose authority is read by the worker model.
        home = HomeFeedPreparationModel(currentAuthority: { receiver.authority },
            now: { Date(timeIntervalSince1970: 1_793_448_000) }, scheduleBoundary: { _, _ in })
        homeReceiver = receiver
        model = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init())
        progress = PodcastPlaybackProgressStore(storage: .init(read: { _ in nil }, write: { _, _ in }))
        progress.changeContext(to: .confirmed(userID: nil))
        let rows: [(String, String, String, String, String, String, Int)] = [
            ("terminal", "Anmeldelse: The Terminal List, sæson 1 på Prime Video", "Frederik Kragh",
             "Chris Pratt genopliver videobutikkens actionhelt i The Terminal List på Prime Video.", "series", "2026-10-28", 5),
            ("nogen", "Boganmeldelse: Nogen der kender nogen", "Liv Brandt",
             "Laura Ringo gør boligjagten til skarp og menneskelig litteratur, men stoler ikke altid på sine egne scener.", "culture", "2026-10-28", 4),
            ("deep-purple", "Anmeldelse: Deep Purple - Royal Arena", "Peter Milo",
             "Deep Purple indtog Royal Arena med klassikere, rå energi og store orgelsoloer.", "music", "2026-10-26", 4),
            ("lanterns", "Anmeldelse: Lanterns, sæson 1. Hvornår bliver det sejt?", "Frederik Kragh",
             "Aaron Pierre og Kyle Chandler efterforsker en kosmisk forbrydelse, men HBO-serien giver mig hverken nok superhelt eller nok menneske.", "series", "2026-10-24", 2),
            ("wolverine", "Marvel’s Wolverine Anmeldelse", "Peter Milo",
             "Logan er tilbage på PS5 med kløerne ude, en mørk fortælling og masser af vrede – men ikke helt nok bid.", "culture", "2026-10-20", 0),
            ("placebo", "Anmeldelse: Placebo i K.B. Hallen - et langt farvel", "Peter Milo",
             "Placebo fejrede 30 år i K.B. Hallen med nostalgi og telefonfri koncert.", "music", "2026-10-26", 3)
        ]
        let authorNames = ["Frederik Kragh", "Liv Brandt", "Peter Milo"]
        let authors = authorNames.enumerated().map { index, name in
            Author(id: "reference-author-\(index)", name: name, bio: nil, imageURL: nil, position: "", photoURL: "")
        }
        let opening = "Man kan fortælle et liv gennem kærlighedsforhold, arbejdspladser og de mennesker, man mister. I Laura Ringos Nogen der kender nogen bruger fortælleren også adresserne. Hvem ejer værelset? Hvor længe må man blive? Og hvor meget taknemmelighed følger med huslejen? Det er en morsom og skarp bog om alt det, et hjem bestemmer over."
        articles = rows.enumerated().map { index, row in
            let path = URL(fileURLWithPath: "/tmp/apropos-figma-iphone-assets-png-20261031")
                .appendingPathComponent(row.0 + ".png")
            let image = FileManager.default.fileExists(atPath: path.path) ? path : nil
            let author = authors.first { $0.name == row.2 }!
            var article = Article(id: String(format: "f1420000000000000000%04d", index + 1), name: row.1,
                slug: "figma-native-reference-" + row.0,
                content: "<p>" + (row.0 == "nogen" ? opening : row.3) + "</p>", intro: row.3,
                stjerne: row.6 > 0 ? row.6 : nil, topicID: row.4, topicsIDs: ["reviews"],
                sectionID: row.4 + "-section", authorID: author.id, mobileImageURL: image,
                isDraft: false, isArchived: false, date: row.5, createdOn: row.5,
                lastPublished: row.5 + "T12:00:00Z",
                isPremium: false)
            article.author = author
            return article
        }
        episodes = Array(articles.prefix(2)).map { article in
            PodcastEpisode(id: "reference-audio-" + article.id, articleId: article.id,
                articleSlug: article.slug, title: article.name ?? "", subtitle: "Lydindhold",
                audioURL: nil, productionSourceURL: nil, duration: nil,
                artworkURL: article.mobileImageURL, hosts: [article.author?.name ?? ""], publishedDate: nil)
        }
        model.authors = authors
        model.topics = [Topic(id: "reviews", name: "Anmeldelser"), Topic(id: "design", name: "Design"),
            Topic(id: "culture", name: "Kultur"), Topic(id: "music", name: "Musik"), Topic(id: "series", name: "Serier & Film")]
        model.sections = [WebflowSection(id: "music-section", name: "Musik"),
            WebflowSection(id: "culture-section", name: "Kultur"), WebflowSection(id: "series-section", name: "Serier & Film")]
        model.articles = articles
    }
    // Stored separately because initialisation must capture the local receiver,
    // never a partially constructed fixture, in currentAuthority.
    private let homeReceiver: HomeFeedInputReceiver

    func prepareHome() {
        guard !prepared else { return }
        prepared = true
        home.update(homeReceiver.receive(articles: articles, topics: model.topics, sections: model.sections,
            authors: model.authors, episodes: episodes, recommendations: [], owner: owner,
            availability: availability, now: now))
    }
}

struct LocalFigmaEditorialReferenceSmokeView: View {
    let screen: String
    @StateObject private var fixture = LocalFigmaEditorialFixture()
    var body: some View {
        LocalFigmaEditorialReferenceShell(screen: screen, fixture: fixture, navigation: fixture.navigation, home: fixture.home)
    }
}

private struct LocalFigmaEditorialReferenceShell: View {
    let screen: String
    @ObservedObject var fixture: LocalFigmaEditorialFixture
    @ObservedObject var navigation: NavigationCoordinator
    @ObservedObject var home: HomeFeedPreparationModel
    @State private var initialized = false
    @State private var showingPodcasts = false

    private var reader: Article { fixture.articles[1] }
    private var ready: Bool { initialized && (screen != "home" || home.snapshot != nil) }
    private var report: String {
        let value: [String: Any] = ["screen": screen, "ready": ready,
            "firebaseStarted": FirebaseApp.allApps != nil,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "bodyKind": "inline-public-opening-excerpt-only", "media": "local-file-only-no-playback",
            "topics": "local-hermetic-examples", "readerID": reader.id,
            "readyMeaning": "host-routed-inputs-ready-not-renderer-acceptance"]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }
    var body: some View {
        AproposNavigationShell(selection: Binding(get: { navigation.selectedTab }, set: { navigation.navigateToTab($0) }),
            hasActiveEpisode: false, hasPreparation: false, onTabReselected: { navigation.reselect($0) }) {
            NavigationStack(path: navigation.path(for: .home)) {
                HomeFeedContent(model: fixture.home, progressStore: fixture.progress,
                    presentation: fixture.presentation, favoriteIDs: [], isLoading: false, errorMessage: nil,
                    actions: .init(firstAppearance: fixture.prepareHome))
            }
            .tabItem { Label("Hjem", systemImage: "house.fill") }.tag(Tab.home)
            NavigationStack(path: navigation.path(for: .search)) {
                SearchView_Enhanced()
                    .navigationDestination(isPresented: $showingPodcasts) {
                        PodcastListView(progressStore: fixture.progress,
                            pairs: zip(fixture.articles, fixture.episodes).map { PodcastArticlePair(article: $0.0, episode: $0.1) },
                            authorProvider: { $0.article.author?.name ?? "" },
                            categoriesProvider: { fixture.model.categories(for: $0) },
                            onOpenArticle: { _ in }, onPlayPair: { _ in })
                    }
                    .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
                    .navigationDestination(for: AppRoute.self) { route in
                        if case .categoryDetail(let name) = route { CategoryDetailView(categoryName: name) }
                    }
            }
            .tabItem { Label("Artikler", systemImage: "doc.text") }.tag(Tab.search)
            NavigationStack(path: navigation.path(for: .categories)) {
                CategoriesView()
                    .navigationDestination(for: AppRoute.self) { route in
                        if case .categoryDetail(let name) = route { CategoryDetailView(categoryName: name) }
                    }
                    .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
            }
            .tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }.tag(Tab.categories)
            // This existing fixture already owns its NavigationStack and the
            // exact shared pages. Do not nest another navigation container.
            LocalNotificationInboxSmokeView()
                .tabItem { Label("Min side", systemImage: "person.crop.circle") }.tag(Tab.favorites)
        } accessory: { EmptyView() }
        .environmentObject(fixture.model)
        .environmentObject(navigation)
        .environment(\.navigationCoordinator, navigation)
        .tint(.primary)
        .onAppear {
            // ContentView applies this platform appearance around the same
            // shell. Keep that chrome configuration for the native reference.
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.stackedLayoutAppearance.normal.iconColor = .systemGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
            appearance.stackedLayoutAppearance.selected.iconColor = .label
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .task {
            guard !initialized else { return }
            initialized = true
            switch screen {
            case "articles", "search", "reader", "podcasts": navigation.selectedTab = .search
            case "categories", "category-detail": navigation.selectedTab = .categories
            case "minside": navigation.selectedTab = .favorites
            default: navigation.selectedTab = .home
            }
            if screen == "reader" { navigation.navigateToArticle(reader, in: .search) }
            if screen == "category-detail" { navigation.navigateToCategory("Anmeldelser", in: .categories) }
            if screen == "podcasts" { showingPodcasts = true }
            fixture.prepareHome()
        }
        .overlay(alignment: .bottomLeading) {
            Text("Reference").font(.system(size: 1)).foregroundStyle(.clear)
                .frame(width: 1, height: 1).clipped().allowsHitTesting(false)
                .accessibilityIdentifier("figma.editorial.reference.metadata").accessibilityValue(report)
        }
    }
}
#endif
