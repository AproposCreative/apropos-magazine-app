//
//  FileEditingThreeBoardGridLinesView+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingThreeBoardGridLinesView {
    
    // MARK: - Computed properties:
    
    /// An array of the vertical grid lines that are based on the size of the proxy, as well as the size of the frame:
    var verticalGridLines: ClosedRange<Int> {
        0...Int(proxy.size.height / frame)
    }
    
    /// An array of the horizontal grid lines that are based on the size of the proxy, as well as the size of the frame:
    var horizontalGridLines: ClosedRange<Int> {
        0...Int(proxy.size.width / frame)
    }
    
    /// Color of each of the grid lines
    var color: Color {
        .primary.opacity(0.05)
    }
    
    /// Size of the frame of each of the grid lines
    var frame: Double {
        1
    }
    
    /// Spacing between the grid lines:
    var spacing: Double {
        10
    }
}
