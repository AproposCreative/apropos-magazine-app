//
//  DataVisualizationFiveView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFiveView: View {
    
    // MARK: - Properties:
    
    /// An array of the categories to display:
    @State var categories: [NT_ExpenseCategory] = []
    
    /// An array of the budgets to display:
    @State var budgets: [NT_Budget] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Time period to display the data for that is currently selected:
    @State private var timePeriod: NT_SummaryTimePeriod = .day
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Summary")
            .toolbarButton(
                title: "Date Picker",
                icon: Icons.calendar,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                action: showDatePicker
            )
            .onChange(
                of: timePeriod,
                timePeriodOnChange
            )
            .animation(
                .default,
                value: categories
            )
            .animation(
                .default,
                value: budgets
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension DataVisualizationFiveView {
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
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isEmpty {
            noData
        } else {
            timePeriodPickerCategoriesBudgets
        }
    }
}

// MARK: - Empty states:

private extension DataVisualizationFiveView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var noData: some View {
        noDataContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noDataContent: some View {
        EmptyStateView(
            title: "No Data",
            subtitle: "We don't have any data to display here."
        )
    }
}

// MARK: - Time period picker, categories, and budgets:

private extension DataVisualizationFiveView {
    private var timePeriodPickerCategoriesBudgets: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            timePeriodPickerCategoriesBudgetsContent
        }
    }
    
    @ViewBuilder
    private var timePeriodPickerCategoriesBudgetsContent: some View {
        timePeriodPicker
        DataVisualizationFiveCategoriesView(categories: categories)
        DataVisualizationFiveBudgetView(budgets: budgets)
    }
}

// MARK: - Time period picker:

private extension DataVisualizationFiveView {
    private var timePeriodPicker: some View {
        timePeriodPickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var timePeriodPickerContent: some View {
        Picker(
            "Time Period",
            selection: $timePeriod
        ) {
            timePeriodsContent
        }
    }
    
    private var timePeriodsContent: some View {
        ForEach(
            timePeriods,
            content: timePeriod
        )
    }
    
    private func timePeriod(_ timePeriod: NT_SummaryTimePeriod) -> some View {
        Text(shortTitle(timePeriod))
            .tag(timePeriod)
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationFiveView()
}
