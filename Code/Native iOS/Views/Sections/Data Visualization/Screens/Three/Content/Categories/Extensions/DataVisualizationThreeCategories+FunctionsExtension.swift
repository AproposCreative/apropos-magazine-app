//
//  DataVisualizationThreeCategories+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationThreeCategoriesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category:
    func title(_ category: NT_ExpenseCategory) -> String {
        category.title
    }
    
    /// Returns the description of the given category:
    func description(_ category: NT_ExpenseCategory) -> String {
        category.description
    }
    
    /// Returns the amount of the given category as a string:
    func amount(_ category: NT_ExpenseCategory) -> String {
        category.amount.formatted(.currency(code: "USD").notation(.compactName))
    }
    
    /// Returns the color of the given category:
    func color(_ category: NT_ExpenseCategory) -> Color {
        category.color
    }
    
    /// Returns the starting color of the gradient of the given category:
    func gradientStart(_ category: NT_ExpenseCategory) -> Color {
        category.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given category:
    func gradientEnd(_ category: NT_ExpenseCategory) -> Color {
        category.gradientEnd
    }
    
    /// Returns the icon of the given category:
    func icon(_ category: NT_ExpenseCategory) -> String {
        category.icon
    }
}
