//
//  NT_CourseLesson.swift
//  Native
//

import Foundation

struct NT_CourseLesson {
    
    // MARK: - Properties:
    
    /// Identifier of the lesson:
    let id: String
    
    /// Title of the lesson:
    let title: String
    
    /// Subtitle of the lesson:
    let subtitle: String
    
    /// 'Bool' value indicating whether or not the lesson was already completed by the user:
    let isCompleted: Bool
    
    init(
        id: String,
        title: String,
        subtitle: String,
        isCompleted: Bool
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isCompleted = isCompleted
    }
}

// MARK: - Identifiable:

extension NT_CourseLesson: Identifiable {  }

// MARK: - Equatable:

extension NT_CourseLesson: Equatable {  }

// MARK: - Hashable:

extension NT_CourseLesson: Hashable {  }

// MARK: - Example:

extension NT_CourseLesson {
    
    // MARK: - Computed properties:
    
    /// An array of the example lessons:
    static var example: [NT_CourseLesson] {
        [
            .init(
                id: "Item.1",
                title: "Lesson - 1",
                subtitle: "Subtitle",
                isCompleted: true
            ),
            .init(
                id: "Item.2",
                title: "Lesson - 2",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.3",
                title: "Lesson - 3",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.4",
                title: "Lesson - 4",
                subtitle: "Subtitle",
                isCompleted: true
            ),
            .init(
                id: "Item.5",
                title: "Lesson - 5",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.6",
                title: "Lesson - 6",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.7",
                title: "Lesson - 7",
                subtitle: "Subtitle",
                isCompleted: true
            ),
            .init(
                id: "Item.8",
                title: "Lesson - 8",
                subtitle: "Subtitle",
                isCompleted: true
            ),
            .init(
                id: "Item.9",
                title: "Lesson - 9",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.10",
                title: "Lesson - 10",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.11",
                title: "Lesson - 11",
                subtitle: "Subtitle",
                isCompleted: false
            ),
            .init(
                id: "Item.12",
                title: "Lesson - 12",
                subtitle: "Subtitle",
                isCompleted: true
            )
        ]
    }
}
