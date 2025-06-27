//
//  MainFour+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainFourView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the sections with the news to display is empty:
    var isEmpty: Bool {
        sections.isEmpty
    }
    
    /// Font of the buttons that are placed in the toolbar:
    var toolbarFont: Font {
        .body
    }
    
    /// Style of the buttons that are placed in the toolbar:
    var toolbarStyle: NT_LabelStyle {
        .iconOnly
    }
}
