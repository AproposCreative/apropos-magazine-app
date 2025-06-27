//
//  MainEightArticles+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainEightArticlesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !articles.isEmpty
    }
    
    /// Size of the frame of the images of the view:
    var imageFrame: Double {
        48
    }
}
