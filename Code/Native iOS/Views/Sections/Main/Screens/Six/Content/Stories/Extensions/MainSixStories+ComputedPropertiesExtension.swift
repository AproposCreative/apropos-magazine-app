//
//  MainSixStories+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainSixStoriesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !stories.isEmpty
    }
    
    /// Width of each of the stories that is based on the size of the dynamic type that is currently selected:
    var storyWidth: Double {
        dynamicTypeSize >= .accessibility1 ? 128 : 64
    }
}
