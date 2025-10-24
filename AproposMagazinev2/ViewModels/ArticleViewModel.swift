import Foundation
import Combine
import FirebaseFirestore

@MainActor
class ArticleViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var aiRecommendations: [Article] = []
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
    
    // Track which articles are currently being loaded to prevent duplicate calls
    var loadingArticles: Set<String> = []
    
    // Limit concurrent article loading to prevent system overload
    private let maxConcurrentLoads = 1  // Reduced to 1 to prevent memory issues
    private var currentLoadCount = 0
    private var pendingLoads: [String] = []
    
    private var notificationObserverTokens: [NSObjectProtocol] = []
    
    init() {
        // FirestoreService.shared and UserManager.shared are always available, so no need to check
        
        print("🔄 ArticleViewModel: Starting initialization...")
        FirestoreService.shared.configurePersistenceIfNeeded()
        print("🔄 ArticleViewModel: Firestore configured")
        
        loadFavorites()
        print("🔄 ArticleViewModel: Favorites loaded")
        
        fetchArticles()
        print("🔄 ArticleViewModel: Articles fetch started")
        
        fetchAIRecommendations()
        print("🔄 ArticleViewModel: AI recommendations fetch started")
        
        fetchTopics()
        print("🔄 ArticleViewModel: Topics fetch started")
        
        fetchSections()
        print("🔄 ArticleViewModel: Sections fetch started")
        
        fetchAuthors()
        print("🔄 ArticleViewModel: Authors fetch started")
        
        fetchStars()
        print("🔄 ArticleViewModel: Stars fetch started")
        
        print("🔄 ArticleViewModel: Initialization completed")
        
        // Listen for notification navigation
        let openArticleToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenArticleFromNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let articleId = notification.userInfo?["articleId"] as? String {
                Task { @MainActor in
                    self.navigateToArticleFromNotification(articleId: articleId)
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
                
                // Safety check: ensure we have a valid user
                if let user = user, !user.uid.isEmpty {
                    print("[Sync] User authenticated, starting sync: \(user.uid)")
                    Task { await self.syncFavoritesWithFirestore() }
                } else {
                    print("[Sync] No valid user, skipping sync")
                }
            }
            .store(in: &cancellables)
            
        // Realtime favorites updates
        favoritesListener = FirestoreService.shared.listenFavorites { [weak self] articles in
            guard let self = self else { return }
            // Safety check: ensure we have valid articles
            guard !articles.isEmpty else {
                print("ℹ️ No favorites received from Firestore")
                return
            }
            
            self.favorites = articles
            self.saveFavorites()
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
        
        print("[ArticleViewModel] deinit: cleaned up observers and listeners")
    }
    
    func fetchArticles() {
        // Safety check: ensure we're not already loading
        guard !isLoading else {
            print("❌ Articles already loading")
            return
        }
        
        // WebflowService.shared is always available, so no need to check
        
        isLoading = true
        fetchError = nil
        // print("[DEBUG] fetchArticles: Starter fetch...")
        
        // Ensure shimmer shows for at least 1 second
        let startTime = Date()
        
        // Try cache first for fast startup
        if let cached = CacheManager.shared.getCachedArticles(), !cached.isEmpty {
            print("[DEBUG] fetchArticles: Found \(cached.count) cached articles")
            // Sort cached articles by date (newest first)
            let sortedCached = cached.sorted { article1, article2 in
                var mutableArticle1 = article1
                var mutableArticle2 = article2
                let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
                let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
                return date1 > date2
            }
            print("[DEBUG] fetchArticles: Setting cached articles to \(sortedCached.count) articles")
            self.articles = sortedCached
            
            // Load favorites after articles are available
            Task { [weak self] in await self?.syncFavoritesWithFirestore() }
            
            // Ensure minimum loading time for shimmer effect
            let elapsed = Date().timeIntervalSince(startTime)
            let minLoadingTime: TimeInterval = 1.0
            let remainingTime = max(0, minLoadingTime - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                self?.isLoading = false
            }
        } else {
            // No cached articles, fetch from Webflow
            WebflowService.shared.fetchArticles { [weak self] result in
                // Ensure minimum loading time for shimmer effect
                let elapsed = Date().timeIntervalSince(startTime)
                let minLoadingTime: TimeInterval = 1.0
                let remainingTime = max(0, minLoadingTime - elapsed)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                    self?.isLoading = false
                    switch result {
                    case .success(let articles):
                        print("[DEBUG] fetchArticles: Fik \(articles.count) artikler")
                        // Sort articles by date (newest first)
                        let sortedArticles = articles.sorted { article1, article2 in
                            var mutableArticle1 = article1
                            var mutableArticle2 = article2
                            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
                            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
                            return date1 > date2
                        }
                        print("[DEBUG] fetchArticles: Setting articles to \(sortedArticles.count) articles")
                        self?.articles = sortedArticles
                        CacheManager.shared.cacheArticles(sortedArticles)
                        // Load favorites after articles are available
                        Task { [weak self] in await self?.syncFavoritesWithFirestore() }
                        if articles.isEmpty {
                            print("[DEBUG] fetchArticles: Ingen artikler fundet!")
                            self?.fetchError = NSError(domain: "ViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ingen artikler fundet."])
                        }
                    case .failure(let error):
                        // print("[DEBUG] fetchArticles: FEJL: \(error)")
                        self?.fetchError = error
                        self?.articles = []
                    }
                }
            }
        }
    }
    
    func fetchAIRecommendations() {
        // Safety check: ensure we're not already loading
        guard !isLoadingAI else {
            print("❌ AI recommendations already loading")
            return
        }
        
        isLoadingAI = true
        // AI recommendations logic here
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isLoadingAI = false
        }
    }
    
    func fetchTopics() {
        // WebflowService.shared is always available, so no need to check
        
        let startTime = Date()
        WebflowService.shared.fetchTopics { [weak self] result in
            // Ensure minimum loading time for shimmer effect
            let elapsed = Date().timeIntervalSince(startTime)
            let minLoadingTime: TimeInterval = 0.8
            let remainingTime = max(0, minLoadingTime - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                switch result {
                case .success(let topics):
                    self?.topics = topics
                case .failure(_):
                    // print("[DEBUG] fetchTopics: FEJL: \(error)")
                    break
                }
            }
        }
    }
    
    func fetchSections() {
        // WebflowService.shared is always available, so no need to check
        
        let startTime = Date()
        WebflowService.shared.fetchSections { [weak self] result in
            // Ensure minimum loading time for shimmer effect
            let elapsed = Date().timeIntervalSince(startTime)
            let minLoadingTime: TimeInterval = 0.8
            let remainingTime = max(0, minLoadingTime - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                switch result {
                case .success(let sections):
                    self?.sections = sections
                    // print("[DEBUG] fetchSections: SUCCESS - Found \(sections.count) sections")
                    // print("[DEBUG] Sections: \(sections.map { "\($0.name) (ID: \($0.id))" })")
                case .failure(_):
                    // print("[DEBUG] fetchSections: FEJL: \(error)")
                    break
                }
            }
        }
    }
    
    func fetchAuthors() {
        // WebflowService.shared is always available, so no need to check
        
        let startTime = Date()
        WebflowService.shared.fetchAuthors { [weak self] result in
            // Ensure minimum loading time for shimmer effect
            let elapsed = Date().timeIntervalSince(startTime)
            let minLoadingTime: TimeInterval = 0.8
            let remainingTime = max(0, minLoadingTime - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                switch result {
                case .success(let authors):
                    self?.authors = authors
                case .failure(_):
                    // print("[DEBUG] fetchAuthors: FEJL: \(error)")
                    break
                }
            }
        }
    }
    
    func fetchStars() {
        // WebflowService.shared is always available, so no need to check
        
        WebflowService.shared.fetchStarsMapping { [weak self] mapping in
            DispatchQueue.main.async {
                self?.starsMapping = mapping
            }
        }
    }
    
    func fetchArticle(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            completion(.failure(NSError(domain: "Invalid ID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Article ID is empty"])))
            return
        }
        
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
                print(String(data: data, encoding: .utf8) ?? "Invalid JSON")
                completion(.failure(error))
            }
        }.resume()
    }
    
    func author(for article: Article) -> Author? {
        // If no authors loaded, return nil to prevent crashes
        guard !authors.isEmpty else {
            return nil
        }
        
        guard let authorRef = article.authorID else { return nil }
        return authors.first(where: { $0.id == authorRef })
    }
    

    
    func loadFullArticle(with id: String) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            print("❌ Article ID is empty")
            return
        }
        
        // Safety check: ensure we have articles loaded
        guard !articles.isEmpty else {
            print("❌ No articles loaded yet")
            return
        }
        
        // Safety check: avoid loading the same article multiple times or if already loading or queued
        if let existingArticle = articles.first(where: { $0.id == id }),
           existingArticle.author != nil {
            print("✅ Article \(id) already has author, skipping")
            return
        }
        
        if loadingArticles.contains(id) {
            print("🔄 Article \(id) already being loaded, skipping")
            return
        }
        
        if pendingLoads.contains(id) {
            print("🔄 Article \(id) already queued for loading, skipping")
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
                        print("❌ Failed to fetch author: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self.fullArticle = updatedArticle
                        self.updateArticleInAllArrays(updatedArticle)
                        self.finishLoadingArticle(id)
                    }
                }

            case .failure(let error):
                print("❌ Failed to fetch article: \(error.localizedDescription)")
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
            print("❌ Cannot update article with invalid ID")
            return
        }
        
        func replace(in array: inout [Article]) {
            // Safety check: ensure we have a valid article ID
            guard !updated.id.isEmpty else {
                print("❌ Cannot replace article with invalid ID")
                return
            }
            
            if let index = array.firstIndex(where: { $0.id == updated.id }) {
                array[index] = updated
                // print("✅ Updated article at index \(index)")
            } else {
                print("ℹ️ Article not found in array for replacement")
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
            print("❌ Cannot toggle favorite for invalid article")
            return 
        }
        
        let wasFavorite = isFavorite(article)
        
        if wasFavorite {
            favorites.removeAll { $0.id == article.id }
        } else {
            favorites.append(article)
        }
        
        // Always save to UserDefaults for local persistence (works for logged out users)
        saveFavorites()
        
        // Sync with Firebase and UserManager only if user is logged in
        if let user = UserManager.shared.currentUser {
            // Sync with Firebase
            Task {
                do {
                    try await FirestoreService.shared.toggleFavorite(article, isFavorite: !wasFavorite)
                    print("✅ Firebase sync successful for article: \(article.name ?? "Unknown")")
                } catch {
                    print("❌ Firebase sync failed: \(error.localizedDescription)")
                    // Note: We don't revert local change for logged-in users to avoid confusion
                    // The local change is already saved and will be synced later
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
        } else {
            print("ℹ️ User not logged in - favorites saved locally only")
        }
    }
    
    private func loadFavorites() {
        // Safety check: ensure we're not already loading favorites
        guard !isLoadingFavorites else {
            print("❌ Already loading favorites")
            return
        }
        
        // First try to load from UserDefaults for fast access
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([Article].self, from: data) {
            favorites = decoded
        }
        
        // Then sync with Firebase if user is logged in
        Task { [weak self] in
            await self?.syncFavoritesWithFirestore()
        }
    }
    
    private func syncFavoritesWithFirestore() async {
        // Safety check: ensure we're not already syncing
        guard !isLoadingFavorites else {
            print("❌ Already syncing favorites")
            return
        }
        
        guard UserManager.shared.currentUser != nil else {
            print("ℹ️ No user logged in - using local favorites only")
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
                self.isLoadingFavorites = false
                // print("✅ Synced favorites: \(self.favorites.count) total")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.favoriteError = "Kunne ikke synkronisere favoritter: \(error.localizedDescription)"
                self?.isLoadingFavorites = false
                print("❌ Failed to sync with Firebase: \(error.localizedDescription)")
            }
        }
    }
    
    private func reloadFavorites() {
        // Safety check: ensure we're not already syncing
        guard !isLoadingFavorites else {
            print("❌ Already syncing favorites")
            return
        }
        
        Task { [weak self] in
            await self?.syncFavoritesWithFirestore()
        }
    }
    
    private func saveFavorites() {
        // Safety check: ensure we have valid favorites to save
        guard !favorites.isEmpty else {
            print("ℹ️ No favorites to save")
            return
        }
        
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
            // print("✅ Saved \(favorites.count) favorites to UserDefaults")
        } else {
            print("❌ Failed to encode favorites")
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
    private var heroArticles: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            return []
        }
        return Array(articles.prefix(5))
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
        
        // Popular articles - exclude hero and anmeldelser articles
        let allArticles = Array(articles.prefix(25)) // Take more articles to ensure we have enough after filtering
        let filtered = excludeArticles(withIDs: Array(usedArticleIDs), from: allArticles)
        let result = Array(filtered.prefix(6)) // Ensure at least 5-6 articles
        
        // Fallback: if we don't have enough articles, use some general articles
        if result.count < 5 {
            let fallbackArticles = Array(articles.prefix(20))
            return Array(fallbackArticles.prefix(6))
        }
        
        return result
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
        
        // Sort by date (newest first) and take first 10
        let sortedArticles = excludedArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            
            return date1 > date2
        }.prefix(10).map { $0 }
        
        return sortedArticles
    }

    var musicArticles: [Article] {
        // Find the music section ID from the sections we fetched
        let musicSectionID = sections.first(where: { $0.name.lowercased().contains("musik") })?.id
        
        // print("[DEBUG] Music section ID found: \(musicSectionID ?? "nil")")
        // print("[DEBUG] Available sections: \(sections.map { "\($0.name) (ID: \($0.id))" })")
        
        // Filter articles by music section
        let musicArticles = articles.filter { article in
            // Check if article belongs to music section
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == musicSectionID
            }
            return false
        }
        
        // print("[DEBUG] Found \(musicArticles.count) music articles using section-based filtering")
        
        // If no music articles found, use some general articles as fallback
        if musicArticles.isEmpty {
            // print("[DEBUG] No music articles found, using fallback articles")
            let fallbackArticles = Array(articles.prefix(20))
            return excludeArticles(withIDs: Array(usedArticleIDs), from: fallbackArticles).prefix(6).map { $0 }
        }
        
        // Music articles - exclude hero and anmeldelser articles, then sort by date (newest first)
        let excludedArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: Array(musicArticles.prefix(20)))
        return excludedArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }.prefix(6).map { $0 }
    }
    
    var kulturArticles: [Article] {
        // Find the kultur section ID from the sections we fetched
        let kulturSectionID = sections.first(where: { $0.name.lowercased().contains("kultur") })?.id
        
        // print("[DEBUG] Kultur section ID found: \(kulturSectionID ?? "nil")")
        
        // Filter articles by kultur section
        let kulturArticles = articles.filter { article in
            // Check if article belongs to kultur section
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == kulturSectionID
            }
            return false
        }
        
        // print("[DEBUG] Found \(kulturArticles.count) kultur articles using section-based filtering")
        
        // If no kultur articles found, use some general articles as fallback
        if kulturArticles.isEmpty {
            // print("[DEBUG] No kultur articles found, using fallback articles")
            let fallbackArticles = Array(articles.prefix(20))
            return excludeArticles(withIDs: Array(usedArticleIDs), from: fallbackArticles).prefix(6).map { $0 }
        }
        
        // Kultur articles - exclude hero and anmeldelser articles, then sort by date (newest first)
        let excludedArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: Array(kulturArticles.prefix(20)))
        let finalKulturArticles = excludedArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }.prefix(6).map { $0 }
        // print("[DEBUG] Final kultur articles: \(finalKulturArticles.map { $0.name ?? "Unknown" })")
        return finalKulturArticles
    }
    
    var serierFilmArticles: [Article] {
        // Find the serier & film section ID from the sections we fetched
        let serierFilmSectionID = sections.first(where: { $0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film") })?.id
        
        // print("[DEBUG] Serier & Film section ID found: \(serierFilmSectionID ?? "nil")")
        
        // Filter articles by serier & film section
        let serierFilmArticles = articles.filter { article in
            // Check if article belongs to serier & film section
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == serierFilmSectionID
            }
            return false
        }
        
        // print("[DEBUG] Found \(serierFilmArticles.count) serier & film articles using section-based filtering")
        
        // If no serier & film articles found, use some general articles as fallback
        if serierFilmArticles.isEmpty {
            // print("[DEBUG] No serier & film articles found, using fallback articles")
            let fallbackArticles = Array(articles.prefix(20))
            return excludeArticles(withIDs: Array(usedArticleIDs), from: fallbackArticles).prefix(6).map { $0 }
        }
        
        // Serier & Film articles - exclude hero and anmeldelser articles, then sort by date (newest first)
        let excludedArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: Array(serierFilmArticles.prefix(20)))
        let finalSerierFilmArticles = excludedArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }.prefix(6).map { $0 }
        // print("[DEBUG] Final serier & film articles: \(finalSerierFilmArticles.map { $0.name ?? "Unknown" })")
        return finalSerierFilmArticles
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
            var mutableArticle = article
            let date = mutableArticle.publishedDate ?? mutableArticle.createdDate
            guard let date, date <= now else { return nil }
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
        // If no sections loaded, return empty array to prevent crashes
        guard !sections.isEmpty else {
            // print("[DEBUG] No sections loaded, returning empty allMusicArticles")
            return []
        }
        
        // Find the music section ID from the sections we fetched
        let musicSectionID = sections.first(where: { $0.name.lowercased().contains("musik") })?.id
        
        // Filter articles by music section
        let musicArticles = articles.filter { article in
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == musicSectionID
            }
            return false
        }
        
        // Sort by date (newest first)
        let sortedArticles = musicArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }
        
        return sortedArticles
    }
    
    var allKulturArticles: [Article] {
        // If no sections loaded, return empty array to prevent crashes
        guard !sections.isEmpty else {
            // print("[DEBUG] No sections loaded, returning empty allKulturArticles")
            return []
        }
        
        // Find the kultur section ID from the sections we fetched
        let kulturSectionID = sections.first(where: { $0.name.lowercased().contains("kultur") })?.id
        
        // Filter articles by kultur section
        let kulturArticles = articles.filter { article in
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == kulturSectionID
            }
            return false
        }
        
        // Sort by date (newest first)
        return kulturArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var allSerierFilmArticles: [Article] {
        // If no sections loaded, return empty array to prevent crashes
        guard !sections.isEmpty else {
            // print("[DEBUG] No sections loaded, returning empty allSerierFilmArticles")
            return []
        }
        
        // Find the serier & film section ID from the sections we fetched
        let serierFilmSectionID = sections.first(where: { $0.name.lowercased().contains("serier") || $0.name.lowercased().contains("film") })?.id
        
        // Filter articles by serier & film section
        let serierFilmArticles = articles.filter { article in
            if let articleSection = findSectionForArticle(article) {
                return articleSection.id == serierFilmSectionID
            }
            return false
        }
        
        // Sort by date (newest first)
        return serierFilmArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }
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
        
        // Sort by date (newest first)
        return filteredArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var allPopularArticles: [Article] {
        // If no articles loaded, return empty array to prevent crashes
        guard !articles.isEmpty else {
            // print("[DEBUG] No articles loaded, returning empty allPopularArticles")
            return []
        }
        
        // Get all popular articles (not just first 6)
        let filteredArticles = excludeArticles(withIDs: Array(usedArticleIDs), from: articles)
        
        // Sort by date (newest first)
        return filteredArticles.sorted { article1, article2 in
            var mutableArticle1 = article1
            var mutableArticle2 = article2
            let date1 = mutableArticle1.publishedDate ?? mutableArticle1.createdDate ?? Date.distantPast
            let date2 = mutableArticle2.publishedDate ?? mutableArticle2.createdDate ?? Date.distantPast
            return date1 > date2
        }
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
            var mutableArticle = article
            let date = mutableArticle.publishedDate ?? mutableArticle.createdDate
            guard let date, date <= now else { return nil }
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
        print("📱 Navigating to article from notification: \(articleId)")
        
        // First check if article is already loaded
        if let existingArticle = articles.first(where: { $0.id == articleId }) {
            print("📱 Article already loaded, navigating directly")
            navigateToArticle(existingArticle)
            return
        }
        
        // If not loaded, fetch it first
        fetchAndNavigateToArticle(articleId: articleId)
    }
    
    /// Fetch article and navigate to it
    private func fetchAndNavigateToArticle(articleId: String) {
        print("📱 Fetching article for navigation: \(articleId)")
        
        fetchArticle(by: articleId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let article):
                print("📱 Article fetched successfully, navigating to: \(article.name ?? "Unknown")")
                self.navigateToArticle(article)
            case .failure(let error):
                print("❌ Failed to fetch article for navigation: \(error.localizedDescription)")
            }
        }
    }
    
    /// Navigate to article using NavigationCoordinator
    private func navigateToArticle(_ article: Article) {
        // Post notification to NavigationCoordinator
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToArticle"),
            object: nil,
            userInfo: ["article": article]
        )
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

