import SwiftUI

struct CinemasView: View {
    @EnvironmentObject var viewModel: MovieViewModel
    
    private let cinemaData: [(chain: CinemaChain, cinemas: [Cinema])] = [
        (
            chain: .nordiskFilm,
            cinemas: [
                Cinema(id: "imperial", chainId: "nordisk-film", chainName: "Nordisk Film Biografer", name: "Imperial", slug: "imperial", city: "København", address: "Ved Vesterport 4, 1612 København V", latitude: 55.6761, longitude: 12.5683, phone: nil, websiteURL: "https://www.nfbio.dk"),
                Cinema(id: "palads", chainId: "nordisk-film", chainName: "Nordisk Film Biografer", name: "Palads", slug: "palads", city: "København", address: "Axeltorv 9, 1609 København V", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.nfbio.dk"),
                Cinema(id: "nfbio-aarhus", chainId: "nordisk-film", chainName: "Nordisk Film Biografer", name: "Aarhus C", slug: "aarhus-c", city: "Aarhus", address: "Søndergade 28, 8000 Aarhus C", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.nfbio.dk"),
                Cinema(id: "nfbio-odense", chainId: "nordisk-film", chainName: "Nordisk Film Biografer", name: "Odense", slug: "odense", city: "Odense", address: "Ørbækvej 75-77, 5220 Odense SØ", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.nfbio.dk"),
                Cinema(id: "nfbio-aalborg", chainId: "nordisk-film", chainName: "Nordisk Film Biografer", name: "Aalborg City Syd", slug: "aalborg-city-syd", city: "Aalborg", address: "Hobrovej 452, 9200 Aalborg SV", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.nfbio.dk"),
            ]
        ),
        (
            chain: .vue,
            cinemas: [
                Cinema(id: "vue-kbh", chainId: "vue", chainName: "Vue", name: "Vue København", slug: "vue-koebenhavn", city: "København", address: "Fisketorvet, Kalvebod Brygge 59", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.cinemaxx.dk"),
                Cinema(id: "vue-aarhus", chainId: "vue", chainName: "Vue", name: "Vue Aarhus", slug: "vue-aarhus", city: "Aarhus", address: "Bruuns Galleri, M.P. Bruuns Gade 25", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.cinemaxx.dk"),
                Cinema(id: "vue-odense", chainId: "vue", chainName: "Vue", name: "Vue Odense", slug: "vue-odense", city: "Odense", address: "Rosengårdcentret", latitude: nil, longitude: nil, phone: nil, websiteURL: "https://www.cinemaxx.dk"),
            ]
        ),
    ]
    
    var filteredCinemaData: [(chain: CinemaChain, cinemas: [Cinema])] {
        cinemaData.map { group in
            let filtered = group.cinemas.filter { $0.city == viewModel.selectedCity }
            return (chain: group.chain, cinemas: filtered.isEmpty ? group.cinemas : filtered)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Biografer")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    CitySelectorButton(selectedCity: viewModel.selectedCity) { city in
                        viewModel.updateCity(city)
                    }
                }
                .padding(.horizontal)
                
                ForEach(filteredCinemaData, id: \.chain.id) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.chain.name)
                            .font(.title3.bold())
                            .foregroundColor(Color(hex: "818CF8"))
                            .padding(.horizontal)
                        
                        ForEach(group.cinemas) { cinema in
                            CinemaRow(cinema: cinema)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(hex: "0F0F23"))
    }
}

struct CinemaRow: View {
    let cinema: Cinema
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Button {
            if let urlString = cinema.websiteURL, let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                    .foregroundColor(Color(hex: "6366F1"))
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(cinema.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    
                    if let address = cinema.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text(cinema.city)
                        .font(.caption2)
                        .foregroundColor(Color(hex: "6366F1").opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
}
