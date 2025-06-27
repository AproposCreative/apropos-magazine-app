//
//  SortAndFilterThreeTimePeriodView.swift
//  Native
//

import SwiftUI

struct SortAndFilterThreeTimePeriodView: View {
    
    // MARK: - Private properties:
    
    /// Time period filter that is currently selected:
    @Binding private var selectedTimePeriodFilter: NT_BudgetTimePeriodFilter
    
    init(selectedTimePeriodFilter: Binding<NT_BudgetTimePeriodFilter>) {
        
        /// Properties initialization:
        _selectedTimePeriodFilter = selectedTimePeriodFilter
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        picker
            .pickerStyle(.segmented)
            .labelsHidden()
    }
}

// MARK: - Picker:

private extension SortAndFilterThreeTimePeriodView {
    private var picker: some View {
        Picker(
            "Time Period",
            selection: $selectedTimePeriodFilter
        ) {
            timePeriodFiltersContent
        }
    }
}

// MARK: - Time period filters:

private extension SortAndFilterThreeTimePeriodView {
    private var timePeriodFiltersContent: some View {
        ForEach(
            timePeriodFilters,
            content: timePeriodFilter
        )
    }
    
    private func timePeriodFilter(_ filter: NT_BudgetTimePeriodFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedTimePeriodFilter: NT_BudgetTimePeriodFilter = .thisWeek
    
    ScrollView {
        SortAndFilterThreeTimePeriodView(selectedTimePeriodFilter: $selectedTimePeriodFilter)
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
