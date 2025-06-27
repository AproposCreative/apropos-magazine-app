//
//  NT_ComparisonRowType.swift
//  Native
//

import Foundation

enum NT_ComparisonRowType {
    
    // MARK: - Cases:
    
    case none
    case header (
        title: String,
        isTitleLocalized: Bool
    )
    case included
    case excluded
}

// MARK: - Equatable:

extension NT_ComparisonRowType: Equatable {  }

// MARK: - Hashable:

extension NT_ComparisonRowType: Hashable {  }
