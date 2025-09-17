import SwiftUI

struct ReadingStatsView: View {
    let stats: ReadingStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Læsestatistik")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Læste artikler",
                    value: "\(stats.totalArticlesRead)",
                    icon: "book.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Bookmarks",
                    value: "\(stats.totalBookmarks)",
                    icon: "bookmark.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Favorit kategorier",
                    value: "\(stats.favoriteCategories)",
                    icon: "tag.fill",
                    color: .green
                )
                
                StatCard(
                    title: "Favorit forfattere",
                    value: "\(stats.favoriteAuthors)",
                    icon: "person.fill",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
