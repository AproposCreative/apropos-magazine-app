#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

/// Actual cache admission, input receiver, worker and prepared Home UI with
/// memory transports. No normal application service or player is constructed.
@MainActor
private final class LocalHomeFixture: ObservableObject {
    enum Scenario: String { case cache, withdrawal, owner, edge, layout, authorAlignment, allCards, compactRows, favoriteRows, favoriteControls, tabReselect, heroTags, listNavigation, podcastRows, allTabReselect }
    let scenario: Scenario
    let model: HomeFeedPreparationModel
    let progress: PodcastPlaybackProgressStore
    let presentation: PodcastPlayerPresentationModel
    private let memory: Memory
    private let cache: ArticleCacheHydrationCoordinator
    private var modelSubscription: AnyCancellable?
    @Published private(set) var openedArticle: Article?
    @Published private(set) var favoriteIDs = Set<String>()

    @MainActor
    private final class Memory {
        let receiver = HomeFeedInputReceiver()
        let worker = HomeFeedWorker()
        let now = Date(timeIntervalSince1970: 1_792_584_000)
        var owner = UUID(), availability = UUID(), ownerName = "Gæst"
        var articles: [Article] = [], episodes = LocalHomeFixture.episodes
        var topics = LocalHomeFixture.topics
        var recommendations: [HomeRecommendation] = []
        var cacheData: Data?
        var cacheLoads = 0
        var cacheError: String?
        var progressData: [String: Data] = [:]
        var playback = PodcastPlayerPresentation.empty
        var holdAuthorities = Set<UUID>()
        var replies: [(HomeFeedSnapshot, CheckedContinuation<HomeFeedSnapshot, Never>)] = []
        var heldActions: [@MainActor () -> Void] = []
        var holdNextAction = false
        var played = 0, denied = 0
        var coverAdmissions: [String: Bool] = [:]
        var lastCoverAdmissions: [Bool] = []
        var changed: (() -> Void)?

