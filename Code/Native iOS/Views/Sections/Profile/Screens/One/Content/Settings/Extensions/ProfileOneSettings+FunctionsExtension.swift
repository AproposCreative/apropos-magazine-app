//
//  ProfileOneSettings+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProfileOneSettingsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given setting:
    func title(_ setting: NT_ProfileSetting) -> String {
        setting.title
    }
    
    /// Returns the description of the given setting:
    func description(_ setting: NT_ProfileSetting) -> String {
        setting.description
    }
    
    /// Returns the color of the given setting:
    func color(_ setting: NT_ProfileSetting) -> Color {
        setting.color
    }
    
    /// Returns the starting color of the gradient of the given setting:
    func gradientStart(_ setting: NT_ProfileSetting) -> Color {
        setting.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given setting:
    func gradientEnd(_ setting: NT_ProfileSetting) -> Color {
        setting.gradientEnd
    }
    
    /// Returns the icon of the given setting:
    func icon(_ setting: NT_ProfileSetting) -> String {
        setting.icon
    }
}
