//
//  MainThreeMyGroups+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainThreeMyGroupsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !groups.isEmpty
    }
    
    /// Color of the border of the indicator of the avatar:
    var avatarIndicatorBorderColor: Color {
        .init(.secondarySystemGroupedBackground)
    }
    
    /// Maximum number of lines that the title can have that is based on the size of the dynamic type that is currently selected:
    var titleLineLimit: Int {
        shouldMoveContent ? 2 : 1
    }
    
    /// Maximum number of lines that the subtitle can have that is based on the size of the dynamic type that is currently selected:
    var subtitleLineLimit: Int {
        shouldMoveContent ? 3 : 2
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
}
