//
//  NT_TransactionType.swift
//  Native
//

import Foundation

enum NT_TransactionType: Int {
    
    // MARK: - Cases:
    
    case income
    case expense
    case transfer
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .income: return .init(localized: "Income")
        case .expense: return .init(localized: "Expense")
        case .transfer: return .init(localized: "Transfer")
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionType: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionType: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionType: Hashable {  }
