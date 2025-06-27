//
//  NT_DesignToolHorizontalAlignmentType.swift
//  Native
//

import Foundation

enum NT_DesignToolHorizontalAlignmentType: Int {
    
    // MARK: - Cases:
    
    case leading
    case center
    case trailing
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .leading: return "Leading"
        case .center: return "Center"
        case .trailing: return "Trailing"
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolHorizontalAlignmentType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolHorizontalAlignmentType: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolHorizontalAlignmentType: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolHorizontalAlignmentType: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolHorizontalAlignmentType: Codable {  }
