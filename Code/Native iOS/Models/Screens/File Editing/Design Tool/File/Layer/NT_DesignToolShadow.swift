//
//  NT_DesignToolShadow.swift
//  Native
//

import Foundation

struct NT_DesignToolShadow {
    
    // MARK: - Properties:
    
    /// Color of the shadow:
    let color: String
    
    /// Opacity of the color of the shadow:
    let opacity: Double
    
    /// Radius of the shadow:
    let radius: Double
    
    /// X-axis value of the shadow:
    let xAxis: Double
    
    /// Y-axis value of the shadow:
    let yAxis: Double
    
    /// 'Bool' value indicating whether or not the shadow should be mirrored onto the opposite side of the layer too:
    let isMirroring: Bool
    
    init(
        color: String,
        opacity: Double,
        radius: Double,
        xAxis: Double,
        yAxis: Double,
        isMirroring: Bool
    ) {
        
        /// Properties initialization:
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.isMirroring = isMirroring
    }
}

// MARK: - Equatable:

extension NT_DesignToolShadow: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolShadow: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolShadow: Codable {  }
