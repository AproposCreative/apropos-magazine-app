//
//  MainSevenCategories+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSevenCategoriesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category:
    func title(_ category: NT_ProductsCategory) -> String {
        category.title
    }
    
    /// Returns the count of the products that are part of the given category as a string:
    func productsCount(_ category: NT_ProductsCategory) -> String {
        "\(category.productsCount) products"
    }
    
    /// Returns the color of the given category:
    func color(_ category: NT_ProductsCategory) -> Color {
        category.color
    }
    
    /// Returns the starting color of the gradient of the given category:
    func gradientStart(_ category: NT_ProductsCategory) -> Color {
        category.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given category:
    func gradientEnd(_ category: NT_ProductsCategory) -> Color {
        category.gradientEnd
    }
    
    /// Returns the icon of the given category:
    func icon(_ category: NT_ProductsCategory) -> String {
        category.icon
    }
}
