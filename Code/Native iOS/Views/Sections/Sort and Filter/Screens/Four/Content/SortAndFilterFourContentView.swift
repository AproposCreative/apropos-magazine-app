//
//  SortAndFilterFourContentView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFourContentView: View {
    
    // MARK: - Private properties:
    
    /// Sort order that is currently selected:
    @State private var sortOrder: NT_ProjectSortOrder = .creationDate
    
    /// An array of the filters that are currently selected:
    @State private var filters: [NT_ProjectFilter] = []
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Filter")
            .toolbarButton(
                title: "New Filter",
                icon: Icons.plusCircle,
                font: .body,
                style: .iconOnly,
                action: newFilter
            )
            .animation(
                .default,
                value: sortOrder
            )
            .animation(
                .default,
                value: filters
            )
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension SortAndFilterFourContentView {
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
        SortAndFilterFourSortView(selectedSortOrder: $sortOrder)
        SortAndFilterFourFilterView(selectedFilters: $filters)
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterFourContentView()
}
