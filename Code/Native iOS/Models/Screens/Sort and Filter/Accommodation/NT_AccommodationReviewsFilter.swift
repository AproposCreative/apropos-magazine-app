//
//  NT_AccommodationReviewsFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationReviewsFilter: Int {
    
    // MARK: - Cases:
    
    case outstanding
    case excellent
    case good
    case average
    case poor
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .outstanding: return .init(localized: "Outstanding")
        case .excellent: return .init(localized: "Excellent")
        case .good: return .init(localized: "Good")
        case .average: return .init(localized: "Average")
        case .poor: return .init(localized: "Poor")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationReviewsFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationReviewsFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationReviewsFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationReviewsFilter: Hashable {  }
