//
//  NT_ImageResolution.swift
//  Native
//

import Foundation

enum NT_ImageResolution: Int {
    
    // MARK: - Cases:
    
    case low
    case medium
    case high
    case full
    
    // MARK: - Computed properties:
    
    /// Identifier of the resolution:
    var id: Int {
        rawValue
    }
    
    /// Title of the resolution:
    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .full: return "Full"
        }
    }
}

// MARK: - Identifiable:

extension NT_ImageResolution: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ImageResolution: CaseIterable {  }

// MARK: - Equatable:

extension NT_ImageResolution: Equatable {  }

// MARK: - Hashable:

extension NT_ImageResolution: Hashable {  }
