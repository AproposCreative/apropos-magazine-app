//
//  AccountOneSettings+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension AccountOneSettingsView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections with the settings to display:
    var sections: [NT_AccountSettingsSection] {
        NT_AccountSettingsSection.allCases
    }
}
