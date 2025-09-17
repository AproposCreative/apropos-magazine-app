import SwiftUI

struct CategoryQuickAccessView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Binding var selectedCategory: String
    let showAllOption: Bool
    
    init(selectedCategory: Binding<String>, showAllOption: Bool = true) {
        self._selectedCategory = selectedCategory
        self.showAllOption = showAllOption
    }
    
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableCategories, id: \.self) { category in
                    CategoryChipView(
                        title: category,
                        isSelected: selectedCategory == category,
                        count: category == "Alle" ? nil : viewModel.articles(for: category).count
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct CategoryChipView: View {
    let title: String
    let isSelected: Bool
    let count: Int?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CategoryQuickAccessView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryQuickAccessView(selectedCategory: .constant("Alle"))
            .environmentObject(ArticleViewModel())
            .padding()
    }
}
