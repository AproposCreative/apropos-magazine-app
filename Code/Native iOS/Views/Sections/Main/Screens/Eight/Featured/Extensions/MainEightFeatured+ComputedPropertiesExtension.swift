//
//  MainEightFeatured+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainEightFeaturedView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !articles.isEmpty
    }
    
    /// 'Bool' value indicating whether or the horizontal size class of the device that the app is running on is regular:
    var isRegularHorizontalSizeClass: Bool {
        horizontalSizeClass == .regular
    }
    
    /// Count of the items to display when using the 'containerRelativeFrame' modifier that is based on the horizontal size class of the device that the app is running on:
    var containerRelativeFrameCount: Int {
        isRegularHorizontalSizeClass ? 2 : 1
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        24
    }
    
    /// Spacing between the content of the articles:
    var articlesSpacing: Double {
        16
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
