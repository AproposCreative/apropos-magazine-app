//
//  NT_AdditionalCustomizationOptionsFilter.swift
//  Native
//

import Foundation

enum NT_AdditionalCustomizationOptionsFilter: Int {
    
    // MARK: - Cases:
    
    case none
    case included
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .none: return .init(localized: "None")
        case .included: return .init(localized: "Included")
        }
    }
}

// MARK: - Identifiable:

extension NT_AdditionalCustomizationOptionsFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AdditionalCustomizationOptionsFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_AdditionalCustomizationOptionsFilter: Equatable {  }

// MARK: - Hashable:

extension NT_AdditionalCustomizationOptionsFilter: Hashable {  }
