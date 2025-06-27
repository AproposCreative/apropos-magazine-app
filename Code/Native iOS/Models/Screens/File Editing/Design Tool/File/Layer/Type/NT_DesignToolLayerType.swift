//
//  NT_DesignToolLayerType.swift
//  Native
//

import Foundation

enum NT_DesignToolLayerType {
    
    // MARK: - Cases:
    
    case shape (NT_DesignToolShape)
    case stack (NT_DesignToolStack)
    
    // MARK: - Computed properties:
    
    /// Title of the type:
    var title: String {
        switch self {
        case .shape (_): return "Shape"
        case .stack (_): return "Stack"
        }
    }
    
    /// Icon of the given type:
    var icon: String {
        switch self {
        case .shape (_): return Icons.rectangle
        case .stack (_): return Icons.squareStackThreeDUp
        }
    }
    
    /// An array of all of the types:
    static var allTypes: [Self] {
        [
            .shape(.roundedRectangle),
            .stack(.depth)
        ]
    }
}

// MARK: - Equatable:

extension NT_DesignToolLayerType: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolLayerType: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolLayerType: Codable {  }
