//
//  NT_TransactionsTimePeriod.swift
//  Native
//

import Foundation

enum NT_TransactionsTimePeriod: Int {
    
    // MARK: - Cases:
    
    case day
    case week
    case month
    case year
    
    // MARK: - Computed properties:
    
    /// Identifier of the time period:
    var id: Int {
        rawValue
    }
    
    /// Title of the time period:
    var title: String {
        switch self {
        case .day: return .init(localized: "Day")
        case .week: return .init(localized: "Week")
        case .month: return .init(localized: "Month")
        case .year: return .init(localized: "Year")
        }
    }
    
    /// Shortened title of the time period:
    var shortTitle: String {
        switch self {
        case .day: return .init(localized: "D")
        case .week: return .init(localized: "W")
        case .month: return .init(localized: "M")
        case .year: return .init(localized: "Y")
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionsTimePeriod: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionsTimePeriod: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionsTimePeriod: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionsTimePeriod: Hashable {  }
