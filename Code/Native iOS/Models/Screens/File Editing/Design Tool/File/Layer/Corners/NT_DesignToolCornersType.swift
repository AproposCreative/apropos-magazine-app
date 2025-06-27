//
//  NT_DesignToolCornersType.swift
//  Native
//

import Foundation

enum NT_DesignToolCornersType: Int {
    
    // MARK: - Cases:
    
    case continuous
    case circular
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .continuous: return "Continuous"
        case .circular: return "Circular"
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolCornersType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolCornersType: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolCornersType: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolCornersType: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolCornersType: Codable {  }
