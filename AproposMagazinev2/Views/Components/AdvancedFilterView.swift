import SwiftUI

// MARK: - Filter Models

struct ArticleFilter {
    var dateRange: DateRange = .all
    var categories: Set<String> = []
    var authors: Set<String> = []
    var rating: Double = 0.0
    var searchQuery: String = ""
    var sortBy: SortOption = .newest
    
    var isActive: Bool {
        return dateRange != .all ||
               !categories.isEmpty ||
               !authors.isEmpty ||
               rating > 0.0 ||
               !searchQuery.isEmpty
    }
    
    mutating func reset() {
        dateRange = .all
        categories.removeAll()
        authors.removeAll()
        rating = 0.0
        searchQuery = ""
        sortBy = .newest
    }
}

enum DateRange: String, CaseIterable {
    case all = "all"
    case today = "today"
    case thisWeek = "thisWeek"
    case thisMonth = "thisMonth"
    case lastMonth = "lastMonth"
    case last3Months = "last3Months"
    case last6Months = "last6Months"
    case lastYear = "lastYear"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .all: return "Alle datoer"
        case .today: return "I dag"
        case .thisWeek: return "Denne uge"
        case .thisMonth: return "Denne måned"
        case .lastMonth: return "Sidste måned"
        case .last3Months: return "Sidste 3 måneder"
        case .last6Months: return "Sidste 6 måneder"
        case .lastYear: return "Sidste år"
        case .custom: return "Tilpasset"
        }
    }
    
    var dateInterval: DateInterval? {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .all:
            return nil
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return DateInterval(start: startOfDay, end: endOfDay)
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return DateInterval(start: startOfWeek, end: now)
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)!.start
            return DateInterval(start: startOfMonth, end: now)
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let startOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)!.start
            let startOfThisMonth = calendar.dateInterval(of: .month, for: now)!.start
            return DateInterval(start: startOfLastMonth, end: startOfThisMonth)
        case .last3Months:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
            return DateInterval(start: threeMonthsAgo, end: now)
        case .last6Months:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
            return DateInterval(start: sixMonthsAgo, end: now)
        case .lastYear:
            let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
            return DateInterval(start: lastYear, end: now)
        case .custom:
            return nil
        }
    }
}

enum SortOption: String, CaseIterable {
    case newest = "newest"
    case oldest = "oldest"
    case rating = "rating"
    case title = "title"
    case author = "author"
    
    var displayName: String {
        switch self {
        case .newest: return "Nyeste først"
        case .oldest: return "Ældste først"
        case .rating: return "Højeste rating"
        case .title: return "Titel A-Z"
        case .author: return "Forfatter A-Z"
        }
    }
}

// MARK: - Advanced Filter View

struct AdvancedFilterView: View {
    @Binding var filter: ArticleFilter
    let articles: [Article]
    let onApply: ([Article]) -> Void
    let onReset: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var tempFilter: ArticleFilter
    @State private var customDateRange: DateInterval?
    @State private var showCustomDatePicker = false
    
    init(
        filter: Binding<ArticleFilter>,
        articles: [Article],
        onApply: @escaping ([Article]) -> Void,
        onReset: @escaping () -> Void
    ) {
        self._filter = filter
        self.articles = articles
        self.onApply = onApply
        self.onReset = onReset
        self._tempFilter = State(initialValue: filter.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Search
                        searchSection
                        
                        // Date Range
                        dateRangeSection
                        
                        // Categories
                        categoriesSection
                        
                        // Authors
                        authorsSection
                        
                        // Rating
                        ratingSection
                        
                        // Sort Options
                        sortSection
                        
                        // Results Preview
                        resultsPreviewSection
                    }
                    .padding()
                }
                
