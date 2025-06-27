//
//  AccountFiveSettings+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension AccountFiveSettingsView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections with the settings to display:
    var sections: [NT_AccountSettingsSection] {
        NT_AccountSettingsSection.allCases
    }
}