        func prepare(_ input: HomeFeedInput) async -> HomeFeedSnapshot {
            let hold = holdAuthorities.remove(input.authority.content) != nil
            let snapshot = await worker.prepare(input)
            if hold {
                return await withCheckedContinuation { continuation in
                    replies.append((snapshot, continuation)); changed?()
                }
            }
            return snapshot
        }
        func capture() -> HomeFeedInput {
            receiver.receive(articles: articles, topics: topics,
                sections: LocalHomeFixture.sections, authors: LocalHomeFixture.authors,
                episodes: episodes, recommendations: recommendations,
                owner: owner, recommendationOwner: recommendations.isEmpty ? nil : owner, availability: availability, now: now)
        }
        func release() {
            let held = replies; replies.removeAll()
            held.forEach { $0.1.resume(returning: $0.0) }
            let actions = heldActions; heldActions.removeAll(); actions.forEach { $0() }
            changed?()
        }
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-HomeSmokeScenario"), arguments.indices.contains(index + 1) {
            scenario = Scenario(rawValue: arguments[index + 1]) ?? .cache
        } else { scenario = .cache }
        let memory = Memory(); self.memory = memory
        if scenario == .owner {
            memory.ownerName = "A"
            memory.recommendations = [.init(articleID: "music-1", reason: "For dine interesser i musik")]
        }
        if scenario == .podcastRows {
            // The actual EPISODE title is long. Changing only Article.name does
            // not exercise the separate title rendered by PodcastListView.
            memory.episodes = Self.episodes.map { episode in
                let title = episode.id == "audio-hero"
                    ? "Anmeldelse: Historien om scenen, fællesskabet og de mennesker der ændrede musikken, mens byen blev ved med at lytte og stille nye spørgsmål til den næste generation"
                    : episode.id == "audio-music" ? "Musik" : "En historie uden cover og uden en færdig lydversion"
                return PodcastEpisode(id: episode.id, articleId: episode.articleId, articleSlug: episode.articleSlug,
                    title: title, subtitle: episode.subtitle, audioURL: episode.audioURL,
                    productionSourceURL: episode.productionSourceURL, duration: episode.duration,
                    artworkURL: episode.artworkURL, hosts: episode.hosts, publishedDate: episode.publishedDate,
                    isAINarration: episode.isAINarration, sourceContentRevision: episode.sourceContentRevision)
            }
        }
        memory.holdNextAction = scenario == .withdrawal
        var cachedArticles = Self.articles
        if scenario == .layout {
            memory.topics = Self.topics.map {
                $0.id == "music" ? Topic(id: "music", name: "Musik og scenekunst med internationale perspektiver") : $0
            }
            if let index = cachedArticles.firstIndex(where: { $0.id == "music-1" }) {
                cachedArticles[index] = Self.article("music-1",
                    title: "Musikkens nye stemmer åbner en større samtale om kultur, fællesskab og scenerne vi deler",
                    topic: "music", day: 15,
                    intro: "En lang redaktionel indledning med plads til perspektiv, eftertanke og de mennesker, der former musikken. Her følger vi historierne helt til dørs, også når der er meget at fortælle.",
                    rating: 5, displayDate: "2026-09-21")
            }
        }
        memory.cacheData = try? JSONEncoder().encode(CacheData(articles: cachedArticles, timestamp: memory.now, version: "1.3"))
        let decoder = ArticleCacheDecodeWorker()
        let cache = ArticleCacheHydrationCoordinator(read: { memory.cacheData.map { .encoded($0) } },
            prepare: { source, policy in await decoder.prepare(source, policy: policy) }, now: { memory.now })
        self.cache = cache
        let model = HomeFeedPreparationModel(prepare: { input in await memory.prepare(input) },
            currentAuthority: { memory.receiver.authority }, now: { memory.now }, scheduleBoundary: { _, _ in })
        self.model = model
        let progress = PodcastPlaybackProgressStore(storage: .init(read: { memory.progressData[$0.storageKey] },
            write: { memory.progressData[$0.storageKey] = $1 }))
        self.progress = progress
        presentation = PodcastPlayerPresentationModel(read: { memory.playback })
        progress.changeContext(to: .confirmed(userID: scenario == .owner ? "A" : nil))
        memory.changed = { [weak self] in self?.objectWillChange.send() }
        modelSubscription = model.changes.sink { [weak self] _ in self?.objectWillChange.send() }
        let original = cache.capture(), originalOwner = memory.owner
        Task {
            let result = await cache.load(original, stillPermitted: { memory.owner == originalOwner })
            guard cache.isCurrent(original), memory.owner == originalOwner else { return }
            if case .ready(let prepared) = result {
                memory.articles = prepared.articles; memory.cacheLoads += 1
                model.update(memory.capture())
            } else { memory.cacheError = "Cache kunne ikke indlæses" }
            memory.changed?()
        }
    }

    var status: String {
        let metrics = model.snapshot?.metrics ?? .init()
        let firstCover = memory.coverAdmissions["home.card.music.music-1"].map { $0 ? "ready" : "blocked" } ?? "unknown"
        let lastCover = memory.coverAdmissions["home.card.music.music-6"].map { $0 ? "ready" : "blocked" } ?? "unknown"
        let lastCoverEvents = memory.lastCoverAdmissions.map { $0 ? "ready" : "blocked" }.joined(separator: ",")
        return "firebase=\(FirebaseApp.allApps == nil ? "off" : "ON") cache=\(memory.cacheLoads) articles=\(memory.articles.count) hero=\(model.snapshot?.hero.count ?? 0) builds=\(metrics.builds) sorts=\(metrics.archiveSorts) matches=\(metrics.podcastCandidateChecks) preparing=\(model.state.isPreparing ? 1 : 0) owner=\(memory.ownerName) held=\(memory.replies.count) actions=\(memory.heldActions.count) played=\(memory.played) denied=\(memory.denied) favorites=\(favoriteIDs.count) opened=\(openedArticle == nil ? 0 : 1) firstCover=\(firstCover) lastCover=\(lastCover) lastCoverEvents=\(lastCoverEvents)"
    }
    var errorMessage: String? { memory.cacheError }
    var isLoading: Bool { memory.cacheLoads == 0 && memory.cacheError == nil }
    func coverAdmission(_ identifier: String, admitted: Bool) {
        guard memory.coverAdmissions[identifier] != admitted else { return }
        memory.coverAdmissions[identifier] = admitted
        if identifier == "home.card.music.music-6" { memory.lastCoverAdmissions.append(admitted) }
        memory.changed?()
    }
    var actions: HomeFeedActions {
        .init(openArticle: { [weak self] article, authority, _ in
            guard let self else { return }
            guard self.model.isCurrent(authority),
                  let current = self.model.snapshot?.resumeIndex.articlesByID[article.id],
                  current.bodyRevision == article.bodyRevision else { self.memory.denied += 1; self.memory.changed?(); return }
            self.openedArticle = current
        }, toggleFavorite: { [weak self] article, authority in
            guard let self else { return }
            guard self.model.isCurrent(authority),
                  self.model.snapshot?.resumeIndex.articlesByID[article.id]?.bodyRevision == article.bodyRevision else {
                self.memory.denied += 1; self.memory.changed?(); return
            }
            if !self.favoriteIDs.insert(article.id).inserted { self.favoriteIDs.remove(article.id) }
        }, play: { [weak self] pair, authority, ownership in
            guard let self else { return }
            let originalAction: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                let progressIsCurrent = ownership.map { $0.context == self.progress.context && $0.generation == self.progress.snapshot.generation } ?? true
                let currentProgress = self.progress.snapshot
                let resume = self.model.snapshot?.resumeIndex.pair(episodeID: currentProgress.lastPlayedEpisodeID,
                    articleID: currentProgress.lastPlayedArticleID,
                    hasResumableProgress: currentProgress.hasResumableProgress(for: pair.episode.id))
                let originalResumeIsCurrent = ownership == nil || (resume?.article.id == pair.article.id && resume?.episode.id == pair.episode.id)
                guard self.model.isCurrent(authority), progressIsCurrent,
                      originalResumeIsCurrent,
                      self.model.snapshot?.resumeIndex.articlesByID[pair.article.id]?.bodyRevision == pair.article.bodyRevision,
                      HomePodcastAdmission.rawEpisode(for: pair, in: self.memory.episodes, requiresUniquePlayableID: ownership != nil) != nil,
                      pair.episode.hasPlayableAudioURL else { self.memory.denied += 1; self.memory.changed?(); return }
                self.memory.played += 1; self.memory.changed?()
            }
            if self.memory.holdNextAction {
                self.memory.holdNextAction = false; self.memory.heldActions.append(originalAction); self.memory.changed?()
            } else { originalAction() }
        }, refresh: { [weak self] in self?.holdPreparation() })
    }

    func holdPreparation() {
        guard !model.state.isPreparing else { return }
        memory.articles.append(Self.article("refresh-story", title: "En ny historie", topic: "music", day: 1, month: 9))
        let original = memory.capture()
        memory.holdAuthorities.insert(original.authority.content)
        model.update(original)
    }
    func withdraw() {
        cache.invalidate()
        memory.articles.removeAll { $0.id == "hero-1" }
        memory.episodes.removeAll { $0.articleId == "hero-1" }
        memory.availability = UUID()
        model.update(memory.capture())
    }
    func release() { memory.release() }
    func dismissArticle() { openedArticle = nil }
    func position() {
        if let session = progress.beginSession(episodeID: "audio-music", articleID: "music-1") {
            _ = progress.save(session.ticket, seconds: 42, duration: 600)
        }
        model.update(memory.capture()); memory.changed?()
    }
    func toggleActive() {
        presentation.sourceWillChange()
        memory.playback.activeEpisodeID = memory.playback.activeEpisodeID == nil ? "audio-music" : nil
        model.update(memory.capture()); memory.changed?()
    }
    func switchToB() {
        memory.owner = UUID(); memory.ownerName = "B"
        progress.changeContext(to: .confirmed(userID: "B"))
        memory.recommendations = [.init(articleID: "culture-1", reason: "For dine interesser i kultur")]
        model.update(memory.capture())
    }

    private static let topics = [Topic(id: "music", name: "Musik"), Topic(id: "culture", name: "Kultur"),
        Topic(id: "series", name: "Serier & Film"), Topic(id: "reviews", name: "Anmeldelser"),
        Topic(id: "design", name: "Design")]
    private static let sections = [WebflowSection(id: "music-section", name: "Musik"),
        WebflowSection(id: "culture-section", name: "Kultur"), WebflowSection(id: "series-section", name: "Serier & Film")]
    private static let authors = [Author(id: "fixture-author", name: "Signe Jensen", bio: nil,
        imageURL: nil, position: "Journalist", photoURL: "")]
    private static func article(_ id: String, title: String, topic: String, day: Int, month: Int = 10,
                                intro: String = "Journalistik med perspektiv og plads til fordybelse.",
                                rating: Int? = nil, displayDate: String? = nil) -> Article {
        let date = String(format: "2026-%02d-%02dT12:00:00Z", month, day)
        return Article(id: id, name: title, slug: id, content: "<p>Lokal redaktionel tekst.</p>",
            intro: intro, stjerne: rating, topicID: topic,
            topicsIDs: id == "hero-1" ? ["culture", "design"] : nil, authorID: "fixture-author",
            mobileImageURL: URL(string: "https://example.invalid/\(id).jpg"), isDraft: false, isArchived: false,
            date: displayDate ?? date, createdOn: date, lastPublished: date,
            contentRevision: "fixture-v1")
    }
    private static var articles: [Article] {
        (1...5).map { article("hero-\($0)", title: "Fra redaktionen \($0)", topic: "culture", day: 21 - $0) }
            + (1...8).map { article("music-\($0)", title: "Musikkens nye stemmer \($0)", topic: "music", day: 16 - $0) }
            + (1...2).map { article("review-\($0)", title: "En anmeldelse med perspektiv \($0)", topic: "reviews", day: 8 - $0) }
            + (1...2).map { article("culture-\($0)", title: "Kulturen i bevægelse \($0)", topic: "culture", day: 6 - $0) }
            + (1...2).map { article("series-\($0)", title: "Historier på skærmen \($0)", topic: "series", day: 4 - $0) }
    }
    private static let episodes: [PodcastEpisode] = [
        .init(id: "audio-hero", articleId: "hero-1", articleSlug: "hero-1", title: "Klubkultur og mode: Hvem får lov?",
            subtitle: "Kultur", audioURL: URL(string: "https://example.invalid/hero.mp3"), productionSourceURL: nil,
            duration: "10 min", artworkURL: nil, hosts: ["Signe Jensen"], publishedDate: nil,
            isAINarration: true, sourceContentRevision: "fixture-v1"),
        .init(id: "audio-pending", articleId: "hero-2", articleSlug: "hero-2", title: "Fra redaktionen 2",
            subtitle: "Kultur", audioURL: nil, productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: ["Signe Jensen"], publishedDate: nil),
        .init(id: "audio-music", articleId: "music-1", articleSlug: "music-1", title: "Musikkens nye stemmer 1",
            subtitle: "Musik", audioURL: URL(string: "https://example.invalid/music.mp3"), productionSourceURL: nil,
            duration: "10 min", artworkURL: nil, hosts: ["Signe Jensen"], publishedDate: nil)
    ]
}

@MainActor
struct LocalHomeSmokeView: View {
    @StateObject private var fixture = LocalHomeFixture()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var heroFrames: [String: CGRect] = [:]
    private var reducedMotion: Bool { systemReduceMotion || ProcessInfo.processInfo.arguments.contains("-HomeSmokeReduceMotion") }
    var body: some View {
        if fixture.scenario == .edge || fixture.scenario == .heroTags {
            // Same native container hierarchy as ContentView. The fixture status
            // occupies only a bottom inset so it cannot mask a top-edge regression.
            TabView {
                homeNavigation.tabItem { Label("Hjem", systemImage: "house.fill") }
                Text("Artikler").tabItem { Label("Artikler", systemImage: "doc.text") }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if fixture.scenario == .heroTags { fixtureControls.dynamicTypeSize(.large) }
                else { fixtureControls }
            }
        } else {
            VStack(spacing: 0) {
                if fixture.scenario == .favoriteRows || fixture.scenario == .favoriteControls || fixture.scenario == .tabReselect || fixture.scenario == .listNavigation || fixture.scenario == .podcastRows || fixture.scenario == .allTabReselect { fixtureControls.dynamicTypeSize(.large) }
                else { fixtureControls }
                Divider()
                if fixture.scenario == .authorAlignment { authorAlignment }
                else if fixture.scenario == .allCards { LocalAllArticleCardsView() }
                else if fixture.scenario == .compactRows { LocalCompactArticleRowsView() }
                else if fixture.scenario == .favoriteRows { LocalFavoriteArticleRowsView() }
                else if fixture.scenario == .favoriteControls { LocalFavoriteControlsView() }
                else if fixture.scenario == .tabReselect || fixture.scenario == .allTabReselect {
                    LocalHomeTabReselectView(fixture: fixture, extended: fixture.scenario == .allTabReselect)
                }
                else if fixture.scenario == .listNavigation { LocalListNavigationView() }
                else if fixture.scenario == .podcastRows { LocalPodcastArticleRowsView(fixture: fixture) }
                else { homeNavigation }
            }
        }
    }

