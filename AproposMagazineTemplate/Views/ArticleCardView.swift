import SwiftUI

struct ArticleCardView: View {
    let article: Article
    @EnvironmentObject var viewModel: ArticleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: article.imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.15)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                
                Button(action: {
                    viewModel.toggleFavorite(for: article)
                }) {
                    Image(systemName: viewModel.isFavorite(article) ? "heart.fill" : "heart")
                        .foregroundColor(viewModel.isFavorite(article) ? Color("Accent") : Color("Text").opacity(0.3))
                        .padding(8)
                        .background(Color("Background").opacity(0.85))
                        .clipShape(Circle())
                }
                .padding(10)
            }

            Text(article.title)
                .font(.title2.weight(.semibold))
                .foregroundColor(Color("Text"))
                .lineLimit(2)
                .padding(.bottom, 2)

            Text(article.intro)
                .font(.callout)
                .foregroundColor(Color("Text").opacity(0.8))
                .lineLimit(3)
                .padding(.bottom, 2)

            HStack {
                Text("★ \(article.rating)")
                    .font(.caption)
                    .foregroundColor(Color("Accent"))
                Spacer()
            }
        }
        .padding(20)
        .background(Color("Background"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
