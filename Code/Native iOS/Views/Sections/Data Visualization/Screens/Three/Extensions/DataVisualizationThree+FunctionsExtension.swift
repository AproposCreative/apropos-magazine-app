//
//  DataVisualizationThree+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationThreeView {
    
    // MARK: - Functions:
    
    /// Method that gets called whenever the current tab changes:
    func currentTabOnChange(
        _ previousTab: NT_Tab,
        _ newTab: NT_Tab
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
