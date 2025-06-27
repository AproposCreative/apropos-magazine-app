//
//  NT_DesignToolVerticalAlignmentType.swift
//  Native
//

import Foundation

enum NT_DesignToolVerticalAlignmentType: Int {
    
    // MARK: - Cases:
    
    case top
    case center
    case bottom
    case firstTextBaseline
    case lastTextBaseline
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        case .firstTextBaseline: return "First Text Baseline"
        case .lastTextBaseline: return "Last Text Baseline"
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolVerticalAlignmentType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolVerticalAlignmentType: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolVerticalAlignmentType: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolVerticalAlignmentType: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolVerticalAlignmentType: Codable {  }
