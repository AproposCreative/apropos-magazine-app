//
//  NT_Task.swift
//  Native
//

import Foundation

struct NT_Task {
    
    // MARK: - Properties:
    
    /// Identifier of the task:
    let id: String
    
    /// Title of the task:
    let title: String
    
    /// Notes of the task:
    let notes: String
    
    /// 'Bool' value indicating whether or not the task is completed:
    let isCompleted: Bool
    
    /// An array of the tags that are assigned to the task:
    let tags: [NT_TasksTag]
    
    init(
        id: String,
        title: String,
        notes: String,
        isCompleted: Bool,
        tags: [NT_TasksTag]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.tags = tags
    }
}

// MARK: - Identifiable:

extension NT_Task: Identifiable {  }

// MARK: - Equatable:

extension NT_Task: Equatable {  }

// MARK: - Hashable:

extension NT_Task: Hashable {  }

// MARK: - Example:

extension NT_Task {
    
    // MARK: - Computed properties:
    
    /// An array of the example tasks:
    static var example: [NT_Task] {
        [
            .init(
                id: "Item.1",
                title: "Send an Email to John About the Latest Design Project",
                notes: "Make sure to include all the latest updates and changes",
                isCompleted: false,
                tags: NT_TasksTag.example.filter {
                    $0.id == "Item.1"
                    || $0.id == "Item.2"
                }
            ),
            .init(
                id: "Item.2",
                title: "Complete a Set of User Interviews for the Upcoming Redesign Project",
                notes: "Try to interview at least 5-10 users",
                isCompleted: false,
                tags: NT_TasksTag.example.filter { $0.id == "Item.3" }
            ),
            .init(
                id: "Item.3",
                title: "Schedule Monthly 1:1’s with the team members",
                notes: "Ask about their preferred time",
                isCompleted: false,
                tags: NT_TasksTag.example.filter {
                    $0.id == "Item.4"
                    || $0.id == "Item.5"
                    || $0.id == "Item.6"
                }
            )
        ]
    }
}