                // Action Buttons
                actionButtons
            }
            .navigationTitle("Filtrer artikler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuller") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Nulstil") {
                        resetFilters()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showCustomDatePicker) {
            CustomDateRangePicker(dateRange: $customDateRange)
        }
    }
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Søg")
                .font(.headline)
            
            TextField("Søg i titel, indhold...", text: $tempFilter.searchQuery)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dato")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    FilterChip(
                        title: range.displayName,
                        isSelected: tempFilter.dateRange == range
                    ) {
                        tempFilter.dateRange = range
                        if range == .custom {
                            showCustomDatePicker = true
                        }
                    }
                }
            }
            
            if let customRange = customDateRange {
                HStack {
                    Text("Tilpasset periode:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatDateRange(customRange))
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kategorier")
                .font(.headline)
            
            let categories = Set(articles.compactMap { $0.topicID })
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(Array(categories), id: \.self) { category in
                    FilterChip(
                        title: category,
                        isSelected: tempFilter.categories.contains(category)
                    ) {
                        if tempFilter.categories.contains(category) {
                            tempFilter.categories.remove(category)
                        } else {
                            tempFilter.categories.insert(category)
                        }
                    }
                }
            }
        }
    }
    
    private var authorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Forfattere")
                .font(.headline)
            
            let authors = Set(articles.compactMap { $0.authorID })
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(Array(authors), id: \.self) { author in
                    FilterChip(
                        title: author,
                        isSelected: tempFilter.authors.contains(author)
                    ) {
                        if tempFilter.authors.contains(author) {
                            tempFilter.authors.remove(author)
                        } else {
                            tempFilter.authors.insert(author)
                        }
                    }
                }
            }
        }
    }
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minimum rating")
                .font(.headline)
            
            HStack {
                Text("0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $tempFilter.rating, in: 0...5, step: 0.5)
                    .accentColor(.blue)
                
                Text("5")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                
                if tempFilter.rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<Int(tempFilter.rating), id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        if tempFilter.rating.truncatingRemainder(dividingBy: 1) > 0 {
                            Image(systemName: "star.leadinghalf.filled")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        Text("og op")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Alle ratings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
    }
    
    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sortér efter")
                .font(.headline)
            
            Picker("Sortér", selection: $tempFilter.sortBy) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var resultsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resultater")
                .font(.headline)
            
            let filteredCount = applyFilters(to: articles).count
            let totalCount = articles.count
            
            HStack {
                Text("\(filteredCount) af \(totalCount) artikler")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if tempFilter.isActive {
                    Text("Filtreret")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: applyFilters) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Anvend filtre")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button(action: resetFilters) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Nulstil filtre")
                }
                .font(.subheadline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private func applyFilters() {
        let filteredArticles = applyFilters(to: articles)
        filter = tempFilter
        onApply(filteredArticles)
        HapticManager.shared.success()
        dismiss()
    }
    
    private func resetFilters() {
        tempFilter.reset()
        customDateRange = nil
        HapticManager.shared.mediumImpact()
    }
    
    private func applyFilters(to articles: [Article]) -> [Article] {
        var filtered = articles
        
        // Search filter
        if !tempFilter.searchQuery.isEmpty {
            filtered = filtered.filter { article in
                let query = tempFilter.searchQuery.lowercased()
                let title = article.name?.lowercased() ?? ""
                let content = article.content?.lowercased() ?? ""
                let intro = article.intro?.lowercased() ?? ""
                
                return title.contains(query) || content.contains(query) || intro.contains(query)
            }
        }
        
        // Date filter
        if tempFilter.dateRange.dateInterval != nil {
            filtered = filtered.filter { article in
                // This would be enhanced with actual publication dates
                return true // Placeholder
            }
        }
        
        // Category filter
        if !tempFilter.categories.isEmpty {
            filtered = filtered.filter { article in
                guard let topicID = article.topicID else { return false }
                return tempFilter.categories.contains(topicID)
            }
        }
        
        // Author filter
        if !tempFilter.authors.isEmpty {
            filtered = filtered.filter { article in
                guard let authorID = article.authorID else { return false }
                return tempFilter.authors.contains(authorID)
            }
        }
        
        // Rating filter
        if tempFilter.rating > 0 {
            filtered = filtered.filter { article in
                return article.rating >= Int(tempFilter.rating)
            }
        }
        
        // Sort
        filtered.sort { first, second in
            switch tempFilter.sortBy {
            case .newest:
                return first.id > second.id // Placeholder
            case .oldest:
                return first.id < second.id // Placeholder
            case .rating:
                return first.rating > second.rating
            case .title:
                return (first.name ?? "") < (second.name ?? "")
            case .author:
                return (first.authorID ?? "") < (second.authorID ?? "")
            }
        }
        
        return filtered
    }
    
    private func formatDateRange(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let startDate = formatter.string(from: interval.start)
        let endDate = formatter.string(from: interval.end)
        
        return "\(startDate) - \(endDate)"
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Date Range Picker

struct CustomDateRangePicker: View {
    @Binding var dateRange: DateInterval?
    @Environment(\.dismiss) private var dismiss
    
    @State private var startDate = Date()
    @State private var endDate = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vælg startdato")
                        .font(.headline)
                    
                    DatePicker("Startdato", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vælg slutdato")
                        .font(.headline)
                    
                    DatePicker("Slutdato", selection: $endDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Tilpasset dato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuller") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Gem") {
                        dateRange = DateInterval(start: startDate, end: endDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func withAdvancedFilters(
        articles: [Article],
        onApply: @escaping ([Article]) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        self.sheet(isPresented: .constant(true)) {
            AdvancedFilterView(
                filter: .constant(ArticleFilter()),
                articles: articles,
                onApply: onApply,
                onReset: onReset
            )
        }
    }
}

#Preview {
    let sampleArticles = [
        Article(
            id: "1",
            name: "Justice (O Days Festival)",
            slug: "justice-o-days",
            content: "Sample content",
            intro: "Sample intro",
            stjerne: 4,
            topicID: "Festival",
            topicsIDs: ["Festival"],
            authorID: "Frederik Emil",
            thumbURL: URL(string: "https://picsum.photos/400/300")!,
            coverURL: nil,
            location: "Odense",
            subtitle: nil,
            isDraft: nil
        ),
        Article(
            id: "2",
            name: "Another Article",
            slug: "another-article",
            content: "Sample content",
            intro: "Sample intro",
            stjerne: 5,
            topicID: "Musik",
            topicsIDs: ["Musik"],
            authorID: "Anden Forfatter",
            thumbURL: URL(string: "https://picsum.photos/400/300")!,
            coverURL: nil,
            location: "København",
            subtitle: nil,
            isDraft: nil
        )
    ]
    
    AdvancedFilterView(
        filter: .constant(ArticleFilter()),
        articles: sampleArticles,
        onApply: { _ in },
        onReset: { }
    )
}
