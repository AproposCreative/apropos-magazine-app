//
//  NT_AccommodationRoomTypeFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationRoomTypeFilter: Int {
    
    // MARK: - Cases:
    
    case standard
    case deluxe
    case suite
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .standard: return .init(localized: "Standard")
        case .deluxe: return .init(localized: "Deluxe")
        case .suite: return .init(localized: "Suite")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationRoomTypeFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationRoomTypeFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationRoomTypeFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationRoomTypeFilter: Hashable {  }
