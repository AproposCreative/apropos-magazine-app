//
//  NT_AccountScreen.swift
//  Native
//

import Foundation

/*
 
 NOTE: Account screen model that is used for the different account screens.
 
 */

enum NT_AccountScreen: Int {
    
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

extension NT_AccountScreen: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccountScreen: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccountScreen: Equatable {  }

// MARK: - Hashable:

extension NT_AccountScreen: Hashable {  }
