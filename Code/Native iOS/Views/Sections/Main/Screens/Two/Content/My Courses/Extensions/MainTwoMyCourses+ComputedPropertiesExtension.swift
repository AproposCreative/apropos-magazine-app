//
//  MainTwoMyCourses+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainTwoMyCoursesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !courses.isEmpty
    }
}
