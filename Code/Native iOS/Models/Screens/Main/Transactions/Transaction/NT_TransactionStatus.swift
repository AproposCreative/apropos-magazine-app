//
//  NT_TransactionStatus.swift
//  Native
//

import Foundation

enum NT_TransactionStatus: Int {
    
    // MARK: - Cases:
    
    case cleared
    case pending
    
    // MARK: - Computed properties:
    
    /// Identifier of the status:
    var id: Int {
        rawValue
    }
    
    /// Title of the status:
    var title: String {
        switch self {
        case .cleared: return "Cleared"
        case .pending: return "Pending"
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionStatus: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionStatus: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionStatus: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionStatus: Hashable {  }
