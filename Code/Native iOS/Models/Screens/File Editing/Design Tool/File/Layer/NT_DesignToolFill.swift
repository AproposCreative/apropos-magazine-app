//
//  NT_DesignToolFill.swift
//  Native
//

import Foundation

enum NT_DesignToolFill: Int {
    
    // MARK: - Cases:
    
    case none
    case solid
    case gradient
    
    // MARK: - Computed properties:
    
    /// Identifier of the fill:
    var id: Int {
        rawValue
    }
    
    /// Title of the fill:
    var title: String {
        switch self {
        case .none: return "None"
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolFill: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolFill: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolFill: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolFill: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolFill: Codable {  }
