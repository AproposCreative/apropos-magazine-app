//
//  MainTwoJustForYou+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainTwoJustForYouView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !courses.isEmpty
    }
    
    /// Count of the items to display when using the 'containerRelativeFrame' modifier that is based on the size class of the device that the app is running on:
    var containerRelativeFrameCount: Int {
        horizontalSizeClass == .regular ? 2 : 1
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Height of each of the images of the courses that is based on the size of the dynamic type that is currently selected:
    var imageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 304 : 224
    }
}
