//
//  NT_AccountType.swift
//  Native
//

import Foundation

enum NT_AccountType: Int {
    
    // MARK: - Cases:
    
    case personal
    case business
    
    // MARK: - Computed properties:
    
    /// Identifier of the type of the account:
    var id: Int {
        rawValue
    }
    
    /// Title of the type of the account:
    var title: String {
        switch self {
        case .personal: return .init(localized: "Personal")
        case .business: return .init(localized: "Business")
        }
    }
}

// MARK: - Identifiable:

extension NT_AccountType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccountType: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccountType: Equatable {  }

// MARK: - Hashable:

extension NT_AccountType: Hashable {  }
