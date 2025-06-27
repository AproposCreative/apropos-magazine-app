//
//  NT_ProductSortOrder.swift
//  Native
//

import Foundation

enum NT_ProductSortOrder: Int {
    
    // MARK: - Cases:
    
    case ascendingPrice
    case descendingPrice
    
    // MARK: - Computed properties:
    
    /// Identifier of the sort order:
    var id: Int {
        rawValue
    }
    
    /// Title of the sort order:
    var title: String {
        switch self {
        case .ascendingPrice: return .init(localized: "Ascending Price")
        case .descendingPrice: return .init(localized: "Descending Price")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductSortOrder: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductSortOrder: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductSortOrder: Equatable {  }

// MARK: - Hashable:

extension NT_ProductSortOrder: Hashable {  }
