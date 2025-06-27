//
//  NT_Folder.swift
//  Native
//

import SwiftUI

struct NT_Folder {
    
    // MARK: - Properties:
    
    /// Identifier of the folder:
    let id: String
    
    /// Title of the folder:
    let title: String
    
    /// Color of the folder:
    let color: Color
    
    /// Starting color of the gradient of the folder:
    let gradientStart: Color
    
    /// Ending color of the gradient of the folder:
    let gradientEnd: Color
    
    /// An array of the files that are part of the folder:
    let files: [NT_File]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        files: [NT_File]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.files = files
    }
    
    // MARK: - Computed properties:
    
    /// Count of the files that are part of the folder:
    var filesCount: Int {
        files.count
    }
}

// MARK: - Identifiable:

extension NT_Folder: Identifiable {  }

// MARK: - Equatable:

extension NT_Folder: Equatable {  }

// MARK: - Hashable:

extension NT_Folder: Hashable {  }

// MARK: - Example:

extension NT_Folder {
    
    // MARK: - Computed properties:
    
    /// An array of the example folders:
    static var example: [NT_Folder] {
        [
            .init(
                id: "Item.1",
                title: "Design Projects",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                files: .init(NT_File.example.prefix(2))
            ),
            .init(
                id: "Item.2",
                title: "Inspiration",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                files: .init(NT_File.example.prefix(4))
            ),
            .init(
                id: "Item.3",
                title: "Meeting Notes",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                files: .init(NT_File.example.prefix(3))
            ),
            .init(
                id: "Item.4",
                title: "App Ideas",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                files: NT_File.example
            ),
            .init(
                id: "Item.5",
                title: "Invoices",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                files: .init(NT_File.example.prefix(5))
            ),
            .init(
                id: "Item.6",
                title: "Agreements",
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                files: .init(NT_File.example.prefix(6))
            )
        ]
    }
}
