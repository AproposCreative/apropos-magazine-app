//
//  NT_DesignToolShape.swift
//  Native
//

import Foundation

enum NT_DesignToolShape: Int {
    
    // MARK: - Cases:
    
    case roundedRectangle
    case rectangle
    case circle
    case capsule
    case ellipse
    case path
    
    // MARK: - Computed properties:
    
    /// Identifier of the shape:
    var id: Int {
        rawValue
    }
    
    /// Title of the shape:
    var title: String {
        switch self {
        case .roundedRectangle: return "Rounded Rectangle"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .capsule: return "Capsule"
        case .ellipse: return "Ellipse"
        case .path: return "Path"
        }
    }
    
    /// Icon of the shape:
    var icon: String {
        switch self {
        case .roundedRectangle: return Icons.rectangle
        case .rectangle: return Icons.square
        case .circle: return Icons.circle
        case .capsule: return Icons.capsule
        case .ellipse: return Icons.oval
        case .path: return Icons.appDashed
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolShape: Identifiable {  }

// MARK: - CaseIterable:

extension NT_DesignToolShape: CaseIterable {  }

// MARK: - Equatable:

extension NT_DesignToolShape: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolShape: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolShape: Codable {  }
