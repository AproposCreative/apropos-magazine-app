//
//  DataVisualizationFourInterests+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFourInterestsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !interests.isEmpty
    }
    
    /// An array of the types of the interests to select from:
    var types: [NT_InterestType] {
        NT_InterestType.allCases
    }
    
    /// An array of the sectors to display in the chart:
    var sectors: [NT_ChartSector] {
        interests.map {
            .init(
                id: $0.id,
                valueTitle: $0.title,
                value: $0.value,
                color: $0.color,
                gradientStart: $0.gradientStart,
                gradientEnd: $0.gradientEnd
            )
        }
    }
}
