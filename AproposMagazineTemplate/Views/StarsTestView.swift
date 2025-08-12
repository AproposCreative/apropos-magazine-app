import SwiftUI

struct StarsTestView: View {
    @State private var articles: [Article] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            List(articles, id: \ .title) { article in
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.headline)
                    HStack(spacing: 4) {
                        if let label = article.stjerner {
                            Text(label)
                                .foregroundColor(.yellow)
                        } else {
                            Text("Ingen stjerner")
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("Raw stjerner value: \(article.stjerner ?? "nil")")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Stars Test")
            .overlay(
                Group {
                    if isLoading {
                        ProgressView("Loading articles...")
                    }
                }
            )
            .onAppear {
                isLoading = true
                WebflowService.shared.fetchArticles { fetchedArticles in
                    self.articles = fetchedArticles
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    StarsTestView()
} 