    private var fixtureControls: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Lokale Home-data").font(.caption)
                    .accessibilityIdentifier("home.fixture.state")
                    .accessibilityValue(fixture.status + " homeReduce=\(reducedMotion ? 1 : 0)"
                        + (fixture.scenario == .heroTags ? " heroGeometry=" + heroGeometryReport : ""))
                HStack(spacing: 8) {
                    switch fixture.scenario {
                    case .cache, .edge, .layout, .authorAlignment, .allCards, .compactRows, .favoriteRows, .favoriteControls, .tabReselect, .heroTags, .listNavigation, .podcastRows, .allTabReselect:
                        Text("Cache uden netværk").font(.caption).foregroundStyle(.secondary)
                    case .withdrawal:
                        Button("Hold", action: fixture.holdPreparation).accessibilityIdentifier("home.fixture.hold")
                        Button("Træk tilbage", action: fixture.withdraw).accessibilityIdentifier("home.fixture.withdraw")
                        Button("Frigiv", action: fixture.release).accessibilityIdentifier("home.fixture.release")
                    case .owner:
                        Button("Position", action: fixture.position).accessibilityIdentifier("home.fixture.position")
                        Button("Aktiv lyd", action: fixture.toggleActive).accessibilityIdentifier("home.fixture.active")
                        Button("Konto B", action: fixture.switchToB).accessibilityIdentifier("home.fixture.ownerB")
                    }
                }
                .font(.caption).buttonStyle(.bordered)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var authorAlignment: some View { LocalAuthorArticleCardsView() }

    private var homeNavigation: some View {
        NavigationStack {
                HomeFeedContent(model: fixture.model, progressStore: fixture.progress, presentation: fixture.presentation,
                    favoriteIDs: fixture.favoriteIDs, isLoading: fixture.isLoading, errorMessage: fixture.errorMessage, actions: fixture.actions)
                    .navigationDestination(isPresented: Binding(get: { fixture.openedArticle != nil },
                        set: { if !$0 { fixture.dismissArticle() } })) {
                            if let article = fixture.openedArticle {
                                Text(article.name ?? "Artikel").font(.title).padding()
                                    .navigationTitle("Lokal artikel").toolbar(.visible, for: .navigationBar)
                                    .accessibilityIdentifier("home.fixture.openedArticle")
                            }
                        }
            }
            .environment(\.homeImagePolicy, .placeholder)
            .environment(\.homeCoverAdmissionProbe, { fixture.coverAdmission($0, admitted: $1) })
            .environment(\.homeReduceMotionOverride, reducedMotion)
            .environment(\.homeHeroGeometryProbe, heroGeometryProbe)
    }

    private var heroGeometryProbe: ((String, CGRect) -> Void)? {
        guard fixture.scenario == .heroTags else { return nil }
        return { key, frame in recordHeroFrame(key, frame) }
    }
    private var heroGeometryReport: String {
        let payload: [String: Any] = [
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "frames": heroFrames.mapValues { ["x": Double($0.minX), "y": Double($0.minY),
                "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    private func recordHeroFrame(_ key: String, _ frame: CGRect) {
        guard key.hasPrefix("hero-1.") || key.hasPrefix("indicator.") else { return }
        if heroFrames[key] != frame { heroFrames[key] = frame }
    }
}

/// Actual audio list/card and Home-prepared pairs. Only artwork, geometry and
/// route/play effects are local; no player or image network loader is started.
@MainActor
private struct LocalPodcastArticleRowsView: View {
    @ObservedObject var fixture: LocalHomeFixture
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCards = false
    @State private var frames: [String: CGRect] = [:]
    private let episodeOrder = ["audio-music", "audio-hero", "audio-pending"]

    private static let artwork: UIImage = {
        let size = CGSize(width: 180, height: 300)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor(red: 0.05, green: 0.28, blue: 0.74, alpha: 1).setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.08, green: 0.80, blue: 0.78, alpha: 1).setFill()
            renderer.fill(CGRect(x: 20, y: 0, width: 40, height: 300))
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 100, y: 0, width: 16, height: 300))
        }
    }()
    private var pairs: [PodcastArticlePair] {
        let available = fixture.model.snapshot?.podcastPairs ?? []
        return episodeOrder.compactMap { id in available.first { $0.episode.id == id } }
    }
    private var report: String {
        let payload: [String: Any] = [
            "mode": showingCards ? "card" : "list",
            "firebaseStarted": FirebaseApp.allApps != nil,
            "systemTextCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "episodeTitles": Dictionary(uniqueKeysWithValues: pairs.map { ($0.episode.id, $0.episode.title) }),
            "fixtureArtworkIDs": ["audio-music", "audio-hero"], "placeholderIDs": ["audio-pending"],
            "realPlayerStarted": false, "realReaderOpened": false, "remoteImagePolicy": false,
            "fullFixtureStatus": fixture.status,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY),
                "width": Double($0.width), "height": Double($0.height)] }
        ]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Lokal lydrækkes geometri").font(.caption2).dynamicTypeSize(.large)
                    .accessibilityIdentifier("home.podcast.fixture.geometry").accessibilityValue(report)
                HStack {
                    Button("Vis liste") { frames.removeAll(); showingCards = false }
                        .accessibilityIdentifier("home.podcast.fixture.showList")
                    Button("Vis kort") { frames.removeAll(); showingCards = true }
                        .accessibilityIdentifier("home.podcast.fixture.showCards")
                }
                .font(.caption).dynamicTypeSize(.large).buttonStyle(.bordered)
                if let snapshot = fixture.model.snapshot {
                    if showingCards {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(pairs) { pair in
                                    PodcastCardView(progressStore: fixture.progress, pair: pair,
                                        categoryText: snapshot.metadataByID[pair.article.id]?.categories.first ?? "Generelt",
                                        onPlay: { fixture.actions.play($0, snapshot.authority, nil) },
                                        onOpenArticle: { fixture.actions.openArticle($0, snapshot.authority, nil) })
                                }
                            }
                            .padding(16)
                        }
                        .accessibilityIdentifier("home.podcast.fixture.cards")
                        .navigationTitle("Lydkort")
                        .navigationBarTitleDisplayMode(.inline)
                    } else {
                        PodcastListView(progressStore: fixture.progress, pairs: pairs,
                            authorProvider: { snapshot.podcastByline(for: $0) },
                            categoriesProvider: { snapshot.metadataByID[$0.id]?.categories ?? ["Generelt"] },
                            onOpenArticle: { fixture.actions.openArticle($0, snapshot.authority, nil) },
                            onPlayPair: { fixture.actions.play($0, snapshot.authority, nil) })
                    }
                }
            }
            .navigationDestination(isPresented: Binding(get: { fixture.openedArticle != nil },
                set: { if !$0 { fixture.dismissArticle() } })) {
                    if let article = fixture.openedArticle {
                        VStack(spacing: 16) {
                            Text(article.name ?? "Artikel").font(.title)
                                .accessibilityIdentifier("home.podcast.fixture.destination")
                            Button("Tilbage til lydlisten") { fixture.dismissArticle() }
                                .accessibilityIdentifier("home.podcast.fixture.return")
                        }
                        .padding(16).navigationTitle("Lokal artikel")
                    }
                }
        }
        .environment(\.homeImagePolicy, .placeholder)
        .environment(\.podcastRowFixtureArtwork, { id in id == "audio-pending" ? nil : Self.artwork })
        .environment(\.podcastRowGeometryProbe, { key, frame in
            if frames[key] != frame { frames[key] = frame }
        })
    }
}

