//
//  NT_BudgetTimePeriodFilter.swift
//  Native
//

import Foundation

enum NT_BudgetTimePeriodFilter: Int {
    
    // MARK: - Cases:
    
    case thisWeek
    case thisMonth
    case lastMonth
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .thisWeek: return .init(localized: "This Week")
        case .thisMonth: return .init(localized: "This Month")
        case .lastMonth: return .init(localized: "Last Month")
        }
    }
}

// MARK: - Identifiable:

extension NT_BudgetTimePeriodFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_BudgetTimePeriodFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_BudgetTimePeriodFilter: Equatable {  }

// MARK: - Hashable:

extension NT_BudgetTimePeriodFilter: Hashable {  }
