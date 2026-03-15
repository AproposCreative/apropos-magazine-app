import SwiftUI
import SDWebImageSwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var viewModel: MovieViewModel
    @State private var detail: MovieDetail?
    @State private var isInWatchlist = false
    @State private var showTrailer = false
    @Environment(\.openURL) var openURL
    
    var displayMovie: Movie {
        detail?.movie ?? movie
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                
                VStack(alignment: .leading, spacing: 20) {
                    titleSection
                    actionButtons
                    
                    if let overview = displayMovie.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }
                    
                    if let cast = detail?.cast, !cast.isEmpty {
                        castSection(cast)
                    }
                    
                    showtimesPlaceholder
                }
                .padding()
            }
        }
        .background(Color(hex: "0F0F23"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMovieDetail(tmdbId: movie.tmdbId)
            detail = viewModel.selectedMovieDetail
            isInWatchlist = viewModel.isInWatchlist(movie)
        }
        .sheet(isPresented: $showTrailer) {
            if let key = detail?.trailerYoutubeKey ?? movie.trailerYoutubeKey {
                TrailerView(youtubeKey: key, title: movie.title)
            }
        }
    }
    
    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            if let backdropURL = displayMovie.backdropURL {
                WebImage(url: backdropURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(hex: "1A1A2E"))
                        .aspectRatio(16/9, contentMode: .fill)
                }
            } else {
                Rectangle()
                    .fill(Color(hex: "1A1A2E"))
                    .aspectRatio(16/9, contentMode: .fill)
            }
            
            LinearGradient(
                colors: [.clear, Color(hex: "0F0F23")],
                startPoint: .top,
                endPoint: .bottom
            )
            
            if detail?.trailerYoutubeKey != nil || movie.trailerYoutubeKey != nil {
                Button {
                    showTrailer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Se trailer")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(hex: "6366F1"))
                    .clipShape(Capsule())
                }
                .padding()
            }
        }
        .frame(height: 250)
        .clipped()
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayMovie.title)
                .font(.title.bold())
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                if let rating = displayMovie.ratingFormatted {
                    Label(rating, systemImage: "star.fill")
                        .foregroundColor(Color(hex: "F59E0B"))
                }
                
                if !displayMovie.genreNames.isEmpty {
                    Text(displayMovie.genreNames.joined(separator: " · "))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                if let runtime = displayMovie.runtimeFormatted {
                    Text(runtime)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .font(.subheadline)
            
            if let date = displayMovie.releaseDateFormatted {
                Text("Premiere: \(date)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            if let director = detail?.director {
                Text("Instruktør: \(director)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if isInWatchlist {
                        await viewModel.removeFromWatchlist(movie)
                    } else {
                        await viewModel.addToWatchlist(movie)
                    }
                    isInWatchlist.toggle()
                }
            } label: {
                Label(
                    isInWatchlist ? "I din watchlist" : "Tilføj til watchlist",
                    systemImage: isInWatchlist ? "heart.fill" : "heart"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isInWatchlist ? Color(hex: "F59E0B") : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isInWatchlist
                    ? Color(hex: "F59E0B").opacity(0.15)
                    : Color.white.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handling")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(overview)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
    }
    
    private func castSection(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medvirkende")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cast, id: \.name) { member in
                        VStack(spacing: 6) {
                            if let profileURL = member.profileURL {
                                WebImage(url: profileURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color(hex: "1A1A2E"))
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color(hex: "1A1A2E"))
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                            }
                            
                            Text(member.name)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(member.character)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        .frame(width: 80)
                    }
                }
            }
        }
    }
    
    private var showtimesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spilletider i \(viewModel.selectedCity)")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.title)
                    .foregroundColor(Color(hex: "6366F1"))
                
                Text("Spilletider kommer snart")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                
                Text("Vi arbejder på at forbinde til biografernes data. Snart kan du se spilletider fra alle danske biografer her.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
