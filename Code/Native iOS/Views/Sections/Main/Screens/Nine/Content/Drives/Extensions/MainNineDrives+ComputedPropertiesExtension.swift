//
//  MainNineDrives+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainNineDrivesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !drives.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Size of the frame of each of the second icons of the accounts that is based on the size of the dynamic type that is currently selected:
    var secondIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
