//
//  SortAndFilterThreeCategoriesView.swift
//  Native
//

import SwiftUI

struct SortAndFilterThreeCategoriesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the budget category filters that are currently selected:
    @Binding var selectedBudgetCategoryFilters: [NT_BudgetCategoryFilter]
    
    init(selectedBudgetCategoryFilters: Binding<[NT_BudgetCategoryFilter]>) {
        
        /// Properties initialization:
        _selectedBudgetCategoryFilters = selectedBudgetCategoryFilters
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension SortAndFilterThreeCategoriesView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Budget Categories")
        budgetCategoryFiltersContent
    }
}

// MARK: - Budget category filters:

private extension SortAndFilterThreeCategoriesView {
    private var budgetCategoryFiltersContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            budgetCategoryFiltersItem
        }
    }
    
    private var budgetCategoryFiltersItem: some View {
        ForEach(
            budgetCategoryFilters,
            content: budgetCategoryFilter
        )
    }
    
    private func budgetCategoryFilter(_ filter: NT_BudgetCategoryFilter) -> some View {
        budgetCategoryFilterContent(filter)
            .accessibilityAddTraits(accessibilityTraits(filter))
    }
    
    private func budgetCategoryFilterContent(_ filter: NT_BudgetCategoryFilter) -> some View {
        Button {
            select(filter)
        } label: {
            budgetCategoryFilterLabel(filter)
        }
    }
    
    private func budgetCategoryFilterLabel(_ filter: NT_BudgetCategoryFilter) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(filter),
            iconColor: color(filter),
            iconGradientStart: gradientStart(filter),
            iconGradientEnd: gradientEnd(filter),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .thirtyTwoPixels,
            title: title(filter),
            titleFont: .footnote.bold(),
            titleAlignment: .center,
            isShowingSubtitle: false,
            subtitle: "",
            subtitleFont: .caption,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 2,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            spacing: 8,
            verticalPadding: padding,
            horizontalPadding: padding,
            maxHeight: .infinity,
            cornerRadius: 12,
            borderWidth: borderWidth(filter),
            borderColor: .init(.systemFill),
            borderGradientStart: gradientStart(filter),
            borderGradientEnd: gradientEnd(filter),
            isBorderColorGradient: isSelected(filter)
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedBudgetCategoryFilters: [NT_BudgetCategoryFilter] = [.housing]
    
    ScrollView {
        SortAndFilterThreeCategoriesView(selectedBudgetCategoryFilters: $selectedBudgetCategoryFilters)
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
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
