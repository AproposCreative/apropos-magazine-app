//
//  NT_TransactionTypeFilter.swift
//  Native
//

import Foundation

enum NT_TransactionTypeFilter: Int {
    
    // MARK: - Cases:
    
    case income
    case expense
    case transfer
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .income: return .init(localized: "Income")
        case .expense: return .init(localized: "Expense")
        case .transfer: return .init(localized: "Transfer")
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionTypeFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionTypeFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionTypeFilter: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionTypeFilter: Hashable {  }
