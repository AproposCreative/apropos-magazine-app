//
//  MainOneContent+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainOneContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the accounts to display, as well as the bars to display in the charts are both empty:
    var isEmpty: Bool {
        accounts.isEmpty && bars.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
}
