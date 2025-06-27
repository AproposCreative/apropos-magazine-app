//
//  MainTen+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainTenView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the locations, an array of the forecasts for today, as well as an array of the forecasts to display are all empty:
    var isEmpty: Bool {
        locations.isEmpty
        && todayForecasts.isEmpty
        && forecasts.isEmpty
    }
    
    /// Date when the weather data was last updated:
    var lastUpdated: Date {
        .dateWithComponents(
            withYear: 2024,
            withMonth: 8,
            withDay: 1,
            withHour: 14,
            withMinute: 30
        )
    }
}
