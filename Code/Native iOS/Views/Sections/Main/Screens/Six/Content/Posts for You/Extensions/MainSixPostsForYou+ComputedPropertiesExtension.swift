//
//  MainSixPostsForYou+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSixPostsForYouView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !posts.isEmpty
    }
    
    /// Color of the buttons of the view:
    var buttonColor: Color {
        .primary
    }
    
    /// Color of the background of the buttons of the view:
    var buttonBackgroundColor: Color {
        .init(.systemFill)
    }
    
    /// Font of the icon of the 'Like' button:
    var likeIconFont: Font {
        .system(
            size: 13,
            weight: .regular,
            design: .default
        )
    }
    
    /// Padding around the buttons of the view:
    var buttonPadding: Double {
        12
    }
    
    /// Padding around the content of the 'Bookmark' button:
    var bookmarkPadding: Double {
        5
    }
    
    /// Size of the frame of the icon of the 'Bookmark' button that is based on the size of the dynamic type that is currently selected:
    var bookmarkIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