/// Actual production rows with nil image URLs and an inert metadata-only view
/// model. Never calls start(), fetch, favorites or any service-backed property.
@MainActor
private struct LocalAllArticleCardsView: View {
    @StateObject private var viewModel = ArticleViewModel()

    private func article(_ kind: String, intro: String) -> Article {
        var article = Article(id: "alignment-" + kind,
            name: "Kulturens nye stemmer og de fællesskaber, vi bygger sammen",
            slug: "alignment-" + kind, content: "", intro: intro, topicID: "fixture-culture")
        article.author = Author(id: "fixture-author", name: "Signe Jensen", bio: nil,
            imageURL: nil, position: "Journalist", photoURL: "")
        return article
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gemte artikler").font(.headline)
                        FavoriteArticleRow(article: article("favorite", intro: "En gemt historie om kulturen og de mennesker, der giver den liv."))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.fixture.row.favorite")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kategorier").font(.headline)
                        ArticleRowCompact(article: article("compact", intro: "Nye perspektiver på musik, samfund og den scene, vi deler."))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.fixture.row.compact")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kategoriliste").font(.headline)
                        ListArticleCard(article: article("categoryList", intro: "Journalistik med plads til nysgerrighed og eftertanke."))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.fixture.row.categoryList")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Serie").font(.headline)
                        SeriesArticleRow(article: article("series", intro: "Mød en ny generation af fortællere, som udfordrer vores blik på verden."))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.fixture.row.series")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hjem · Se alle").font(.headline)
                        HomePreparedArticleRow(article: article("homeList", intro: "Historierne bag det, vi taler om."), metadata: nil)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.fixture.row.homeList")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("home.fixture.allCards")
            .navigationTitle("Lokale artikelkort")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(viewModel)
        .environment(\.homeImagePolicy, .placeholder)
        .onAppear { viewModel.topics = [Topic(id: "fixture-culture", name: "Kultur og scenekunst")] }
    }
}
/// The category list's actual row inside the same plain Button shape, with an
/// in-memory navigation destination. The image is generated locally; no URL,
/// Firebase service, player, or normal view-model start is used.
@MainActor
private struct LocalCompactArticleRowsView: View {
    @StateObject private var viewModel = ArticleViewModel()
    @State private var frames: [String: CGRect] = [:]
    @State private var selectedID: String?
    @State private var openedCount = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Sample: Identifiable {
        let id: String
        let title: String
        let intro: String
        let rating: Int?
        var article: Article {
            Article(id: id, name: title, slug: id, content: "", intro: intro,
                stjerne: rating, topicID: "fixture-culture")
        }
    }
    private static let samples: [Sample] = [
        .init(id: "compact-rated-five", title: "En anmeldelse med nye perspektiver på kultur og fællesskab",
            intro: "Mød menneskene og fortællingerne, der giver oplevelsen liv.", rating: 5),
        .init(id: "compact-rated-six", title: "Byliv", intro: "Kort fortalt.", rating: 6),
        .init(id: "compact-unrated", title: "Historien bag byens nye scene",
            intro: "Journalistik med plads til nysgerrighed og eftertanke.", rating: nil),
        .init(id: "compact-zero", title: "Musik", intro: "Nye stemmer.", rating: 0)
    ]
    private static let artwork: UIImage = {
        let size = CGSize(width: 160, height: 240)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor(red: 0.04, green: 0.25, blue: 0.68, alpha: 1).setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.82).setFill()
            renderer.fill(CGRect(x: 24, y: 0, width: 26, height: 240))
            UIColor(red: 0.31, green: 0.59, blue: 0.94, alpha: 1).setFill()
            renderer.fill(CGRect(x: 80, y: 0, width: 56, height: 240))
        }
    }()
    private var report: String {
        let payload: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil,
            "openedCount": openedCount, "selectedID": selectedID ?? "",
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY),
                "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Kortenes faktiske geometri").font(.caption).dynamicTypeSize(.large).padding(4)
                    .accessibilityIdentifier("home.compact.geometry").accessibilityValue(report)
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Self.samples) { sample in
                            Button {
                                selectedID = sample.id; openedCount += 1
                            } label: {
                                ArticleRowCompact(article: sample.article, fixtureImage: sample.id == "compact-zero" ? nil : Self.artwork,
                                    onFrame: { record(sample.id + "." + $0, $1) })
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.compact.row." + sample.id)
                            if sample.id != Self.samples.last?.id { Divider().padding(.horizontal, 16) }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .accessibilityIdentifier("home.fixture.compactRows")
            }
            .navigationTitle("Lokale kategorikort")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(get: { selectedID != nil },
                set: { if !$0 { selectedID = nil } })) {
                if let sample = Self.samples.first(where: { $0.id == selectedID }) {
                    VStack(spacing: 16) {
                        Text(sample.title).font(.title).accessibilityIdentifier("home.compact.destination")
                        Button("Tilbage til kortene") { selectedID = nil }
                            .accessibilityIdentifier("home.compact.return")
                    }
                    .padding(16).navigationTitle("Lokal artikel").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .environmentObject(viewModel)
        .onAppear { viewModel.topics = [Topic(id: "fixture-culture", name: "Kultur og scenekunst")] }
    }
    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}

/// Actual favorite image preparation and local decoding, with isolated mapping
/// files and an inert metadata-only view model. No service or player is started.
@MainActor
private final class LocalFavoriteRowsFixture: ObservableObject {
    struct Sample: Identifiable {
        let id: String
        let title: String
        let intro: String
        let rating: Int?
        let key: String
        let url: URL?
        var article: Article {
            Article(id: id, name: title, slug: id, content: "", intro: intro, stjerne: rating,
                topicID: "fixture-culture", mobileImageURL: url, contentRevision: "favorite-row-r1")
        }
    }
    let samples: [Sample]
    let cache: OfflineArticleImageCache
    private let root: URL
    @Published private(set) var states: [String: String] = [:]
    @Published private(set) var replaced = false
    @Published private(set) var imageFailureText = ""

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("favorite-rows-\(UUID().uuidString)", isDirectory: true)
        self.root = root
        let samples: [Sample] = [
            .init(id: "favorite-five", title: "Placebo giver gamle sange nyt liv på den store scene",
                intro: "En aften med nærvær og nye perspektiver.", rating: 5,
                key: String(repeating: "a", count: 64), url: root.appendingPathComponent("five.png")),
            .init(id: "favorite-six", title: "Wolverine", intro: "Kort fortalt.", rating: 6,
                key: String(repeating: "b", count: 64), url: root.appendingPathComponent("six.png")),
            .init(id: "favorite-unrated", title: "Historien bag scenen", intro: "Mød de nye stemmer.", rating: nil,
                key: String(repeating: "c", count: 64), url: root.appendingPathComponent("unrated.png")),
            .init(id: "favorite-zero", title: "Musik", intro: "Nye oplevelser.", rating: 0,
                key: String(repeating: "d", count: 64), url: nil)
        ]
        self.samples = samples
        let generation = UUID()
        cache = OfflineArticleImageCache(cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            download: { _ in throw URLError(.unsupportedURL) }, online: { false },
            preparationAccess: { id, revision in
                guard revision == "favorite-row-r1", let sample = samples.first(where: { $0.id == id }) else {
                    return .init(contentKey: nil, generation: generation, isCurrent: { false })
                }
                return .init(contentKey: sample.key, generation: generation, isCurrent: { true })
            })
        do {
            for sample in samples where sample.url != nil {
                try seed(sample, corrupt: sample.id == "favorite-unrated", replacement: false)
            }
        } catch { self.imageFailureText = String(describing: error) }
    }
    func record(_ event: PreparedArticleImage.Event, id: String) {
        let state: String
        switch event {
        case .preparing: state = "preparing"
        case .loading: state = "loading"
        case .loaded: state = "loaded"
        case .failed: state = "failed"
        }
        if states[id] != state { states[id] = state }
    }
    func replaceFailedImage() {
        guard !replaced, states["favorite-unrated"] == "failed",
              let sample = samples.first(where: { $0.id == "favorite-unrated" }) else { return }
        cache.removeContent(sample.key)
        do { try seed(sample, corrupt: false, replacement: true); replaced = true }
        catch { self.imageFailureText = String(describing: error) }
    }
    private func seed(_ sample: Sample, corrupt: Bool, replacement: Bool) throws {
        guard let url = sample.url else { return }
        let directory = root.appendingPathComponent("cache", isDirectory: true).appendingPathComponent(sample.key, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = String(repeating: replacement ? "2" : "1", count: 64) + ".png"
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 240), format: format).pngData { context in
            (replacement ? UIColor.systemGreen : UIColor.systemBlue).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 240))
            UIColor.white.setFill(); context.fill(CGRect(x: 24, y: 0, width: 28, height: 240))
        }
        try (corrupt ? Data("Not an image".utf8) : bytes).write(to: directory.appendingPathComponent(file), options: .atomic)
        try JSONEncoder().encode([url.absoluteString: file]).write(to: directory.appendingPathComponent("mapping.json"), options: .atomic)
    }
}

