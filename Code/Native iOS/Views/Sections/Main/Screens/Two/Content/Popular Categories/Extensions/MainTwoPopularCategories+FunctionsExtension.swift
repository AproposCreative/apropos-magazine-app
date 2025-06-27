//
//  MainTwoPopularCategories+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTwoPopularCategoriesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category:
    func title(_ category: NT_CoursesCategory) -> String {
        category.title
    }
    
    /// Returns the courses of courses that are part of the given category:
    func coursesCount(_ category: NT_CoursesCategory) -> String {
        "\(category.coursesCount) courses"
    }
    
    /// Returns the color of the given category:
    func color(_ category: NT_CoursesCategory) -> Color {
        category.color
    }
    
    /// Returns the starting color of the gradient of the given category:
    func gradientStart(_ category: NT_CoursesCategory) -> Color {
        category.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given category:
    func gradientEnd(_ category: NT_CoursesCategory) -> Color {
        category.gradientEnd
    }
    
    /// Returns the icon of the given category:
    func icon(_ category: NT_CoursesCategory) -> String {
        category.icon
    }
}
