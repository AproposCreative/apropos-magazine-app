//
//  DataVisualizationFourNewFollowersView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFourNewFollowersView: View {
    
    // MARK: - Properties:
    
    /// An array of the data for the number of the new followers to display:
    let newFollowersData: [NT_NewFollowersData]
    
    init(newFollowersData: [NT_NewFollowersData]) {
        
        /// Properties initialization:
        self.newFollowersData = newFollowersData
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

private extension DataVisualizationFourNewFollowersView {
    private var item: some View {
        BarChartTitleSubtitleValueView(
            title: "New Followers",
            valueColor: .green,
            subtitle: "Last 30 days",
            bars: bars,
            chartHeight: 120,
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationFourNewFollowersView(newFollowersData: NT_NewFollowersData.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Analytics")
    .navigationStack()
}
