//
//  MainTenToday+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainTenTodayView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !forecasts.isEmpty
    }
    
    /// Padding around the content of each of the forecasts for today:
    var forecastPadding: Double {
        8
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Width of each of the forecasts that is based on the size of the dynamic type that is currently selected:
    var forecastWidth: Double {
        dynamicTypeSize >= .accessibility1 ? 144 : 88
    }
}
