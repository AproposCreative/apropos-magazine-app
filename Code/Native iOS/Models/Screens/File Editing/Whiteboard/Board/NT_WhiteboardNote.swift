//
//  NT_WhiteboardNote.swift
//  Native
//

import SwiftUI

struct NT_WhiteboardNote {
    
    // MARK: - Properties:
    
    /// Identifier of the note:
    let id: String
    
    /// An actual text of the note:
    let text: String
    
    /// Color of the note:
    let color: Color
    
    /// Starting color of the gradient of the note:
    let gradientStart: Color
    
    /// Ending color of the gradient of the note:
    let gradientEnd: Color
    
    /// Position of the note on the X-axis:
    let xAxisPosition: Double
    
    /// Position of the note on the Y-axis:
    let yAxisPosition: Double
    
    init(
        id: String,
        text: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        xAxisPosition: Double,
        yAxisPosition: Double
    ) {
        
        /// Properties initialization:
        self.id = id
        self.text = text
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.xAxisPosition = xAxisPosition
        self.yAxisPosition = yAxisPosition
    }
}

// MARK: - Identifiable:

extension NT_WhiteboardNote: Identifiable {  }

// MARK: - Equatable:

extension NT_WhiteboardNote: Equatable {  }

// MARK: - Hashable:

extension NT_WhiteboardNote: Hashable {  }

// MARK: - Example:

extension NT_WhiteboardNote {
    
    // MARK: - Computed properties:
    
    /// An array of the example notes:
    static var example: [NT_WhiteboardNote] {
        [
            .init(
                id: "Item.1",
                text: """
                Mobile app can be improved with more features, such as:
                
                - Bulk editing support on the main screen of the app
                - Redesigned settings screen
                - Ability to request the new
                features directly in the app
                """,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                xAxisPosition: 16,
                yAxisPosition: 16
            ),
            .init(
                id: "Item.2",
                text: """
                Schedule weekly sync meetings for the design and the development teams to review the redesign of the website.
                
                Ask the team members about their preferred days and times for that meeting.
                """,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                xAxisPosition: 232,
                yAxisPosition: 112
            ),
            .init(
                id: "Item.3",
                text: """
                Users complained that the web app takes a while to load properly which is a major issue and needs to be looked into as soon as possible. I will provide more details regarding this by the end of this week.
                """,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                xAxisPosition: 448,
                yAxisPosition: 64
            ),
            .init(
                id: "Item.4",
                text: """
                This quarter we need to focus on gathering the user feedback for our upcoming redesign of the entire web app.
                """,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                xAxisPosition: 64,
                yAxisPosition: 328
            )
        ]
    }
}
