import SwiftUI

struct CategoryFilterView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Binding var selectedCategory: String
    let showAllOption: Bool
    let title: String
    
    init(selectedCategory: Binding<String>, showAllOption: Bool = true, title: String = "Kategori") {
        self._selectedCategory = selectedCategory
        self.showAllOption = showAllOption
        self.title = title
    }
    
    // Get available categories based on current articles
    private var availableCategories: [String] {
        let categories = viewModel.topics
            .filter { topic in
                viewModel.articles.contains { article in
                    let topicName = viewModel.topics.first(where: { $0.id == article.topicID })?.name ?? ""
                    return topicName.trimmingCharacters(in: .whitespacesAndNewlines) == topic.name
                }
            }
            .map { $0.name }
            .sorted()
        
        return showAllOption ? ["Alle"] + categories : categories
    }
    
    var body: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { category in
                Button(action: { selectedCategory = category }) {
                    HStack {
                        Text(category)
                        if selectedCategory == category {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedCategory == "Alle" ? "Alle kategorier" : selectedCategory)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct CategoryFilterView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryFilterView(selectedCategory: .constant("Alle"))
            .environmentObject(ArticleViewModel())
            .padding()
    }
}
