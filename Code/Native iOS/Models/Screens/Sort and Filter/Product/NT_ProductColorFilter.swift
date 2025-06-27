//
//  NT_ProductColorFilter.swift
//  Native
//

import Foundation

enum NT_ProductColorFilter: Int {
    
    // MARK: - Cases:
    
    case all
    case spaceBlack
    case spaceGray
    case silver
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .all: return .init(localized: "All")
        case .spaceBlack: return .init(localized: "Space Black")
        case .spaceGray: return .init(localized: "Space Gray")
        case .silver: return .init(localized: "Silver")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductColorFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductColorFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductColorFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductColorFilter: Hashable {  }
