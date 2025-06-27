//
//  DataVisualizationFourContent+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationFourContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the data with the new followers to display in the chart, an array of the activities to display, as well as an array of the data with the interests to display in the chart are all empty:
    var isEmpty: Bool {
        newFollowersData.isEmpty
        && activities.isEmpty
        && interests.isEmpty
    }
    
    /// Font of the buttons that are placed in the toolbar:
    var toolbarFont: Font {
        .body
    }
    
    /// Style of the buttons that are placed in the toolbar:
    var toolbarStyle: NT_LabelStyle {
        .iconOnly
    }
}
