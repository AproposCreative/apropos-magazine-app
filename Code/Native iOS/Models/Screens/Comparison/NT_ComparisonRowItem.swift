//
//  NT_ComparisonRowItem.swift
//  Native
//

import Foundation

struct NT_ComparisonRowItem {
    
    // MARK: - Properties:
    
    /// Identifier of the item of the row for the comparison:
    let id: String
    
    /// Type of the item of the row for the comparison:
    let type: NT_ComparisonRowType
    
    init(
        id: String,
        type: NT_ComparisonRowType
    ) {
        
        /// Properties initialization:
        self.id = id
        self.type = type
    }
}

// MARK: - Identifiable:

extension NT_ComparisonRowItem: Identifiable {  }

// MARK: - Equatable:

extension NT_ComparisonRowItem: Equatable {  }

// MARK: - Hashable:

extension NT_ComparisonRowItem: Hashable {  }
