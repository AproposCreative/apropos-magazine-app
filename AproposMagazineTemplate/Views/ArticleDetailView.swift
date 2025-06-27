import SwiftUI

struct ArticleDetailView: View {
    let article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    
    // Manuel mapping fra option-ID til stjerner
    let optionMap: [String: String] = [
        "e209f692efa04411b0a8bd37266b9c46": "5",
        "1916f929878a66bc67f669e8699e7d06": "6",
        "96be449898a935fc069ed09fe2f72a29": "4",
        "ac332c20118cd638883a9137b3fbb4ed": "3",
        "b9a5ef043f1f58db54c41ed6fe3e746e": "1",
        "14fc811721e2560e3cce4c6584cd685a": "2"
        // Tilføj flere hvis nødvendigt
    ]
    
    // Helper til at vise stjerner
    func starString(from stjerner: String?, starsOptionID: String?) -> String {
        if let stjerner = stjerner, let count = Int(stjerner) {
            return String(repeating: "★", count: count)
        } else if let id = starsOptionID, let mapped = optionMap[id], let count = Int(mapped) {
            return String(repeating: "★", count: count)
        } else {
            return "Stjerner felt: mangler"
        }
    }
    
    var body: some View {
        // DEBUG: Print værdien af stjerner til konsollen
        DispatchQueue.main.async {
            print("DEBUG: article.stjerner = \(article.stjerner ?? "nil")")
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: {
                        viewModel.toggleFavorite(for: article)
                    }) {
                        Image(systemName: viewModel.isFavorite(article) ? "heart.fill" : "heart")
                            .foregroundColor(viewModel.isFavorite(article) ? Color("Accent") : Color("Text").opacity(0.3))
                            .padding(8)
                            .background(Color("Background").opacity(0.85))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(viewModel.isFavorite(article) ? "Fjern fra favoritter" : "Gem som favorit")
                    Spacer()
                }
                if !article.imageURL.isEmpty, let url = URL(string: article.imageURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.gray.opacity(0.15)
                    }
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(article.title)
                    .font(.title)
                    .bold()
                    .padding(.bottom, 2)
                // Vis stjerner grafisk eller via option-ID
                HStack(spacing: 12) {
                    Text(starString(from: article.stjerner, starsOptionID: article.options))
                        .font(.headline)
                        .foregroundColor(Color("Accent"))
                    if let stjerner = article.stjerner {
                        Text("Stjerner (tal): \(stjerner)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if let id = article.options, let mapped = optionMap[id] {
                        Text("Stjerner (option): \(mapped)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Stjerner (tal): mangler")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Text(article.intro)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Divider()
                Text(article.content)
                    .font(.body)
                    .foregroundColor(Color("Text"))
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Artikel")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color("Background"))
    }
} 