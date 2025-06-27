//
//  NT_DesignToolCorners.swift
//  Native
//

import SwiftUI

struct NT_DesignToolCorners {
    
    // MARK: - Properties:
    
    /// Radius of the corners:
    let radius: Double
    
    /// Type of the corners:
    let type: NT_DesignToolCornersType
    
    init(
        radius: Double,
        type: NT_DesignToolCornersType
    ) {
        
        /// Properties initialization:
        self.radius = radius
        self.type = type
    }
    
    // MARK: - Computed properties:
    
    /// Style of the corners:
    var style: RoundedCornerStyle {
        switch type {
        case .continuous: return .continuous
        case .circular: return .circular
        }
    }
}

// MARK: - Equatable:

extension NT_DesignToolCorners: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolCorners: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolCorners: Codable {  }
