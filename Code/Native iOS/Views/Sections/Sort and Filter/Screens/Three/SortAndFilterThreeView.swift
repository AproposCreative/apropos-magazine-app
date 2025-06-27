//
//  SortAndFilterThreeView.swift
//  Native
//

import SwiftUI

struct SortAndFilterThreeView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Time period filter that is currently selected:
    @State private var timePeriodFilter: NT_BudgetTimePeriodFilter = .thisWeek
    
    /// An array of the transaction type filters that are currently selected:
    @State private var transactionTypeFilters: [NT_TransactionTypeFilter] = []
    
    /// An array of the budget category filters that are currently selected:
    @State private var budgetCategoryFilters: [NT_BudgetCategoryFilter] = []
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(backgroundColor)
            .localizedNavigationTitle(title: "Filter")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .onChange(
                of: timePeriodFilter,
                timePeriodFilterOnChange
            )
            .animation(
                .default,
                value: transactionTypeFilters
            )
            .animation(
                .default,
                value: budgetCategoryFilters
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension SortAndFilterThreeView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension SortAndFilterThreeView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        SortAndFilterThreeTimePeriodView(selectedTimePeriodFilter: $timePeriodFilter)
        SortAndFilterThreeTypesView(selectedTransactionTypeFilters: $transactionTypeFilters)
        SortAndFilterThreeCategoriesView(selectedBudgetCategoryFilters: $budgetCategoryFilters)
    }
}

// MARK: - Toolbar:

private extension SortAndFilterThreeView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            contentAlignment: .horizontal,
            backgroundColor: backgroundColor
        ) {
            clearAllApplyButtons
        }
    }
    
    @ViewBuilder
    private var clearAllApplyButtons: some View {
        clearAllButton
        applyButton
    }
    
    private var clearAllButton: some View {
        ButtonView(
            title: "Clear All",
            titleColor: .primary,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            action: clearAll
        )
    }
    
    private var applyButton: some View {
        ButtonView(
            title: "Apply",
            action: apply
        )
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterThreeView()
}
