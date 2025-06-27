//
//  ProfileTwo+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not there is an account to display the details for:
    var isNoAccount: Bool {
        account == nil
    }
    
    /// Font of the buttons that are placed in the toolbar:
    var toolbarFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are placed in the toolbar:
    var toolbarIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Style of the buttons that are placed in the toolbar:
    var toolbarStyle: NT_LabelStyle {
        .iconOnly
    }
}
