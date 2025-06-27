//
//  DataVisualizationTwoPerformance+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationTwoPerformanceView {
    
    // MARK: - Functions:
    
    /// Returns an array of the bars to display in the chart for the given performance item:
    func bars(_ performanceItem: NT_Performance) -> [NT_ChartBar] {
        performanceItem.data.map {
            .init(
                id: $0.id,
                title: $0.title,
                valueTitle: $0.valueTitle,
                value: $0.value,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            )
        }
    }
}
