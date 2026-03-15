import Foundation

struct Movie: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let tmdbId: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let trailerYoutubeKey: String?
    let releaseDate: String?
    let runtimeMinutes: Int?
    let genres: [Genre]
    let voteAverage: Double?
    let voteCount: Int?
    let isUpcoming: Bool
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
    
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }
    
    var thumbnailPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
    
    var trailerURL: URL? {
        guard let key = trailerYoutubeKey else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }
    
    var releaseDateFormatted: String? {
        guard let releaseDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: releaseDate) else { return nil }
        
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "da_DK")
        displayFormatter.dateStyle = .long
        return displayFormatter.string(from: date)
    }
    
    var releaseDateObject: Date? {
        guard let releaseDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: releaseDate)
    }
    
    var runtimeFormatted: String? {
        guard let minutes = runtimeMinutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)t \(mins)m" : "\(mins)m"
    }
    
    var ratingFormatted: String? {
        guard let rating = voteAverage, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }
    
    var genreNames: [String] {
        genres.map { $0.name }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(tmdbId)
    }
    
    static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.id == rhs.id && lhs.tmdbId == rhs.tmdbId
    }
}

struct Genre: Codable, Equatable, Hashable {
    let id: Int
    let name: String
}

struct CastMember: Codable, Equatable {
    let name: String
    let character: String
    let profilePath: String?
    
    var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }
}

struct MovieDetail: Codable {
    let movie: Movie
    let cast: [CastMember]
    let director: String?
    let trailerYoutubeKey: String?
}

extension Movie {
    static var sample: Movie {
        Movie(
            id: 912649,
            tmdbId: 912649,
            title: "Venom: The Last Dance",
            originalTitle: "Venom: The Last Dance",
            overview: "Eddie Brock og symbioten Venom er på flugt. Jagtet af begge deres verdener er duoen tvunget til at tage en ødelæggende beslutning.",
            posterPath: "/aosm8NMQ3UyoBVpSxyimorCQyNb.jpg",
            backdropPath: "/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
            trailerYoutubeKey: "HyIyd9joTTc",
            releaseDate: "2026-03-20",
            runtimeMinutes: 120,
            genres: [Genre(id: 28, name: "Action"), Genre(id: 878, name: "Sci-Fi")],
            voteAverage: 6.8,
            voteCount: 1500,
            isUpcoming: false
        )
    }
    
    static var sampleUpcoming: Movie {
        Movie(
            id: 1184918,
            tmdbId: 1184918,
            title: "The Wild Robot 2",
            originalTitle: "The Wild Robot 2",
            overview: "Fortsættelsen af den elskede animationsfilm om robotten Roz.",
            posterPath: nil,
            backdropPath: nil,
            trailerYoutubeKey: nil,
            releaseDate: "2026-06-15",
            runtimeMinutes: nil,
            genres: [Genre(id: 16, name: "Animation")],
            voteAverage: nil,
            voteCount: nil,
            isUpcoming: true
        )
    }
}
