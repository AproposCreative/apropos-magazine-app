//
//  NT_ProjectSortOrder.swift
//  Native
//

import Foundation

enum NT_ProjectSortOrder: Int {
    
    // MARK: - Cases:
    
    case dueDate
    case priority
    case creationDate
    
    // MARK: - Computed properties:
    
    /// Identifier of the sort order:
    var id: Int {
        rawValue
    }
    
    /// Title of the sort order:
    var title: String {
        switch self {
        case .dueDate: return .init(localized: "Due Date")
        case .priority: return .init(localized: "Priority")
        case .creationDate: return .init(localized: "Creation Date")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProjectSortOrder: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProjectSortOrder: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProjectSortOrder: Equatable {  }

// MARK: - Hashable:

extension NT_ProjectSortOrder: Hashable {  }
