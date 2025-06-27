//
//  MainTwoJustForYou+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTwoJustForYouView {
    
    // MARK: - Functions:
    
    /// Returns the identifier of the given course:
    func identifier(_ course: NT_Course) -> String {
        course.id
    }
    
    /// Returns the title of the given course:
    func title(_ course: NT_Course) -> String {
        course.title
    }
    
    /// Returns the count of lessons that are part of the given course as a string:
    func lessonsCount(_ course: NT_Course) -> String {
        "\(course.lessonsCount) lessons"
    }
    
    /// Returns the image of the given course:
    func image(_ course: NT_Course) -> Image {
        .init(course.image)
    }
    
    /// Returns the scale effect of the content in the given phase (Needed to add the scroll transition when scrolling between the different courses):
    nonisolated func scaleEffect(inPhase phase: ScrollTransitionPhase) -> Double {
        phase.isIdentity ? 1 : 0.8
    }
}
