//
//  TermsFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension TermsFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the overview items for the terms, as well as an array of the sections with the terms to display are both empty:
    var isEmpty: Bool {
        overviewItems.isEmpty && sections.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
    
    /// Style of each of the buttons that are placed on the view:
    var buttonStyle: NT_LabelStyle {
        .titleAndIcon
    }
}
