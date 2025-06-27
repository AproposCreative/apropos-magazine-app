//
//  DataVisualizationFiveCategories+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFiveCategoriesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !categories.isEmpty
    }
    
    /// An array of the bars to display in the chart:
    var bars: [NT_ChartBar] {
        categories.map {
            .init(
                id: $0.id,
                title: $0.title,
                valueTitle: $0.title,
                value: $0.amount,
                color: $0.color,
                gradientStart: $0.gradientStart,
                gradientEnd: $0.gradientEnd
            )
        }
    }
    
    /// Size of the frame of the icon that is displayed in the header of the view that is based on the size of the dynamic type that is currently selected:
    var headerIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 25
    }
}
