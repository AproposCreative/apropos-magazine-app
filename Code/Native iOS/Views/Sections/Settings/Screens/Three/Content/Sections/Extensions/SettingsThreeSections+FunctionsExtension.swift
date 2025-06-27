//
//  SettingsThreeSections+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension SettingsThreeSectionsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given section with the settings:
    func title(_ section: NT_SettingsSection) -> LocalizedStringKey {
        .init(section.title)
    }
    
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
    
    /// Returns an array of the settings that are part of the given section to display:
    func settings(_ section: NT_SettingsSection) -> [NT_Setting] {
        section.settings
    }
}
