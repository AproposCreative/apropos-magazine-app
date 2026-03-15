import SwiftUI
import SDWebImageSwiftUI

struct WatchlistView: View {
    @EnvironmentObject var viewModel: MovieViewModel
    
    var body: some View {
        Group {
            if UserManager.shared.currentUser == nil {
                notLoggedInState
            } else if viewModel.watchlistMovies.isEmpty {
                emptyState
            } else {
                watchlistContent
            }
        }
        .background(Color(hex: "0F0F23"))
        .navigationTitle("Watchlist")
    }
    
    private var watchlistContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.watchlistMovies) { movie in
                    NavigationLink(value: movie) {
                        WatchlistRow(movie: movie) {
                            Task {
                                await viewModel.removeFromWatchlist(movie)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "6366F1").opacity(0.5))
            
            Text("Din watchlist er tom")
                .font(.title3.bold())
                .foregroundColor(.white)
            
            Text("Tilføj film til din watchlist og få besked når de har premiere i biografen.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                NavigationCoordinator.shared.navigateToTab(.home)
            } label: {
                Text("Udforsk film")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(hex: "6366F1"))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notLoggedInState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "6366F1").opacity(0.5))
            
            Text("Log ind for at se din watchlist")
                .font(.title3.bold())
                .foregroundColor(.white)
            
            Text("Opret en konto eller log ind for at gemme film og få premiere-notifikationer.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                NavigationCoordinator.shared.navigateToTab(.profile)
            } label: {
                Text("Gå til profil")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(hex: "6366F1"))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WatchlistRow: View {
    let movie: Movie
    let onRemove: () -> Void
    
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
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                
                if let date = movie.releaseDateFormatted {
                    HStack(spacing: 4) {
                        Image(systemName: movie.isUpcoming ? "clock.fill" : "checkmark.circle.fill")
                            .font(.caption2)
                        Text(movie.isUpcoming ? "Premiere: \(date)" : date)
                            .font(.caption2)
                    }
                    .foregroundColor(movie.isUpcoming ? Color(hex: "F59E0B") : .white.opacity(0.4))
                }
            }
            
            Spacer()
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "heart.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
