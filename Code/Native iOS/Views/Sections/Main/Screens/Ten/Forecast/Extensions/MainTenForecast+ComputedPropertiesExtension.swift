//
//  MainTenForecast+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainTenForecastView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !forecasts.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
