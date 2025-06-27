//
//  DataVisualizationFourActivity+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationFourActivityView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given activity:
    func title(_ activity: NT_Activity) -> String {
        activity.title
    }
    
    /// Returns the description of the given activity:
    func description(_ activity: NT_Activity) -> String {
        activity.description
    }
    
    /// Returns the value of the given activity as a string:
    func value(_ activity: NT_Activity) -> String {
        activity.value.formatted(.number.notation(.compactName))
    }
    
    /// Returns the color of the given activity:
    func color(_ activity: NT_Activity) -> Color {
        activity.color
    }
    
    /// Returns the starting color of the gradient of the given activity:
    func gradientStart(_ activity: NT_Activity) -> Color {
        activity.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given activity:
    func gradientEnd(_ activity: NT_Activity) -> Color {
        activity.gradientEnd
    }
    
    /// Returns the icon of the given activity:
    func icon(_ activity: NT_Activity) -> String {
        activity.icon
    }
}
