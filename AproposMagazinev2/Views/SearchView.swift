import SwiftUI

struct SearchView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @State private var searchText = ""

    var filteredArticles: [Article] {
        if searchText.isEmpty {
            return viewModel.articles
        } else {
            return viewModel.articles.filter { article in
                let title = article.name?.lowercased() ?? ""
                let intro = article.intro?.lowercased() ?? ""
                let searchQuery = searchText.lowercased()
                return title.contains(searchQuery) || intro.contains(searchQuery)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Søg artikler...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding([.horizontal, .top])

                if filteredArticles.isEmpty {
                    Spacer()
                    Text("Ingen artikler matcher din søgning.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(filteredArticles) { article in
                        NavigationLink(destination: ArticleDetailView(article: article).environmentObject(viewModel)) {
                            HStack(alignment: .top, spacing: 12) {
                                var mutableArticle = article
                                let thumbnailURL = mutableArticle.thumbnailURL
                                if let url = URL(string: thumbnailURL), !thumbnailURL.isEmpty {
                                    AsyncImage(url: url) { image in
                                        image.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipped()
                                            .cornerRadius(8)
                                    } placeholder: {
                                        Color.gray.frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(article.name ?? "")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(article.intro ?? "")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Søg")
        }
    }
}

#Preview {
    SearchView().environmentObject(ArticleViewModel())
} 