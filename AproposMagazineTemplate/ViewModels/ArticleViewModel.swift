import Foundation

@MainActor
class ArticleViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var aiRecommendations: [Article] = []
    @Published var isLoading: Bool = false
    @Published var fetchError: String? = nil
    @Published var isLoadingAI: Bool = false
    @Published var aiError: String? = nil
    @Published var favorites: [Article] = []
    
    private let favoritesKey = "favoriteArticlesJSON"
    
    init() {
        loadFavorites()
        fetchArticles()
        fetchAIRecommendations()
    }
    
    func fetchArticles() {
        isLoading = true
        fetchError = nil
        WebflowService.shared.fetchArticles { [weak self] articles in
            guard let self = self else { return }
            if articles.isEmpty {
                self.fetchError = "Kunne ikke hente artikler fra Webflow. Tjek din internetforbindelse eller prøv igen senere."
            }
            self.articles = articles
            self.isLoading = false
        }
    }
    
    func fetchAIRecommendations() {
        isLoadingAI = true
        aiError = nil
        let readTitles = articles.map { $0.title }
        OpenAIManager.shared.getRecommendations(for: readTitles) { [weak self] recommendations in
            guard let self = self else { return }
            if recommendations.isEmpty {
                self.aiError = "Kunne ikke hente AI-anbefalinger. Prøv igen senere."
                self.aiRecommendations = [
                    Article(title: "Fallback: Kunst i København", intro: "Oplev byens skjulte gallerier.", content: "En guide til kunstoplevelser...", imageURL: "", rating: 5),
                    Article(title: "Fallback: Musik for alle", intro: "Fra jazz til elektronisk.", content: "Musikscenen i Danmark...", imageURL: "", rating: 4),
                    Article(title: "Fallback: Litteraturens nye stemmer", intro: "Mød morgendagens forfattere.", content: "Interview med unge forfattere...", imageURL: "", rating: 5)
                ]
            } else {
                self.aiRecommendations = recommendations
            }
            self.isLoadingAI = false
        }
    }
    
    func toggleFavorite(for article: Article) {
        if let index = favorites.firstIndex(where: { $0.title == article.title }) {
            favorites.remove(at: index)
        } else {
            favorites.append(article)
        }
        saveFavorites()
    }
    
    func isFavorite(_ article: Article) -> Bool {
        favorites.contains(where: { $0.title == article.title })
    }
    
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey) else { return }
        if let decoded = try? JSONDecoder().decode([Article].self, from: data) {
            favorites = decoded
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
