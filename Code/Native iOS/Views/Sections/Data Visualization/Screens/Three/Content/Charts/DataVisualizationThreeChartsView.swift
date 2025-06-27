//
//  DataVisualizationThreeChartsView.swift
//  Native
//

import SwiftUI

struct DataVisualizationThreeChartsView: View {
    
    // MARK: - Properties:
    
    /// An array of the categories of the income to display:
    let incomeCategories: [NT_IncomeCategory]
    
    /// An array of the unpaid invoices to display:
    let unpaidInvoices: [NT_UnpaidInvoice]
    
    /// An array of the investments to display:
    let investments: [NT_Investment]
    
    init(
        incomeCategories: [NT_IncomeCategory],
        unpaidInvoices: [NT_UnpaidInvoice],
        investments: [NT_Investment]
    ) {
        
        /// Properties initialization:
        self.incomeCategories = incomeCategories
        self.unpaidInvoices = unpaidInvoices
        self.investments = investments
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

private extension DataVisualizationThreeChartsView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        incomeChart
        unpaidInvoicesChart
        investmentsChart
    }
}

// MARK: - Charts:

private extension DataVisualizationThreeChartsView {
    private var incomeChart: some View {
        BarChartView(
            title: "Income",
            bars: incomeCategoriesBars
        ) {
            
        }
    }
    
    private var unpaidInvoicesChart: some View {
        PieChartView(
            title: "Unpaid Invoices",
            sectors: unpaidInvoicesSectors
        )
    }
    
    private var investmentsChart: some View {
        LineChartView(
            title: "Investments",
            totalValueType: .lastValue,
            lines: investmentsLines,
            xAxisTitle: "Date",
            yAxisTitle: "Amount"
        ) {
            
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationThreeChartsView(
            incomeCategories:  NT_IncomeCategory.example,
            unpaidInvoices: NT_UnpaidInvoice.example,
            investments: NT_Investment.example
        )
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
    .localizedNavigationTitle(title: "Overview")
    .navigationStack()
}
