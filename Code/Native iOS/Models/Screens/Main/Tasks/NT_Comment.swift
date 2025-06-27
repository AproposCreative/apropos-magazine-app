//
//  NT_Comment.swift
//  Native
//

import Foundation

struct NT_Comment {
    
    // MARK: - Properties:
    
    /// Identifier of the comment:
    let id: String
    
    /// Name of the person who left the comment:
    let name: String
    
    /// An actual comment:
    let content: String
    
    /// Date when the comment was left:
    let date: Date
    
    /// Image of the person who left the comment
    let image: String
    
    /// 'Bool' value indicating whether or not the user has read the comment:
    let isRead: Bool
    
    init(
        id: String,
        name: String,
        content: String,
        date: Date,
        image: String,
        isRead: Bool
    ) {
        
        /// Properties initialization:
        self.id = id
        self.name = name
        self.content = content
        self.date = date
        self.image = image
        self.isRead = isRead
    }
    
    // MARK: - Computed properties:
    
    /// Time interval since the comment was left as a string:
    var timeIntervalSinceLeft: String {
        if let timeInterval: String = Formatters.timeInterval(fromDate: date) {
            return timeInterval
        } else {
            return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_Comment: Identifiable {  }

// MARK: - Equatable:

extension NT_Comment: Equatable {  }

// MARK: - Hashable:

extension NT_Comment: Hashable {  }

// MARK: - Example:

extension NT_Comment {
    
    // MARK: - Computed properties:
    
    /// An array of the example comments:
    static var example: [NT_Comment] {
        [
            .init(
                id: "Item.1",
                name: "Amanda Clarke",
                content: "Hey, how are you doing today? I have got a question about our latest design project.",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29,
                    withHour: 14,
                    withMinute: 8
                ),
                image: Images.main51,
                isRead: false
            ),
            .init(
                id: "Item.2",
                name: "Tom Johnson",
                content: "Could you please take a look at my website and give me the feedback?",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 28,
                    withHour: 10,
                    withMinute: 30
                ),
                image: Images.main52,
                isRead: false
            ),
            .init(
                id: "Item.3",
                name: "Jenny Poulson",
                content: "I am not sure, but I think it’s okay. I would maybe change the design of the hero section of the website, but other than that, I think it’s great.",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 25,
                    withHour: 8,
                    withMinute: 45
                ),
                image: Images.main53,
                isRead: true
            )
        ]
    }
}
