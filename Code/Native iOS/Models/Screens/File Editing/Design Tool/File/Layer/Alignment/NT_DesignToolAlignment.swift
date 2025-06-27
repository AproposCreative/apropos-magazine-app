//
//  NT_DesignToolAlignment.swift
//  Native
//

import Foundation

enum NT_DesignToolAlignment {
    
    // MARK: - Cases:
    
    case generic (NT_DesignToolAlignmentType)
    case vertical (NT_DesignToolVerticalAlignmentType)
    case horizontal (NT_DesignToolHorizontalAlignmentType)
    
    // MARK: - Computed properties:
    
    /// Title of the alignment:
    var title: String {
        switch self {
        case .generic (let type): return type.title
        case .vertical (let type): return type.title
        case .horizontal (let type): return type.title
        }
    }
}

// MARK: - Equatable:

extension NT_DesignToolAlignment: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolAlignment: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolAlignment: Codable {  }
