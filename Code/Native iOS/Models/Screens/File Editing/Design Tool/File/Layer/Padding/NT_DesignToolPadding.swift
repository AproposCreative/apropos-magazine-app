//
//  NT_DesignToolPadding.swift
//  Native
//

import Foundation

struct NT_DesignToolPadding {
    
    // MARK: - Properties:
    
    /// Position of the padding:
    let position: NT_DesignToolPaddingPosition
    
    /// Amount of the padding:
    let amount: Double
    
    init(
        position: NT_DesignToolPaddingPosition,
        amount: Double
    ) {
        
        /// Properties initialization:
        self.position = position
        self.amount = amount
    }
}

// MARK: - Equatable:

extension NT_DesignToolPadding: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolPadding: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolPadding: Codable {  }
