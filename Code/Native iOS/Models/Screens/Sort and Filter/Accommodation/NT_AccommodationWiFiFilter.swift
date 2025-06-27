//
//  NT_AccommodationWiFiFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationWiFiFilter: Int {
    
    // MARK: - Cases:
    
    case yes
    case no
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .yes: return .init(localized: "Yes")
        case .no: return .init(localized: "No")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationWiFiFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationWiFiFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationWiFiFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationWiFiFilter: Hashable {  }
