//
//  NT_Drive.swift
//  Native
//

import SwiftUI

struct NT_Drive {
    
    // MARK: - Properties:
    
    /// Identifier of the drive:
    let id: String
    
    /// Title of the drive:
    let title: String
    
    /// Color of the drive:
    let color: Color
    
    /// Starting color of the gradient of the drive:
    let gradientStart: Color
    
    /// Ending color of the gradient of the drive:
    let gradientEnd: Color
    
    /// Capacity of the drive:
    let capacity: Int64
    
    /// An array of the files that are part of the drive:
    let files: [NT_File]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        capacity: Int64,
        files: [NT_File]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.capacity = capacity
        self.files = files
    }
    
    // MARK: - Computed properties:
    
    /// Count of the files that are part of the drive:
    var filesCount: Int {
        files.count
    }
    
    /// Capacity of the drive that is currently used that is based on the files that are part of it:
    var usedCapacity: Int64 {
        files.map { $0.size }.reduce(0, +)
    }
}

// MARK: - Identifiable:

extension NT_Drive: Identifiable {  }

// MARK: - Equatable:

extension NT_Drive: Equatable {  }

// MARK: - Hashable:

extension NT_Drive: Hashable {  }

// MARK: - Example:

extension NT_Drive {
    
    // MARK: - Computed properties:
    
    /// An array of the example drives:
    static var example: [NT_Drive] {
        [
            .init(
                id: "Item.1",
                title: "External Drive",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                capacity: 128000000000,
                files: .init(NT_File.example.prefix(5))
            ),
            .init(
                id: "Item.2",
                title: "Photography and Design 2024",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                capacity: 2000000000000,
                files: .init(NT_File.example.prefix(3))
            ),
            .init(
                id: "Item.3",
                title: "Work Projects and Ideas",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                capacity: 512000000000,
                files: .init(NT_File.example.prefix(2))
            ),
            .init(
                id: "Item.4",
                title: "Backup Drive",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                capacity: 8000000000000,
                files: .init(NT_File.example.prefix(8))
            ),
            .init(
                id: "Item.5",
                title: "Shared Drive",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                capacity: 1000000000000,
                files: .init(NT_File.example.prefix(6))
            ),
            .init(
                id: "Item.6",
                title: "App Design and Development",
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                capacity: 256000000000,
                files: .init(NT_File.example.prefix(4))
            )
        ]
    }
}
