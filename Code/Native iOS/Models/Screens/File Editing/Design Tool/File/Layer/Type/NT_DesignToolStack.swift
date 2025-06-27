//
//  NT_DesignToolStack.swift
//  Native
//

import Foundation

enum NT_DesignToolStack: Int {
    
    // MARK: - Cases:
    
    case depth
    case vertical
    case horizontal
    
    // MARK: - Computed properties:
    
    /// Identifier of the stack:
    var id: Int {
        rawValue
    }
    
    /// Title of the stack:
    var title: String {
        switch self {
        case .depth: return "Depth"
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }
    
    /// Icon of the stack:
    var icon: String {
        switch self {
        case .depth: return Icons.squareStackThreeDUp
        case .vertical: return Icons.linesMeasurementVertical
        case .horizontal: return Icons.linesMeasurementHorizontal
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolStack: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolStack: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolStack: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolStack: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolStack: Codable {  }
