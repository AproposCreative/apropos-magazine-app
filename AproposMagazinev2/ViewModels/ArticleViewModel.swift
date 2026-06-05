import Combine
import FirebaseFirestore
import Foundation
import OSLog

@MainActor
class ArticleViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var aiRecommendations: [Article] = []
    @Published var personalizedRecommendations: [(Article, String)] = []
    @Published var isLoading: Bool = false
    @Published var fetchError: Error? = nil
    @Published var isLoadingAI: Bool = false
    @Published var aiError: String? = nil
    @Published var favorites: [Article] = []
    @Published var favoriteError: String? = nil
    @Published var isLoadingFavorites: Bool = false
    @Published var user: UserProfile? = nil
    @Published var topics: [Topic] = []
    @Published var topicsError: Error? = nil
    @Published var sections: [WebflowSection] = []
    @Published var sectionsError: Error? = nil
    @Published var authors: [Author] = []
    @Published var starsMapping: [String: String] = [:]
    @Published var fullArticle: Article?
    @Published var anmeldelserTopicID:String? = nil
    private let favoritesKey = "favoriteArticlesJSON"
    private var hasStarted = false
    
    // Track which articles are currently being loaded to prevent duplicate calls
    var loadingArticles: Set<String> = []
    
    // Limit concurrent article loading to prevent system overload
    private let maxConcurrentLoads = 1  // Reduced to 1 to prevent memory issues
    private var currentLoadCount = 0
    private var pendingLoads: [String] = []
    private var didStartFavoritesListener = false
    
    private var notificationObserverTokens: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "ArticleViewModel")
    
    init() {
        // Listen for notification navigation
        let openArticleToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenArticleFromNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Try articleId first
            if let articleId = notification.userInfo?["articleId"] as? String, !articleId.isEmpty {
                Task { @MainActor in
                    self.navigateToArticleFromNotification(articleId: articleId)
                }
            }
            // Fallback: search by article name
            else if let articleName = notification.userInfo?["articleName"] as? String, !articleName.isEmpty {
                Task { @MainActor in
                    self.navigateToArticleByName(articleName: articleName)
                }
            }
        }
        notificationObserverTokens.append(openArticleToken)
        
        // Listen for article fetch requests
        let fetchArticleToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FetchArticleForNavigation"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let articleId = notification.userInfo?["articleId"] as? String {
                Task { @MainActor in
                    self.fetchAndNavigateToArticle(articleId: articleId)
                }
            }
        }
        notificationObserverTokens.append(fetchArticleToken)

    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Let SwiftUI paint the first frame before decoding caches or starting network work.
        Task { @MainActor in
            await Task.yield()
            loadFavorites()
            fetchArticles()
            loadCachedMetadata()
        }

        // Delay non-critical fetches to after initial load
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            fetchMetadataInBackground()
        }

        // Lazy load cached recommendations only (fetch on scroll in HomeView)
        Task { @MainActor in
            if let cached = RecommendationService.shared.loadCached() {
                personalizedRecommendations = cached
            }
            await SeriesService.shared.fetchSeries()
        }

        // Overvåg UserManager ændringer og synkroniser favoritter
        UserManager.shared.$currentUser
            .removeDuplicates { user1, user2 in
                // Safety check: ensure we have valid users to compare
                guard let uid1 = user1?.uid, !uid1.isEmpty,
                      let uid2 = user2?.uid, !uid2.isEmpty else {
                    return false
                }
                return uid1 == uid2
            }
            .sink { [weak self] user in
                guard let self = self else { return }
                
                if let user = user, !user.uid.isEmpty {
                    self.startFavoritesListenerIfNeeded()
                    Task { await self.syncFavoritesWithFirestore() }
                }
            }
            .store(in: &cancellables)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard UserManager.shared.currentUser != nil else { return }
            startFavoritesListenerIfNeeded()
            await syncFavoritesWithFirestore()
        }
    }
    
    deinit {
        if let favoritesListener = favoritesListener {
            favoritesListener.remove()
            self.favoritesListener = nil
        }
        
        for token in notificationObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationObserverTokens.removeAll()
    }
    
    func fetchArticles(forceRefresh: Bool = false) {
        // Safety check: ensure we're not already loading
        guard !isLoading else {
            return
        }
        
        let startTime = Date()
        
        // Try cache first for fast startup (unless force refresh)
        if !forceRefresh, let cached = CacheManager.shared.getCachedArticles(), !cached.isEmpty {
            // Sort cached articles by date (newest first)
            let sortedCached = sortedNewestFirst(cached)
            
            // Show cached articles immediately (no loading state)
            self.articles = sortedCached
            self.isLoading = false
            
            // Keep launch light: only warm the first few visible images.
            CacheManager.shared.preloadImages(for: Array(sortedCached.prefix(5)))
            
            // Load favorites after articles are available
            Task { [weak self] in await self?.syncFavoritesWithFirestore() }
            
            // Silently refresh in background (don't show loading state)
            refreshArticlesInBackground()
        } else {
            // No cached articles or force refresh - show loading state
            isLoading = true
            fetchError = nil
            
            fetchRemoteArticles { [weak self] result in
                guard let self = self else { return }
                
                let elapsed = Date().timeIntervalSince(startTime)
                // Only show minimum loading time if fetch was very fast (< 0.3s)
                // This prevents UI flicker but doesn't slow down the app unnecessarily
                let minLoadingTime: TimeInterval = elapsed < 0.3 ? 0.3 : 0
                let remainingTime = max(0, minLoadingTime - elapsed)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                    guard let self = self else { return }
                    self.isLoading = false
                    self.handleRemoteArticlesResult(result, clearOnEmptyFailure: !forceRefresh)
                }
            }
        }
    }

    func refreshArticles() async {
        fetchArticles(forceRefresh: true)
        await PodcastRepository.shared.refreshManifest(force: true)
    }
    
    private func fetchRemoteArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
        FirestoreArticleService.shared.fetchArticles { result in
            switch result {
            case .success:
                completion(result)
            case .failure(FirestoreArticleError.empty):
                self.logger.info("Firestore articles empty – falling back to Webflow")
                WebflowService.shared.fetchArticles(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func handleRemoteArticlesResult(_ result: Result<[Article], Error>, clearOnEmptyFailure: Bool) {
        switch result {
        case .success(let articles):
            let sortedArticles = sortedNewestFirst(articles)
            self.articles = sortedArticles
            CacheManager.shared.cacheArticles(sortedArticles)
            CacheManager.shared.preloadImages(for: Array(sortedArticles.prefix(5)))
            Task { [weak self] in await self?.syncFavoritesWithFirestore() }

            if articles.isEmpty {
                self.fetchError = NSError(
                    domain: "ViewModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Ingen artikler fundet."]
                )
            } else {
                self.fetchError = nil
            }
        case .failure(let error):
            logger.error("Fejl ved hentning af artikler: \(error.localizedDescription, privacy: .public)")
            self.fetchError = error
            if clearOnEmptyFailure && self.articles.isEmpty {
                self.articles = []
            }
        }
    }
    
    /// Silently refresh articles in background without showing loading state
    private func refreshArticlesInBackground() {
        Task { [weak self] in
            guard let self = self else { return }
            
            // Wait a bit to not interfere with initial load
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            fetchRemoteArticles { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let articles):
                    let sortedArticles = self.sortedNewestFirst(articles)
                    
                    Task { @MainActor in
                        if sortedArticles.count != self.articles.count ||
                           sortedArticles.first?.id != self.articles.first?.id {
                            self.articles = sortedArticles
                            CacheManager.shared.cacheArticles(sortedArticles)
                        }
                    }
                case .failure(let error):
                    self.logger.error("Baggrundsopdatering af artikler fejlede: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    func fetchAIRecommendations() {
        fetchPersonalizedRecommendationsIfNeeded(force: true)
    }

    func fetchPersonalizedRecommendationsIfNeeded(force: Bool = false) {
        guard force || personalizedRecommendations.isEmpty else { return }
        guard !isLoadingAI else { return }

        isLoadingAI = true
        aiError = nil

        Task { @MainActor in
            let readIds = iCloudSyncService.shared.readArticleIds
            let subscribedCategories = UserManager.shared.currentUser?.favoriteCategories ?? []
            let recommendations = await RecommendationService.shared.generateRecommendations(
                articles: articles,
                favorites: favorites,
                subscribedCategoryIds: subscribedCategories,
                readArticleIds: readIds
            )
            personalizedRecommendations = recommendations
            aiRecommendations = recommendations.map(\.0)
            isLoadingAI = false
        }
    }
    
    // MARK: - Metadata Loading (with caching)
    
    /// Load cached metadata immediately (fast)
    private func loadCachedMetadata() {
        // Load topics from cache
        if let cachedTopics = CacheManager.shared.getCachedTopics() {
            self.topics = cachedTopics
        }
        
        // Load sections from cache
        if let cachedSections = CacheManager.shared.getCachedSections() {
            self.sections = cachedSections
        }
        
        // Load authors from cache
        if let cachedAuthors = CacheManager.shared.getCachedAuthors() {
            self.authors = cachedAuthors
        }
        
        // Load stars mapping from cache
        if let cachedStars = CacheManager.shared.getCachedStarsMapping() {
            self.starsMapping = cachedStars
        }
    }
    
    /// Fetch metadata in background and update cache
    private func fetchMetadataInBackground() {
        fetchTopics()
        fetchSections()
        fetchAuthors()
        fetchStars()
    }
    
    func fetchTopics() {
        WebflowService.shared.fetchTopics { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let topics):
                self.topics = topics
                CacheManager.shared.cacheTopics(topics)
            case .failure:
                break
            }
        }
    }
    
    func fetchSections() {
        WebflowService.shared.fetchSections { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let sections):
                self.sections = sections
                CacheManager.shared.cacheSections(sections)
            case .failure:
                break
            }
        }
    }
    
    func fetchAuthors() {
        WebflowService.shared.fetchAuthors { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let authors):
                self.authors = authors
                CacheManager.shared.cacheAuthors(authors)
            case .failure:
                break
            }
        }
    }
    
    func fetchStars() {
        WebflowService.shared.fetchStarsMapping { [weak self] mapping in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.starsMapping = mapping
                CacheManager.shared.cacheStarsMapping(mapping)
            }
        }
    }
    
    func fetchArticle(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        guard !id.isEmpty else {
            completion(.failure(NSError(domain: "Invalid ID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Article ID is empty"])))
            return
        }

        FirestoreArticleService.shared.fetchArticle(by: id) { result in
            switch result {
            case .success(let article):
                completion(.success(article))
            case .failure(FirestoreArticleError.empty):
                self.logger.info("Firestore article \(id, privacy: .public) missing – falling back to Webflow")
                self.fetchArticleFromWebflow(by: id, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func fetchArticleFromWebflow(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items/\(id)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(WebflowService.shared.apiToken)", forHTTPHeaderField: "Authorization")

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
                let article = try decoder.decode(Article.self, from: data)
                completion(.success(article))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchAuthor(by id: String, completion: @escaping (Result<Author, Error>) -> Void) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            completion(.failure(NSError(domain: "Invalid ID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Author ID is empty"])))
            return
        }
        
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294/items/\(id)"
        
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(WebflowService.shared.apiToken)", forHTTPHeaderField: "Authorization")
        
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
                let authorWrapper = try decoder.decode(AuthorWrapper.self, from: data)
                let author = authorWrapper.toAuthor()
                completion(.success(author))
            } catch {
                self.logger.error("Kunne ikke dekode forfatterdata: \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
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
    

    
    func loadFullArticle(with id: String) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            logger.error("loadFullArticle kaldt med tomt ID")
            return
        }
        
        guard !articles.isEmpty else {
            return
        }
        
        if let existingArticle = articles.first(where: { $0.id == id }) {
            if existingArticle.author != nil {
                return
            }
            
            if let content = existingArticle.content, !content.isEmpty {
                loadAuthorIfNeeded(for: existingArticle)
                return
            }
        }
        
        if loadingArticles.contains(id) {
            return
        }
        
        if pendingLoads.contains(id) {
            return
        }
        
        // Check if we've reached the concurrent load limit
        if currentLoadCount >= maxConcurrentLoads {
            // print("🔄 Max concurrent loads reached, queuing article \(id)")
            pendingLoads.append(id)
            return
        }
        
        // Start loading the article
        startLoadingArticle(id)
    }
    
    private func loadAuthorIfNeeded(for article: Article) {
        guard let authorID = article.authorID, !authorID.isEmpty else { return }
        guard !loadingArticles.contains(article.id) else { return }
        
        loadingArticles.insert(article.id)
        fetchAuthor(by: authorID) { [weak self] result in
            guard let self else { return }
            
            var updatedArticle = article
            if case .success(let author) = result {
                updatedArticle.author = author
            }
            
            DispatchQueue.main.async {
                self.updateArticleInAllArrays(updatedArticle)
                self.loadingArticles.remove(article.id)
            }
        }
    }
    
    private func startLoadingArticle(_ id: String) {
        // Mark article as being loaded
        loadingArticles.insert(id)
        currentLoadCount += 1
        // print("🔄 Fetching article with ID: \(id) (loads: \(currentLoadCount)/\(maxConcurrentLoads))")
        
        // Add timeout to prevent articles from being stuck in loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in  // Reduced timeout
            guard let self = self else { return }
            if self.loadingArticles.contains(id) {
                // print("⏰ Timeout for article \(id), removing from loading state")
                self.loadingArticles.remove(id)
                self.currentLoadCount = max(0, self.currentLoadCount - 1)
                self.processNextPendingLoad()
            }
        }

        fetchArticle(by: id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fetchedArticle):
                // print("✅ Article fetched: \(fetchedArticle.name ?? "No name")")

                var updatedArticle = fetchedArticle

                // Safety check: ensure authorID is not empty before fetching
                guard let authorID = fetchedArticle.authorID, !authorID.isEmpty else {
                    DispatchQueue.main.async {
                        self.fullArticle = updatedArticle
                        self.updateArticleInAllArrays(updatedArticle)
                        self.finishLoadingArticle(id)
                    }
                    return
                }

                self.fetchAuthor(by: authorID) { authorResult in
                    switch authorResult {
                    case .success(let author):
                        updatedArticle.author = author
                        // print("✅ Author fetched: \(author.name)")
                    case .failure(let error):
                        self.logger.error("Kunne ikke hente forfatter: \(error.localizedDescription, privacy: .public)")
                    }
                    DispatchQueue.main.async {
                        self.fullArticle = updatedArticle
                        self.updateArticleInAllArrays(updatedArticle)
                        self.finishLoadingArticle(id)
                    }
                }

            case .failure(let error):
                logger.error("Kunne ikke hente artikel \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self.finishLoadingArticle(id)
                }
            }
        }
    }
    
    private func finishLoadingArticle(_ id: String) {
        loadingArticles.remove(id)
        currentLoadCount = max(0, currentLoadCount - 1)
        // print("✅ Finished loading article \(id) (loads: \(currentLoadCount)/\(maxConcurrentLoads))")
        
        // Process next pending load
        processNextPendingLoad()
    }
    
    private func processNextPendingLoad() {
        guard currentLoadCount < maxConcurrentLoads, !pendingLoads.isEmpty else {
            return
        }
        
        let nextId = pendingLoads.removeFirst()
        // print("🔄 Processing next pending load: \(nextId)")
        startLoadingArticle(nextId)
    }

    private func updateArticleInAllArrays(_ updated: Article) {
        // Safety check: ensure we have a valid article
        guard !updated.id.isEmpty else {
            logger.error("Forsøgte at opdatere artikel uden ID")
            return
        }
        
        func replace(in array: inout [Article]) {
            // Safety check: ensure we have a valid article ID
            guard !updated.id.isEmpty else {
                logger.error("Forsøgte at erstatte artikel uden ID")
                return
            }
            
            if let index = array.firstIndex(where: { $0.id == updated.id }) {
                array[index] = updated
            }
        }

        replace(in: &self.articles)
    }
    
    private var cancellables: Set<AnyCancellable> = []
    private var favoritesListener: ListenerRegistration?
    
    func isFavorite(_ article: Article) -> Bool {
        // Safety check: ensure we have a valid article and favorites array
        guard let name = article.name, !name.isEmpty else { return false }
        
        // If no favorites loaded, return false to prevent crashes
        guard !favorites.isEmpty else {
            return false
        }
        
        return favorites.contains(where: { $0.name == article.name })
    }
    
    func toggleFavorite(for article: Article) {
        // Safety check: ensure we have a valid article
        guard let name = article.name, !name.isEmpty else { 
            logger.error("Forsøgte at togg­le favorit på artikel uden navn")
            return 
        }
        
        let wasFavorite = isFavorite(article)
        
        if wasFavorite {
            favorites.removeAll { $0.id == article.id }
            OfflineManager.shared.removeArticleFromOffline(article.id)
        } else {
            favorites.append(article)
            OfflineManager.shared.saveArticleForOffline(article)
        }
        
        // Always save to UserDefaults for local persistence (works for logged out users)
        saveFavorites()
        
        // Sync with Firebase and UserManager only if user is logged in
        if let user = UserManager.shared.currentUser {
            // Sync with Firebase
            Task {
                do {
                    try await FirestoreService.shared.toggleFavorite(article, isFavorite: !wasFavorite)
                } catch {
                    self.logger.error("Favorit sync-fejl: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            // Sync with UserManager for cloud sync
            if !wasFavorite {
                // Add to bookmarked articles in UserManager
                if !user.bookmarkedArticles.contains(article.id) {
                    UserManager.shared.toggleBookmark(article.id)
                }
            } else {
                // Remove from bookmarked articles in UserManager
                if user.bookmarkedArticles.contains(article.id) {
                    UserManager.shared.toggleBookmark(article.id)
                }
            }
        }
    }
    
    private func loadFavorites() {
        // Safety check: ensure we're not already loading favorites
        guard !isLoadingFavorites else {
            return
        }
        
        // First try to load from UserDefaults for fast access
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([Article].self, from: data) {
            favorites = decoded
            OfflineArticleImageCache.shared.scheduleCacheImages(for: favorites)
            OfflineManager.shared.savePodcastsForOffline(favorites)
        }
        
        // Firebase sync is delayed until after launch to keep the first frame responsive.
    }

    private func startFavoritesListenerIfNeeded() {
        guard !didStartFavoritesListener else { return }
        didStartFavoritesListener = true

        favoritesListener = FirestoreService.shared.listenFavorites { [weak self] articles in
            guard let self = self else { return }
            guard !articles.isEmpty else { return }

            self.favorites = articles
            self.saveFavorites()
            OfflineArticleImageCache.shared.scheduleCacheImages(for: articles)
            OfflineManager.shared.savePodcastsForOffline(articles)
        }
    }
    
    private func syncFavoritesWithFirestore() async {
        // Safety check: ensure we're not already syncing
        guard !isLoadingFavorites else {
            return
        }
        
        guard UserManager.shared.currentUser != nil else {
            // For logged-out users, just ensure local favorites are loaded
            DispatchQueue.main.async { [weak self] in
                self?.isLoadingFavorites = false
                self?.favoriteError = nil
            }
            return
        }
        
        // FirestoreService.shared is always available, so no need to check
        
        isLoadingFavorites = true
        favoriteError = nil
        
        do {
            let firebaseFavorites = try await FirestoreService.shared.fetchFavorites()
            // print("📱 Loaded \(firebaseFavorites.count) favorites from Firebase")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Merge Firebase favorites with local favorites
                let localFavorites = self.favorites.filter { localArticle in
                    !firebaseFavorites.contains { firebaseArticle in
                        firebaseArticle.id == localArticle.id
                    }
                }
                self.favorites = firebaseFavorites + localFavorites
                self.saveFavorites()
                for article in self.favorites {
                    OfflineManager.shared.saveArticleForOffline(article)
                }
                self.isLoadingFavorites = false
                // print("✅ Synced favorites: \(self.favorites.count) total")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.favoriteError = "Kunne ikke synkronisere favoritter: \(error.localizedDescription)"
                self?.isLoadingFavorites = false
                self?.logger.error("Favoritsync mod Firebase fejlede: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func reloadFavorites() {
        // Safety check: ensure we're not already syncing
        guard !isLoadingFavorites else {
            return
        }
        
        Task { [weak self] in
            await self?.syncFavoritesWithFirestore()
        }
    }
    
    private func saveFavorites() {
        // Safety check: ensure we have valid favorites to save
        guard !favorites.isEmpty else {
            return
        }
        
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        } else {
            logger.error("Kunne ikke serialisere favoritter til disk")
        }
    }
    
    // Enhanced category management
    var categories: [String] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        
        let allCategories = articles.compactMap { article in
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
        
        let categoryCounts = Dictionary(grouping: articles) { article in
            topics.first(where: { $0.id == article.topicID })?.name ?? "Ukendt"
        }.mapValues { $0.count }
        
        return categoryCounts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
    
    // Get articles by category
    func articles(for category: String) -> [Article] {
        // If no articles or topics loaded, return empty array to prevent crashes
        guard !articles.isEmpty && !topics.isEmpty else {
            return []
        }
        
        return articles.filter { article in
            let topicName = topics.first(where: { $0.id == article.topicID })?.name ?? ""
            return topicName.trimmingCharacters(in: .whitespacesAndNewlines) == category
        }
    }
    
    // Get categories for an article
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
            // print("[DEBUG] No topics loaded, returning empty featuredCategories")
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
    
    // Get hero articles (first 5 articles)
    var heroArticles: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        return Array(sortedNewestFirst(articles).prefix(5))
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
        articles.sorted { articleFeedDate($0) > articleFeedDate($1) }
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
            // print("[DEBUG] No articles loaded, returning empty continueWatching")
            return []
        }
        
        // "Anbefalet til dig" can show any articles, including duplicates
        return Array(articles.dropFirst(5).prefix(10))
    }
    
    var popular: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            // print("[DEBUG] No articles loaded, returning empty popular")
            return []
        }
        
        // Popular articles use the same editorial feed order as the rest of Home.
        let filtered = excludeArticles(withIDs: Array(usedArticleIDs), from: articles)
        return Array(sortedNewestFirst(filtered).prefix(6))
    }
    
    var allAnmeldelser: [Article] {
        // If no topics loaded, return empty array to prevent crashes
        guard !topics.isEmpty else {
            // print("[DEBUG] No topics loaded, returning empty allAnmeldelser")
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
            // print("[DEBUG] No articles loaded, returning empty section")
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
            // print("[DEBUG] No topics loaded, returning empty allAnmeldelserArticles")
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
            // print("[DEBUG] No articles loaded, returning empty allPopularArticles")
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
            // print("[DEBUG] No articles loaded, returning empty allSectionArticles")
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
            // print("[DEBUG] No sections or topics loaded yet")
            return nil
        }
        
        // Get the article's topic information
        let articleTopicID = article.topicID
        let articleTopicsIDs = article.topicsIDs ?? []
        
        // print("[DEBUG] Article '\(article.name ?? "Unknown")' analysis:")
        // print("[DEBUG] - Main topic ID: \(articleTopicID ?? "nil")")
        // print("[DEBUG] - Additional topics IDs: \(articleTopicsIDs)")
        
        // Find the topic name for the main topic
        if let mainTopicID = articleTopicID,
           let mainTopic = topics.first(where: { $0.id == mainTopicID }) {
            // print("[DEBUG] - Main topic name: \(mainTopic.name)")
            
            // Map topic to section based on content
            if let section = mapTopicToSection(mainTopic.name) {
                // print("[DEBUG] - Mapped to section: \(section.name)")
                return section
            }
        }
        
        // Check additional topics
        for topicID in articleTopicsIDs {
            if let topic = topics.first(where: { $0.id == topicID }) {
                // print("[DEBUG] - Additional topic: \(topic.name)")
                if let section = mapTopicToSection(topic.name) {
                    // print("[DEBUG] - Mapped to section: \(section.name)")
                    return section
                }
            }
        }
        
        // print("[DEBUG] - No section mapping found")
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
    
    // MARK: - Notification Navigation
    
    /// Navigate to article from notification
    private func navigateToArticleFromNotification(articleId: String) {
        // First check if article is already loaded
        if let existingArticle = articles.first(where: { $0.id == articleId }) {
            navigateToArticle(existingArticle)
            return
        }
        
        // If not loaded, fetch it first
        fetchAndNavigateToArticle(articleId: articleId)
    }
    
    /// Fetch article and navigate to it
    private func fetchAndNavigateToArticle(articleId: String) {
        fetchArticle(by: articleId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let article):
                self.navigateToArticle(article)
            case .failure(let error):
                self.logger.error("Kunne ikke hente artikel \(articleId, privacy: .public) til navigation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    /// Navigate to article using NavigationCoordinator
    private func navigateToArticle(_ article: Article) {
        // Post notification to NavigationCoordinator
        // Use DispatchQueue to ensure this happens on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToArticle"),
                object: nil,
                userInfo: ["article": article]
            )
        }
    }
    
    /// Navigate to article by name (fallback when ID is not available)
    private func navigateToArticleByName(articleName: String) {
        let searchName = articleName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // If "Ny artikel" or similar, we need to find the newest article
        // But first, ensure we have fresh articles loaded
        if searchName.contains("ny") || searchName.contains("new") {
            // Force refresh articles to get the latest
            fetchArticles()
            
            // Wait for articles to load, then find the newest
            Task { @MainActor in
                // Wait longer for articles to load from server
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                
                // Get the newest article by the same editorial feed order as Home.
                if let newestArticle = self.sortedNewestFirst(self.articles).first {
                    self.navigateToArticle(newestArticle)
                    return
                }
            }
            return
        }
        
        // For specific article names, try exact match first
        if let existingArticle = articles.first(where: { 
            let articleName = $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return articleName == searchName
        }) {
            navigateToArticle(existingArticle)
            return
        }
        
        // Try partial match (contains)
        if let existingArticle = articles.first(where: { 
            let articleName = $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return articleName.contains(searchName) || searchName.contains(articleName)
        }) {
            navigateToArticle(existingArticle)
            return
        }
        
        // If not found, wait a bit for articles to load, then search again
        Task { @MainActor in
            // Refresh articles to ensure we have latest
            self.fetchArticles()
            
            // Wait for articles to potentially load
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Try exact match again
            if let foundArticle = self.articles.first(where: { 
                let articleName = $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return articleName == searchName
            }) {
                self.navigateToArticle(foundArticle)
                return
            }
            
            // Try partial match again
            if let foundArticle = self.articles.first(where: { 
                let articleName = $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return articleName.contains(searchName) || searchName.contains(articleName)
            }) {
                self.navigateToArticle(foundArticle)
                return
            }
        }
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
