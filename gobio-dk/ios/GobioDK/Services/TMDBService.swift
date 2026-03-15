import Foundation
import OSLog

class TMDBService {
    static let shared = TMDBService()
    
    private let baseURL = "https://api.themoviedb.org/3"
    private let logger = Logger(subsystem: "dk.gobio.app", category: "TMDBService")
    
    private var apiKey: String {
        SecureConfig.shared.tmdbAPIKey ?? ""
    }
    
    private init() {}
    
    private func makeRequest(path: String, params: [String: String] = [:]) -> URLRequest? {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else { return nil }
        
        var queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        queryItems.append(URLQueryItem(name: "language", value: "da-DK"))
        queryItems.append(URLQueryItem(name: "region", value: "DK"))
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        return request
    }
    
    // MARK: - Movie Lists
    
    func fetchNowPlaying(page: Int = 1) async throws -> TMDBMovieResponse {
        guard let request = makeRequest(path: "/movie/now_playing", params: ["page": String(page)]) else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
    }
    
    func fetchUpcoming(page: Int = 1) async throws -> TMDBMovieResponse {
        guard let request = makeRequest(path: "/movie/upcoming", params: ["page": String(page)]) else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
    }
    
    func fetchPopular(page: Int = 1) async throws -> TMDBMovieResponse {
        guard let request = makeRequest(path: "/movie/popular", params: ["page": String(page)]) else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
    }
    
    // MARK: - Movie Details
    
    func fetchMovieDetails(tmdbId: Int) async throws -> TMDBMovieDetail {
        guard let request = makeRequest(path: "/movie/\(tmdbId)", params: ["append_to_response": "videos,credits"]) else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBMovieDetail.self, from: data)
    }
    
    func fetchMovieVideos(tmdbId: Int) async throws -> TMDBVideoResponse {
        guard let request = makeRequest(path: "/movie/\(tmdbId)/videos") else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBVideoResponse.self, from: data)
    }
    
    // MARK: - Search
    
    func searchMovies(query: String, page: Int = 1) async throws -> TMDBMovieResponse {
        guard let request = makeRequest(path: "/search/movie", params: [
            "query": query,
            "page": String(page),
            "include_adult": "false"
        ]) else {
            throw TMDBError.invalidRequest
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
    }
    
    // MARK: - Conversion
    
    func toMovie(_ tmdbMovie: TMDBMovie, isUpcoming: Bool = false) -> Movie {
        Movie(
            id: tmdbMovie.id,
            tmdbId: tmdbMovie.id,
            title: tmdbMovie.title,
            originalTitle: tmdbMovie.original_title,
            overview: tmdbMovie.overview,
            posterPath: tmdbMovie.poster_path,
            backdropPath: tmdbMovie.backdrop_path,
            trailerYoutubeKey: nil,
            releaseDate: tmdbMovie.release_date,
            runtimeMinutes: tmdbMovie.runtime,
            genres: tmdbMovie.genres ?? (tmdbMovie.genre_ids ?? []).map { Genre(id: $0, name: genreName(for: $0)) },
            voteAverage: tmdbMovie.vote_average,
            voteCount: tmdbMovie.vote_count,
            isUpcoming: isUpcoming
        )
    }
    
    func toMovieDetail(_ detail: TMDBMovieDetail) -> MovieDetail {
        let trailer = detail.videos?.results.first(where: {
            $0.site == "YouTube" && $0.type == "Trailer" && $0.official
        }) ?? detail.videos?.results.first(where: {
            $0.site == "YouTube" && $0.type == "Trailer"
        }) ?? detail.videos?.results.first(where: {
            $0.site == "YouTube"
        })
        
        let director = detail.credits?.crew.first(where: { $0.job == "Director" })
        
        let cast = (detail.credits?.cast ?? []).prefix(10).map {
            CastMember(name: $0.name, character: $0.character, profilePath: $0.profile_path)
        }
        
        let movie = Movie(
            id: detail.id,
            tmdbId: detail.id,
            title: detail.title,
            originalTitle: detail.original_title,
            overview: detail.overview,
            posterPath: detail.poster_path,
            backdropPath: detail.backdrop_path,
            trailerYoutubeKey: trailer?.key,
            releaseDate: detail.release_date,
            runtimeMinutes: detail.runtime,
            genres: detail.genres ?? [],
            voteAverage: detail.vote_average,
            voteCount: detail.vote_count,
            isUpcoming: false
        )
        
        return MovieDetail(
            movie: movie,
            cast: Array(cast),
            director: director?.name,
            trailerYoutubeKey: trailer?.key
        )
    }
    
    private func genreName(for id: Int) -> String {
        let genreMap: [Int: String] = [
            28: "Action", 12: "Eventyr", 16: "Animation", 35: "Komedie",
            80: "Krimi", 99: "Dokumentar", 18: "Drama", 10751: "Familie",
            14: "Fantasy", 36: "Historie", 27: "Gyser", 10402: "Musik",
            9648: "Mysterium", 10749: "Romantik", 878: "Sci-Fi",
            10770: "TV-film", 53: "Thriller", 10752: "Krig", 37: "Western"
        ]
        return genreMap[id] ?? "Ukendt"
    }
}

// MARK: - TMDB API Response Types

struct TMDBMovieResponse: Codable {
    let page: Int
    let results: [TMDBMovie]
    let total_pages: Int
    let total_results: Int
}

struct TMDBMovie: Codable {
    let id: Int
    let title: String
    let original_title: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let runtime: Int?
    let vote_average: Double?
    let vote_count: Int?
    let genre_ids: [Int]?
    let genres: [Genre]?
}

struct TMDBMovieDetail: Codable {
    let id: Int
    let title: String
    let original_title: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let runtime: Int?
    let vote_average: Double?
    let vote_count: Int?
    let genres: [Genre]?
    let videos: TMDBVideoResponse?
    let credits: TMDBCredits?
}

struct TMDBVideoResponse: Codable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Codable {
    let key: String
    let site: String
    let type: String
    let name: String
    let official: Bool
}

struct TMDBCredits: Codable {
    let cast: [TMDBCast]
    let crew: [TMDBCrew]
}

struct TMDBCast: Codable {
    let name: String
    let character: String
    let profile_path: String?
}

struct TMDBCrew: Codable {
    let name: String
    let job: String
}

enum TMDBError: LocalizedError {
    case invalidRequest
    case noData
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Ugyldig API-forespørgsel"
        case .noData: return "Ingen data modtaget"
        case .decodingError: return "Kunne ikke behandle data"
        }
    }
}
