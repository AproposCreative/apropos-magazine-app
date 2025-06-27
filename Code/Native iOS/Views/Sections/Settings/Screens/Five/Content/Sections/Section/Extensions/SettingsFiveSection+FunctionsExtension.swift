//
//  SettingsFiveSection+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension SettingsFiveSectionView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given setting:
    func title(_ setting: NT_Setting) -> String {
        setting.title
    }
    
    /// Returns the color of the given setting:
    func color(_ setting: NT_Setting) -> Color {
        setting.color
    }
    
    /// Returns the starting color of the gradient of the given setting:
    func gradientStart(_ setting: NT_Setting) -> Color {
        setting.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given setting:
    func gradientEnd(_ setting: NT_Setting) -> Color {
        setting.gradientEnd
    }
    
    /// Returns the icon of the given setting:
    func icon(_ setting: NT_Setting) -> String {
        setting.icon
    }
    
    /// Returns a 'Bool' value indicating whether or not the given setting should be a toggle instead of a navigation link:
    func isToggle(_ setting: NT_Setting) -> Bool {
        setting.isToggle
    }
}
