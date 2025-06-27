//
//  SortAndFilterFourSortView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFourSortView: View {
    
    // MARK: - Properties:
    
    /// Sort order that is currently selected:
    @Binding var selectedSortOrder: NT_ProjectSortOrder
    
    init(selectedSortOrder: Binding<NT_ProjectSortOrder>) {
        
        /// Properties initialization:
        _selectedSortOrder = selectedSortOrder
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension SortAndFilterFourSortView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Sort By")
        sortOrdersContent
    }
}

// MARK: - Sort orders:

private extension SortAndFilterFourSortView {
    private var sortOrdersContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: spacing
        ) {
            sortOrdersItem
        }
    }
    
    private var sortOrdersItem: some View {
        ForEach(
            sortOrders,
            content: sortOrder
        )
    }
    
    private func sortOrder(_ sortOrder: NT_ProjectSortOrder) -> some View {
        SelectButtonTitleSubtitleView(
            isSelected: isSelected(sortOrder),
            title: title(sortOrder),
            isShowingSubtitle: false,
            subtitle: "",
            isReversed: true
        ) {
            select(sortOrder)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedSortOrder: NT_ProjectSortOrder = .dueDate
    
    ScrollView {
        SortAndFilterFourSortView(selectedSortOrder: $selectedSortOrder)
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
