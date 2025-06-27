//
//  NT_Message.swift
//  Native
//

import Foundation

struct NT_Message {
    
    // MARK: - Properties:
    
    /// Identifier of the message:
    let id: String
    
    /// Name of the person who sent the message:
    let name: String
    
    /// An actual message:
    let content: String
    
    /// Date when the message was sent:
    let date: Date
    
    /// Image of the person who sent the message
    let image: String
    
    /// 'Bool' value indicating whether or not the user has read the message:
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
    
    /// Time interval since the message was sent as a string:
    var timeIntervalSinceSent: String {
        if let timeInterval: String = Formatters.timeInterval(fromDate: date) {
            return timeInterval
        } else {
            return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_Message: Identifiable {  }

// MARK: - Equatable:

extension NT_Message: Equatable {  }

// MARK: - Hashable:

extension NT_Message: Hashable {  }

// MARK: - Example:

extension NT_Message {
    
    // MARK: - Computed properties:
    
    /// An array of the example messages:
    static var example: [NT_Message] {
        [
            .init(
                id: "Item.1",
                name: "Amanda Clarke",
                content: "Hey, how are you doing today? I have got a question about our trip to Mexico.",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29,
                    withHour: 14,
                    withMinute: 8
                ),
                image: Images.main31,
                isRead: false
            ),
            .init(
                id: "Item.2",
                name: "Jessica Anderson",
                content: "Do you have time today for a quick meeting to discuss a new project?",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29,
                    withHour: 9,
                    withMinute: 15
                ),
                image: Images.main32,
                isRead: true
            ),
            .init(
                id: "Item.3",
                name: "Tom Johnson",
                content: "Could you please take a look at my website and give me the feedback?",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 28,
                    withHour: 10,
                    withMinute: 30
                ),
                image: Images.main33,
                isRead: false
            ),
            .init(
                id: "Item.4",
                name: "Jenny Poulson",
                content: "I am not sure, but I think it’s okay. I would maybe change the design of the hero section of the website, but other than that, I think it’s great.",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 27,
                    withHour: 16,
                    withMinute: 15
                ),
                image: Images.main34,
                isRead: true
            ),
            .init(
                id: "Item.5",
                name: "James Phillips",
                content: "Okay, thanks!",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 25,
                    withHour: 8,
                    withMinute: 45
                ),
                image: Images.main35,
                isRead: true
            )
        ]
    }
}
