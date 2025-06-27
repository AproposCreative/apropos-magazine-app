//
//  NT_AccommodationBreakfastFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationBreakfastFilter: Int {
    
    // MARK: - Cases:
    
    case included
    case paid
    case notAvailable
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .included: return .init(localized: "Included")
        case .paid: return .init(localized: "Paid")
        case .notAvailable: return .init(localized: "Not Available")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationBreakfastFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationBreakfastFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationBreakfastFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationBreakfastFilter: Hashable {  }
