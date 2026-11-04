import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ArticleViewModel: ObservableObject {
    typealias ReadPermission = @MainActor () -> Bool
    typealias ReadCompletion<Value> = (Result<Value, Error>) -> Void
    /// Lazy effects at the existing read/cache boundaries; construction opens no SDK.
    @MainActor struct ReadEffects {
        typealias CatalogPreparation = (ArticleMirrorCatalog.Update, @escaping @MainActor () -> [Article], @escaping ReadPermission) async throws -> ArticleFeedSnapshot.Update
        var feed: (@escaping ReadPermission, @escaping ReadCompletion<[Article]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var catalog: ((@escaping ReadPermission, @escaping ReadCompletion<ArticleMirrorCatalog.Update>) -> Void)?
        var beginCatalogRead: () -> CatalogPreparation = { { _, _, _ in throw CancellationError() } }
        var invalidateFeedCache: () -> Void = {}
        var cacheFeed: (ArticleFeedSnapshot.Update) -> Void = { _ in }
        var recordFeedArticles: ([Article]) -> Void = { _ in }
        var scheduleFeedTimeout: ArticleFeedRefreshCoordinator.ScheduleTimeout?
        var reconcileAvailability: (Set<String>) -> Void = { _ in }
        var pruneFeedCache: () -> Void = {}
        var article: (String, @escaping ReadPermission, @escaping ReadCompletion<Article>) -> Void = { _, _, done in done(.failure(CancellationError())) }
        var canDownloadSavedBodies: () -> Bool = { false }
        var recoverSavedAudioDownloads: (@escaping ReadPermission) -> Void = { _ in }
        var refreshSavedAudioCatalog: (@escaping ReadPermission) async -> Void = { _ in }
        var feedFallback: (@escaping ReadPermission, @escaping ReadCompletion<[Article]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var topics: (@escaping ReadPermission, @escaping ReadCompletion<[Topic]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var topicsFallback: (@escaping ReadPermission, @escaping ReadCompletion<[Topic]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var sections: (@escaping ReadPermission, @escaping ReadCompletion<[WebflowSection]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var sectionsFallback: (@escaping ReadPermission, @escaping ReadCompletion<[WebflowSection]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var authors: (@escaping ReadPermission, @escaping ReadCompletion<[Author]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var authorsFallback: (@escaping ReadPermission, @escaping ReadCompletion<[Author]>) -> Void = { _, done in done(.failure(CancellationError())) }
        var stars: (@escaping ReadPermission, @escaping ([String: String]?) -> Void) -> Void = { _, done in done(nil) }
        var starsFallback: (@escaping ReadPermission, @escaping ([String: String]) -> Void) -> Void = { _, done in done([:]) }
        var incoming: (String, @escaping ReadPermission) async -> Result<Article, Error> = { _, _ in .failure(CancellationError()) }
        var cacheTopics: ([Topic]) -> Void = { _ in }
        var cacheSections: ([WebflowSection]) -> Void = { _ in }
        var cacheAuthors: ([Author]) -> Void = { _ in }
        var cacheStars: ([String: String]) -> Void = { _ in }
        static var live: Self {
            var e = Self()
            e.feed = { permission, done in FirestoreArticleService.shared.fetchArticles(stillCurrent: permission, completion: done) }
            e.catalog = { permission, done in FirestoreArticleService.shared.fetchCatalog(stillCurrent: permission, completion: done) }
            e.beginCatalogRead = {
                let cache = CacheManager.shared, original = cache.captureArticlesHydration()
                return { update, current, permission in
                    try await cache.prepareFeedUpdate(update, original: original, current: current, stillPermitted: permission)
                }
            }
            e.invalidateFeedCache = { CacheManager.shared.invalidateArticleReads() }
            e.cacheFeed = { update in
                if let date = update.cacheTimestamp {
                    CacheManager.shared.cacheArticles(update.articles, articlesAreSorted: true, timestamp: date)
                }
            }
            e.recordFeedArticles = { PodcastAvailabilityService.recordArticles($0) }
            e.reconcileAvailability = { withdrawn in
                let availability = ArticleAvailabilityService.model
                for id in withdrawn {
                    let offline = OfflineManager.shared.offlineArticle(articleID: id)
                    if availability.withdrawnIDs.contains(id) || offline.map({ !availability.permitsBody($0) }) != false {
                        OfflineManager.shared.removeArticleFromOffline(id)
                    }
                }
                FavoritesRuntime.model.reconcileAvailability()
                OfflineManager.shared.synchronizeCurrentMembership()
            }
            e.pruneFeedCache = { CacheManager.shared.pruneUnavailableArticleMetadata() }
            e.article = { id, permission, done in FirestoreArticleService.shared.fetchArticle(by: id, stillCurrent: permission, completion: done) }
            e.canDownloadSavedBodies = { OfflineManager.shared.isOnline }
            e.recoverSavedAudioDownloads = { permission in
                guard permission() else { return }
                OfflineManager.shared.recoverSavedAudioDownloads()
            }
            e.refreshSavedAudioCatalog = { permission in
                guard permission() else { return }
                await PodcastRepository.shared.refreshManifest(force: true, allowPrefetch: false)
            }
            e.feedFallback = { permission, done in guard permission() else { done(.failure(CancellationError())); return }; WebflowService.shared.fetchArticles(completion: done) }
            e.topics = { permission, done in FirestoreMetadataService.shared.fetchTopics(stillCurrent: permission, completion: done) }
            e.topicsFallback = { permission, done in guard permission() else { done(.failure(CancellationError())); return }; WebflowService.shared.fetchTopics(completion: done) }
            e.sections = { permission, done in FirestoreMetadataService.shared.fetchSections(stillCurrent: permission, completion: done) }
            e.sectionsFallback = { permission, done in guard permission() else { done(.failure(CancellationError())); return }; WebflowService.shared.fetchSections(completion: done) }
            e.authors = { permission, done in FirestoreMetadataService.shared.fetchAuthors(stillCurrent: permission, completion: done) }
            e.authorsFallback = { permission, done in guard permission() else { done(.failure(CancellationError())); return }; WebflowService.shared.fetchAuthors(completion: done) }
            e.stars = { permission, done in FirestoreMetadataService.shared.fetchStarsMapping(stillCurrent: permission, completion: done) }
            e.starsFallback = { permission, done in guard permission() else { done([:]); return }; WebflowService.shared.fetchStarsMapping(completion: done) }
            e.incoming = { id, permission in await FirestoreArticleService.shared.fetchIncomingLinkArticle(
                identifier: id, language: PreferencesManager.shared.articleLanguage, stillCurrent: permission) }
            e.cacheTopics = { CacheManager.shared.cacheTopics($0) }
            e.cacheSections = { CacheManager.shared.cacheSections($0) }
            e.cacheAuthors = { CacheManager.shared.cacheAuthors($0) }
            e.cacheStars = { CacheManager.shared.cacheStarsMapping($0) }
            return e
        }
    }
    private let injectedStartup: ReaderSDKStartupState?
    private let readIdentity: CanonicalSessionState
    private let injectedActualUserID: (@MainActor () -> String?)?
    private let readEffects: ReadEffects
    private var startRequested = false
    private var startedContext: CanonicalSessionState.ContextTicket?
    private var startAttempt = UUID()
    private var startupStepsOverride: [(@escaping ReadPermission) -> Void]?
    private var metadataStartupTask: Task<Void, Never>?
    private var metadataRequests: [String: UUID] = [:]

    struct AvailabilitySelection: Equatable {
        let articleID: String
        fileprivate let token: UUID
    }
    private let injectedAvailabilityModel: ArticleAvailabilityModel?
    private let injectedAvailabilitySubscribe: ArticleAvailabilityService.Subscribe?
    private let injectedAvailabilityMirror: ArticleAvailabilityService.Mirror?
    private var availabilitySelection: AvailabilitySelection?
    private var availabilityAttempt: UUID?
    private var availabilityPermission: ReadPermission?
    private var availabilityObservation: (model: ArticleAvailabilityModel, ticket: ArticleAvailabilityModel.ObservationTicket)?

    func captureReadPermission() -> ReadPermission? {
        if let injectedStartup {
            guard let actual = injectedActualUserID else { return nil }
            return injectedStartup.captureReaderWork(identity: readIdentity, actualUserID: actual)
        }
        return AuthService.shared.captureReaderWorkPermission()
    }

    /// The future guarded composition calls this after its accepted startup.
    /// Legacy identity changes also call it, giving cold guest/account a fresh read.
    func resumeReaderStartup(retryFailedFavorites: Bool = true) {
        resumeAvailabilityObservation()
        if retryFailedFavorites { refreshFavoritesAfterInterruption() }
        else if favoritesObservationRequested { startFavoritesListenerIfNeeded() }
        guard startRequested else { return }
        start(readerSteps: startupStepsOverride)
        if startupStepsOverride == nil { IncomingLinkRuntime.shared.refreshStartupReadiness() }
    }

    private func readContextChanged() {
        stopFavoritesListener()
        retireAvailabilityObservation()
        startAttempt = UUID(); startedContext = nil
        startupHydrationTask?.cancel(); startupHydrationTask = nil
        startupHydrationBegan = false; startupAdmission.invalidate()
        delayedFeedRefresh?.cancel(); delayedFeedRefresh = nil
        metadataStartupTask?.cancel(); metadataStartupTask = nil
        metadataRequests.removeAll()
        feedRefreshCoordinator.invalidate()
        objectWillChange.send()
        Task { @MainActor [weak self] in self?.resumeReaderStartup() }
    }

    private let feedPublication = ArticleFeedPublication()
    private lazy var startupAdmission = ArticleFeedStartupAdmission(feed: feedPublication)
    var articles: [Article] {
        get { feedPublication.snapshot.articles }
        set { _ = feedPublication.replace(newValue) }
    }
    var articleChanges: AnyPublisher<[Article], Never> { feedPublication.changes.map(\.articles).eraseToAnyPublisher() }
    private let languagePreferences: PreferencesManager?
    @Published private(set) var articleLanguage: ArticleContentLanguage = .danish
    let accountSaveGate: SavedArticleAccountGate
    private let languageChanges = PassthroughSubject<Void, Never>()
    private var feedFailures: [ArticleContentLanguage: Error] = [:]
    /// Keep the authoritative catalog intact. A language choice only changes
    /// presentation; it never removes a favorite, cached body or publication.
    var visibleArticles: [Article] { ArticleLanguageSelection.visible(articles, language: articleLanguage) }
    var visibleArticleChanges: AnyPublisher<[Article], Never> {
        Publishers.Merge(articleChanges.map { _ in () }, languageChanges.eraseToAnyPublisher())
            .map { [weak self] in self?.visibleArticles ?? [] }.eraseToAnyPublisher()
    }
    func isVisibleArticle(_ article: Article) -> Bool {
        article.hasValidContentIdentity && article.contentLanguage == articleLanguage
    }

    private func selectArticleLanguage(_ language: ArticleContentLanguage) {
        guard language != articleLanguage else { return }
        accountSaveGate.cancel()
        articleLanguage = language
        fetchError = feedFailures[language].map { _ in ArticleMirrorCatalog.LanguageFailure(language: language) }
        languageChanges.send()
        guard hasStarted else { return }
        // A result from the previous language cannot refill its Home rails.
        recommendationCoordinator.invalidate()
        personalizedRecommendations = []
        aiRecommendations = []
        homeRecommendations = []
        prepareHomeIfNeeded()
        queueRecommendationRefresh()
        CacheManager.shared.syncWidgetFeed(from: articles, language: language)
    }
    private let homeInputReceiver = HomeFeedInputReceiver()
    private lazy var preparedHome = HomeFeedPreparationModel(currentAuthority: { [weak self] in
        self?.homeInputReceiver.authority
    })
    var homeFeedModel: HomeFeedPreparationModel { preparedHome }
    private var homeAvailabilityRevision = UUID()
    private var homeRecommendations: [HomeRecommendation] = []
    private var homeRecommendationsOwner: UUID?
    private var startupHydrationTask: Task<Void, Never>?
    private var startupHydrationBegan = false
    private var warmedHomeImageURLs = Set<URL>()
    @Published var aiRecommendations: [Article] = []
    @Published var personalizedRecommendations: [(Article, String)] = []
    @Published var isLoading: Bool = false
    @Published var fetchError: Error? = nil
    @Published var isLoadingAI: Bool = false
    @Published var aiError: String? = nil
    // Membership is never copied into a second mutable or legacy-backed list.
    var favorites: [Article] { FavoritesRuntime.model.snapshot.articles }
    var favoriteError: String? { FavoritesRuntime.model.snapshot.issueMessage }
    var isLoadingFavorites: Bool { FavoritesRuntime.model.snapshot.state == .loading }
    @Published var user: UserProfile? = nil
    private struct Metadata {
        var topics: [Topic] = []
        var sections: [WebflowSection] = []
        var authors: [Author] = []
        var starsMapping: [String: String] = [:]
    }
    private var metadata = Metadata()
    private let authorEvents = PassthroughSubject<[Author], Never>()
    var authorChanges: AnyPublisher<[Author], Never> { authorEvents.eraseToAnyPublisher() }
    var topics: [Topic] {
        get { metadata.topics }
        set { commitMetadata(newValue, at: \.topics, stillCurrent: { true }) }
    }
    var sections: [WebflowSection] {
        get { metadata.sections }
        set { commitMetadata(newValue, at: \.sections, stillCurrent: { true }) }
    }
    var authors: [Author] {
        get { metadata.authors }
        set { commitMetadata(newValue, at: \.authors, stillCurrent: { true }); authorEvents.send(metadata.authors) }
    }
    var starsMapping: [String: String] {
        get { metadata.starsMapping }
        set { commitMetadata(newValue, at: \.starsMapping, stillCurrent: { true }) }
    }
    private var topicFailure: Error?
    var topicsError: Error? { topicFailure }
    private func commitTopicsError(_ error: Error?, stillCurrent: ReadPermission) {
        guard stillCurrent() else { return }
        objectWillChange.send()
        guard stillCurrent() else { return }
        topicFailure = error
    }
    var isLoadingTopics: Bool { metadataRequests["topics"] != nil }
    @Published var sectionsError: Error? = nil

    private func commitMetadata<Value>(_ value: Value, at path: WritableKeyPath<Metadata, Value>, stillCurrent: ReadPermission) {
        guard stillCurrent() else { return }
        objectWillChange.send()
        guard stillCurrent() else { return }
        metadata[keyPath: path] = value
        prepareHomeIfNeeded()
    }
    @Published var fullArticle: Article?
    @Published var anmeldelserTopicID:String? = nil
    private var hasStarted = false
    private var feedAvailabilityObservation: AnyCancellable?
    private var appliedWithdrawals = Set<String>()
    private var recommendationRefreshTask: Task<Void, Never>?
    private var recommendationCanonicalUID: String? { AuthService.shared.state.snapshot.userID }
    private var recommendationAccountInput: ReaderRecommendationAccountInput?
    private var recommendationProfileUID: String?
    private var recommendationProfileReadIDs: [String] = []
    private var recommendationHistoryGeneration: UUID?
    private var recommendationReadIDs = Set<String>()
    private var observedFavoritesGeneration: UUID?
    private lazy var recommendationCoordinator = RecommendationHistoryCoordinator(calculate: { input in
        await RecommendationService.shared.generateRecommendations(input: input)
    }, onChange: { [weak self] state in self?.applyRecommendations(state) })
    
    // Detail work has one active transport and only the latest pending selection.
    @Published private(set) var loadingArticles: Set<String> = []
    private lazy var detailLoader = ArticleDetailLoader(
        fetchArticle: { [weak self] id, completion in
            // The callback carries the membership/revision which existed before
            // transport. It cannot acquire a later account's cache authority.
            let access = OfflineManager.shared.captureAccess(articleID: id)
            self?.fetchArticle(by: id) { result in
                Task { @MainActor in
                    if let access, case .success(let article) = result {
                        _ = OfflineManager.shared.saveArticleForOffline(article, ticket: access)
                    }
                    completion(result)
                }
            }
        },
        fetchAuthor: { [weak self] id, completion in
            self?.fetchAuthor(by: id) { result in
                Task { @MainActor in completion(result) }
            }
        },
        offlineArticle: { Self.offlineArticle(for: $0) },
        permitsBody: { ArticleAvailabilityService.model.permitsBody($0) },
        onBody: { [weak self] article, origin in self?.applyDetailBody(article, origin: origin) },
        onAuthor: { [weak self] id, authorID, author in
            self?.applyDetailAuthor(author, articleID: id, authorID: authorID)
        },
        onFailure: { _, _ in
            AppDiagnostics.recordOperational(.contentFetchFailed)
        },
        onLoadingChange: { [weak self] in self?.loadingArticles = $0 }
    )

    init(startup: ReaderSDKStartupState? = nil, identity: CanonicalSessionState? = nil,
         featureIdentity: CanonicalSessionState? = nil,
         actualUserID: (@MainActor () -> String?)? = nil, readEffects: ReadEffects? = nil,
         availabilityModel: ArticleAvailabilityModel? = nil,
         availabilitySubscribe: ArticleAvailabilityService.Subscribe? = nil,
         availabilityMirror: ArticleAvailabilityService.Mirror? = nil,
         favoriteObservationModel: FavoritesModel? = nil,
         favoriteOffline: FavoritesOfflineCoordinator? = nil,
         favoriteSubscribe: FirestoreService.FavoriteSubscribe? = nil,
         favoriteCanonicalUserID: (@MainActor () -> String?)? = nil,
         favoriteRetry: (@MainActor (UUID) -> Void)? = nil,
         languagePreferences: PreferencesManager? = nil) {
        self.languagePreferences = languagePreferences
        articleLanguage = languagePreferences?.articleLanguage ?? .danish
        injectedFavoriteModel = favoriteObservationModel
        injectedFavoriteOffline = favoriteOffline
        injectedFavoriteSubscribe = favoriteSubscribe
        injectedFavoriteCanonicalUserID = favoriteCanonicalUserID
        injectedFavoriteRetry = favoriteRetry
        injectedAvailabilityModel = availabilityModel
        injectedAvailabilitySubscribe = availabilitySubscribe
        injectedAvailabilityMirror = availabilityMirror
        injectedStartup = startup
        readIdentity = identity ?? AuthService.shared.bootstrapIdentity
        accountSaveGate = SavedArticleAccountGate(canonical: featureIdentity ?? identity ?? AuthService.shared.state)
        injectedActualUserID = actualUserID
        self.readEffects = readEffects ?? .live
        if let favoriteObservationModel, favoriteOffline != nil {
            // The all-local composition exercises the same narrow callback as
            // the production favorite observer without starting its services.
            favoriteObservationModel.changes.sink { [weak self] snapshot in
                self?.observeSavedOfflineFavorites(snapshot)
            }.store(in: &cancellables)
        }
        accountSaveGate.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        languagePreferences?.$preferences.map { $0.contentPreferences.language == .english
            ? ArticleContentLanguage.english : .danish }.removeDuplicates()
            .sink { [weak self] in self?.selectArticleLanguage($0) }.store(in: &cancellables)
        var previous = readIdentity.contextTicket()
        readIdentity.changes.sink { [weak self] _ in
            guard let self else { return }
            let next = self.readIdentity.contextTicket()
            guard next != previous else { return }
            previous = next
            self.readContextChanged()
        }.store(in: &cancellables)
        (startup ?? ReaderSDKStartupState.application).changes.sink { [weak self] in
            // Identity may already have arrived while local startup was closed.
            // Re-evaluate through the same original-account guards, including
            // explicit guest startup; closing also retires old observations.
            self?.readContextChanged()
        }.store(in: &cancellables)
        // Inert forwarding only; no SDK, cache or player construction.
        feedPublication.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        feedPublication.changes.sink { [weak self] _ in
            guard let self, self.hasStarted else { return }
            self.queueRecommendationRefresh()
            self.prepareHomeIfNeeded()
        }.store(in: &cancellables)
    }

    /// Captures committed source values only. Clock/progress/loading are absent.
    /// Availability edges call this synchronously, before any deferred cleanup.
    func prepareHomeIfNeeded() {
        guard hasStarted else { return }
        let owner = AuthService.shared.state.snapshot.generation
        let permittedArticles = visibleArticles.filter { ArticleAvailabilityService.model.permitsBody($0) }
        let permittedEpisodes = PodcastRepository.shared.episodes.filter { PodcastAvailabilityService.model.allows($0) }
        let input = homeInputReceiver.receive(articles: permittedArticles, topics: topics, sections: sections,
            authors: authors, episodes: permittedEpisodes, recommendations: homeRecommendations,
            owner: owner, recommendationOwner: homeRecommendationsOwner, availability: homeAvailabilityRevision, now: Date())
        preparedHome.update(input)
    }

    func acceptedHomeArticle(id: String, authority: HomeFeedAuthority) -> Article? {
        guard hasStarted, homeInputReceiver.isCurrent(authority, owner: AuthService.shared.state.snapshot.generation),
              let original = preparedHome.snapshot,
              original.authority == authority,
              let article = articles.first(where: { $0.id == id }),
              isVisibleArticle(article),
              ArticleAvailabilityService.model.permitsBody(article) else { return nil }
        return article
    }

    func acceptedHomePair(articleID: String, episodeID: String, authority: HomeFeedAuthority) -> PodcastArticlePair? {
        guard let article = acceptedHomeArticle(id: articleID, authority: authority),
              let pair = preparedHome.snapshot?.podcastPairs.first(where: { $0.article.id == articleID && $0.episode.id == episodeID }),
              ArticleDetailContentPolicy.sameRevision(pair.article, article),
              HomePodcastAdmission.rawEpisode(for: pair, in: PodcastRepository.shared.episodes, requiresUniquePlayableID: false) != nil,
              PodcastAvailabilityService.model.allows(pair.episode, articleID: articleID) else { return nil }
        return PodcastArticlePair(article: article, episode: pair.episode)
    }

    func acceptedHomeResumePair(articleID: String, episodeID: String, authority: HomeFeedAuthority,
                                progressContext: PodcastProgressContext, progressGeneration: UUID) -> PodcastArticlePair? {
        guard let article = acceptedHomeArticle(id: articleID, authority: authority) else { return nil }
        let store = PodcastProgressRuntime.store
        let progress = store.snapshot
        guard progressContext.namespace != nil, store.context == progressContext,
              progress.generation == progressGeneration,
              let pair = preparedHome.snapshot?.resumeIndex.pair(episodeID: progress.lastPlayedEpisodeID,
                articleID: progress.lastPlayedArticleID, hasResumableProgress: progress.hasResumableProgress(for: episodeID)),
              pair.article.id == articleID, pair.episode.id == episodeID,
              ArticleDetailContentPolicy.sameRevision(pair.article, article),
              HomePodcastAdmission.rawEpisode(for: pair, in: PodcastRepository.shared.episodes, requiresUniquePlayableID: true) != nil,
              PodcastAvailabilityService.model.allows(pair.episode, articleID: articleID) else { return nil }
        return PodcastArticlePair(article: article, episode: PodcastRepository.enriched(pair.episode, with: article))
    }

    /// Called only by the shared Home presentation after accepted content is
    /// displayed. A completed worker or a dismissed spinner alone is not shown.
    func homeSnapshotWasShown(_ snapshot: HomeFeedSnapshot) {
        guard hasStarted, !snapshot.hero.isEmpty || snapshot.rails.contains(where: { !$0.visible.isEmpty }),
              homeInputReceiver.isCurrent(snapshot.authority, owner: AuthService.shared.state.snapshot.generation),
              preparedHome.isCurrent(snapshot.authority) else { return }
        let heroURLs = snapshot.hero.prefix(2).compactMap { snapshot.metadataByID[$0.id]?.heroImageCandidates.first }
        let articleURLs = (snapshot.podcastPairs.prefix(2).map(\.article) + snapshot.rail(.recommended).visible.prefix(4))
            .compactMap { snapshot.metadataByID[$0.id]?.cardImageURL }
        let requested = Array((heroURLs + articleURLs).prefix(FeatureFlags.homeImagePreloadLimit))
            .filter { warmedHomeImageURLs.insert($0).inserted }
        if !requested.isEmpty { CacheManager.shared.prefetchURLs(requested) }
    }

    func homeSceneBecameActive() { preparedHome.sceneBecameActive() }

    func start(readerSteps: [(@escaping ReadPermission) -> Void]? = nil) {
        startRequested = true
        if let readerSteps { startupStepsOverride = readerSteps }
        guard let permission = captureReadPermission() else { return }
        let context = readIdentity.contextTicket()
        guard startedContext != context else { return }
        let attempt = UUID(); startAttempt = attempt
        let steps = startupStepsOverride ?? [
            { [weak self] permission in self?.installReaderObservers(stillCurrent: permission) },
            { [weak self] permission in self?.beginStartupHydrationIfNeeded(stillCurrent: permission) },
            { [weak self] permission in self?.scheduleReaderLoads(stillCurrent: permission) }
        ]
        for step in steps {
            guard startAttempt == attempt, permission() else { return }
            step(permission)
        }
        guard startAttempt == attempt, permission() else { return }
        startedContext = context
    }

    private func installReaderObservers(stillCurrent: @escaping ReadPermission) {
        guard !hasStarted, stillCurrent() else { return }
        hasStarted = true
        IncomingLinkRuntime.shared.bindResolver({ [weak self] request in
            await self?.resolveIncomingLink(request)
        }, cancelPendingSeek: { PodcastPlayerManager.shared.cancelIncomingLinkSeek() })
        let favoritesModel = FavoritesRuntime.model
        favoritesModel.changes.sink { [weak self] snapshot in
            self?.observeFavorites(snapshot)
        }.store(in: &cancellables)
        observeFavorites(favoritesModel.snapshot)
        let history = ReadingHistoryRuntime.model
        observeRecommendationHistory(history.snapshot)
        history.changes.sink { [weak self] snapshot in
            self?.observeRecommendationHistory(snapshot)
        }.store(in: &cancellables)
        let canonical = AuthService.shared.state
        canonical.changes.sink { [weak self, weak canonical] snapshot in
            guard let canonical, snapshot.generation == canonical.snapshot.generation,
                  snapshot.revision == canonical.snapshot.revision else { return }
            self?.observeRecommendationAccount()
        }.store(in: &cancellables)
        let profileState = UserManager.shared.state
        let receiveProfile: (UserProfileState.Snapshot) -> Void = { [weak self, weak profileState] snapshot in
            guard let self, let profileState,
                  snapshot.generation == profileState.snapshot.generation,
                  snapshot.revision == profileState.snapshot.revision else { return }
            let profile = snapshot.profile
            let uid = profile?.uid
            let ids = RecommendationHistorySelection.validatedProfileIDs(profile?.readArticles ?? [])
            guard uid != self.recommendationProfileUID || Set(ids) != Set(self.recommendationProfileReadIDs) else { return }
            self.recommendationProfileUID = uid
            self.recommendationProfileReadIDs = ids
            self.queueRecommendationRefresh()
        }
        profileState.changes.sink(receiveValue: receiveProfile).store(in: &cancellables)
        receiveProfile(profileState.snapshot)
        installFeedAvailabilityObserver(stillCurrent: stillCurrent)
        if stillCurrent() { ReaderPreferencesService.shared.start() }
        let preferences = ReaderPreferencesService.shared.model
        preferences.changes.sink { [weak self, weak preferences] snapshot in
            guard let preferences, snapshot.generation == preferences.snapshot.generation,
                  snapshot.revision == preferences.snapshot.revision else { return }
            self?.observeRecommendationAccount()
        }.store(in: &cancellables)
        let guestInterests = ReaderIntroductionRuntime.guestInterests
        guestInterests.changes.sink { [weak self, weak guestInterests] snapshot in
            guard let guestInterests, snapshot.revision == guestInterests.snapshot.revision else { return }
            self?.observeRecommendationAccount()
        }.store(in: &cancellables)
        guestInterests.start()
        // Passthrough publishers deliberately do not replay a previous owner.
        // Capture the actual committed initial state after subscribing to both.
        observeRecommendationAccount()

        let repository = PodcastRepository.shared
        repository.changes.sink { [weak self] _ in self?.prepareHomeIfNeeded() }.store(in: &cancellables)
        PodcastAvailabilityService.model.changes.sink { [weak self] in
            self?.homeAvailabilityRevision = UUID()
            self?.prepareHomeIfNeeded()
        }.store(in: &cancellables)
        prepareHomeIfNeeded()

    }

    /// Same subscription in the live composition and the isolated read harness.
    /// Installing it alone never starts account, metadata or playback services.
    func installFeedAvailabilityObserver(stillCurrent: @escaping ReadPermission) {
        guard feedAvailabilityObservation == nil, stillCurrent() else { return }
        let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
        feedAvailabilityObservation = availability.changes.sink { [weak self] change in
            // Preserve the denial edge even if republication overtakes cleanup.
            self?.homeAvailabilityRevision = UUID()
            self?.prepareHomeIfNeeded()
            self?.recommendationCoordinator.invalidate()
            for id in change.invalidatedBodyIDs { self?.detailLoader.invalidate(id: id) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyArticleAvailability(observedWithdrawals: change.withdrawnIDs)
                if change.refreshFeed { _ = self.requestFeedRefresh(showsLoading: false) }
            }
        }
    }

    private func scheduleReaderLoads(stillCurrent: @escaping ReadPermission) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, stillCurrent(), !Task.isCancelled else { return }
            self.loadFavorites()
            guard stillCurrent() else { return }
            self.loadCachedMetadata(stillCurrent: stillCurrent)
        }
        metadataStartupTask?.cancel()
        metadataStartupTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
            guard let self, stillCurrent(), !Task.isCancelled,
                  !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }
            self.fetchMetadataInBackground(stillCurrent: stillCurrent)
            guard stillCurrent(), !Task.isCancelled else { return }
            self.fetchPersonalizedRecommendationsIfNeeded(force: true)
            guard stillCurrent(), !Task.isCancelled else { return }
            await SeriesService.shared.fetchSeries(stillCurrent: stillCurrent)
        }
    }

    deinit {
        // The shared editorial model outlives this VM. Retire only this exact
        // listener; a new view may subscribe before MainActor cleanup runs.
        if let observation = availabilityObservation {
            Task { @MainActor in observation.model.stop(observation: observation.ticket) }
        }
        recommendationRefreshTask?.cancel()
        startupHydrationTask?.cancel()
        metadataStartupTask?.cancel()
        delayedFeedRefresh?.cancel()
        if let observation = favoritesObservation {
            Task { @MainActor in
                observation.model.endObservation(observation.ticket)
                observation.listener?.remove()
            }
        }
        

    }
    
    private var delayedFeedRefresh: Task<Void, Never>?
    private lazy var feedRefreshCoordinator = ArticleFeedRefreshCoordinator(
        fetchCatalog: { [weak self] permission, completion in
            guard let self else {
                completion(.failure(CancellationError()))
                return
            }
            guard permission() else { completion(.failure(CancellationError())); return }
            self.fetchRemoteFeedUpdate(stillCurrent: permission, completion: completion)
        },
        scheduleTimeout: readEffects.scheduleFeedTimeout,
        loadingChanged: { [weak self] isLoading in
            self?.isLoading = isLoading
            if isLoading { self?.fetchError = nil }
        },
        completedCatalog: { [weak self] result, showsLoading, permission in
            guard let self, permission() else { return }
            self.handleRemoteArticlesResult(result, isSilent: !showsLoading, stillCurrent: permission)
        }
    )

    func fetchArticles(forceRefresh: Bool = false) {
        if forceRefresh || feedRefreshCoordinator.isRefreshing || startupHydrationBegan {
            _ = requestFeedRefresh(showsLoading: forceRefresh || articles.isEmpty)
        } else {
            beginStartupHydrationIfNeeded()
        }
    }

    private func beginStartupHydrationIfNeeded(stillCurrent: ReadPermission? = nil) {
        guard !startupHydrationBegan, let permission = stillCurrent ?? captureReadPermission(), permission() else { return }
        startupHydrationBegan = true
        // Empty is not an authoritative result while the captured cache is
        // still decoding. Late cache replies recheck ownership before clearing.
        isLoading = articles.isEmpty
        let original = startupAdmission.capture()
        let cache = CacheManager.shared
        let capture = cache.captureArticlesHydration()
        startupHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await cache.loadCapturedArticles(capture, stillPermitted: { [weak self] in
                permission() && self?.startupAdmission.isCurrent(original) == true && !Task.isCancelled
            })
            guard permission(), self.startupAdmission.isCurrent(original), !Task.isCancelled else { return }
            if case .ready(let prepared) = outcome, !prepared.articles.isEmpty {
                let availability = ArticleAvailabilityService.model
                let authority = availability.projectionRevision
                let accepted = prepared.articles.filter { availability.permitsBody($0) }
                guard !accepted.isEmpty else {
                    _ = self.requestFeedRefresh(showsLoading: self.articles.isEmpty, stillCurrent: permission)
                    return
                }
                PodcastAvailabilityService.recordArticles(accepted)
                guard let receipt = self.startupAdmission.adopt(accepted, original: original,
                    stillPermitted: { permission() && cache.isCurrentArticleRead(capture)
                        && availability.projectionRevision == authority }),
                    self.startupAdmission.isCurrent(original), self.feedPublication.isCurrent(receipt),
                    cache.isCurrentArticleRead(capture), permission(), availability.projectionRevision == authority else { return }
                self.isLoading = false
                guard permission(), self.startupAdmission.isCurrent(original), self.feedPublication.isCurrent(receipt),
                      availability.projectionRevision == authority else { return }
                cache.syncWidgetFeed(from: accepted, articlesAreSorted: true)
                // Home performs one bounded first-screen warm from its snapshot.
                self.refreshArticlesInBackground(stillCurrent: permission)
            } else {
                _ = self.requestFeedRefresh(showsLoading: self.articles.isEmpty, stillCurrent: permission)
            }
        }
    }

    func refreshArticles() async {
        guard let permission = captureReadPermission() else { return }
        await performRemoteArticleFetch(forceRefresh: true, minimumLoadingDuration: 0)
        guard permission(), !Task.isCancelled else { return }
        await PodcastRepository.shared.refreshManifest(force: true)
    }

    private func performRemoteArticleFetch(
        forceRefresh: Bool,
        minimumLoadingDuration: TimeInterval
    ) async {
        // Keep this entry point for notification navigation. Request ownership
        // is shared with silent refreshes; force never bypasses an active query.
        // Local loading no longer adds an artificial minimum delay.
        await requestFeedRefresh(showsLoading: true).value
    }

    /// Waits until the current article fetch cycle completes.
    func waitForArticleLoadCycle() async {
        await feedRefreshCoordinator.waitForCurrentRefresh()
    }

    @discardableResult
    private func requestFeedRefresh(showsLoading: Bool, stillCurrent: ReadPermission? = nil) -> Task<Void, Never> {
        guard let permission = stillCurrent ?? captureReadPermission(), permission() else { return Task {} }
        delayedFeedRefresh?.cancel()
        delayedFeedRefresh = nil
        return feedRefreshCoordinator.refresh(showsLoading: showsLoading, stillCurrent: permission)
    }
    
    /// Feed list without HTML bodies. Keeps any body already loaded in `articles`
    /// so an open reader is not blanked by a silent refresh.
    private func feedArticles(from articles: [Article]) -> [Article] {
        return ArticleFeedSnapshot.merging(articles, retainingDetailsFrom: self.articles)
    }

    func fetchRemoteArticles(stillCurrent: ReadPermission? = nil, completion: @escaping ReadCompletion<[Article]>) {
        fetchRemoteFeedUpdate(stillCurrent: stillCurrent) { result in
            completion(result.flatMap { update in
                if let error = ArticleContentLanguage.allCases.compactMap({ update.failures[$0] }).first {
                    return .failure(error)
                }
                return .success(update.articles)
            })
        }
    }

    func fetchRemoteFeedUpdate(stillCurrent: ReadPermission? = nil,
                               completion: @escaping ReadCompletion<ArticleFeedSnapshot.Update>) {
        guard let permission = stillCurrent ?? captureReadPermission(), permission() else {
            completion(.failure(CancellationError())); return
        }
        if readEffects.canDownloadSavedBodies(), permission() {
            let model = injectedFavoriteModel ?? FavoritesRuntime.model
            let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
            availability.trackPublicationIDs(Set(model.snapshot.articles.map(\.id)))
        }
        if let catalog = readEffects.catalog {
            guard permission() else { completion(.failure(CancellationError())); return }
            let prepare = readEffects.beginCatalogRead()
            guard permission() else { completion(.failure(CancellationError())); return }
            catalog(permission) { [weak self] result in
                Task { @MainActor in
                    guard let self, permission() else { completion(.failure(CancellationError())); return }
                    switch result {
                    case .success(let update):
                        do {
                            let prepared = try await prepare(update, { [weak self] in self?.articles ?? [] }, permission)
                            completion(permission() ? .success(prepared) : .failure(CancellationError()))
                        } catch { completion(permission() ? .failure(error) : .failure(CancellationError())) }
                    case .failure(let error as FirestoreArticleError) where error.allowsCMSFallback:
                        self.readEffects.feedFallback(permission) { result in
                            Task { @MainActor in
                                completion(permission() ? result.map(ArticleFeedSnapshot.Update.complete) : .failure(CancellationError()))
                            }
                        }
                    case .failure(let error): completion(.failure(error))
                    }
                }
            }
            return
        }
        readEffects.feed(permission) { [weak self] result in
            Task { @MainActor in
                guard let self, permission() else { completion(.failure(CancellationError())); return }
                if case .failure(let error as FirestoreArticleError) = result, error.allowsCMSFallback {
                    self.readEffects.feedFallback(permission) { result in
                        Task { @MainActor in completion(permission() ? result.map(ArticleFeedSnapshot.Update.complete) : .failure(CancellationError())) }
                    }
                } else { completion(result.map(ArticleFeedSnapshot.Update.complete)) }
            }
        }
    }

    private func handleRemoteArticlesResult(_ result: Result<ArticleFeedSnapshot.Update, Error>, isSilent: Bool, stillCurrent: @escaping ReadPermission) {
        guard stillCurrent() else { return }
        switch result {
        case .success(let update):
            guard update.baselineIsCurrent(), stillCurrent(), update.baselineIsCurrent() else { return }
            guard update.hasAcceptedNamespace else {
                // A forced refresh can precede normal startup hydration. Failed
                // reads may still reveal an existing valid cache, never renew it.
                if articles.isEmpty && !update.articles.isEmpty {
                    let original = startupAdmission.capture()
                    let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
                    let authority = availability.projectionRevision
                    let cached = feedArticles(from: update.articles).filter { availability.permitsBody($0) }
                    guard let receipt = startupAdmission.adopt(cached, original: original, stillPermitted: {
                        update.baselineIsCurrent() && stillCurrent() && update.baselineIsCurrent()
                            && availability.projectionRevision == authority
                    }), feedPublication.isCurrent(receipt), stillCurrent() else { return }
                }
                feedFailures = update.failures
                fetchError = update.displayError(for: articleLanguage)
                return
            }
            // Even an authoritative empty result wins over an older cache read.
            startupAdmission.invalidate()
            readEffects.invalidateFeedCache()
            let original = startupAdmission.capture()
            let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
            readEffects.recordFeedArticles(update.sourceArticles)
            guard stillCurrent(), startupAdmission.isCurrent(original) else { return }
            let authority = availability.projectionRevision
            let permitted: ReadPermission = {
                stillCurrent() && availability.projectionRevision == authority
            }
            let sortedArticles = feedArticles(from: update.articles).filter { availability.permitsBody($0) }
            guard let receipt = startupAdmission.adopt(sortedArticles, original: original, stillPermitted: permitted),
                  startupAdmission.isCurrent(original), feedPublication.isCurrent(receipt), permitted() else { return }
            if update.cacheTimestamp != nil { readEffects.cacheFeed(.init(articles: sortedArticles,
                sourceArticles: update.sourceArticles, cacheTimestamp: update.cacheTimestamp,
                failures: update.failures, hasAcceptedNamespace: true, didChange: update.didChange,
                freshLanguages: update.freshLanguages, baselineIsCurrent: { true })) }
            guard permitted(), startupAdmission.isCurrent(original), feedPublication.isCurrent(receipt) else { return }
            refreshSavedOfflineContent(from: update.sourceArticles.filter {
                $0.contentLanguage.map(update.freshLanguages.contains) == true && availability.permitsBody($0)
            }, stillCurrent: {
                permitted() && self.startupAdmission.isCurrent(original) && self.feedPublication.isCurrent(receipt)
            })
            guard permitted(), startupAdmission.isCurrent(original), feedPublication.isCurrent(receipt) else { return }
            Task { [weak self] in guard permitted() else { return }; await self?.syncFavoritesWithFirestore() }

            guard stillCurrent() else { return }
            feedFailures = update.failures
            if let error = update.displayError(for: articleLanguage) {
                self.fetchError = error
            } else if update.articles.isEmpty {
                self.fetchError = NSError(
                    domain: "ViewModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("Ingen artikler fundet.", language: articleLanguage)]
                )
            } else {
                self.fetchError = nil
            }
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            feedFailures = Dictionary(uniqueKeysWithValues: ArticleContentLanguage.allCases.map { ($0, error) })
            AppDiagnostics.recordOperational(.contentFetchFailed)
            if !isSilent || self.articles.isEmpty {
                self.fetchError = ArticleMirrorCatalog.LanguageFailure(language: articleLanguage)
            }
        }
    }
    
    /// Silently refresh articles in background without showing loading state
    private func refreshArticlesInBackground(stillCurrent: ReadPermission? = nil) {
        guard delayedFeedRefresh == nil, let permission = stillCurrent ?? captureReadPermission(), permission() else { return }
        delayedFeedRefresh = Task { [weak self] in
            // Wait a bit to not interfere with initial load
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { return }
            guard !Task.isCancelled, let self, permission() else { return }
            self.delayedFeedRefresh = nil
            await self.requestFeedRefresh(showsLoading: false, stillCurrent: permission).value
        }
    }
    
    /// Silent refresh used when the app returns to the foreground. Shows no
    /// loading state and only replaces the list if the content actually changed,
    /// so the user sees fresh articles without a jarring spinner or scroll reset.
    func refreshOnForeground() {
        // The scene already retried favorites before its playback/feed throttle.
        resumeReaderStartup(retryFailedFavorites: false)
        guard let permission = captureReadPermission() else { return }
        preparedHome.sceneBecameActive()
        guard !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }
        _ = requestFeedRefresh(showsLoading: false, stillCurrent: permission)
        Task { @MainActor in
            guard permission(), !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }
            await PodcastRepository.shared.refreshManifest()
        }
    }

    func fetchAIRecommendations() {
        fetchPersonalizedRecommendationsIfNeeded(force: true)
    }

    func fetchPersonalizedRecommendationsIfNeeded(force: Bool = false) {
        guard force || personalizedRecommendations.isEmpty else { return }
        recommendationCoordinator.update(capturedRecommendationInput(), force: force)
    }

    private func capturedRecommendationInput() -> RecommendationHistoryInput? {
        let history = ReadingHistoryRuntime.model
        let account = ReaderRecommendationSelection.capture(canonical: AuthService.shared.state.snapshot,
            preferences: ReaderPreferencesService.shared.model.snapshot,
            guestInterestTopicIDs: ReaderIntroductionRuntime.guestInterests.selectedTopicIDs)
        return RecommendationHistorySelection.capture(context: history.context, snapshot: history.snapshot,
            canonicalUserID: account.canonicalUserID, profileUserID: recommendationProfileUID,
            profileReadIDs: recommendationProfileReadIDs, articles: visibleArticles, favorites: favorites.filter(isVisibleArticle),
            favoritesGeneration: FavoritesCloudSelection.recommendationGeneration(
                favoritesContext: FavoritesRuntime.model.context, favoritesSnapshot: FavoritesRuntime.model.snapshot,
                historyContext: history.context, historyGeneration: history.snapshot.generation,
                canonicalUserID: account.canonicalUserID),
            interestTopicIDs: account.interestTopicIDs)
    }

    private func observeRecommendationAccount() {
        let account = ReaderRecommendationSelection.capture(canonical: AuthService.shared.state.snapshot,
            preferences: ReaderPreferencesService.shared.model.snapshot,
            guestInterestTopicIDs: ReaderIntroductionRuntime.guestInterests.selectedTopicIDs)
        guard account != recommendationAccountInput else { return }
        recommendationAccountInput = account
        prepareHomeIfNeeded()
        queueRecommendationRefresh()
        startFavoritesListenerIfNeeded()
    }

    private func observeRecommendationHistory(_ snapshot: ReadingHistorySnapshot) {
        guard RecommendationHistorySelection.isCurrent(snapshot, comparedTo: ReadingHistoryRuntime.model.snapshot) else { return }
        let ids = Set(snapshot.readArticleIDs)
        guard snapshot.generation != recommendationHistoryGeneration || ids != recommendationReadIDs else { return }
        recommendationHistoryGeneration = snapshot.generation
        recommendationReadIDs = ids
        queueRecommendationRefresh()
        startFavoritesListenerIfNeeded()
    }

    private func queueRecommendationRefresh() {
        recommendationCoordinator.invalidate()
        recommendationRefreshTask?.cancel()
        recommendationRefreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.recommendationCoordinator.update(self.capturedRecommendationInput())
        }
    }

    private func applyRecommendations(_ state: RecommendationHistoryCoordinator.State) {
        guard recommendationCoordinator.isCurrent(state) else { return }
        isLoadingAI = state.isLoading
        guard recommendationCoordinator.isCurrent(state) else { return }
        aiError = nil
        let visible = state.recommendations.filter { isVisibleArticle($0.0) && ArticleAvailabilityService.model.permitsBody($0.0) }
        let originalOwner = AuthService.shared.state.snapshot.generation
        guard recommendationCoordinator.isCurrent(state) else { return }
        personalizedRecommendations = visible
        guard recommendationCoordinator.isCurrent(state), AuthService.shared.state.snapshot.generation == originalOwner else { return }
        aiRecommendations = visible.map(\.0)
        guard recommendationCoordinator.isCurrent(state), AuthService.shared.state.snapshot.generation == originalOwner else { return }
        homeRecommendations = visible.map { HomeRecommendation(articleID: $0.0.id, reason: $0.1) }
        homeRecommendationsOwner = originalOwner
        prepareHomeIfNeeded()
    }
    
    // MARK: - Metadata Loading (with caching)
    
    /// Load cached metadata immediately (fast)
    private func loadCachedMetadata(stillCurrent: @escaping ReadPermission) {
        guard stillCurrent() else { return }
        // Load topics from cache
        if let cachedTopics = CacheManager.shared.getCachedTopics() {
            self.commitMetadata(cachedTopics, at: \.topics, stillCurrent: stillCurrent)
        }
        
        guard stillCurrent() else { return }
        // Load sections from cache
        if let cachedSections = CacheManager.shared.getCachedSections() {
            self.commitMetadata(cachedSections, at: \.sections, stillCurrent: stillCurrent)
        }
        
        guard stillCurrent() else { return }
        // Load authors from cache
        if let cachedAuthors = CacheManager.shared.getCachedAuthors() {
            self.commitMetadata(cachedAuthors, at: \.authors, stillCurrent: stillCurrent)
            if stillCurrent() { self.authorEvents.send(cachedAuthors) }
        }
        
        guard stillCurrent() else { return }
        // Load stars mapping from cache
        if let cachedStars = CacheManager.shared.getCachedStarsMapping() {
            self.commitMetadata(cachedStars, at: \.starsMapping, stillCurrent: stillCurrent)
        }
    }
    
    /// Fetch metadata in background and update cache
    private func fetchMetadataInBackground(stillCurrent: @escaping ReadPermission) {
        for load in [{ self.fetchTopics(stillCurrent: stillCurrent) }, { self.fetchSections(stillCurrent: stillCurrent) }, { self.fetchAuthors(stillCurrent: stillCurrent) }, { self.fetchStars(stillCurrent: stillCurrent) }] {
            guard stillCurrent() else { return }
            load()
        }
    }

    func fetchTopics(stillCurrent: ReadPermission? = nil) {
        fetchMetadata(key: "topics", stillCurrent: stillCurrent, primary: readEffects.topics, fallback: readEffects.topicsFallback) { [weak self] values, permission in
            guard let self, permission() else { return }
            self.commitMetadata(values, at: \.topics, stillCurrent: permission)
            guard permission() else { return }
            self.readEffects.cacheTopics(values)
        }
    }
    func fetchSections(stillCurrent: ReadPermission? = nil) {
        fetchMetadata(key: "sections", stillCurrent: stillCurrent, primary: readEffects.sections, fallback: readEffects.sectionsFallback) { [weak self] values, permission in
            guard let self, permission() else { return }
            self.commitMetadata(values, at: \.sections, stillCurrent: permission)
            guard permission() else { return }
            self.readEffects.cacheSections(values)
        }
    }
    func fetchAuthors(stillCurrent: ReadPermission? = nil) {
        fetchMetadata(key: "authors", stillCurrent: stillCurrent, primary: readEffects.authors, fallback: readEffects.authorsFallback) { [weak self] values, permission in
            guard let self, permission() else { return }
            self.commitMetadata(values, at: \.authors, stillCurrent: permission)
            guard permission() else { return }
            self.authorEvents.send(values)
            guard permission() else { return }
            self.readEffects.cacheAuthors(values)
        }
    }
    func fetchStars(stillCurrent: ReadPermission? = nil) {
        fetchMetadata(key: "stars", stillCurrent: stillCurrent, primary: { [readEffects] permission, done in
            readEffects.stars(permission) { value in done(value.flatMap { $0.isEmpty ? nil : $0 }.map(Result.success) ?? .failure(FirestoreMetadataError.empty)) }
        }, fallback: { [readEffects] permission, done in
            readEffects.starsFallback(permission) { done(.success($0)) }
        }) { [weak self] values, permission in
            guard let self, permission() else { return }
            self.commitMetadata(values, at: \.starsMapping, stillCurrent: permission)
            guard permission() else { return }
            self.readEffects.cacheStars(values)
        }
    }
    private func fetchMetadata<Value>(key: String, stillCurrent: ReadPermission? = nil,
        primary: (@escaping ReadPermission, @escaping ReadCompletion<Value>) -> Void,
        fallback: @escaping (@escaping ReadPermission, @escaping ReadCompletion<Value>) -> Void,
        apply: @escaping (Value, ReadPermission) -> Void) {
        guard metadataRequests[key] == nil, let permission = stillCurrent ?? captureReadPermission(), permission() else { return }
        let id = UUID(); metadataRequests[key] = id
        let current: ReadPermission = { [weak self] in permission() && self?.metadataRequests[key] == id }
        if key == "topics" { commitTopicsError(nil, stillCurrent: current) }
        let cleanup: @MainActor () -> Void = { [weak self] in
            guard let self, self.metadataRequests[key] == id else { return }
            self.metadataRequests[key] = nil
            if key == "topics" { self.objectWillChange.send() }
        }
        let complete: ReadCompletion<Value> = { [weak self] result in
            Task { @MainActor in
                guard let self, current() else { cleanup(); return }
                if key == "topics" {
                    guard current() else { cleanup(); return }
                    if case .failure(let error) = result { self.commitTopicsError(error, stillCurrent: current) }
                }
                guard current() else { cleanup(); return }
                if case .success(let value) = result { apply(value, current) }
                cleanup()
            }
        }
        guard current() else { cleanup(); return }
        primary(current) { result in
            Task { @MainActor in
                guard current() else { cleanup(); return }
                if case .failure(FirestoreMetadataError.empty) = result { fallback(current, complete) }
                else { complete(result) }
            }
        }
    }

    func fetchArticle(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        guard !id.isEmpty else {
            completion(.failure(NSError(domain: "Invalid ID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Article ID is empty"])))
            return
        }

        guard let permission = captureReadPermission() else { completion(.failure(CancellationError())); return }
        let savedRead = captureSavedPublicationRead(articleID: id, permission: permission)
        guard permission() else { completion(.failure(CancellationError())); return }
        readEffects.article(id, permission) { result in
            Task { @MainActor in
            guard permission() else { completion(.failure(CancellationError())); return }
            switch result {
            case .success(let article):
                if let savedRead { self.applySavedPublicationRead(article, capture: savedRead) }
                guard permission() else { completion(.failure(CancellationError())); return }
                completion(.success(article))
            case .failure(let error as FirestoreArticleError) where error.allowsCMSFallback
                && ArticleLanguageSelection.mirrorLanguage(forReaderID: id) == .danish:
                AppDiagnostics.recordOperational(.contentFallbackUsed)
                self.fetchArticleFromWebflow(by: id) { result in
                    Task { @MainActor in completion(permission() ? result : .failure(CancellationError())) }
                }
            case .failure(let error):
                completion(.failure(error))
            }
            }
        }
    }

    private func fetchArticleFromWebflow(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        // Articles are served from Firestore in release builds; the Webflow key is
        // only present during local development. Skip the request when we have no
        // token rather than firing a guaranteed 401.
        let token = WebflowService.shared.apiToken
        guard !token.isEmpty else {
            completion(.failure(FirestoreArticleError.empty))
            return
        }

        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items/\(id)/live"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let description = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                completion(.failure(NSError(domain: "HTTPError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode): \(description)"])));
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                guard let liveData = try WebflowLiveCatalogLoader.normalizedLiveItem(data) else {
                    completion(.failure(FirestoreArticleError.withdrawn)); return
                }
                let article = try decoder.decode(Article.self, from: liveData)
                guard article.isPubliclyPublished else {
                    completion(.failure(NSError(
                        domain: "WebflowService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Article is not published"]
                    )))
                    return
                }
                completion(.success(article))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchAuthor(by id: String, completion: @escaping (Result<Author, Error>) -> Void) {
        guard let permission = captureReadPermission() else { completion(.failure(CancellationError())); return }
        let deliver: (Result<Author, Error>) -> Void = { result in
            Task { @MainActor in completion(permission() ? result : .failure(CancellationError())) }
        }
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            deliver(.failure(NSError(domain: "Invalid ID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Author ID is empty"])))
            return
        }

        // Authors are served from Firestore (synced server-side). Resolve from the
        // already-loaded list or the on-disk cache before touching the network.
        if let resolved = authors.first(where: { $0.id == id })
            ?? CacheManager.shared.getCachedAuthors()?.first(where: { $0.id == id }) {
            deliver(.success(resolved))
            return
        }

        // The Webflow key no longer ships in release builds, so only attempt the
        // legacy direct fetch when a token is actually available (local dev).
        // Without it the request would just return 401 on every article open.
        let token = WebflowService.shared.apiToken
        guard !token.isEmpty else {
            deliver(.failure(NSError(
                domain: "AuthorUnavailable",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Forfatter ikke tilgængelig i cache."]
            )))
            return
        }

        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294/items/\(id)"
        
        guard let url = URL(string: urlString) else {
            deliver(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        guard permission() else { deliver(.failure(CancellationError())); return }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                deliver(.failure(error))
                return
            }
            
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let description = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                deliver(.failure(NSError(domain: "HTTPError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode): \(description)"])));
                return
            }
            
            guard let data = data else {
                deliver(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let authorWrapper = try decoder.decode(AuthorWrapper.self, from: data)
                let author = authorWrapper.toAuthor()
                deliver(.success(author))
            } catch {
                AppDiagnostics.recordOperational(.metadataDecodeFailed)
                deliver(.failure(error))
            }
        }.resume()
    }
    
    func author(for article: Article) -> Author? {
        guard !authors.isEmpty else { return nil }
        guard let authorRef = article.authorID else { return nil }

        let normalizedRef = authorRef
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedRef.isEmpty else { return nil }

        return authors.first(where: { author in
            let normalizedID = author.id
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedID == normalizedRef {
                return true
            }

            let normalizedName = author.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return normalizedName == normalizedRef
        })
    }

    func articles(byAuthorId id: String) -> [Article] {
        let normalizedId = id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedId.isEmpty else { return [] }

        let matches = visibleArticles.filter { article in
            if let authorID = article.authorID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               authorID == normalizedId {
                return true
            }
            if let resolved = author(for: article),
               resolved.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedId {
                return true
            }
            return false
        }
        return sortedNewestFirst(matches)
    }
    

    
    func loadFullArticle(with id: String, initialArticle: Article? = nil) {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppDiagnostics.recordOperational(.contentIdentityInvalid)
            return
        }
        guard !ArticleAvailabilityService.model.withdrawnIDs.contains(id) else { return }
        let isOnline = OfflineManager.shared.isOnline
        var cached = !isOnline ? Self.offlineArticle(for: id) : nil
        if cached == nil {
            cached = ArticleDetailContentPolicy.cachedArticle(
                id: id,
                feed: articles.first(where: { $0.id == id }),
                full: fullArticle,
                initial: initialArticle
            )
        }
        cached = cached.flatMap { ArticleAvailabilityService.model.sanitized($0) }
        if var article = cached, let author = author(for: article) {
            article.author = author
            cached = article
        }
        detailLoader.select(id: id, cached: cached, canFetch: isOnline)
    }

    func cancelFullArticleLoad(for id: String) {
        detailLoader.deselect(id: id)
    }

    /// A view owns its exact selection, not every future observation of this ID.
    /// Retain the selection while startup is closed, without touching a live model/SDK.
    @discardableResult
    func observeArticleAvailability(for id: String) -> AvailabilitySelection {
        let selection = AvailabilitySelection(articleID: id, token: UUID())
        availabilitySelection = selection
        retireAvailabilityObservation()
        guard availabilitySelection == selection else { return selection }
        resumeAvailabilityObservation()
        return selection
    }

    func stopObservingArticleAvailability(_ selection: AvailabilitySelection) {
        guard availabilitySelection == selection else { return }
        availabilitySelection = nil
        retireAvailabilityObservation()
    }

    private func retireAvailabilityObservation() {
        let previous = availabilityObservation
        availabilityObservation = nil
        availabilityAttempt = nil
        availabilityPermission = nil
        if let previous { previous.model.stop(observation: previous.ticket) }
    }

    private func resumeAvailabilityObservation() {
        guard let selection = availabilitySelection else { return }
        if let permission = availabilityPermission, let previousAttempt = availabilityAttempt {
            let permitted = permission()
            guard availabilitySelection == selection, availabilityAttempt == previousAttempt else { return }
            // A returned listener may already have permanently revoked itself.
            // A synchronous subscription still on the stack only needs deduplication.
            let observing = availabilityObservation.map { $0.model.isCurrent($0.ticket) } ?? true
            guard availabilitySelection == selection, availabilityAttempt == previousAttempt else { return }
            if permitted && observing { return }
        }
        retireAvailabilityObservation()
        guard availabilitySelection == selection,
              CMSMirrorDocumentPolicy.isSafeDocumentID(selection.articleID),
              let permission = captureReadPermission(),
              availabilitySelection == selection, permission(),
              availabilitySelection == selection else { return }
        let attempt = UUID()
        availabilityAttempt = attempt
        let original: ReadPermission = { [weak self] in
            guard let self, self.availabilitySelection == selection, self.availabilityAttempt == attempt else { return false }
            let permitted = permission()
            return permitted && self.availabilitySelection == selection && self.availabilityAttempt == attempt
        }
        availabilityPermission = original
        let model = injectedAvailabilityModel ?? ArticleAvailabilityService.model
        guard original() else { return }
        let ticket = ArticleAvailabilityService.observe(selection.articleID, stillCurrent: original,
            model: model, subscribe: injectedAvailabilitySubscribe, recordPodcastMirror: injectedAvailabilityMirror)
        // subscribe/model notifications may synchronously replace this selection.
        guard original(), let ticket, model.isCurrent(ticket) else {
            if let ticket { model.stop(observation: ticket) }
            if availabilityAttempt == attempt {
                availabilityAttempt = nil; availabilityPermission = nil
            }
            return
        }
        availabilityObservation = (model, ticket)
    }

    private func applyArticleAvailability(observedWithdrawals: Set<String>) {
        recommendationCoordinator.invalidate()
        let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
        // Transport invalidation was synchronous; preserve each observed edge
        // for local cleanup even if republication overtook this UI task.
        readEffects.reconcileAvailability(observedWithdrawals.subtracting(appliedWithdrawals))
        appliedWithdrawals = observedWithdrawals
        articles = articles.filter { availability.permitsBody($0) }
        aiRecommendations = aiRecommendations.filter { availability.permitsBody($0) }
        personalizedRecommendations = personalizedRecommendations.filter { availability.permitsBody($0.0) }
        fullArticle = fullArticle.flatMap { availability.sanitized($0) }
        readEffects.pruneFeedCache()
        queueRecommendationRefresh()
    }

    private func applyDetailBody(_ article: Article, origin: ArticleDetailBodyOrigin) {
        guard ArticleAvailabilityService.model.permitsBody(article) else { return }
        let current = articles.first(where: { $0.id == article.id })
        let canUpdateFeed: Bool
        switch origin {
        case .fetched(let requestedFrom):
            guard ArticleDetailContentPolicy.canApplyFetchedBody(
                article, requestedFrom: requestedFrom, current: current
            ) else { return }
            canUpdateFeed = true
        case .cached, .offlineFallback:
            // An offline snapshot may remain readable without restoring old
            // metadata/body to a feed which already carries a newer revision.
            canUpdateFeed = current.map { ArticleDetailContentPolicy.sameRevision($0, article) } ?? true
        }
        fullArticle = article
        if canUpdateFeed { updateArticleInAllArrays(article) }
    }

    private func applyDetailAuthor(_ author: Author, articleID: String, authorID: String) {
        guard !ArticleAvailabilityService.model.withdrawnIDs.contains(articleID) else { return }
        // Patch current values: an author callback must never reintroduce an
        // older body or overwrite metadata committed by a feed refresh.
        if let current = ArticleDetailContentPolicy.applyingAuthor(
            author, articleID: articleID, authorID: authorID, to: fullArticle
        ) {
            fullArticle = current
        }
        if let index = articles.firstIndex(where: { $0.id == articleID && $0.authorID == authorID }) {
            if let current = ArticleDetailContentPolicy.applyingAuthor(
                author, articleID: articleID, authorID: authorID, to: articles[index]
            ) {
                articles[index] = current
            }
        }
    }

    private static func offlineArticle(for id: String) -> Article? {
        guard !ArticleAvailabilityService.model.withdrawnIDs.contains(id) else { return nil }
        if let offline = OfflineManager.shared.offlineArticle(articleID: id),
           ArticleDetailContentPolicy.hasBody(offline) {
            return ArticleAvailabilityService.model.sanitized(offline)
        }
        return nil
    }
    
    private func updateArticleInAllArrays(_ updated: Article) {
        guard ArticleAvailabilityService.model.permitsBody(updated) else { return }
        // Safety check: ensure we have a valid article
        guard !updated.id.isEmpty else {
            AppDiagnostics.recordOperational(.contentUpdateRejected)
            return
        }
        
        func replace(in array: inout [Article]) {
            // Safety check: ensure we have a valid article ID
            guard !updated.id.isEmpty else {
                AppDiagnostics.recordOperational(.contentUpdateRejected)
                return
            }
            
            if let index = array.firstIndex(where: { $0.id == updated.id }) {
                array[index] = updated
            }
        }

        replace(in: &self.articles)
    }
    
    private var cancellables: Set<AnyCancellable> = []
    @MainActor private final class FavoriteObservation {
        let model: FavoritesModel
        let ticket: FavoritesModel.ObservationTicket
        let uid: String
        let generation: UUID
        let permission: ReadPermission
        var listener: FirestoreService.FavoriteListener?
        var attaching = true
        var attachmentFailed = false
        var revoked = false
        init(model: FavoritesModel, ticket: FavoritesModel.ObservationTicket, uid: String,
             generation: UUID, permission: @escaping ReadPermission) {
            self.model = model; self.ticket = ticket; self.uid = uid
            self.generation = generation; self.permission = permission
        }
    }
    private let injectedFavoriteModel: FavoritesModel?
    private let injectedFavoriteOffline: FavoritesOfflineCoordinator?
    private var refreshingSavedOfflineContent = false
    private struct SavedPublicationRead {
        let model: FavoritesModel
        let offline: FavoritesOfflineCoordinator
        let member: FavoritesModel.MembershipTicket
        let current: ReadPermission
        let published: @MainActor (Article) -> Bool
    }
    private let injectedFavoriteSubscribe: FirestoreService.FavoriteSubscribe?
    private let injectedFavoriteCanonicalUserID: (@MainActor () -> String?)?
    private let injectedFavoriteRetry: (@MainActor (UUID) -> Void)?
    private var favoritesObservation: FavoriteObservation?
    private var favoritesObservationRequested = false
    private var favoritesEntry = UUID()

    private var favoriteCanonicalUID: String? {
        if let injectedFavoriteCanonicalUserID { return injectedFavoriteCanonicalUserID() }
        return recommendationCanonicalUID
    }
    private func favoriteActualUID() -> String? {
        if let injectedActualUserID { return injectedActualUserID() }
        return Auth.auth().currentUser?.uid
    }

    
    func isFavorite(_ article: Article) -> Bool {
        guard !article.id.isEmpty else { return false }
        return favorites.contains(where: { $0.id == article.id })
    }
    
    func toggleFavorite(for article: Article) {
        guard let safe = ArticleAvailabilityService.model.sanitized(article) else { return }
        if accountSaveGate.isGuest, isFavorite(safe) {
            _ = setFavorite(safe, enabled: false)
            return
        }
        if accountSaveGate.isGuest {
            _ = accountSaveGate.present(article: safe, language: articleLanguage)
            return
        }
        guard accountSaveGate.hasAccount else { return }
        let enabled = !isFavorite(safe)
        _ = setFavorite(safe, enabled: enabled)
    }

    func reconcileAccountSave() {
        let model = FavoritesRuntime.model
        accountSaveGate.reconcile(language: articleLanguage, favorites: model.snapshot,
            favoritesContext: model.context, canSave: model.canChangeSelection,
            currentArticle: { [weak self] id in
                guard let self else { return nil }
                let candidate = self.articles.first { $0.id == id }
                    ?? (self.fullArticle?.id == id ? self.fullArticle : nil)
                    ?? self.accountSaveGate.request?.article
                return candidate.flatMap {
                    ArticleAvailabilityService.model.permitsBody($0)
                        ? ArticleAvailabilityService.model.sanitized($0) : nil
                }
            }, save: { [weak self] in self?.setFavorite($0, enabled: true) == true })
    }

    @discardableResult
    private func setFavorite(_ safe: Article, enabled: Bool) -> Bool {
        guard !enabled || accountSaveGate.hasAccount else { return false }
        guard let mutation = FavoritesRuntime.shared.setFavorite(safe, enabled: enabled),
              FavoritesRuntime.model.isCurrent(mutation) else { return false }
        OfflineManager.shared.synchronizeCurrentMembership()
        guard enabled, let access = OfflineManager.shared.captureAccess(articleID: safe.id) else { return true }
        let candidates = [safe, fullArticle, articles.first { $0.id == safe.id }].compactMap { $0 }
        let body = candidates.first(where: {
            $0.id == safe.id && $0.bodyRevision == safe.bodyRevision && ArticleDetailContentPolicy.hasBody($0)
        })
        OfflineManager.shared.requestBody(ticket: access, candidate: body, fetch: fetchOfflineBody)
        return true
    }

    /// A delayed body can fill only the membership/revision captured at start.
    /// Revision migration requires a separate canonical observation, not a late
    /// callback recapturing whatever membership now happens to exist.
    private func fetchOfflineBody(articleID: String, completion: @escaping @MainActor (Result<Article, Error>) -> Void) {
        fetchArticle(by: articleID) { result in
            Task { @MainActor in completion(result) }
        }
    }

    private func captureSavedPublicationRead(articleID: String, permission: @escaping ReadPermission) -> SavedPublicationRead? {
        guard readEffects.canDownloadSavedBodies(), permission() else { return nil }
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        let offline = injectedFavoriteModel != nil ? injectedFavoriteOffline : FavoritesRuntime.shared.offline
        guard let offline, let uid = favoriteCanonicalUID, model.context == .confirmed(userID: uid),
              favoriteActualUID() == uid, permission(), model.context == .confirmed(userID: uid),
              let member = model.membershipTicket(articleID: articleID), permission() else { return nil }
        let generation = model.snapshot.generation
        let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
        let capture = SavedPublicationRead(model: model, offline: offline, member: member, current: { [weak self, weak model] in
            guard let self, let model else { return false }
            return self.ownsSavedOfflineOwner(model, uid: uid, generation: generation, permission: permission)
        }, published: { article in
            availability.hasFreshPublicationRead(article)
        })
        guard capture.current(), model.isCurrent(member) else { return nil }
        availability.trackPublicationIDs([member.articleID])
        guard capture.current(), model.isCurrent(member) else { return nil }
        return capture
    }

    /// Identity/connectivity providers are injected hooks. Recheck the original
    /// pure model state after each lookup and leave no provider call after the
    /// final guard, matching the existing cloud-observation admission boundary.
    private func ownsSavedOfflineOwner(_ model: FavoritesModel, uid: String, generation: UUID,
                                      permission: ReadPermission) -> Bool {
        func currentModel() -> Bool {
            model.context == .confirmed(userID: uid) && model.snapshot.generation == generation
        }
        guard currentModel() else { return false }
        let canonical = favoriteCanonicalUID
        guard currentModel(), permission(), currentModel() else { return false }
        let actual = favoriteActualUID()
        guard currentModel(), permission(), currentModel() else { return false }
        return canonical == uid && actual == uid && currentModel()
    }

    private func applySavedPublicationRead(_ article: Article, capture: SavedPublicationRead) {
        guard capture.current(), capture.published(article),
              let member = capture.model.adoptPublishedMetadata(article, ticket: capture.member,
                stillCurrent: capture.current, permitsPublication: capture.published),
              capture.current(), capture.model.isCurrent(member),
              let access = capture.offline.captureAccess(articleID: article.id),
              access.contentRevision == article.bodyRevision, capture.current() else { return }
        _ = capture.offline.saveBody(article, ticket: access)
    }

    /// A current public catalog can repair metadata for an already saved item.
    /// It cannot create a save intention, rewrite a pending upload or adopt an
    /// unconfirmed cache revision. Queued downloads retain the resulting exact
    /// membership; neither their transport nor completion recaptures an owner.
    private func refreshSavedOfflineContent(from catalog: [Article], stillCurrent: @escaping ReadPermission) {
        guard !refreshingSavedOfflineContent, readEffects.canDownloadSavedBodies(), stillCurrent() else { return }
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        let offline = injectedFavoriteModel != nil ? injectedFavoriteOffline : FavoritesRuntime.shared.offline
        guard let offline, let uid = favoriteCanonicalUID, model.context == .confirmed(userID: uid) else { return }
        let generation = model.snapshot.generation
        let availability = injectedAvailabilityModel ?? ArticleAvailabilityService.model
        guard let workPermission = captureReadPermission() else { return }
        let ownerCurrent: ReadPermission = { [weak self, weak model] in
            guard let self, let model else { return false }
            return self.ownsSavedOfflineOwner(model, uid: uid, generation: generation, permission: workPermission)
        }
        let published: @MainActor (Article) -> Bool = { article in
            availability.hasFreshPublicationRead(article)
        }
        guard ownerCurrent() else { return }
        refreshingSavedOfflineContent = true
        defer { refreshingSavedOfflineContent = false }
        let members = model.snapshot.articles.compactMap { model.membershipTicket(articleID: $0.id) }
        availability.trackPublicationIDs(Set(members.map(\.articleID)))
        guard ownerCurrent(), stillCurrent() else { return }
        var tickets: [FavoritesOfflineCoordinator.AccessTicket] = []
        for member in members {
            guard ownerCurrent(), stillCurrent() else { return }
            guard let article = catalog.first(where: { $0.id == member.articleID }), published(article),
                  model.isCurrent(member), ownerCurrent() else { continue }
            let replacement = model.adoptPublishedMetadata(article, ticket: member,
                stillCurrent: { ownerCurrent() && stillCurrent() }, permitsPublication: published)
            // An unchanged pending save can download its own current version;
            // an old pending payload cannot be silently migrated here.
            guard ownerCurrent(), let accepted = replacement ?? (model.isCurrent(member)
                && member.contentRevision == article.bodyRevision ? member : nil),
                  model.isCurrent(accepted), let access = offline.captureAccess(articleID: article.id),
                  access.contentRevision == article.bodyRevision, ownerCurrent() else { continue }
            tickets.append(access)
        }
        guard ownerCurrent() else { return }
        _ = offline.requestBodies(tickets: tickets) { [weak self] id, complete in
            guard let self, ownerCurrent(), self.readEffects.canDownloadSavedBodies(), ownerCurrent() else {
                complete(.failure(CancellationError())); return
            }
            self.fetchOfflineBody(articleID: id) { result in
                complete(ownerCurrent() ? result : .failure(CancellationError()))
            }
        }
    }

    func retryOfflineBody(ticket: FavoritesOfflineCoordinator.AccessTicket) {
        OfflineManager.shared.retryBody(ticket: ticket, fetch: fetchOfflineBody)
    }

    func retryOfflineContent(ticket: FavoritesOfflineCoordinator.AccessTicket) {
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        let offline = injectedFavoriteModel != nil ? injectedFavoriteOffline : FavoritesRuntime.shared.offline
        guard let offline, let permission = captureReadPermission(),
              let uid = favoriteCanonicalUID, model.context == .confirmed(userID: uid) else { return }
        let generation = model.snapshot.generation
        let current: ReadPermission = { [weak self, weak model] in
            guard let self, let model,
                  self.ownsSavedOfflineOwner(model, uid: uid, generation: generation, permission: permission),
                  offline.isCurrent(ticket) else { return false }
            let online = self.readEffects.canDownloadSavedBodies()
            return online && self.ownsSavedOfflineOwner(model, uid: uid, generation: generation, permission: permission)
                && offline.isCurrent(ticket)
        }
        guard current() else { return }
        _ = offline.retryBody(ticket: ticket, fetch: fetchOfflineBody)
        guard current() else { return }
        readEffects.recoverSavedAudioDownloads(current)
        Task { @MainActor [weak self] in
            guard let self, current(), !Task.isCancelled else { return }
            await self.readEffects.refreshSavedAudioCatalog(current)
        }
    }

    func refreshSavedOfflineAfterInterruption() {
        guard readEffects.canDownloadSavedBodies(), let permission = captureReadPermission(), permission() else { return }
        // Existing feed work coalesces these explicit lifecycle events. Unlike
        // visual Home warming, saved downloads must recover while audio plays.
        _ = requestFeedRefresh(showsLoading: false, stillCurrent: permission)
    }

    private func loadFavorites() {
        observeFavorites(FavoritesRuntime.model.snapshot)
    }

    /// Canonical sign-out already selected the guest partition. Do not clear
    /// another owner's persisted library or suspend the newly confirmed guest.
    func clearSessionDataOnLogout() {
        stopFavoritesListener()
        observeFavorites(FavoritesRuntime.model.snapshot)
        OfflineManager.shared.synchronizeCurrentMembership()
    }

    private func observeFavorites(_ snapshot: FavoritesSnapshot) {
        let model = FavoritesRuntime.model
        guard snapshot.generation == model.snapshot.generation, snapshot.revision == model.snapshot.revision else { return }
        if observedFavoritesGeneration != snapshot.generation {
            observedFavoritesGeneration = snapshot.generation
            stopFavoritesListener()
        }
        // Includes server-proof/overlay edges when the visible array is equal.
        queueRecommendationRefresh()
        objectWillChange.send()
        guard snapshot.generation == model.snapshot.generation, snapshot.revision == model.snapshot.revision else { return }
        startFavoritesListenerIfNeeded()
        observeSavedOfflineFavorites(snapshot)
    }

    private func observeSavedOfflineFavorites(_ snapshot: FavoritesSnapshot) {
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        guard snapshot.generation == model.snapshot.generation,
              snapshot.revision == model.snapshot.revision else { return }
        if let permission = captureReadPermission() {
            let revision = feedPublication.snapshot.revision
            refreshSavedOfflineContent(from: articles, stillCurrent: { [weak self] in
                permission() && self?.feedPublication.snapshot.revision == revision
            })
        }
    }

    /// Detach first: a provider removal hook may synchronously start a new attempt.
    func stopFavoritesListener() {
        favoritesEntry = UUID()
        retireFavoritesObservation()
    }

    private func retireFavoritesObservation() {
        let previous = favoritesObservation
        favoritesObservation = nil
        if let previous {
            previous.model.endObservation(previous.ticket)
            previous.listener?.remove()
        }
    }

    private func ownsFavoriteObservation(_ observation: FavoriteObservation) -> Bool {
        guard !observation.revoked, favoritesObservation === observation,
              observation.model.isCurrent(observation.ticket) else { return false }
        guard observation.permission() else { observation.revoked = true; return false }
        guard !observation.revoked, favoritesObservation === observation,
              observation.model.isCurrent(observation.ticket) else { return false }
        let uid = favoriteCanonicalUID
        // Identity lookup may synchronously change the provider/startup session.
        // Never accept its old returned UID as authority for this callback.
        guard observation.permission() else { observation.revoked = true; return false }
        guard !observation.revoked, favoritesObservation === observation,
              observation.model.isCurrent(observation.ticket) else { return false }
        let owned = FavoritesCloudSelection.ownsObservation(context: observation.model.context,
            snapshot: observation.model.snapshot, canonicalUserID: uid,
            expectedUserID: observation.uid, expectedGeneration: observation.generation)
        if !owned { observation.revoked = true }
        return owned
    }

    /// An explicit lifecycle/connectivity event may retry a terminal failure.
    /// Ordinary model publication must not repeatedly retry an unavailable query.
    func refreshFavoritesAfterInterruption() {
        guard favoritesObservationRequested else { return }
        favoritesObservation?.attachmentFailed = false
        startFavoritesListenerIfNeeded()
    }

    func startFavoritesListenerIfNeeded() {
        favoritesObservationRequested = true
        let entry = UUID(); favoritesEntry = entry
        guard let permission = captureReadPermission(), favoritesEntry == entry else {
            if favoritesEntry == entry { retireFavoritesObservation() }
            return
        }
        // Injected model paths are all-local or closed, never a partial fallback
        // into an application's account/transport singleton.
        if injectedFavoriteModel != nil && (injectedFavoriteSubscribe == nil || injectedFavoriteCanonicalUserID == nil || injectedActualUserID == nil) {
            retireFavoritesObservation(); return
        }
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        let uid = favoriteCanonicalUID
        guard favoritesEntry == entry else { return }
        let actual = favoriteActualUID()
        guard favoritesEntry == entry else { return }
        guard let uid, permission(), favoritesEntry == entry,
              FavoritesCloudSelection.canObserve(context: model.context, snapshot: model.snapshot, expectedUserID: uid), actual == uid else {
            if favoritesEntry == entry { retireFavoritesObservation() }
            return
        }
        if let previous = favoritesObservation {
            let owned = ownsFavoriteObservation(previous)
            guard favoritesEntry == entry else { return }
            let listening = previous.attachmentFailed || (previous.listener?.isCurrent() ?? previous.attaching)
            guard favoritesEntry == entry else { return }
            if owned && listening { return }
        }
        retireFavoritesObservation()
        guard favoritesEntry == entry, permission(), favoritesEntry == entry,
              favoriteCanonicalUID == uid, favoritesEntry == entry,
              FavoritesCloudSelection.canObserve(context: model.context, snapshot: model.snapshot, expectedUserID: uid),
              let ticket = model.observationTicket() else { return }
        let observation = FavoriteObservation(model: model, ticket: ticket, uid: uid,
            generation: model.snapshot.generation, permission: permission)
        favoritesObservation = observation
        let original: ReadPermission = { [weak self, weak observation] in
            guard let self, let observation else { return false }
            return self.ownsFavoriteObservation(observation)
        }
        let listener = FirestoreService.shared.listenFavorites(expectedUserID: uid, stillCurrent: original,
            actualUserID: { [weak self] in self?.favoriteActualUID() }, subscribe: injectedFavoriteSubscribe) { [weak self, weak observation] result in
            guard let self, let observation, self.ownsFavoriteObservation(observation) else { return }
            switch result {
            case .success(let remote): _ = model.applyRemote(remote, ticket: ticket)
            case .failure(let error):
                if let failure = error as? FirestoreService.FavoriteFailure, case .unavailable = failure {
                    // Set before publication: model observers may call start.
                    observation.attachmentFailed = true
                }
                model.observationFailed(ticket: ticket)
                guard self.ownsFavoriteObservation(observation) else { return }
                AppDiagnostics.recordOperational(.favoritesSyncFailed)
            }
        }
        guard original() else {
            model.endObservation(ticket)
            listener?.remove()
            if favoritesObservation === observation { favoritesObservation = nil }
            return
        }
        observation.attaching = false
        observation.listener = listener
        if listener == nil {
            let alreadyReported = observation.attachmentFailed
            observation.attachmentFailed = true
            if !alreadyReported { model.observationFailed(ticket: ticket) }
        }
    }

    func retryFavorites(generation: UUID) {
        let model = injectedFavoriteModel ?? FavoritesRuntime.model
        guard model.snapshot.generation == generation else { return }
        let entry = UUID(); favoritesEntry = entry
        // Retire before retry can publish. A nested observer may then attach the
        // replacement; the original retry must not tear that replacement down.
        retireFavoritesObservation()
        guard favoritesEntry == entry, model.snapshot.generation == generation else { return }
        if injectedFavoriteModel != nil { injectedFavoriteRetry?(generation) }
        else { FavoritesRuntime.shared.retryCurrentChanges(generation: generation) }
        guard favoritesEntry == entry, model.snapshot.generation == generation else { return }
        startFavoritesListenerIfNeeded()
    }

    private func syncFavoritesWithFirestore() async { startFavoritesListenerIfNeeded() }

    // Enhanced category management
    var categories: [String] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        let allCategories = visibleArticles.compactMap { article in
            article.topicID?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return Array(Set(allCategories)).sorted()
    }
    
    // Get categories with article counts
    var categoriesWithCounts: [(name: String, count: Int)] {
        // If no articles or topics loaded, return empty array to prevent crashes
        guard !articles.isEmpty && !topics.isEmpty else {
            return []
        }
        
        let categoryCounts = Dictionary(grouping: visibleArticles) { article in
            topics.first(where: { $0.id == article.topicID })?.name ?? "Ukendt"
        }.mapValues { $0.count }
        
        return categoryCounts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
    
    // Resolve membership through the same known primary/secondary topic IDs
    // already used by the article's category chips, preserving feed order.
    func articles(for category: String) -> [Article] {
        let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !articles.isEmpty else { return [] }
        let matchingIDs = Set(topics.lazy.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
        }.map(\.id))
        guard !matchingIDs.isEmpty else { return [] }
        return visibleArticles.filter { article in
            if let primary = article.topicID, matchingIDs.contains(primary) { return true }
            return article.topicsIDs?.contains(where: matchingIDs.contains) ?? false
        }
    }
    
    // Get categories for an article
    /// Resolves the CMS "Section" name for an article (e.g. "Serier & Film").
    /// Prefers the article's direct section reference, falling back to the
    /// topic→section heuristic so older items without a section still get one.
    func sectionName(for article: Article) -> String? {
        if let sectionID = article.sectionID, !sectionID.isEmpty,
           let section = sections.first(where: { $0.id == sectionID }) {
            return section.name
        }
        return findSectionForArticle(article)?.name
    }

    func categories(for article: Article) -> [String] {
        // If no topics loaded, return default category to prevent crashes
        guard !topics.isEmpty else {
            return ["Generelt"]
        }
        
        var categories: [String] = []
        
        // Add main topic category
        if let topicID = article.topicID,
           let topic = topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        // Add multi-topic categories if available
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }
    
    // Get featured categories (categories with most articles)
    var featuredCategories: [Topic] {
        // If no topics loaded, return empty array to prevent crashes
        guard !topics.isEmpty else {
            return []
        }
        
        let sortedTopics = topics.sorted { first, second in
            let firstCount = articles(for: first.name).count
            let secondCount = articles(for: second.name).count
            return firstCount > secondCount
        }
        return Array(sortedTopics.prefix(6)) // Top 6 categories
    }
    
    // MARK: - Intelligent Article Filtering for HomeView
    
    // Get hero articles (first 5 articles by CMS created date)
    var heroArticles: [Article] {
        guard !articles.isEmpty else {
            return []
        }

        let now = Date()
        return Array(
            Article.sortedByCreatedNewestFirst(articles.filter(\.isPubliclyPublished))
                .filter { article in
                    let displayDate = article.createdSortDate ?? article.feedSortDate
                    return displayDate <= now
                }
                .prefix(5)
        )
    }
    
    // Helper function to exclude articles by IDs
    private func excludeArticles(withIDs excludedIDs: [String], from articles: [Article]) -> [Article] {
        // Safety check: ensure we have valid input
        guard !articles.isEmpty else {
            return []
        }
        
        // Safety check: ensure excludedIDs is not nil
        guard !excludedIDs.isEmpty else {
            return articles
        }
        
        return articles.filter { article in
            guard !article.id.isEmpty else {
                return false // Exclude articles with invalid IDs
            }
            return !excludedIDs.contains(article.id)
        }
    }

    private func articleFeedDate(_ article: Article) -> Date {
        article.feedSortDate
    }

    private func sortedNewestFirst(_ articles: [Article]) -> [Article] {
        Article.sortedByCreatedNewestFirst(articles)
    }

    private func articles(inSectionNamed sectionMatcher: (String) -> Bool) -> [Article] {
        guard !sections.isEmpty else { return [] }
        guard let section = sections.first(where: { sectionMatcher($0.name.lowercased()) }) else {
            return []
        }

        return articles.filter { article in
            findSectionForArticle(article)?.id == section.id
        }
    }

    private func latestSectionArticles(named sectionMatcher: (String) -> Bool, limit: Int = 6) -> [Article] {
        let sectionArticles = articles(inSectionNamed: sectionMatcher)
        let visibleArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: sectionArticles)
        return Array(sortedNewestFirst(visibleArticles).prefix(limit))
    }
    
    // Track which articles are already shown in other sections
    private var usedArticleIDs: Set<String> {
        var usedIDs = Set<String>()
        
        // Add hero articles
        usedIDs.formUnion(heroArticles.map { $0.id })
        
        // Add anmeldelser articles
        if !topics.isEmpty {
            let anmeldelserTopicID = topics.first(where: { $0.name == "Anmeldelser" })?.id
            let anmeldelserArticles = articles.filter { $0.topicID == anmeldelserTopicID }
            let filteredAnmeldelser = excludeArticles(withIDs: Array(usedIDs), from: anmeldelserArticles)
            usedIDs.formUnion(filteredAnmeldelser.prefix(10).map { $0.id })
        }
        
        return usedIDs
    }
    
    // Computed properties for HomeView-sektioner
    var continueWatching: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        // "Anbefalet til dig" can show any articles, including duplicates
        return Array(articles.dropFirst(5).prefix(10))
    }
    
    var popular: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        // Popular articles use the same editorial feed order as the rest of Home.
        let filtered = excludeArticles(withIDs: Array(usedArticleIDs), from: articles)
        return Array(sortedNewestFirst(filtered).prefix(6))
    }
    
    var allAnmeldelser: [Article] {
        // If no topics loaded, return empty array to prevent crashes
        guard !topics.isEmpty else {
            return []
        }
        
        // Anmeldelser - exclude hero articles only
        let anmeldelserTopicID = topics.first(where: { $0.name == "Anmeldelser" })?.id
        let filteredArticles = articles.filter { $0.topicID == anmeldelserTopicID }
        let excludedArticles = excludeArticles(withIDs: heroArticles.map { $0.id }, from: filteredArticles)
        
        // Sort by editorial publication date (newest first) and take first 10
        let sortedArticles = sortedNewestFirst(excludedArticles).prefix(10).map { $0 }
        
        return sortedArticles
    }

    var musicArticles: [Article] {
        latestSectionArticles(named: { $0.contains("musik") })
    }
    
    var kulturArticles: [Article] {
        latestSectionArticles(named: { $0.contains("kultur") })
    }
    
    var serierFilmArticles: [Article] {
        latestSectionArticles(named: { $0.contains("serier") || $0.contains("film") })
    }

    var popularat: [Article] {
        articles.filter { $0.featured == true }
    }
    
    var section: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        let now = Date()

        let recentArticles = articles.compactMap { article -> (Article, Date)? in
            let date = articleFeedDate(article)
            guard date <= now else { return nil }
            return (article, date)
        }

        let sorted = recentArticles
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { $0.0 }

        // Section articles - exclude hero and anmeldelser articles
        return excludeArticles(withIDs: Array(usedArticleIDs), from: Array(sorted))
    }
    
    // MARK: - ALL Articles for Each Section (for "Se alle" functionality)
    
    var allMusicArticles: [Article] {
        sortedNewestFirst(articles(inSectionNamed: { $0.contains("musik") }))
    }
    
    var allKulturArticles: [Article] {
        sortedNewestFirst(articles(inSectionNamed: { $0.contains("kultur") }))
    }
    
    var allSerierFilmArticles: [Article] {
        sortedNewestFirst(articles(inSectionNamed: { $0.contains("serier") || $0.contains("film") }))
    }
    
    var allAnmeldelserArticles: [Article] {
        // If no topics loaded, return empty array to prevent crashes
        guard !topics.isEmpty else {
            return []
        }
        
        // Get all anmeldelser articles (not just first 10)
        let anmeldelserTopicID = topics.first(where: { $0.name == "Anmeldelser" })?.id
        let anmeldelserArticles = articles.filter { $0.topicID == anmeldelserTopicID }
        let filteredArticles = excludeArticles(withIDs: heroArticles.map { $0.id }, from: anmeldelserArticles)
        
        // Sort by editorial publication date (newest first)
        return sortedNewestFirst(filteredArticles)
    }
    
    var allPopularArticles: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        // Get all popular articles (not just first 6)
        let filteredArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: articles)
        
        // Sort by editorial publication date (newest first)
        return sortedNewestFirst(filteredArticles)
    }
    
    var allSectionArticles: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        // Get all section articles (not just first 10)
        let now = Date()
        
        let recentArticles = articles.compactMap { article -> (Article, Date)? in
            let date = articleFeedDate(article)
            guard date <= now else { return nil }
            return (article, date)
        }
        
        let sorted = recentArticles
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        
        return excludeArticles(withIDs: Array(usedArticleIDs), from: sorted)
    }

    // MARK: - Section Analysis Functions
    
    /// Find which section an article belongs to based on its topic
    func findSectionForArticle(_ article: Article) -> WebflowSection? {
        // First check if we have sections and topics loaded
        guard !sections.isEmpty && !topics.isEmpty else {
            return nil
        }
        
        // Get the article's topic information
        let articleTopicID = article.topicID
        let articleTopicsIDs = article.topicsIDs ?? []
        
        
        // Find the topic name for the main topic
        if let mainTopicID = articleTopicID,
           let mainTopic = topics.first(where: { $0.id == mainTopicID }) {
            
            // Map topic to section based on content
            if let section = mapTopicToSection(mainTopic.name) {
                return section
            }
        }
        
        // Check additional topics
        for topicID in articleTopicsIDs {
            if let topic = topics.first(where: { $0.id == topicID }) {
                if let section = mapTopicToSection(topic.name) {
                    return section
                }
            }
        }
        
        return nil
    }
    
    /// Map a topic name to a section based on content analysis
    private func mapTopicToSection(_ topicName: String) -> WebflowSection? {
        // If no sections loaded, return nil to prevent crashes
        guard !sections.isEmpty else {
            return nil
        }
        
        let lowercasedTopic = topicName.lowercased()
        
        // Map topics to sections based on content
        if lowercasedTopic.contains("serier") || lowercasedTopic.contains("tv") {
            return sections.first(where: { $0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film") })
        } else if lowercasedTopic.contains("film") {
            return sections.first(where: { $0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film") })
        } else if lowercasedTopic.contains("musik") || lowercasedTopic.contains("koncert") {
            return sections.first(where: { $0.name.lowercased().contains("musik") })
        } else if lowercasedTopic.contains("kultur") || lowercasedTopic.contains("mening") {
            return sections.first(where: { $0.name.lowercased().contains("kultur") })
        } else if lowercasedTopic.contains("bøger") {
            // Note: No "Bøger" section in current sections, so this will return nil
            return nil
        } else if lowercasedTopic.contains("anmeldelser") {
            // Note: No "Anmeldelser" section in current sections, so this will return nil
            return nil
        }
        
        return nil
    }
    
    // MARK: - Incoming links

    private func resolveIncomingLink(_ request: IncomingLinkCoordinator.Request) async {
        let runtime = IncomingLinkRuntime.shared
        guard let accountPermission = captureReadPermission() else { return }
        let language = articleLanguage
        let permission: ReadPermission = { [weak self] in
            accountPermission() && self?.articleLanguage == language
        }
        guard permission(), runtime.isCurrent(request.ticket), !Task.isCancelled else { return }
        switch request.link {
        case .category(let name):
            NavigationCoordinator.shared.selectedTab = .categories
            guard permission(), runtime.isCurrent(request.ticket) else { return }
            NavigationCoordinator.shared.navigateToCategory(name, in: .categories)
        case .author(let id):
            let author: Author? = await withCheckedContinuation { continuation in
                fetchAuthor(by: id) { result in continuation.resume(returning: try? result.get()) }
            }
            guard permission(), runtime.isCurrent(request.ticket), !Task.isCancelled else { return }
            guard let author, author.id == id else {
                runtime.showMessage("Forfatteren kunne ikke åbnes lige nu. Prøv igen senere.", ticket: request.ticket)
                return
            }
            NavigationCoordinator.shared.selectedTab = .home
            guard permission(), runtime.isCurrent(request.ticket) else { return }
            NavigationCoordinator.shared.navigateToAuthor(author, in: .home)
        case .article(let id):
            guard let article = await resolveIncomingArticle(id, fallback: request.fallbackIdentifier, ticket: request.ticket, stillCurrent: permission),
                  permission(), runtime.isCurrent(request.ticket), !Task.isCancelled else { return }
            openIncomingArticle(article, ticket: request.ticket, stillCurrent: permission)
        case .podcast(let id, let startSeconds):
            guard let article = await resolveIncomingArticle(id, fallback: request.fallbackIdentifier, ticket: request.ticket, stillCurrent: permission),
                  permission(), runtime.isCurrent(request.ticket), !Task.isCancelled else { return }
            await PodcastRepository.shared.refreshManifest(force: true, allowPrefetch: false)
            guard permission(), runtime.isCurrent(request.ticket), !Task.isCancelled,
                  ArticleAvailabilityService.model.permitsBody(article) else { return }
            guard let raw = IncomingLinkResolutionPolicy.episode(for: article, in: PodcastRepository.shared.episodes),
                  PodcastAvailabilityService.model.allows(raw, articleID: article.id) else {
                openIncomingArticle(article, ticket: request.ticket, stillCurrent: permission)
                runtime.showMessage("Lyden er ikke tilgængelig lige nu. Du kan læse artiklen her.", ticket: request.ticket)
                return
            }
            let episode = PodcastRepository.enriched(raw, with: article)
            guard permission(), runtime.willStartPlayerWork(ticket: request.ticket) else { return }
            let accepted = PodcastPlayerManager.shared.play(episode: episode, articleId: article.id,
                audioStartSeconds: startSeconds.map(TimeInterval.init),
                routeIsCurrent: { permission() && runtime.isCurrent(request.ticket) })
            guard permission(), runtime.isCurrent(request.ticket) else { return }
            if accepted {
                PodcastPlayerManager.shared.isFullPlayerPresented = true
                AnalyticsService.shared.trackPodcastPlay(episode: episode, articleId: article.id)
            } else {
                openIncomingArticle(article, ticket: request.ticket, stillCurrent: permission)
                runtime.showMessage("Lyden kunne ikke åbnes. Du kan læse artiklen her.", ticket: request.ticket)
            }
        }
    }

    private func resolveIncomingArticle(_ identifier: String, fallback: String?, ticket: IncomingLinkCoordinator.Ticket, stillCurrent: @escaping ReadPermission) async -> Article? {
        let runtime = IncomingLinkRuntime.shared
        guard stillCurrent(), runtime.isCurrent(ticket) else { return nil }
        // Offline lookup is scoped to this owned snapshot. An online route uses
        // the bounded canonical server lookup, never a partial slug cache hit.
        if !OfflineManager.shared.isOnline {
            let cache = CacheManager.shared
            let capture = cache.captureArticlesHydration()
            let outcome = await cache.loadCapturedArticles(capture, stillPermitted: { stillCurrent() && runtime.isCurrent(ticket) && !Task.isCancelled })
            guard stillCurrent(), runtime.isCurrent(ticket), !Task.isCancelled else { return nil }
            let candidates = ArticleLanguageSelection.visible(articles + (outcome.articles ?? []), language: articleLanguage)
            let found = IncomingLinkResolutionPolicy.offlineArticle(
                identifier: ArticleLanguageSelection.identifier(identifier, language: articleLanguage), in: candidates,
                permits: { ArticleAvailabilityService.model.permitsBody($0) })
            if let found { return found }
            runtime.showMessage("Linket kunne ikke bekræftes offline. Prøv igen, når du er online.", ticket: ticket)
            return nil
        }
        let permission: ReadPermission = { stillCurrent() && runtime.isCurrent(ticket) && !Task.isCancelled }
        if let article = await fetchIncomingArticle(identifier, fallback: fallback, stillCurrent: permission) { return article }
        guard permission() else { return nil }
        runtime.showMessage("Artiklen kunne ikke åbnes. Den kan være ændret eller ikke længere publiceret.", ticket: ticket)
        return nil
    }

    private func openIncomingArticle(_ article: Article, ticket: IncomingLinkCoordinator.Ticket, stillCurrent: @escaping ReadPermission) {
        openIncomingArticle(article, ticket: ticket, stillCurrent: stillCurrent,
            runtime: .shared, navigation: .shared,
            permitsBody: { ArticleAvailabilityService.model.permitsBody($0) },
            dismissFullPlayer: { PodcastPlayerManager.shared.dismissFullPlayer() })
    }

    /// The production route and local tests share the same admission and path
    /// commit. Injected effects do not construct a player or reader transport.
    func openIncomingArticle(_ article: Article, ticket: IncomingLinkCoordinator.Ticket,
                             stillCurrent: @escaping ReadPermission,
                             runtime: IncomingLinkRuntime, navigation: NavigationCoordinator,
                             permitsBody: (Article) -> Bool,
                             dismissFullPlayer: () -> Void) {
        func mayPresent() -> Bool {
            guard stillCurrent(), runtime.isCurrent(ticket), isVisibleArticle(article),
                  permitsBody(article) else { return false }
            // Publication and presentation effects can reenter or revoke a route.
            return stillCurrent() && runtime.isCurrent(ticket)
        }
        guard mayPresent() else { return }
        dismissFullPlayer() // Dismiss the covering sheet; keep ordinary playback.
        guard mayPresent() else { return }
        navigation.selectedTab = .home
        guard mayPresent() else { return }
        navigation.goToRoot(in: .home)
        guard mayPresent() else { return }
        navigation.navigateToArticle(article, in: .home)
    }

    /// Shared server lookup used by actual route resolution and local transports.
    func fetchIncomingArticle(_ identifier: String, fallback: String?, stillCurrent: @escaping ReadPermission = { true }) async -> Article? {
        guard let owner = captureReadPermission() else { return nil }
        let language = articleLanguage
        let permission: ReadPermission = { [weak self] in owner() && stillCurrent()
            && !Task.isCancelled && self?.articleLanguage == language }
        guard permission() else { return nil }
        let first = await readEffects.incoming(ArticleLanguageSelection.identifier(identifier, language: language), permission)
        guard permission() else { return nil }
        if case .success(let article) = first { return isVisibleArticle(article) ? article : nil }
        if case .failure(FirestoreArticleError.empty) = first, let fallback, fallback != identifier {
            let second = await readEffects.incoming(ArticleLanguageSelection.identifier(fallback, language: language), permission)
            guard permission() else { return nil }
            if case .success(let article) = second { return isVisibleArticle(article) ? article : nil }
        }
        return nil
    }

}

// MARK: - Preview Extension
extension ArticleViewModel {
    static var preview: ArticleViewModel {
        let viewModel = ArticleViewModel()
        
        // Add sample topics
        viewModel.topics = [
            Topic(id: "1", name: "Design", description: "Kreativt design og visuel kunst", icon: "paintpalette.fill", color: "purple"),
            Topic(id: "2", name: "Musik", description: "Musik og lydoplevelser", icon: "music.note.list", color: "blue"),
            Topic(id: "3", name: "Litteratur", description: "Bøger og skrivning", icon: "book.fill", color: "orange"),
            Topic(id: "4", name: "Mad", description: "Mad og gastronomi", icon: "fork.knife", color: "red")
        ]
        
        // Add sample articles
        viewModel.articles = [
            Article(
                id: "1",
                name: "Moderne Design i København",
                slug: "moderne-design-kobenhavn",
                content: "En guide til moderne design...",
                intro: "Oplev byens skjulte designperler",
                stjerne: 4,
                topicID: "1",
                topicsIDs: ["1"],
                authorID: "1",
                thumbURL: URL(string: "https://via.placeholder.com/300x200"),
                coverURL: URL(string: "https://via.placeholder.com/1200x800"),
                location: "København",
                subtitle: "Design guide",
                isDraft: false,
                date: "2024-01-15",
                createdOn: "2024-01-15T10:00:00Z",
                lastPublished: "2024-01-15T10:00:00Z",
                featured: true
            ),
            Article(
                id: "2",
                name: "Jazz i Aarhus",
                slug: "jazz-aarhus",
                content: "Jazzscenen i Aarhus...",
                intro: "Oplev jazz i hjertet af Jylland",
                stjerne: 5,
                topicID: "2",
                topicsIDs: ["2"],
                authorID: "2",
                thumbURL: URL(string: "https://via.placeholder.com/300x200"),
                coverURL: URL(string: "https://via.placeholder.com/1200x800"),
                location: "Aarhus",
                subtitle: "Musik guide",
                isDraft: false,
                date: "2024-01-10",
                createdOn: "2024-01-10T10:00:00Z",
                lastPublished: "2024-01-10T10:00:00Z",
                featured: false
            )
        ]
        
        return viewModel
    }
}
