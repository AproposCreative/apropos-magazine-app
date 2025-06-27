//
//  NT_ImageGrid.swift
//  Native
//

import Foundation

enum NT_ImageGrid: Int {
    
    // MARK: - Cases:
    
    case none
    case oneByOne
    case twoByOne
    case threeByOne
    
    // MARK: - Computed properties:
    
    /// Identifier of the grid:
    var id: Int {
        rawValue
    }
    
    /// Title of the grid:
    var title: String {
        switch self {
        case .none: return "None"
        case .oneByOne: return "1:1"
        case .twoByOne: return "2:1"
        case .threeByOne: return "3:1"
        }
    }
}

// MARK: - Identifiable:

extension NT_ImageGrid: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ImageGrid: CaseIterable {  }

// MARK: - Equatable:

extension NT_ImageGrid: Equatable {  }

// MARK: - Hashable:

extension NT_ImageGrid: Hashable {  }