@MainActor
private struct LocalFavoriteArticleRowsView: View {
    @StateObject private var fixture = LocalFavoriteRowsFixture()
    @StateObject private var viewModel = ArticleViewModel()
    @State private var frames: [String: CGRect] = [:]
    @State private var selectedID: String?
    @State private var openedCount = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var report: String {
        let payload: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil, "states": fixture.states,
            "replaced": fixture.replaced, "error": fixture.imageFailureText,
            "openedCount": openedCount, "selectedID": selectedID ?? "",
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY), "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Favoritrækkernes faktiske geometri")
                        .accessibilityIdentifier("home.favoriteRows.geometry").accessibilityValue(report)
                    Button("Erstat fejlet lokalt billede", action: fixture.replaceFailedImage)
                        .accessibilityIdentifier("home.favoriteRows.replace")
                        .disabled(fixture.replaced || fixture.states["favorite-unrated"] != "failed")
                }
                .font(.caption).dynamicTypeSize(.large).padding(4)
                List {
                    Section {
                        ForEach(fixture.samples) { sample in
                            Button { selectedID = sample.id; openedCount += 1 } label: {
                                FavoriteArticleRow(article: sample.article, fixtureImageCache: fixture.cache,
                                    onImageEvent: { fixture.record($0, id: sample.id) },
                                    onFrame: { record(sample.id + "." + $0, $1) })
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.favoriteRows.row." + sample.id)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("home.fixture.favoriteRows")
            }
            .navigationTitle("Lokale favoritrækker").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } })) {
                if let sample = fixture.samples.first(where: { $0.id == selectedID }) {
                    VStack(spacing: 16) {
                        Text(sample.title).font(.title).accessibilityIdentifier("home.favoriteRows.destination")
                        Button("Tilbage til favoritterne") { selectedID = nil }
                            .accessibilityIdentifier("home.favoriteRows.return")
                    }
                    .padding(16).navigationTitle("Lokal artikel").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .environmentObject(viewModel)
        .onAppear { viewModel.topics = [Topic(id: "fixture-culture", name: "Film")] }
    }
    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}

/// The actual favorites controls in the production plain List container. Only
/// selection bindings, count and the search callback are supplied locally; this
/// does not initialize FavoritesRuntime or claim full tab-navigation acceptance.
@MainActor
private struct LocalFavoriteControlsView: View {
    @State private var selectedSort: FavoritesView.SortOption = .titleAZ
    @State private var selectedCategory = "Kultur & Mening"
    @State private var searchRequests = 0
    @State private var frames: [String: CGRect] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var count: Int { selectedCategory == "Alle" ? 3 : selectedCategory == "Film" ? 2 : 1 }
    private var report: String {
        let payload: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil,
            "selectedSort": selectedSort.rawValue, "selectedCategory": selectedCategory,
            "articleCount": count, "searchRequests": searchRequests,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY),
                "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Favoritvalgenes faktiske geometri")
                    .font(.caption).dynamicTypeSize(.large).padding(4)
                    .accessibilityIdentifier("home.favoriteControls.geometry").accessibilityValue(report)
                List {
                    Section {
                        FavoritesControls(selectedSort: $selectedSort, selectedCategory: $selectedCategory,
                            availableCategories: ["Film", "Kultur & Mening"], articleCount: count,
                            onSearch: { searchRequests += 1 }, onFrame: record)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("home.fixture.favoriteControls")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("viewport", $0) }
            }
            .navigationTitle("Lokale favoritvalg").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}

/// Actual shell and coordinator paths. Home remains the prepared production
/// feed; the extended scenario's other roots are local chrome/path receipts,
/// never a claim of live Search, account, reader or playback acceptance.
private struct LocalTabRootReceipt: Equatable {
    let identity: UUID
    let choice: Int
    var json: [String: Any] { ["identity": identity.uuidString, "choice": choice] }
}

@MainActor
private struct LocalTabRootProbe: View {
    let tab: Tab
    let onOpen: () -> Void
    let onState: (LocalTabRootReceipt) -> Void
    @State private var identity = UUID()
    @State private var choice = 0

    private var openTitle: String {
        switch tab {
        case .search: "Åbn lokal artikelliste"
        case .categories: "Åbn lokal kategori"
        case .favorites: "Åbn lokal gemt artikel"
        case .home: "Åbn lokalt Hjem"
        }
    }
    private var openID: String {
        tab == .search ? "home.navigation.search.open" : "tabs.reselect.open." + tab.navigationIdentifier
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("Lokal " + tab.rawValue).font(.title)
                .accessibilityIdentifier("tabs.reselect.root." + tab.navigationIdentifier)
            Button("Bevar lokalt valg") { choice += 1 }
                .accessibilityIdentifier("tabs.reselect.choice." + tab.navigationIdentifier)
                .accessibilityValue(String(choice))
            Button(openTitle, action: onOpen).accessibilityIdentifier(openID)
        }
        .padding(16)
        .navigationTitle(LocalizedStringKey(tab.rawValue)).navigationBarTitleDisplayMode(.inline)
        .onAppear { onState(.init(identity: identity, choice: choice)) }
        .onChange(of: choice) { _, value in onState(.init(identity: identity, choice: value)) }
    }
}

@MainActor
private struct LocalHomeTabReselectView: View {
    @ObservedObject var fixture: LocalHomeFixture
    var extended = false
    @StateObject private var navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
    @State private var homeSelectionBindings = 0
    @State private var homeTabCallbacks = 0
    @State private var rootStates: [String: LocalTabRootReceipt] = [:]
    @State private var playerIdentity = UUID()
    @State private var playerIsPlaying = true
    @State private var playerPauseActions = 0
    @State private var playerForwardActions = 0
    @State private var playerOpenActions = 0
    private let searchArticle = Article(id: "tab-search-article", name: "Lokal søgeartikel", slug: "tab-search-article",
        content: "", intro: "Kun lokal navigation", topicID: "local")
    private let categoryArticle = Article(id: "tab-category-article", name: "Lokal kategoriartikel", slug: "tab-category-article",
        content: "", intro: "Kun lokal navigation", topicID: "local")
    private let favoriteArticle = Article(id: "tab-favorite-article", name: "Lokal gemt artikel", slug: "tab-favorite-article",
        content: "", intro: "Kun lokal navigation", topicID: "local")
    private let author = Author(id: "tab-local-author", name: "Lokal skribent", bio: nil,
        imageURL: nil, position: "", photoURL: "")

