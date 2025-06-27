//
//  NT_AccommodationCancellationPolicyFilter.swift
//  Native
//

import Foundation

enum NT_AccommodationCancellationPolicyFilter: Int {
    
    // MARK: - Cases:
    
    case free
    case paid
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .free: return .init(localized: "Free")
        case .paid: return .init(localized: "Paid")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccommodationCancellationPolicyFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccommodationCancellationPolicyFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccommodationCancellationPolicyFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AccommodationCancellationPolicyFilter: Hashable {  }
