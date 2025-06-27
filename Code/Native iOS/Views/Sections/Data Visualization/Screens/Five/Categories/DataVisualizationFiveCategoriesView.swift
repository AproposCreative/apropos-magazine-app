//
//  DataVisualizationFiveCategoriesView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFiveCategoriesView: View {
    
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

private extension DataVisualizationFiveCategoriesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        chart
    }
}

// MARK: - Header:

private extension DataVisualizationFiveCategoriesView {
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
            subtitle: "Last 30 days"
        )
    }
}

// MARK: - Chart:

private extension DataVisualizationFiveCategoriesView {
    private var chart: some View {
        BarChartView(
            isShowingHeader: false,
            bars: bars
        ) {
            
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationFiveCategoriesView(categories: NT_ExpenseCategory.example2)
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
    .localizedNavigationTitle(title: "Summary")
    .navigationStack()
}
