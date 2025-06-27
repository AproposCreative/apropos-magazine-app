//
//  SortAndFilterThreeTypesView.swift
//  Native
//

import SwiftUI

struct SortAndFilterThreeTypesView: View {
    
    // MARK: - Properties:
    
    /// An array of the transaction type filters that are currently selected:
    @Binding var selectedTransactionTypeFilters: [NT_TransactionTypeFilter]
    
    init(selectedTransactionTypeFilters: Binding<[NT_TransactionTypeFilter]>) {
        
        /// Properties initialization:
        _selectedTransactionTypeFilters = selectedTransactionTypeFilters
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

private extension SortAndFilterThreeTypesView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Transaction Types")
        scroll
    }
}

// MARK: - Scroll:

private extension SortAndFilterThreeTypesView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(
                .all,
                12
            )
            .contentBackground(
                verticalPadding: padding,
                horizontalPadding: padding
            )
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        transactionTypeFiltersContent
            .scrollTargetLayout()
    }
}

// MARK: - Transaction type filters:

private extension SortAndFilterThreeTypesView {
    private var transactionTypeFiltersContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: 8
        ) {
            transactionTypeFiltersItem
        }
    }
    
    private var transactionTypeFiltersItem: some View {
        ForEach(
            transactionTypeFilters,
            content: transactionTypeFilter
        )
    }
    
    private func transactionTypeFilter(_ filter: NT_TransactionTypeFilter) -> some View {
        transactionTypeFilterContent(filter)
            .accessibilityAddTraits(accessibilityTraits(filter))
    }
    
    private func transactionTypeFilterContent(_ filter: NT_TransactionTypeFilter) -> some View {
        Button {
            select(filter)
        } label: {
            transactionTypeFilterLabel(filter)
        }
    }
    
    private func transactionTypeFilterLabel(_ filter: NT_TransactionTypeFilter) -> some View {
        BadgeView(
            title: title(filter),
            titleColor: .primary,
            backgroundColor: .init(.systemGroupedBackground),
            isBackgroundColorGradient: false,
            borderColor: .init(.systemFill),
            isBorderColorGradient: isSelected(filter),
            size: size(filter)
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedTransactionTypeFilters: [NT_TransactionTypeFilter] = [.income]
    
    ScrollView {
        SortAndFilterThreeTypesView(selectedTransactionTypeFilters: $selectedTransactionTypeFilters)
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
