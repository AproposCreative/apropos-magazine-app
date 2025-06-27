//
//  AccountTwoUser+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension AccountTwoUserView {
    
    // MARK: - Computed properties:
    
    /// Name of the user to display:
    var name: String {
        "John Smith"
    }
    
    /// Image of the user to display:
    var image: Image {
        .init(.account2)
    }
}
