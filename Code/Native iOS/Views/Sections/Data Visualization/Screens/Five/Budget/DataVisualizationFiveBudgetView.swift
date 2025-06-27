//
//  DataVisualizationFiveBudgetView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFiveBudgetView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the budgets to display:
    let budgets: [NT_Budget]
    
    init(budgets: [NT_Budget]) {
        
        /// Properties initialization:
        self.budgets = budgets
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

private extension DataVisualizationFiveBudgetView {
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

private extension DataVisualizationFiveBudgetView {
    private var header: some View {
        NavigationLink {
            PlaceholderView(title: "Categories")
        } label: {
            headerLabel
        }
    }
    
    private var headerLabel: some View {
        SectionHeaderView(
            title: "Budget Overview",
            titleMaxWidth: nil,
            isShowingIcon: true,
            iconFrame: headerIconFrame,
            isShowingSubtitle: true,
            subtitle: "Top 6 categories"
        )
    }
}

// MARK: - Budgets:

private extension DataVisualizationFiveBudgetView {
    private var categoriesContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            budgetsItem
        }
    }
    
    private var budgetsItem: some View {
        ForEach(
            budgets,
            content: budget
        )
    }
    
    private func budget(_ budget: NT_Budget) -> some View {
        IconBackgroundTitleSubtitleProgressView(
            icon: icon(budget),
            iconBackgroundColor: color(budget),
            iconBackgroundGradientStart: gradientStart(budget),
            iconBackgroundGradientEnd: gradientEnd(budget),
            iconSize: .thirtyTwoPixels,
            title: title(budget),
            subtitle: totalAmountString(budget),
            progressValue: usedAmount(budget),
            progressTotal: totalAmount(budget),
            isShowingProgressValueTitle: true,
            progressValueTitle: usedAmountString(budget),
            progressColor: color(budget),
            verticalAlignment: .top
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationFiveBudgetView(budgets: NT_Budget.example)
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
