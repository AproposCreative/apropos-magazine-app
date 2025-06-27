//
//  NT_ProductCategoryFilter.swift
//  Native
//

import Foundation

enum NT_ProductCategoryFilter: Int {
    
    // MARK: - Cases:
    
    case all
    case laptop
    case desktop
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .all: return .init(localized: "All")
        case .laptop: return .init(localized: "Laptop")
        case .desktop: return .init(localized: "Desktop")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductCategoryFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductCategoryFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductCategoryFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductCategoryFilter: Hashable {  }
