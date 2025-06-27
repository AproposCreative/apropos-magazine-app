//
//  NT_DesignToolPaddingPosition.swift
//  Native
//

import Foundation

enum NT_DesignToolPaddingPosition: Int {
    
    // MARK: - Cases:
    
    case none
    case all
    case horizontal
    case vertical
    case top
    case leading
    case bottom
    case trailing
    
    // MARK: - Computed properties:
    
    /// Identifier of the position:
    var id: Int {
        rawValue
    }
    
    /// Title of the position:
    var title: String {
        switch self {
        case .none: return "None"
        case .all: return "All"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .top: return "Top"
        case .leading: return "Leading"
        case .bottom: return "Bottom"
        case .trailing: return "Trailing"
        }
    }
    
    /// Count of the position (Which is needed to calculate the correct frame of the layer):
    var count: Int {
        switch self {
        case .none:
            return 0
        case .all,
                .horizontal,
                .vertical:
            return 0
        case .top,
                .leading,
                .bottom,
                .trailing:
            return 1
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolPaddingPosition: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolPaddingPosition: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolPaddingPosition: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolPaddingPosition: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolPaddingPosition: Codable {  }
