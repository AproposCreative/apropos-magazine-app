//
//  NT_DesignToolBorder.swift
//  Native
//

import Foundation

struct NT_DesignToolBorder {
    
    // MARK: - Properties:
    
    /// Width of the border:
    let width: Double
    
    /// Color of the border:
    let color: String
    
    /// Opacity of the color of the border:
    let opacity: Double
    
    init(
        width: Double,
        color: String,
        opacity: Double
    ) {
        
        /// Properties initialization:
        self.width = width
        self.color = color
        self.opacity = opacity
    }
}

// MARK: - Equatable:

extension NT_DesignToolBorder: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolBorder: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolBorder: Codable {  }
