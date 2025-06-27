//
//  NT_Course.swift
//  Native
//

import Foundation

struct NT_Course {
    
    // MARK: - Properties:
    
    /// Identifier of the course:
    let id: String
    
    /// Title of the course:
    let title: String
    
    /// Image of the course:
    let image: String
    
    /// An array of the lessons that are part of the course:
    let lessons: [NT_CourseLesson]
    
    init(
        id: String,
        title: String,
        image: String,
        lessons: [NT_CourseLesson]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.image = image
        self.lessons = lessons
    }
    
    // MARK: - Computed properties:
    
    /// Count of the lessons that are part of the course:
    var lessonsCount: Int {
        lessons.count
    }
    
    /// Count of the completed lessons that are part of the course:
    var completedLessonsCount: Int {
        lessons.filter { $0.isCompleted }.count
    }
}

// MARK: - Identifiable:

extension NT_Course: Identifiable {  }

// MARK: - Equatable:

extension NT_Course: Equatable {  }

// MARK: - Hashable:

extension NT_Course: Hashable {  }

// MARK: - Example:

extension NT_Course {
    
    // MARK: - Computed properties:
    
    /// An array of the example courses:
    static var example: [NT_Course] {
        [
            .init(
                id: "Item.1",
                title: "Advanced SwiftUI",
                image: Images.main21,
                lessons: NT_CourseLesson.example
            ),
            .init(
                id: "Item.2",
                title: "Advanced Product Design",
                image: Images.main22,
                lessons: .init(NT_CourseLesson.example.prefix(3))
            ),
            .init(
                id: "Item.3",
                title: "Graphic Design Introduction",
                image: Images.main23,
                lessons: .init(NT_CourseLesson.example.prefix(5))
            ),
            .init(
                id: "Item.4",
                title: "Introduction to Photography",
                image: Images.main24,
                lessons: .init(NT_CourseLesson.example.prefix(10))
            ),
            .init(
                id: "Item.5",
                title: "Web Development",
                image: Images.main25,
                lessons: .init(NT_CourseLesson.example.prefix(8))
            ),
            .init(
                id: "Item.6",
                title: "Advanced SwiftUI",
                image: Images.main26,
                lessons: .init(NT_CourseLesson.example.prefix(6))
            ),
            .init(
                id: "Item.7",
                title: "Graphic Design for Beginners",
                image: Images.main27,
                lessons: .init(NT_CourseLesson.example.prefix(3))
            ),
            .init(
                id: "Item.8",
                title: "Ultimate Motion Design",
                image: Images.main28,
                lessons: .init(NT_CourseLesson.example.prefix(4))
            )
        ]
    }
}
