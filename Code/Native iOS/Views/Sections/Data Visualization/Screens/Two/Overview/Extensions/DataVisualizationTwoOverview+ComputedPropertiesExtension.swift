//
//  DataVisualizationTwoOverview+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationTwoOverviewView {
    
    // MARK: - Computed properties:
    
    /// An actual amount of the estimated bill as a string to display:
    var amount: String {
        1672.formatted(.currency(code: "USD"))
    }
    
    /// Time period that the estimated bill is for as a string:
    var timePeriod: String {
        "\(Date.now.startOfMonth.formatted(.dateTime.month().day())) - \(Date.now.formatted(.dateTime.year().month().day()))"
    }
    
    /// Font of the title and the amount:
    var titleAmountFont: Font {
        .title2.bold()
    }
}