    private var tabSelection: Binding<Tab> {
        Binding(get: { navigation.selectedTab }, set: { tab in
            if tab == .home {
                homeSelectionBindings += 1
                navigation.navigateToHomeRoot()
            } else { navigation.selectedTab = tab }
        })
    }
    private var navigationActions: HomeFeedActions {
        var actions = fixture.actions
        actions.openArticle = { article, authority, _ in
            guard fixture.model.isCurrent(authority),
                  let current = fixture.model.snapshot?.resumeIndex.articlesByID[article.id],
                  current.bodyRevision == article.bodyRevision else { return }
            navigation.navigateToArticle(current, in: .home)
        }
        return actions
    }
    private func recordRoot(_ tab: Tab, _ value: LocalTabRootReceipt) {
        let key = tab.navigationIdentifier
        if rootStates[key] != value { rootStates[key] = value }
    }
    private var report: String {
        let player: [String: Any] = ["identity": playerIdentity.uuidString,
            "episodeID": extended ? "local-tab-memory-audio" : "", "isPlaying": playerIsPlaying,
            "pauseActions": playerPauseActions, "forwardActions": playerForwardActions, "openActions": playerOpenActions]
        let payload: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil, "extended": extended,
            "selectedTab": navigation.selectedTab.rawValue,
            "homePathCount": navigation.homePath.count, "searchPathCount": navigation.searchPath.count,
            "categoriesPathCount": navigation.categoriesPath.count, "favoritesPathCount": navigation.favoritesPath.count,
            "homeStackID": navigation.homeStackID.uuidString,
            "homeSelectionBindings": homeSelectionBindings, "homeTabCallbacks": homeTabCallbacks,
            "rootStates": rootStates.mapValues(\.json), "playerMemory": player,
            "actualShell": true, "normalPlayerOrReaderStarted": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("Faktisk lokal fanenavigation")
                .font(.caption).dynamicTypeSize(.large).padding(4)
                .accessibilityIdentifier("home.navigation.state").accessibilityValue(report)
            AproposNavigationShell(selection: tabSelection, hasActiveEpisode: extended, hasPreparation: false,
                onTabReselected: { tab in
                    if tab == .home { homeTabCallbacks += 1 }
                    navigation.reselect(tab)
                }) {
                NavigationStack(path: navigation.path(for: .home)) {
                    HomeFeedContent(model: fixture.model, progressStore: fixture.progress,
                        presentation: fixture.presentation, favoriteIDs: fixture.favoriteIDs,
                        isLoading: fixture.isLoading, errorMessage: fixture.errorMessage, actions: navigationActions)
                        .navigationDestination(for: Article.self) { article in
                            Text(article.name ?? "Artikel").font(.title).padding()
                                .accessibilityIdentifier("home.navigation.article")
                                .navigationTitle("Lokal artikel").navigationBarTitleDisplayMode(.inline)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
                .id(navigation.homeStackID)
                .background { if extended { InteractivePopGestureEnabler() } }
                .tabItem { Label("Hjem", systemImage: "house.fill") }
                .tag(Tab.home)


                NavigationStack(path: navigation.path(for: .search)) {
                    searchRoot
                        .navigationTitle("Artikler")
                        .navigationDestination(for: String.self) { _ in
                            VStack(spacing: 16) {
                                Text("Bevaret lokal artikelliste")
                                    .accessibilityIdentifier("home.navigation.search.destination")
                                if extended {
                                    Button("Åbn lokal søgeartikel") { navigation.navigateToArticle(searchArticle, in: .search) }
                                        .accessibilityIdentifier("tabs.reselect.nestedArticle.search")
                                }
                            }
                            .navigationTitle("Lokal liste").navigationBarTitleDisplayMode(.inline)
                        }
                        .navigationDestination(for: Article.self) { article in localArticle(article, in: .search) }
                }
                .background { if extended { InteractivePopGestureEnabler() } }
                .tabItem { Label("Artikler", systemImage: "doc.text") }.tag(Tab.search)

                NavigationStack(path: navigation.path(for: .categories)) {
                    if extended {
                        LocalTabRootProbe(tab: .categories,
                            onOpen: { navigation.navigateToCategory("Lokal kultur", in: .categories) },
                            onState: { recordRoot(.categories, $0) })
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: AppRoute.self) { route in localRoute(route, in: .categories) }
                            .navigationDestination(for: Article.self) { article in localArticle(article, in: .categories) }
                    } else { Text("Lokale kategorier") }
                }
                .background { if extended { InteractivePopGestureEnabler() } }
                .tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }.tag(Tab.categories)

                NavigationStack(path: navigation.path(for: .favorites)) {
                    if extended {
                        LocalTabRootProbe(tab: .favorites,
                            onOpen: { navigation.navigateToArticle(favoriteArticle, in: .favorites) },
                            onState: { recordRoot(.favorites, $0) })
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: Article.self) { article in localArticle(article, in: .favorites) }
                            .navigationDestination(for: AppRoute.self) { route in localRoute(route, in: .favorites) }
                    } else { Text("Lokale favoritter") }
                }
                .background { if extended { InteractivePopGestureEnabler() } }
                .tabItem { Label("Min side", systemImage: "person.crop.circle") }.tag(Tab.favorites)
            } accessory: {
                if extended {
                    PodcastMiniPlayerContent(title: "Lokal fanelyd", subtitle: "Kun memory", artworkURL: nil,
                        isAINarration: false, isBuffering: false, isPlaying: playerIsPlaying, progress: 0.35,
                        togglePlayPause: { playerIsPlaying.toggle(); playerPauseActions += 1 },
                        seekForward: { playerForwardActions += 1 }, openPlayer: { playerOpenActions += 1 },
                        closePlayer: {})
                }
            }
        }
        .environment(\.navigationCoordinator, navigation)
        .environment(\.homeImagePolicy, .placeholder)
    }

    @ViewBuilder private var searchRoot: some View {
        if extended {
            LocalTabRootProbe(tab: .search, onOpen: { navigation.searchPath.append("search-sentinel") },
                onState: { recordRoot(.search, $0) })
        } else {
            Button("Åbn lokal artikelliste") { navigation.searchPath.append("search-sentinel") }
                .accessibilityIdentifier("home.navigation.search.open")
        }
    }
    private func moreDestination(in tab: Tab) -> some View {
        Text("Lokal uddybning").font(.title).padding()
            .accessibilityIdentifier("tabs.reselect.more.destination." + tab.navigationIdentifier)
            .navigationTitle("Lokal uddybning").navigationBarTitleDisplayMode(.inline)
    }
    private func localArticle(_ article: Article, in tab: Tab) -> some View {
        VStack(spacing: 16) {
            Text(article.name ?? "Artikel").font(.title)
                .accessibilityIdentifier("tabs.reselect.article." + tab.navigationIdentifier)
            if tab == .favorites {
                Button("Om lokal skribent") { navigation.navigateToAuthor(author, in: tab) }
                    .accessibilityIdentifier("tabs.reselect.author.open.favorites")
            }
            NavigationLink { moreDestination(in: tab) } label: { Text("Åbn lokal uddybning") }
                .accessibilityIdentifier("tabs.reselect.more.open." + tab.navigationIdentifier)
        }
        .padding(16).navigationTitle("Lokal artikel").navigationBarTitleDisplayMode(.inline)
        .articleNativeBackNavigation()
    }
    @ViewBuilder private func localRoute(_ route: AppRoute, in tab: Tab) -> some View {
        switch route {
        case .categoryDetail(let name):
            VStack(spacing: 16) {
                Text(name).font(.title).accessibilityIdentifier("tabs.reselect.category.destination")
                Button("Åbn lokal kategoriartikel") { navigation.navigateToArticle(categoryArticle, in: tab) }
                    .accessibilityIdentifier("tabs.reselect.nestedArticle.categories")
            }
            .padding(16).navigationTitle("Lokal kategori").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        case .author(let value):
            VStack(spacing: 16) {
                Text(value.name).font(.title).accessibilityIdentifier("tabs.reselect.author.destination")
                NavigationLink { moreDestination(in: tab) } label: { Text("Åbn lokal uddybning") }
                    .accessibilityIdentifier("tabs.reselect.more.open." + tab.navigationIdentifier)
            }
            .padding(16).navigationTitle("Lokal skribent").navigationBarTitleDisplayMode(.inline)
        default:
            Text("Ikke anvendt lokal rute")
        }
    }
}


