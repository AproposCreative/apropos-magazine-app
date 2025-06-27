//
//  NT_ProfileArticleType.swift
//  Native
//

import Foundation

enum NT_ProfileAuthorArticleType: Int {
    
    // MARK: - Cases:
    
    case latest
    case all
    case featured
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .latest: return .init(localized: "Latest")
        case .all: return .init(localized: "All")
        case .featured: return .init(localized: "Featured")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProfileAuthorArticleType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProfileAuthorArticleType: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProfileAuthorArticleType: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAuthorArticleType: Hashable {  }
