//
//  NT_AccommodationCategoryFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationCategoryFilter: Int {
    
    // MARK: - Cases:
    
    case hotel
    case resort
    case apartment
    case house
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .hotel: .init(localized: "Hotel")
        case .resort: .init(localized: "Resort")
        case .apartment: .init(localized: "Apartment")
        case .house: .init(localized: "House")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationCategoryFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationCategoryFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationCategoryFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationCategoryFilter: Hashable {  }
