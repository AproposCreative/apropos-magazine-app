//
//  AccountThreeSettings+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension AccountThreeSettingsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given setting:
    func title(_ setting: NT_AccountSetting) -> String {
        setting.title
    }
    
    /// Returns the color of the given setting:
    func color(_ setting: NT_AccountSetting) -> Color {
        setting.color
    }
    
    /// Returns the starting color of the gradient of the given setting:
    func gradientStart(_ setting: NT_AccountSetting) -> Color {
        setting.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given setting:
    func gradientEnd(_ setting: NT_AccountSetting) -> Color {
        setting.gradientEnd
    }
    
    /// Returns the icon of the given setting:
    func icon(_ setting: NT_AccountSetting) -> String {
        setting.icon
    }
    
    /// Returns a 'Bool' value indicating whether or not the given setting should be a toggle instead of a navigation link:
    func isToggle(_ setting: NT_AccountSetting) -> Bool {
        setting.isToggle
    }
    
    /// Returns an array of the settings that are part of the given section to display:
    func settings(_ section: NT_AccountSettingsSection) -> [NT_AccountSetting] {
        section.settings
    }
}
