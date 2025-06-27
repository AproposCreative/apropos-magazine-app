//
//  NT_AccommodationLevelOfServiceFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationLevelOfServiceFilter: Int {
    
    // MARK: - Cases:
    
    case fiveStars
    case fourStars
    case threeStars
    case twoStars
    case oneStar
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .fiveStars: return .init(localized: "5 stars")
        case .fourStars: return .init(localized: "4 stars")
        case .threeStars: return .init(localized: "3 stars")
        case .twoStars: return .init(localized: "2 stars")
        case .oneStar: return .init(localized: "1 star")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationLevelOfServiceFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationLevelOfServiceFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationLevelOfServiceFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationLevelOfServiceFilter: Hashable {  }
