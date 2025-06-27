//
//  DataVisualizationFiveBudget+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationFiveBudgetView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given budget:
    func title(_ budget: NT_Budget) -> String {
        budget.title
    }
    
    /// Returns the total amount of the given budget as a string:
    func totalAmountString(_ budget: NT_Budget) -> String {
        totalAmount(budget).formatted(.currency(code: currencyCode))
    }
    
    /// Returns the used amount of the given budget as a string:
    func usedAmountString(_ budget: NT_Budget) -> String {
        usedAmount(budget).formatted(.currency(code: currencyCode))
    }
    
    /// Returns the color of the given budget:
    func color(_ budget: NT_Budget) -> Color {
        budget.color
    }
    
    /// Returns the starting color of the gradient of the given budget:
    func gradientStart(_ budget: NT_Budget) -> Color {
        budget.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given budget:
    func gradientEnd(_ budget: NT_Budget) -> Color {
        budget.gradientEnd
    }
    
    /// Returns the icon of the given budget:
    func icon(_ budget: NT_Budget) -> String {
        budget.icon
    }
    
    /// Returns the total amount of the given budget:
    func totalAmount(_ budget: NT_Budget) -> Double {
        budget.totalAmount
    }
    
    /// Returns the used amount of the given budget:
    func usedAmount(_ budget: NT_Budget) -> Double {
        budget.usedAmount
    }
}
