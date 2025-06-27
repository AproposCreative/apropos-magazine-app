//
//  NT_AccommodationAmenitiesFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationAmenitiesFilter: Int {
    
    // MARK: - Cases:
    
    case fitnessCenter
    case spaCentre
    case swimmingPool
    case conferenceRoom
    case gym
    case parking
    case roomService
    case concierge
    case lateCheckout
    case businessCenter
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .fitnessCenter: return .init(localized: "Fitness Center")
        case .spaCentre: return .init(localized: "Spa Centre")
        case .swimmingPool: return .init(localized: "Swimming Pool")
        case .conferenceRoom: return .init(localized: "Conference Room")
        case .gym: return .init(localized: "Gym")
        case .parking: return .init(localized: "Parking")
        case .roomService: return .init(localized: "Room Service")
        case .concierge: return .init(localized: "Concierge")
        case .lateCheckout: return .init(localized: "Late Checkout")
        case .businessCenter: return .init(localized: "Business Center")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationAmenitiesFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationAmenitiesFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationAmenitiesFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationAmenitiesFilter: Hashable {  }
