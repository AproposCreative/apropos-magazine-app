//
//  NT_ComparisonFeature.swift
//  Native
//

import Foundation

enum NT_ComparisonFeature: Int {
    
    // MARK: - Cases:
    
    case latestTechnologies
    case nativeDesign
    case reusableComponents
    case globalStyleguide
    case fullyAccessible
    case scalableSourceCode
    
    // MARK: - Computed properties:
    
    /// Identifier of the feature:
    var id: Int {
        rawValue
    }
    
    /// Title of the feature:
    var title: String {
        switch self {
        case .latestTechnologies: return "Latest Technologies"
        case .nativeDesign: return "Native Design"
        case .reusableComponents: return "Reusable Components"
        case .globalStyleguide: return "Global Styleguide"
        case .fullyAccessible: return "Fully Accessible"
        case .scalableSourceCode: return "Scalable Source Code"
        }
    }
    
    /// 'Bool' value indicating whether or not the feature is available in the free version of the app:
    var isFree: Bool {
        switch self {
        case .latestTechnologies: return true
        case .nativeDesign: return false
        case .reusableComponents: return false
        case .globalStyleguide: return false
        case .fullyAccessible: return false
        case .scalableSourceCode: return false
        }
    }
}

// MARK: - Identifiable:

extension NT_ComparisonFeature: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ComparisonFeature: CaseIterable {  }

// MARK: - Equatable:

extension NT_ComparisonFeature: Equatable {  }

// MARK: - Hashable:

extension NT_ComparisonFeature: Hashable {  }