/// Actual category/search screens and their real path bindings, with only local
/// article destinations. No reader, AVPlayer, SDK, cache, or network is started.
@MainActor
private final class LocalListNavigationFixture: ObservableObject {
    let identity = UUID()
    let viewModel: ArticleViewModel
    let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
    let presentation: PodcastPlayerPresentationModel
    private final class Playback {
        var value = PodcastPlayerPresentation(activeEpisodeID: "local-list-audio", preparationID: nil,
            preparationTitle: nil, isFullPlayerPresented: false, offlinePlaybackMessage: nil)
    }
    private let playback: Playback
    @Published private(set) var playing = true
    @Published private(set) var pauseActions = 0
    @Published private(set) var forwardActions = 0
    @Published private(set) var openActions = 0
    @Published private(set) var openedArticleID: String?
    init() {
        let playback = Playback(); self.playback = playback
        presentation = PodcastPlayerPresentationModel(initial: playback.value, read: { playback.value })
        viewModel = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(),
            actualUserID: { nil }, readEffects: .init())
        viewModel.topics = [Topic(id: "film", name: "Film"), Topic(id: "culture", name: "Kultur"),
            Topic(id: "music", name: "Musik")]
        viewModel.authors = []
        let searchArticles = (1...40).map { index in
            Article(id: "search-\(index)", name: String(format: "Rejse %02d", index),
                slug: "search-\(index)", content: "", intro: "En lokal fortælling.", topicID: "music")
        }
        let categoryArticles = (1...12).map { index in
            Article(id: "culture-\(index)", name: "Kulturfortælling \(index)", slug: "culture-\(index)",
                content: "", intro: "En fortælling fra kulturlivet.", topicID: "culture")
        }
        viewModel.articles = searchArticles + categoryArticles + [
            Article(id: "film-only", name: "Kun film", slug: "film-only", content: "",
                intro: "Denne artikel tilhører kun Film.", topicID: "film"),
            Article(id: "film-culture", name: "Film i kulturen", slug: "film-culture", content: "",
                intro: "Film er hovedemnet, Kultur er også valgt.", topicID: "film", topicsIDs: ["culture"])
        ]
        navigation.selectedTab = .categories
    }

    func showPreparation() {
        playback.value.activeEpisodeID = nil
        playback.value.preparationID = UUID()
        playback.value.preparationTitle = "En lokal lydfortælling"
        presentation.synchronize()
    }
    func cancelPreparation(_ id: UUID) {
        guard playback.value.preparationID == id else { return }
        playback.value.preparationID = nil
        playback.value.preparationTitle = nil
        presentation.synchronize()
    }
    func togglePlaying() { pauseActions += 1; playing.toggle() }
    func forward() { forwardActions += 1 }
    func openPlayer() { openActions += 1 }
    func closePlayer() {
        playback.value.activeEpisodeID = nil
        presentation.synchronize()
    }
    func articleAppeared(_ id: String) { openedArticleID = id }
    func articleDisappeared(_ id: String) {
        if openedArticleID == id { openedArticleID = nil }
    }
}

@MainActor
private struct LocalListNavigationView: View {
    @StateObject private var fixture = LocalListNavigationFixture()
    var body: some View {
        LocalListNavigationContent(fixture: fixture, navigation: fixture.navigation, presentation: fixture.presentation)
    }
}

@MainActor
private struct LocalListNavigationContent: View {
    @ObservedObject var fixture: LocalListNavigationFixture
    @ObservedObject var navigation: NavigationCoordinator
    @ObservedObject var presentation: PodcastPlayerPresentationModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var miniFrame: CGRect = .zero
    @State private var rootBottom: CGFloat = 0
    @State private var detailGeometry = AproposNavigationDetailGeometry()
    @State private var preparationFrame: CGRect = .zero
    private struct Viewport: Equatable {
        var frame: CGRect = .zero
        var safeBottom: CGFloat = 0
        var report: [String: Double] {
            ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width),
                "height": Double(frame.height), "bottom": Double(frame.maxY), "safeBottom": Double(safeBottom)]
        }
    }
    @State private var searchViewport = Viewport()
    @State private var categoryViewport = Viewport()

    private func recordedPath(for tab: Tab) -> Binding<NavigationPath> {
        let original = navigation.path(for: tab)
        return Binding(get: { original.wrappedValue }, set: { value in
            original.wrappedValue = value
        })
    }
    private func selectHome() {
        navigation.navigateToHomeRoot()
    }

    private var report: String {
        let payload: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil,
            "fixtureIdentity": fixture.identity.uuidString,
            "episodeID": presentation.snapshot.activeEpisodeID ?? "",
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "selectedTab": navigation.selectedTab.rawValue,
            "searchPathCount": navigation.searchPath.count, "categoriesPathCount": navigation.categoriesPath.count,
            "homeStackID": navigation.homeStackID.uuidString,
            "openedArticleID": fixture.openedArticleID ?? "", "feedCount": fixture.viewModel.articles.count,
            "playing": fixture.playing, "pauseActions": fixture.pauseActions,
            "forwardActions": fixture.forwardActions, "openActions": fixture.openActions,
            "hasActiveEpisode": presentation.snapshot.hasActiveEpisode,
            "rootBottom": Double(rootBottom),
            "detailFrame": ["x": Double(detailGeometry.frame.minX), "y": Double(detailGeometry.frame.minY),
                "width": Double(detailGeometry.frame.width), "height": Double(detailGeometry.frame.height)],
            "detailSize": ["width": Double(detailGeometry.size.width), "height": Double(detailGeometry.size.height)],
            "detailSafeInsets": ["top": Double(detailGeometry.safeAreaInsets.top),
                "bottom": Double(detailGeometry.safeAreaInsets.bottom)],
            "hasPreparation": presentation.snapshot.preparationTitle != nil,
            "preparationFrame": ["x": Double(preparationFrame.minX), "y": Double(preparationFrame.minY),
                "width": Double(preparationFrame.width), "height": Double(preparationFrame.height)],
            "expectedMiniTop": Double(PodcastMiniPlayerLayout.topEdge(containerBottom: detailGeometry.frame.maxY, for: dynamicTypeSize,
                bottomOffset: UIDevice.current.userInterfaceIdiom == .pad ? 20 : PodcastMiniPlayerLayout.bottomOffset)),
            "searchViewport": searchViewport.report, "categoryViewport": categoryViewport.report,
            "miniFrame": ["x": Double(miniFrame.minX), "y": Double(miniFrame.minY),
                "width": Double(miniFrame.width), "height": Double(miniFrame.height)]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Faktiske lister med lokal afspiller")
                .font(.caption).dynamicTypeSize(.large).padding(4)
                .accessibilityIdentifier("list.navigation.state").accessibilityValue(report)
            HStack {
                Button("Vis forberedelse", action: fixture.showPreparation)
                    .accessibilityIdentifier("ipad.fixture.preparation")
            }
            .font(.caption).dynamicTypeSize(.large)
            AproposNavigationShell(selection: Binding(get: { navigation.selectedTab }, set: {
                navigation.navigateToTab($0)
            }), hasActiveEpisode: presentation.snapshot.hasActiveEpisode, hasPreparation: presentation.snapshot.preparationTitle != nil,
                onTabReselected: { navigation.reselect($0) }) {
                // Local roots isolate shell ownership only. Search/categories
                // below are the actual product screens; account/Home are not
                // claimed as complete screen acceptance by this fixture.
                NavigationStack(path: recordedPath(for: .home)) {
                    Text("Lokalt Hjem").navigationTitle("Hjem")
                }
                .id(navigation.homeStackID)
                .tabItem { Label("Hjem", systemImage: "house.fill") }.tag(Tab.home)
                NavigationStack(path: recordedPath(for: .search)) {
                    SearchView_Enhanced()
                        .accessibilityIdentifier("list.navigation.search")
                        .onGeometryChange(for: Viewport.self) {
                            Viewport(frame: $0.frame(in: .global), safeBottom: $0.safeAreaInsets.bottom)
                        } action: { searchViewport = $0 }
                        .navigationDestination(for: Article.self) { article in articleDestination(article) }
                }
                .tabItem { Label("Artikler", systemImage: "doc.text") }.tag(Tab.search)
                NavigationStack(path: recordedPath(for: .categories)) {
                    CategoriesView()
                        .accessibilityIdentifier("list.navigation.categories")
                        .navigationDestination(for: AppRoute.self) { route in
                            if case .categoryDetail(let name) = route {
                                CategoryDetailView(categoryName: name)
                                    .accessibilityIdentifier("list.navigation.category")
                                    .onGeometryChange(for: Viewport.self) {
                                        Viewport(frame: $0.frame(in: .global), safeBottom: $0.safeAreaInsets.bottom)
                                    } action: { categoryViewport = $0 }
                            }
                        }
                        .navigationDestination(for: Article.self) { article in articleDestination(article) }
                }
                .tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }.tag(Tab.categories)
                NavigationStack(path: recordedPath(for: .favorites)) {
                    Text("Lokal Min side").navigationTitle("Min side")
                }
                .tabItem { Label("Min side", systemImage: "person.crop.circle") }.tag(Tab.favorites)
            } accessory: {
                if presentation.snapshot.hasActiveEpisode {
                    PodcastMiniPlayerContent(title: "En lokal lydfortælling", subtitle: "Apropos Magazine",
                        artworkURL: nil, isAINarration: false, isBuffering: false,
                        isPlaying: fixture.playing, progress: 0.35,
                        togglePlayPause: fixture.togglePlaying, seekForward: fixture.forward,
                        openPlayer: fixture.openPlayer, closePlayer: fixture.closePlayer)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { miniFrame = $0 }
                        .onDisappear { miniFrame = .zero }
                        .zIndex(2)
                } else if let title = presentation.snapshot.preparationTitle,
                          let id = presentation.snapshot.preparationID {
                    PodcastOfflinePreparationBar(title: title, open: fixture.openPlayer,
                        cancel: { fixture.cancelPreparation(id) })
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { preparationFrame = $0 }
                        .onDisappear { preparationFrame = .zero }
                }
            }
            .environment(\.aproposNavigationDetailProbe) { detailGeometry = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { rootBottom = $0 }
        }
        .overlay(alignment: .topLeading) {
            LocalListUIKitDiagnosticsProbe().frame(width: 1, height: 1).allowsHitTesting(false)
        }
        .environmentObject(fixture.viewModel)
        .environmentObject(navigation)
        .environment(\.navigationCoordinator, navigation)
    }

    private func articleDestination(_ article: Article) -> some View {
        Text(article.name ?? "Artikel").font(.title).padding()
            .accessibilityIdentifier("list.navigation.article")
            .navigationTitle("Lokal artikel").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .onAppear { fixture.articleAppeared(article.id) }
            .onDisappear { fixture.articleDisappeared(article.id) }
    }
}



