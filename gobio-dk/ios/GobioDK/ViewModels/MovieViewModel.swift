import Foundation
import SwiftUI
import OSLog
import FirebaseFirestore

@MainActor
class MovieViewModel: ObservableObject {
    @Published var nowPlayingMovies: [Movie] = []
    @Published var upcomingMovies: [Movie] = []
    @Published var popularMovies: [Movie] = []
    @Published var searchResults: [Movie] = []
    @Published var watchlistMovies: [Movie] = []
    
    @Published var selectedMovieDetail: MovieDetail?
    
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    
    @Published var selectedCity: String = "København"
    @Published var searchQuery: String = ""
    
    private let tmdb = TMDBService.shared
    private let firestore = FirestoreService.shared
    private let logger = Logger(subsystem: "dk.gobio.app", category: "MovieViewModel")
    
    private var watchlistListener: ListenerRegistration?
    
    init() {
        if let savedCity = UserDefaults.standard.string(forKey: "selectedCity") {
            selectedCity = savedCity
        }
    }
    
    deinit {
        watchlistListener?.remove()
    }
    
    // MARK: - Fetching Movies
    
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let nowPlaying = tmdb.fetchNowPlaying()
            async let upcoming = tmdb.fetchUpcoming()
            async let popular = tmdb.fetchPopular()
            
            let (nowPlayingResult, upcomingResult, popularResult) = try await (nowPlaying, upcoming, popular)
            
            nowPlayingMovies = nowPlayingResult.results.map { tmdb.toMovie($0) }
            upcomingMovies = upcomingResult.results.map { tmdb.toMovie($0, isUpcoming: true) }
            popularMovies = popularResult.results.map { tmdb.toMovie($0) }
            
            logger.info("Indlæst \(self.nowPlayingMovies.count) aktuelle, \(self.upcomingMovies.count) kommende, \(self.popularMovies.count) populære film")
        } catch {
            errorMessage = "Kunne ikke hente film: \(error.localizedDescription)"
            logger.error("Fejl ved hentning af film: \(error.localizedDescription, privacy: .public)")
        }
        
        isLoading = false
    }
    
    func loadMovieDetail(tmdbId: Int) async {
        do {
            let detail = try await tmdb.fetchMovieDetails(tmdbId: tmdbId)
            selectedMovieDetail = tmdb.toMovieDetail(detail)
        } catch {
            logger.error("Fejl ved hentning af filmdetaljer: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Search
    
    func searchMovies() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            let result = try await tmdb.searchMovies(query: query)
            searchResults = result.results.map { tmdb.toMovie($0) }
        } catch {
            logger.error("Søgefejl: \(error.localizedDescription, privacy: .public)")
        }
        
        isSearching = false
    }
    
    // MARK: - Watchlist
    
    func setupWatchlistListener() {
        watchlistListener?.remove()
        watchlistListener = firestore.listenWatchlist { [weak self] movies in
            Task { @MainActor in
                self?.watchlistMovies = movies
            }
        }
    }
    
    func addToWatchlist(_ movie: Movie) async {
        do {
            try await firestore.addToWatchlist(movie)
            
            if movie.isUpcoming {
                NotificationService.shared.schedulePremiereReminder(movie: movie)
                NotificationService.shared.subscribeToPremiereNotifications(for: movie.tmdbId)
            }
            
            logger.info("Tilføjet til watchlist: \(movie.title, privacy: .public)")
        } catch {
            logger.error("Fejl ved tilføjelse til watchlist: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func removeFromWatchlist(_ movie: Movie) async {
        do {
            try await firestore.removeFromWatchlist(tmdbId: movie.tmdbId)
            
            NotificationService.shared.cancelPremiereReminder(for: movie.tmdbId)
            NotificationService.shared.unsubscribeFromPremiereNotifications(for: movie.tmdbId)
            
            logger.info("Fjernet fra watchlist: \(movie.title, privacy: .public)")
        } catch {
            logger.error("Fejl ved fjernelse fra watchlist: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func isInWatchlist(_ movie: Movie) -> Bool {
        watchlistMovies.contains(where: { $0.tmdbId == movie.tmdbId })
    }
    
    // MARK: - City
    
    func updateCity(_ city: String) {
        selectedCity = city
        UserDefaults.standard.set(city, forKey: "selectedCity")
    }
}
