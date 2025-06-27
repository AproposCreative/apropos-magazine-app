//
//  NT_Usage.swift
//  Native
//

import SwiftUI

struct NT_Usage {
    
    // MARK: - Properties:
    
    /// Identifier of the usage item:
    let id: String
    
    /// Title of the usage item:
    let title: String
    
    /// Color of the usage item:
    let color: Color
    
    /// Starting color of the gradient of the usage item:
    let gradientStart: Color
    
    /// Ending color of the gradient of the usage item:
    let gradientEnd: Color
    
    /// Icon of the usage item:
    let icon: String
    
    /// Type of the usage item:
    let type: NT_UsageType
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        type: NT_UsageType
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.type = type
    }
}

// MARK: - Identifiable:

extension NT_Usage: Identifiable {  }

// MARK: - Equatable:

extension NT_Usage: Equatable {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the arguments on both sides are equal:
    static func == (
        lhs: NT_Usage,
        rhs: NT_Usage
    ) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable:

extension NT_Usage: Hashable {
    
    // MARK: - Functions:
    
    /// Hashes the values of the usage item using the given hasher:
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Example:

extension NT_Usage {
    
    // MARK: - Computed properties:
    
    /// An array of the example usage items:
    static var example: [NT_Usage] {
        [
            .init(
                id: "Item.1",
                title: "Bandwidth",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.serverRack,
                type: .storage(
                    total: 1000000000000,
                    used: 501600000000
                )
            ),
            .init(
                id: "Item.2",
                title: "Storage",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.externaldrive,
                type: .storage(
                    total: 20000000000000,
                    used: 2200000000000
                )
            ),
            .init(
                id: "Item.3",
                title: "Analytics Events",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.chartLineUptrendXYAxis,
                type: .value(
                    total: 250000,
                    used: 177856
                )
            ),
            .init(
                id: "Item.4",
                title: "Functions",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.curlybraces,
                type: .value(
                    total: 500000,
                    used: 153989
                )
            )
        ]
    }
}
