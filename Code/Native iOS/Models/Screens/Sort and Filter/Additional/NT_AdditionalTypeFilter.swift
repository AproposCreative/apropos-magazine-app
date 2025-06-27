//
//  NT_AdditionalTypeFilter.swift
//  Native
//

import Foundation

enum NT_AdditionalTypeFilter: Int {
    
    // MARK: - Cases:
    
    case all
    case new
    case sale
    case demo
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .all: return .init(localized: "All")
        case .new: return .init(localized: "New")
        case .sale: return .init(localized: "Sale")
        case .demo: return .init(localized: "Demo")
        }
    }
}

// MARK: - Identifiable:

extension NT_AdditionalTypeFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AdditionalTypeFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AdditionalTypeFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AdditionalTypeFilter: Hashable {  }
