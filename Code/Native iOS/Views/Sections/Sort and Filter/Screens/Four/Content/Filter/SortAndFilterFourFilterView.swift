//
//  SortAndFilterFourFilterView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFourFilterView: View {
    
    // MARK: - Properties:
    
    /// An array of the filters that are currently selected:
    @Binding var selectedFilters: [NT_ProjectFilter]
    
    init(selectedFilters: Binding<[NT_ProjectFilter]>) {
        
        /// Properties initialization:
        _selectedFilters = selectedFilters
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

private extension SortAndFilterFourFilterView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Filter By Project")
        filtersContent
    }
}

// MARK: - Filters:

private extension SortAndFilterFourFilterView {
    private var filtersContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: spacing
        ) {
            filtersItem
        }
    }
    
    private var filtersItem: some View {
        ForEach(
            filters,
            content: filter
        )
    }
    
    private func filter(_ filter: NT_ProjectFilter) -> some View {
        SelectButtonTitleSubtitleView(
            isSelected: isSelected(filter),
            title: title(filter),
            subtitle: description(filter),
            isReversed: true,
            verticalAlignment: .top
        ) {
            select(filter)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedFilters: [NT_ProjectFilter] = [.work]
    
    ScrollView {
        SortAndFilterFourFilterView(selectedFilters: $selectedFilters)
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
