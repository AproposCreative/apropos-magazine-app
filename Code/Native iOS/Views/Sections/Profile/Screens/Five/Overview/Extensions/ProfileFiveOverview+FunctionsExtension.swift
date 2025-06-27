//
//  ProfileFiveOverview+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProfileFiveOverviewView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given overview item:
    func title(_ overviewItem: NT_ProfileAuthorOverview) -> String {
        overviewItem.title
    }
    
    /// Returns the value of the given overview item as a string:
    func value(_ overviewItem: NT_ProfileAuthorOverview) -> String {
        overviewItem.value.formatted(.number.notation(.compactName))
    }
    
    /// Returns the color of the given overview item:
    func color(_ overviewItem: NT_ProfileAuthorOverview) -> Color {
        overviewItem.color
    }
    
    /// Returns the starting color of the gradient of the given overview item:
    func gradientStart(_ overviewItem: NT_ProfileAuthorOverview) -> Color {
        overviewItem.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given overview item:
    func gradientEnd(_ overviewItem: NT_ProfileAuthorOverview) -> Color {
        overviewItem.gradientEnd
    }
    
    /// Returns the icon of the given overview item:
    func icon(_ overviewItem: NT_ProfileAuthorOverview) -> String {
        overviewItem.icon
    }
}
