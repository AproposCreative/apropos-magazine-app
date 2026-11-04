#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

@MainActor
private final class ReaderAvailabilityFixture: ObservableObject {
    let model = ArticleAvailabilityModel(schedule: { _ in {} })
    @Published var article = Article(id: "fixture-story", name: "Testartikel", slug: "fixture-story",
                                     content: "Gammel lokal artikeltekst", intro: "", topicID: "music",
                                     isDraft: false, lastPublished: "2026-10-20T10:00:00Z", contentRevision: "fixture-v1")
    @Published var wentBack = false
    let listens = PodcastCatalogPublication()
    let audioAvailability = PodcastAvailabilityModel()
    @Published var isOnline = true
    @Published var downloadedEpisode: PodcastEpisode?
    @Published var playCount = 0
    let includesListen = ProcessInfo.processInfo.arguments.contains("-ReaderListenSmoke")
    let usesLegacyAudio = ProcessInfo.processInfo.arguments.contains("legacy-audio-catalog")
    func supplyAudio(replacement: Bool = false) {
        if usesLegacyAudio {
            // The pre-migration producer emitted neither articleId nor sourceContentRevision.
            // Exercise its real decoder, availability, matcher and enrichment, without I/O.
            let payload = #"{"version":1,"episodes":[{"id":"ai-fixture-story","articleSlug":"fixture-story","title":"Testartikel","audioURL":"https://example.invalid/legacy.mp3","hosts":["Apropos Magazine"],"kind":"ai"}]}"#
            guard let manifest = try? JSONDecoder().decode(PodcastManifest.self, from: Data(payload.utf8)) else { return }
            let episodes = manifest.episodes.compactMap { $0.toEpisode() }
            audioAvailability.recordIdentities([(article.id, article.slug)])
            audioAvailability.acceptManifest(episodes)
            listens.replace(episodes.filter { audioAvailability.allows($0) })
            return
        }
        listens.replace([PodcastEpisode(id: "fixture-audio", articleId: article.id, articleSlug: article.slug,
            title: "Testartikel", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/\(replacement ? "replacement" : "original").mp3"),
            productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)])
    }
    func listenEpisode(in catalog: PodcastCatalogPublication) -> PodcastEpisode? {
        guard model.permitsBody(article),
              let episode = PodcastRepository.bestMatch(in: catalog.snapshot.episodes, for: article,
                                                        requirePlayableAudio: true) else { return nil }
        if usesLegacyAudio {
            let enriched = PodcastRepository.enriched(episode, with: article)
            guard audioAvailability.allows(enriched, articleID: article.id) else { return nil }
            return enriched
        }
        return episode
    }
    func canListen(_ episode: PodcastEpisode) -> Bool {
        if usesLegacyAudio { return isOnline && audioAvailability.allows(episode, articleID: article.id) }
        return isOnline || downloadedEpisode == episode
    }
    private var callbacks: [(Result<ArticleAvailabilityModel.Update, Error>) -> Void] = []
    func start() {
        model.observe(id: article.id) { [weak self] _, callback in
            self?.callbacks.append(callback)
            return {}
        }
    }
    func send(withdrawn: Bool, cached: Bool = false, old: Bool = false) {
        let callback = old ? callbacks.first : callbacks.last
        callback?(.success(.init(withdrawn: withdrawn, isFromCache: cached, revision: "fixture-v2")))
    }
    func fail() { callbacks.last?(.failure(URLError(.notConnectedToInternet))) }
    func supplyFreshBody() {
        article = Article(id: article.id, name: "Testartikel", slug: article.id,
                          content: "Ny genpubliceret artikeltekst", intro: "", topicID: "music",
                          isDraft: false, lastPublished: "2026-10-20T10:00:00Z", contentRevision: "fixture-v2")
    }
}

struct LocalReaderAvailabilitySmokeView: View {
    @StateObject private var fixture = ReaderAvailabilityFixture()
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-ReaderListenHeroSmoke") {
            LocalArticleListenHeroSmokeView()
        } else {
            existingReader
        }
    }
    private var existingReader: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    Text("Lokal læsertest · ingen tjenester").font(.footnote)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                        .font(.footnote)
                    HStack {
                        Button("Afpublicér lokalt") { fixture.send(withdrawn: true) }
                        Button("Gammel cache") { fixture.send(withdrawn: false, cached: true) }
                    }
                    HStack {
                        Button("Netværksfejl") { fixture.fail() }
                        Button("Gammelt svar") { fixture.send(withdrawn: false, old: true) }
                        Button("Genpublicér lokalt") { fixture.send(withdrawn: false) }
                    }
                    .font(.footnote)
                    if fixture.includesListen {
                        HStack {
                            Button("Indlæs lydliste") { fixture.supplyAudio() }
                            Button("Fjern lyd") { fixture.listens.replace([]) }
                            Button("Erstat lydfil") { fixture.supplyAudio(replacement: true) }
                        }
                        HStack {
                            Button(fixture.isOnline ? "Gå offline" : "Gå online") { fixture.isOnline.toggle() }
                            Button("Download lyd lokalt") { fixture.downloadedEpisode = fixture.listens.snapshot.episodes.first }
                        }
                        Text("Lokale afspilninger: \(fixture.playCount)").accessibilityIdentifier("reader.listen.count")
                    }
                }.dynamicTypeSize(.large) // Fixture controls; the real gate below uses the simulator text size.
                LocalReaderFixtureContent(fixture: fixture)
                if fixture.wentBack { Text("Tilbage valgt i test") }
            }
            .padding().tint(.primary)
            .navigationTitle("Lokal læsertest")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { fixture.start() }
            .onDisappear { fixture.model.stop() }
        }
    }
}

private struct LocalReaderFixtureContent: View {
    @ObservedObject var fixture: ReaderAvailabilityFixture
    @ObservedObject var availability: ArticleAvailabilityModel
    init(fixture: ReaderAvailabilityFixture) {
        self.fixture = fixture
        self.availability = fixture.model
    }
    var body: some View {
        ArticleAvailabilityGate(articleID: fixture.article.id, availability: availability,
                                retry: { fixture.start() }, back: { fixture.wentBack = true }) {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Testartikel").font(.title)
                    if fixture.includesListen {
                        ArticleListenSection(catalog: fixture.listens,
                            selection: { fixture.listenEpisode(in: $0) },
                            title: { fixture.canListen($0) ? "Lyt til artiklen" : "Lyd kræver internet" },
                            play: { _ in fixture.playCount += 1 }, isEnabled: { fixture.canListen($0) })
                    }
                    if let visible = availability.sanitized(fixture.article),
                       let content = visible.content, !content.isEmpty {
                        Text(content).accessibilityIdentifier("reader.body")
                    } else {
                        ArticleBodyLoadingState(isLoading: false, isOffline: false) { fixture.supplyFreshBody() }
                    }
                    Spacer()
                }
            }
        }
    }
}
#endif
