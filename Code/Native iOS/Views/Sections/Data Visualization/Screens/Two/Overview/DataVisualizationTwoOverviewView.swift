//
//  DataVisualizationTwoOverviewView.swift
//  Native
//

import SwiftUI

struct DataVisualizationTwoOverviewView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        TitleSubtitleValueView(
            title: "Estimated Bill",
            titleFont: titleAmountFont,
            value: amount,
            valueFont: titleAmountFont,
            valueColor: .accent,
            subtitle: timePeriod,
            subtitleFont: .body,
            spacing: 6
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationTwoOverviewView()
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
