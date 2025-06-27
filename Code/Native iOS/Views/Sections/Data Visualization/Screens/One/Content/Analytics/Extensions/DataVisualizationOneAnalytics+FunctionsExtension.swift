//
//  DataVisualizationOneAnalytics+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationOneAnalyticsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given time period:
    func title(_ timePeriod: NT_AnalyticsTimePeriod) -> String {
        timePeriod.title
    }
    
    /// Method that gets called whenever the time period changes:
    func timePeriodOnChange(
        _ previousTimePeriod: NT_AnalyticsTimePeriod,
        _ newTimePeriod: NT_AnalyticsTimePeriod
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
