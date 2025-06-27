//
//  NT_EmptyStateScreen.swift
//  Native
//

import Foundation

/*
 
 NOTE: Empty state screen model that is used for the different empty state screens.
 
 */

enum NT_EmptyStateScreen: Int {
    
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

extension NT_EmptyStateScreen: Identifiable {  }

// MARK: - CaseIterable:

extension NT_EmptyStateScreen: CaseIterable {  }

// MARK: - Equatable:

extension NT_EmptyStateScreen: Equatable {  }

// MARK: - Hashable:

extension NT_EmptyStateScreen: Hashable {  }
