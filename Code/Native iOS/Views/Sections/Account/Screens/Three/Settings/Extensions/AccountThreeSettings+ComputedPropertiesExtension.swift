//
//  AccountThreeSettings+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension AccountThreeSettingsView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections with the settings to display:
    var sections: [NT_AccountSettingsSection] {
        NT_AccountSettingsSection.allCases
    }
}
