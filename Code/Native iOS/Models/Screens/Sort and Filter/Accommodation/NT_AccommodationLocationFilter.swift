//
//  NT_AccommodationLocationFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationLocationFilter: Int {
    
    // MARK: - Cases:
    
    case losAngeles
    case sanFrancisco
    case newYork
    case chicago
    case seattle
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .losAngeles: .init(localized: "Los Angeles, CA")
        case .sanFrancisco: .init(localized: "San Francisco, CA")
        case .newYork: .init(localized: "New York, NY")
        case .chicago: .init(localized: "Chicago, IL")
        case .seattle: .init(localized: "Seattle, WA")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationLocationFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationLocationFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationLocationFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationLocationFilter: Hashable {  }
