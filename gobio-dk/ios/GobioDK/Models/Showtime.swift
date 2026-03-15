import Foundation

struct Showtime: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let movieId: Int
    let cinemaId: String
    let cinemaName: String
    let chainName: String
    let city: String
    let startsAt: Date
    let format: String?
    let language: String?
    let subtitles: String?
    let is3D: Bool
    let isIMAX: Bool
    let bookingURL: String?
    let hallName: String?
    
    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startsAt)
    }
    
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateStyle = .medium
        return formatter.string(from: startsAt)
    }
    
    var dayFormatted: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startsAt) {
            return "I dag"
        } else if calendar.isDateInTomorrow(startsAt) {
            return "I morgen"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "da_DK")
            formatter.dateFormat = "EEEE d. MMM"
            return formatter.string(from: startsAt).capitalized
        }
    }
    
    var formatBadges: [String] {
        var badges: [String] = []
        if isIMAX { badges.append("IMAX") }
        if is3D { badges.append("3D") }
        if let format, !is3D, !isIMAX, !format.isEmpty {
            badges.append(format)
        }
        return badges
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ShowtimeGroup: Identifiable {
    let id: String
    let cinema: Cinema
    let showtimes: [Showtime]
    
    init(cinema: Cinema, showtimes: [Showtime]) {
        self.id = cinema.id
        self.cinema = cinema
        self.showtimes = showtimes.sorted { $0.startsAt < $1.startsAt }
    }
}

extension Showtime {
    static var sample: Showtime {
        Showtime(
            id: "st-1",
            movieId: 912649,
            cinemaId: "imperial",
            cinemaName: "Imperial",
            chainName: "Nordisk Film Biografer",
            city: "København",
            startsAt: Date().addingTimeInterval(3600 * 3),
            format: "2D",
            language: "Engelsk",
            subtitles: "Dansk",
            is3D: false,
            isIMAX: false,
            bookingURL: "https://www.nfbio.dk/film/venom-the-last-dance",
            hallName: "Sal 1"
        )
    }
}
