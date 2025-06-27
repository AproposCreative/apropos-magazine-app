//
//  NT_DesignToolFrame.swift
//  Native
//

import Foundation

struct NT_DesignToolFrame {
    
    // MARK: - Properties:
    
    /// Width of the frame if applicable:
    let width: Double?
    
    /// Height of the frame if applicable:
    let height: Double?
    
    init(
        width: Double?,
        height: Double?
    ) {
        
        /// Properties initialization:
        self.width = width
        self.height = height
    }
}

// MARK: - Equatable:

extension NT_DesignToolFrame: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolFrame: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolFrame: Codable {  }
