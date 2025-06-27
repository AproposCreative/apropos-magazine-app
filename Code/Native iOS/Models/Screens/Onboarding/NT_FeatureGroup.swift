//
//  NT_FeatureGroup.swift
//  Native
//

import Foundation

enum NT_FeatureGroup: Int {
    
    // MARK: - Cases:
    
    case first
    case second
    
    // MARK: - Computed properties:
    
    /// Identifier of the group of the features:
    var id: Int {
        rawValue
    }
    
    /// An array of the features that are part of the group of the features:
    var features: [NT_Feature] {
        switch self {
        case .first: return .init(NT_Feature.allCases.prefix(3))
        case .second: return .init(NT_Feature.allCases.suffix(3))
        }
    }
}

// MARK: - Identifiable:

extension NT_FeatureGroup: Identifiable {  }

// MARK: - CaseIterable:

extension NT_FeatureGroup: CaseIterable {  }

// MARK: - Equatable:

extension NT_FeatureGroup: Equatable {  }

// MARK: - Hashable:

extension NT_FeatureGroup: Hashable {  }
