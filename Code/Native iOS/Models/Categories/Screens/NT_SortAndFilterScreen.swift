//
//  NT_SortAndFilterScreen.swift
//  Native
//

import Foundation

/*
 
 NOTE: Sort and filter screen model that is used for the different sort and filter screens.
 
 */

enum NT_SortAndFilterScreen: Int {
    
    // MARK: - Cases:
    
    case first
    case second
    case third
    case fourth
    case fifth
    
    // MARK: - Computed properties:
    
    /// Identifier of the screen:
    var id: Int {
        rawValue
    }
    
    /// Title of the screen:
    var title: String {
        switch self {
        case .first: return "First"
        case .second: return "Second"
        case .third: return "Third"
        case .fourth: return "Fourth"
        case .fifth: return "Fifth"
        }
    }
    
    /// Icon of the screen:
    var icon: String {
        switch self {
        case .first: return Icons.oneCircle
        case .second: return Icons.twoCircle
        case .third: return Icons.threeCircle
        case .fourth: return Icons.fourCircle
        case .fifth: return Icons.fiveCircle
        }
    }
}

// MARK: - Identifiable:

extension NT_SortAndFilterScreen: Identifiable {  }

// MARK: - CaseIterable:

extension NT_SortAndFilterScreen: CaseIterable {  }

// MARK: - Equatable:

extension NT_SortAndFilterScreen: Equatable {  }

// MARK: - Hashable:

extension NT_SortAndFilterScreen: Hashable {  }
