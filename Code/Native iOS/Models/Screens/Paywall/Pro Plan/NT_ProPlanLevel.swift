//
//  NT_ProPlanLevel.swift
//  Native
//

import Foundation

enum NT_ProPlanLevel: Int {
    
    // MARK: - Cases:
    
    case starter
    case pro
    
    // MARK: - Computed properties:
    
    /// Identifier of the level of the pro plan:
    var id: Int {
        rawValue
    }
    
    /// Title of the level of the pro plan:
    var title: String {
        switch self {
        case .starter: return .init(localized: "Starter")
        case .pro: return .init(localized: "Pro")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProPlanLevel: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProPlanLevel: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProPlanLevel: Equatable {  }

// MARK: - Hashable:

extension NT_ProPlanLevel: Hashable {  }
