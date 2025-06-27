//
//  MainTwoMyCourses+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTwoMyCoursesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given course:
    func title(_ course: NT_Course) -> String {
        course.title
    }
    
    /// Returns the count of the completed lessons that are part of the given course as a string:
    func completedLessonsCount(_ course: NT_Course) -> String {
        "\(course.completedLessonsCount) / \(course.lessonsCount) lessons"
    }
    
    /// Returns the count of the completed lessons that are part of the given course as a doable for a progress:
    func completedLessonsCount(_ course: NT_Course) -> Double {
        .init(course.completedLessonsCount)
    }
    
    /// Returns the count of the lessons that are part of the given course as a doable for a progress:
    func lessonsCount(_ course: NT_Course) -> Double {
        .init(course.lessonsCount)
    }
    
    /// Returns the image of the given course:
    func image(_ course: NT_Course) -> Image {
        .init(course.image)
    }
}
