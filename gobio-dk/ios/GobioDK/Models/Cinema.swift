import Foundation

struct CinemaChain: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let slug: String
    let logoURL: String?
    let websiteURL: String
    let bookingBaseURL: String?
}

struct Cinema: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let chainId: String?
    let chainName: String?
    let name: String
    let slug: String
    let city: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let websiteURL: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CinemaChain {
    static let nordiskFilm = CinemaChain(
        id: "nordisk-film",
        name: "Nordisk Film Biografer",
        slug: "nordisk-film",
        logoURL: nil,
        websiteURL: "https://www.nfbio.dk",
        bookingBaseURL: "https://www.nfbio.dk/film/"
    )
    
    static let vue = CinemaChain(
        id: "vue",
        name: "Vue",
        slug: "vue",
        logoURL: nil,
        websiteURL: "https://www.cinemaxx.dk",
        bookingBaseURL: "https://www.cinemaxx.dk/film/"
    )
    
    static let allChains: [CinemaChain] = [nordiskFilm, vue]
}

extension Cinema {
    static var sample: Cinema {
        Cinema(
            id: "imperial",
            chainId: "nordisk-film",
            chainName: "Nordisk Film Biografer",
            name: "Imperial",
            slug: "imperial",
            city: "København",
            address: "Ved Vesterport 4, 1612 København V",
            latitude: 55.6761,
            longitude: 12.5683,
            phone: nil,
            websiteURL: "https://www.nfbio.dk"
        )
    }
}
