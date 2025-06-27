//
//  NT_Project.swift
//  Native
//

import SwiftUI

struct NT_Project {
    
    // MARK: - Properties:
    
    /// Identifier of the project:
    let id: String
    
    /// Title of the project:
    let title: String
    
    /// Color of the project:
    let color: Color
    
    /// Starting color of the gradient of the project:
    let gradientStart: Color
    
    /// Ending color of the gradient of the project:
    let gradientEnd: Color
    
    /// Icon of the project
    let icon: String
    
    /// An array of the tasks that are part of the project:
    let tasks: [NT_Task]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        tasks: [NT_Task]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.tasks = tasks
    }
    
    // MARK: - Computed properties:
    
    /// Count of the tasks that are part of the project:
    var tasksCount: Int {
        tasks.count
    }
}

// MARK: - Identifiable:

extension NT_Project: Identifiable {  }

// MARK: - Equatable:

extension NT_Project: Equatable {  }

// MARK: - Hashable:

extension NT_Project: Hashable {  }

// MARK: - Example:

extension NT_Project {
    
    // MARK: - Computed properties:
    
    /// An array of the example projects:
    static var example: [NT_Project] {
        [
            .init(
                id: "Item.1",
                title: "New Website Design",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.paintbrush,
                tasks: NT_Task.example
            ),
            .init(
                id: "Item.2",
                title: "Admin Work",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.docPlaintext,
                tasks: .init(NT_Task.example.dropFirst())
            ),
            .init(
                id: "Item.3",
                title: "Weekly 1:1 Meetings",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.calendar,
                tasks: .init(NT_Task.example.dropFirst())
            )
        ]
    }
}
