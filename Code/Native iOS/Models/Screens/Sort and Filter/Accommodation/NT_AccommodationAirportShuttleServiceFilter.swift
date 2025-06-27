//
//  NT_AccommodationAirportShuttleServiceFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationAirportShuttleServiceFilter: Int {
    
    // MARK: - Cases:
    
    case available
    case notAvailable
    case free
    case paid
    case scheduled
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .available: return .init(localized: "Available")
        case .notAvailable: return .init(localized: "Not Available")
        case .free: return .init(localized: "Free")
        case .paid: return .init(localized: "Paid")
        case .scheduled: return .init(localized: "Scheduled")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationAirportShuttleServiceFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationAirportShuttleServiceFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationAirportShuttleServiceFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationAirportShuttleServiceFilter: Hashable {  }
