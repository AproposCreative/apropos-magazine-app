//
//  MainOneSummaryView.swift
//  Native
//

import SwiftUI

struct MainOneSummaryView: View {
    
    // MARK: - Properties:
    
    /// An array of the bars to display in the chart:
    let bars: [NT_ChartBar]
    
    // MARK: - Private properties:
    
    /// Time period to filter the data by that is currently selected:
    @State private var timePeriod: NT_TransactionsTimePeriod = .day
    
    init(bars: [NT_ChartBar]) {
        
        /// Properties initialization:
        self.bars = bars
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .onChange(
                of: timePeriod,
                timePeriodOnChange
            )
    }
}

// MARK: - Item:

private extension MainOneSummaryView {
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
        SectionHeaderView(title: "Summary")
        chart
    }
}

// MARK: - Chart:

private extension MainOneSummaryView {
    private var chart: some View {
        BarChartView(
            title: "Expenses",
            bars: bars
        ) {
            timePeriodPicker
        }
    }
}

// MARK: - Time period picker:

private extension MainOneSummaryView {
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
    
    private func timePeriod(_ timePeriod: NT_TransactionsTimePeriod) -> some View {
        Text(shortTitle(timePeriod))
            .tag(timePeriod)
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainOneSummaryView(bars: NT_ChartBar.example)
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
}
