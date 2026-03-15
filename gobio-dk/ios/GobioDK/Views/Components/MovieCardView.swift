import SwiftUI
import SDWebImageSwiftUI

struct MovieCardView: View {
    let movie: Movie
    var showUpcomingBadge: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let posterURL = movie.posterURL {
                    WebImage(url: posterURL) { image in
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color(hex: "1A1A2E"))
                            .aspectRatio(2/3, contentMode: .fill)
                            .overlay {
                                Image(systemName: "film")
                                    .font(.title)
                                    .foregroundColor(.white.opacity(0.3))
                            }
                    }
                    .transition(.fade(duration: 0.3))
                } else {
                    Rectangle()
                        .fill(Color(hex: "1A1A2E"))
                        .aspectRatio(2/3, contentMode: .fill)
                        .overlay {
                            Image(systemName: "film")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.3))
                        }
                }
                
                if showUpcomingBadge && movie.isUpcoming {
                    Text("Kommer snart")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "F59E0B"))
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                        .padding(6)
                }
                
                if let rating = movie.ratingFormatted {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text(rating)
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(Color(hex: "F59E0B"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(6)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(movie.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            
            if !movie.genreNames.isEmpty {
                Text(movie.genreNames.prefix(2).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 140)
    }
}
