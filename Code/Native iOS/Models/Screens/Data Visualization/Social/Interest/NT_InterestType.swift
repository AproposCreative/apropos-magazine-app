//
//  NT_InterestType.swift
//  Native
//

import Foundation

enum NT_InterestType: Int {
    
    // MARK: - Cases:
    
    case all
    case new
    
    // MARK: - Computed properties:
    
    /// Identifier of the type of the interest:
    var id: Int {
        rawValue
    }
    
    /// Title of the type of the interest:
    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .new: return String(localized: "New")
        }
    }
}

// MARK: - Identifiable:

extension NT_InterestType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_InterestType: CaseIterable {  }

// MARK: - Equatable:

extension NT_InterestType: Equatable {  }

// MARK: - Hashable:

extension NT_InterestType: Hashable {  }
