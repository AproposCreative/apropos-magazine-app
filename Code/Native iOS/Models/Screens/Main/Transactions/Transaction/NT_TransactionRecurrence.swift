//
//  NT_TransactionRecurrence.swift
//  Native
//

import Foundation

enum NT_TransactionRecurrence: Int {
    
    // MARK: - Cases:
    
    case none
    case daily
    case weekly
    case monthly
    case yearly
    
    // MARK: - Computed properties:
    
    /// Identifier of the recurrence:
    var id: Int {
        rawValue
    }
    
    /// Title of the recurrence:
    var title: String {
        switch self {
        case .none: return .init(localized: "None")
        case .daily: return .init(localized: "Daily")
        case .weekly: return .init(localized: "Weekly")
        case .monthly: return .init(localized: "Monthly")
        case .yearly: return .init(localized: "Yearly")
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionRecurrence: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionRecurrence: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionRecurrence: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionRecurrence: Hashable {  }
