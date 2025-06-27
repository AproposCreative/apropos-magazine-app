//
//  DataVisualizationThreeContentView.swift
//  Native
//

import SwiftUI

struct DataVisualizationThreeContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the categories of the income to display:
    @State var incomeCategories: [NT_IncomeCategory] = []
    
    /// An array of the unpaid invoices to display:
    @State var unpaidInvoices: [NT_UnpaidInvoice] = []
    
    /// An array of the investments to display:
    @State var investments: [NT_Investment] = []
    
    /// An array of the categories of the expenses to display:
    @State var expenseCategories: [NT_ExpenseCategory] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Time period to display the data for that is currently selected:
    @State private var timePeriod: NT_OverviewTimePeriod = .today
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Overview")
            .onChange(
                of: timePeriod,
                timePeriodOnChange
            )
            .animation(
                .default,
                value: incomeCategories
            )
            .animation(
                .default,
                value: unpaidInvoices
            )
            .animation(
                .default,
                value: investments
            )
            .animation(
                .default,
                value: expenseCategories
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

private extension DataVisualizationThreeContentView {
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
            timePeriodPickerChartsCategories
        }
    }
}

// MARK: - Empty states:

private extension DataVisualizationThreeContentView {
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

// MARK: - Time period picker, charts, and categories:

private extension DataVisualizationThreeContentView {
    private var timePeriodPickerChartsCategories: some View {
        VStack(
            alignment: .center,
            spacing: 16
        ) {
            timePeriodPickerChartsCategoriesContent
        }
    }
    
    @ViewBuilder
    private var timePeriodPickerChartsCategoriesContent: some View {
        timePeriodPicker
        chartsCategories
    }
}

// MARK: - Time period picker:

private extension DataVisualizationThreeContentView {
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
    
    private func timePeriod(_ timePeriod: NT_OverviewTimePeriod) -> some View {
        Text(title(timePeriod))
            .tag(timePeriod)
    }
}

// MARK: - Charts and categories:

private extension DataVisualizationThreeContentView {
    private var chartsCategories: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            chartsCategoriesContent
        }
    }
    
    @ViewBuilder
    private var chartsCategoriesContent: some View {
        charts
        DataVisualizationThreeCategoriesView(categories: expenseCategories)
    }
    
    private var charts: some View {
        DataVisualizationThreeChartsView(
            incomeCategories: incomeCategories,
            unpaidInvoices: unpaidInvoices,
            investments: investments
        )
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationThreeContentView()
}
