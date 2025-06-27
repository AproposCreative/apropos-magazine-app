//
//  DataVisualizationThreeCategoriesView.swift
//  Native
//

import SwiftUI

struct DataVisualizationThreeCategoriesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the categories to display:
    let categories: [NT_ExpenseCategory]
    
    init(categories: [NT_ExpenseCategory]) {
        
        /// Properties initialization:
        self.categories = categories
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension DataVisualizationThreeCategoriesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        categoriesContent
    }
}

// MARK: - Header:

private extension DataVisualizationThreeCategoriesView {
    private var header: some View {
        NavigationLink {
            PlaceholderView(title: "Categories")
        } label: {
            headerLabel
        }
    }
    
    private var headerLabel: some View {
        SectionHeaderView(
            title: "Expenses by Category",
            titleMaxWidth: nil,
            isShowingIcon: true,
            iconFrame: headerIconFrame,
            isShowingSubtitle: true,
            subtitle: "Top 6 categories today"
        )
    }
}

// MARK: - Categories:

private extension DataVisualizationThreeCategoriesView {
    private var categoriesContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            categoriesItem
        }
    }
    
    private var categoriesItem: some View {
        ForEach(
            categories,
            content: category
        )
    }
    
    private func category(_ category: NT_ExpenseCategory) -> some View {
        IconBackgroundTitleSubtitleValueView(
            icon: icon(category),
            iconColor: color(category),
            iconGradientStart: gradientStart(category),
            iconGradientEnd: gradientEnd(category),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(category),
            value: amount(category),
            valueColor: color(category),
            titleValueAlignment: .center,
            subtitle: description(category),
            alignment: .vertical,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationThreeCategoriesView(
            categories: NT_ExpenseCategory.example1.filter {
                $0.id != "Item.3"
                && $0.id != "Item.8"
                && $0.id != "Item.9"
            }
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Overview")
    .navigationStack()
}
