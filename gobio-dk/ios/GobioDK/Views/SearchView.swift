import SwiftUI
import SDWebImageSwiftUI

struct SearchView: View {
    @EnvironmentObject var viewModel: MovieViewModel
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            searchResults
        }
        .background(Color(hex: "0F0F23"))
        .navigationTitle("Søg film")
        .searchable(text: $searchText, prompt: "Søg efter film...")
        .onChange(of: searchText) { _, newValue in
            viewModel.searchQuery = newValue
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if viewModel.searchQuery == newValue {
                    await viewModel.searchMovies()
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isSearching {
            ProgressView("Søger...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchText.isEmpty {
            emptyState
        } else if viewModel.searchResults.isEmpty {
            noResults
        } else {
            List(viewModel.searchResults) { movie in
                NavigationLink(value: movie) {
                    SearchResultRow(movie: movie)
                }
                .listRowBackground(Color(hex: "1A1A2E"))
            }
            .listStyle(.plain)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "6366F1").opacity(0.5))
            
            Text("Søg efter film")
                .font(.title3.bold())
                .foregroundColor(.white)
            
            Text("Find film der vises i danske biografer og se trailers, anmeldelser og spilletider.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.title)
                .foregroundColor(.white.opacity(0.3))
            
            Text("Ingen resultater for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchResultRow: View {
    let movie: Movie
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = movie.thumbnailPosterURL {
                WebImage(url: posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(hex: "1A1A2E"))
                }
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                
                if !movie.genreNames.isEmpty {
                    Text(movie.genreNames.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                HStack(spacing: 8) {
                    if let rating = movie.ratingFormatted {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    
                    if let date = movie.releaseDateFormatted {
                        Text(date)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
