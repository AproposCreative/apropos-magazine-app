//
//  DataVisualizationFourNewFollowers+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationFourNewFollowersView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !newFollowersData.isEmpty
    }
    
    /// An array of the bars to display in the chart:
    var bars: [NT_ChartBar] {
        newFollowersData.map {
            .init(
                id: $0.id,
                title: $0.date.formatted(.dateTime.month().day()),
                valueTitle: $0.value.formatted(.number),
                value: .init($0.value),
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            )
        }
    }
}