/// Fixture-only diagnostics. XCTest reads the value after each real
/// action; the getter only inspects this label's own window and never mutates it.
@MainActor
private struct LocalListUIKitDiagnosticsProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> LocalListUIKitDiagnosticsLabel {
        let label = LocalListUIKitDiagnosticsLabel()
        label.text = " "
        label.textColor = .clear
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = true
        label.accessibilityElementsHidden = false
        label.accessibilityIdentifier = "list.navigation.diagnostics"
        label.accessibilityLabel = "Lokal UIKit-diagnostik"
        return label
    }
    func updateUIView(_ uiView: LocalListUIKitDiagnosticsLabel, context: Context) {}
}

@MainActor
private final class LocalListUIKitDiagnosticsLabel: UILabel {
    override var accessibilityValue: String? {
        get { currentWindowDiagnostics() }
        set { /* Values are read live, never cached or fed back into layout. */ }
    }

    private func currentWindowDiagnostics() -> String {
        guard let window else { return "{\"attached\":false}" }
        func rectangle(_ value: CGRect) -> [String: Double] {
            ["x": Double(value.minX), "y": Double(value.minY),
                "width": Double(value.width), "height": Double(value.height)]
        }
        func insets(_ value: UIEdgeInsets) -> [String: Double] {
            ["top": Double(value.top), "left": Double(value.left),
                "bottom": Double(value.bottom), "right": Double(value.right)]
        }
        var stack: [(UIView, Int)] = [(window, 0)]
        var visited = 0
        var scrollViews: [[String: Any]] = []
        var navigationBars: [[String: Any]] = []
        while let (view, depth) = stack.popLast(), visited < 512 {
            visited += 1
            guard !view.isHidden, view.alpha > 0.01, view === window || view.window === window else { continue }
            let frame = view.convert(view.bounds, to: window)
            let visible = !frame.isEmpty && !frame.isNull && frame.intersects(window.bounds)
            if visible, let scroll = view as? UIScrollView, scrollViews.count < 24 {
                scrollViews.append([
                    "class": String(reflecting: type(of: scroll)),
                    "identifier": scroll.accessibilityIdentifier ?? "",
                    "frame": rectangle(frame), "bounds": rectangle(scroll.bounds),
                    "contentSize": ["width": Double(scroll.contentSize.width), "height": Double(scroll.contentSize.height)],
                    "contentOffset": ["x": Double(scroll.contentOffset.x), "y": Double(scroll.contentOffset.y)],
                    "contentInset": insets(scroll.contentInset),
                    "adjustedContentInset": insets(scroll.adjustedContentInset),
                    "safeAreaInsets": insets(scroll.safeAreaInsets),
                    "insetAdjustmentBehavior": scroll.contentInsetAdjustmentBehavior.rawValue,
                    "isDragging": scroll.isDragging, "isDecelerating": scroll.isDecelerating
                ])
            }
            if visible, let bar = view as? UINavigationBar, navigationBars.count < 8 {
                navigationBars.append(["class": String(reflecting: type(of: bar)),
                    "frame": rectangle(frame), "topItemTitle": bar.topItem?.title ?? ""])
            }
            if depth < 32 { stack.append(contentsOf: view.subviews.reversed().map { ($0, depth + 1) }) }
        }
        let report: [String: Any] = ["attached": true, "coordinateSpace": "own-window",
            "windowFrame": rectangle(window.frame), "windowBounds": rectangle(window.bounds),
            "visited": visited, "bounded": !stack.isEmpty, "scrollViews": scrollViews, "navigationBars": navigationBars]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{\"encodingFailed\":true}" }
        return result
    }
}

/// The production author card with local artwork; geometry is read-only.
@MainActor
private struct LocalAuthorArticleCardsView: View {
    @State private var frames: [String: CGRect] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let artwork: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 240), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 240))
            UIColor.white.setFill(); context.fill(CGRect(x: 40, y: 0, width: 24, height: 240))
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 160, width: 160, height: 80))
        }
    }()
    private static let wideArtwork: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 100), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 100))
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 130, y: 0, width: 60, height: 100))
            UIColor.white.setFill(); context.fill(CGRect(x: 154, y: 0, width: 12, height: 100))
        }
    }()
    private static let articles: [Article] = [
        Article(id: "author-alignment", name: "Kulturens nye stemmer og de fællesskaber, vi bygger sammen",
            slug: "author-alignment", content: "", intro: "Mød menneskene bag historierne, og kom tættere på de idéer, der former vores hverdag.",
            stjerne: 5, topicID: "culture"),
        Article(id: "author-no-intro", name: "En kort historie uden indledning",
            slug: "author-no-intro", content: "", intro: "", topicID: "culture"),
        Article(id: "author-six", name: "Byliv", slug: "author-six", content: "", intro: "Kort fortalt.", stjerne: 6, topicID: "culture"),
        Article(id: "author-zero", name: "En historie uden vurdering", slug: "author-zero", content: "", intro: "Nye stemmer.", stjerne: 0, topicID: "culture")
    ]
    private var report: String {
        let value: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY), "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Forfatterkortenes geometri").font(.caption).dynamicTypeSize(.large)
                    .accessibilityIdentifier("home.author.geometry").accessibilityValue(report)
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(Self.articles) { article in
                            AuthorArticleCardView(article: article, categoryText: "Kultur og samfund",
                                fixtureImage: article.id == "author-zero" ? nil : article.id == "author-six" ? Self.wideArtwork : Self.artwork,
                                onFrame: { key, frame in
                                    let id = article.id + "." + key
                                    if frames[id] != frame { frames[id] = frame }
                                })
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(article.id == "author-alignment" ? "home.fixture.authorCard" :
                                article.id == "author-no-intro" ? "home.fixture.authorCard.noIntro" : "home.fixture.authorCard." + article.id)
                        }
                    }.padding(16)
                }
                .accessibilityIdentifier("home.fixture.authorAlignment")
            }
            .navigationTitle("Lokalt forfatterkort").navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
