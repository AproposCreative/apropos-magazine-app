//
//  NT_ProductBrandFilter.swift
//  Native
//

import Foundation

enum NT_ProductBrandFilter: Int {
    
    // MARK: - Cases:
    
    case all
    case apple
    case dell
    case hp
    case lenovo
    case acer
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .all: return .init(localized: "All")
        case .apple: return .init(localized: "Apple")
        case .dell: return .init(localized: "Dell")
        case .hp: return .init(localized: "HP")
        case .lenovo: return .init(localized: "Lenovo")
        case .acer: return .init(localized: "Acer")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductBrandFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductBrandFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductBrandFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductBrandFilter: Hashable {  }
