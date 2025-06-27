//
//  MainSevenCategoriesView.swift
//  Native
//

import SwiftUI

struct MainSevenCategoriesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the categories to display:
    let categories: [NT_ProductsCategory]
    
    init(categories: [NT_ProductsCategory]) {
        
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

private extension MainSevenCategoriesView {
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
        SectionHeaderView(title: "Browse Categories")
        categoriesContent
    }
}

// MARK: - Categories:

private extension MainSevenCategoriesView {
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
    
    private func category(_ category: NT_ProductsCategory) -> some View {
        NavigationLink(value: category) {
            categoryLabel(category)
        }
    }
    
    private func categoryLabel(_ category: NT_ProductsCategory) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(category),
            iconColor: color(category),
            iconGradientStart: gradientStart(category),
            iconGradientEnd: gradientEnd(category),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: title(category),
            titleAlignment: .center,
            subtitle: productsCount(category),
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainSevenCategoriesView(categories: NT_ProductsCategory.example)
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
    .localizedNavigationTitle(title: "Explore")
    .navigationDestination(for: NT_ProductsCategory.self) { category in
        PlaceholderView(title: category.title)
    }
    .navigationStack()
}
