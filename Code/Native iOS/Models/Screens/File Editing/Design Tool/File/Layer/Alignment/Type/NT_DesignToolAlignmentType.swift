//
//  NT_DesignToolAlignmentType.swift
//  Native
//

import Foundation

enum NT_DesignToolAlignmentType: Int {
    
    // MARK: - Cases:
    
    case center
    case leading
    case trailing
    case top
    case bottom
    case topLeading
    case bottomLeading
    case topTrailing
    case bottomTrailing
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .center: return "Center"
        case .leading: return "Leading"
        case .trailing: return "Trailing"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topLeading: return "Top Leading"
        case .bottomLeading: return "Bottom Leading"
        case .topTrailing: return "Top Trailing"
        case .bottomTrailing: return "Bottom Trailing"
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolAlignmentType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolAlignmentType: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolAlignmentType: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolAlignmentType: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolAlignmentType: Codable {  }
