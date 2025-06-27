//
//  NT_CoursesCategory.swift
//  Native
//

import SwiftUI

struct NT_CoursesCategory {
    
    // MARK: - Properties:
    
    /// Identifier of the category:
    let id: String
    
    /// Title of the category:
    let title: String
    
    /// Color of the category:
    let color: Color
    
    /// Starting color of the gradient of the category if applicable:
    let gradientStart: Color
    
    /// Ending color of the gradient of the category if applicable:
    let gradientEnd: Color
    
    /// Icon of the category:
    let icon: String
    
    /// An array of the courses that are part of the category:
    let courses: [NT_Course]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        courses: [NT_Course]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.courses = courses
    }
    
    // MARK: - Computed properties:
    
    /// Count of courses that are part of the category:
    var coursesCount: Int {
        courses.count
    }
}

// MARK: - Identifiable:

extension NT_CoursesCategory: Identifiable {  }

// MARK: - Equatable:

extension NT_CoursesCategory: Equatable {  }

// MARK: - Hashable:

extension NT_CoursesCategory: Hashable {  }

// MARK: - Example:

extension NT_CoursesCategory {
    
    // MARK: - Computed properties:
    
    /// An array of the example categories:
    static var example: [NT_CoursesCategory] {
        [
            .init(
                id: "Item.1",
                title: "Product Design & UX",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.handTap,
                courses: NT_Course.example
            ),
            .init(
                id: "Item.2",
                title: "Backend Development",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.gearshape,
                courses: .init(NT_Course.example.prefix(3))
            ),
            .init(
                id: "Item.3",
                title: "Graphic Design",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.paintbrush,
                courses: .init(NT_Course.example.prefix(5))
            ),
            .init(
                id: "Item.4",
                title: "Photography & Video Editing",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.camera,
                courses: .init(NT_Course.example.prefix(4))
            ),
            .init(
                id: "Item.5",
                title: "iOS Development",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.curlybraces,
                courses: .init(NT_Course.example.prefix(6))
            )
        ]
    }
}
