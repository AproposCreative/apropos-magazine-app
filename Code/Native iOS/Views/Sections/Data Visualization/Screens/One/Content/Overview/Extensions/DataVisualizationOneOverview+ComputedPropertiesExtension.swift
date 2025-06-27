//
//  DataVisualizationOneOverview+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationOneOverviewView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !overviewItems.isEmpty
    }
    
    /// Size of the frame of each of the second icons of the overview items that is based on the size of the dynamic type that is currently selected:
    var secondIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
