//
//  NT_MainScreen.swift
//  Native
//

import Foundation

/*
 
 NOTE: Main screen model that is used for the different main screens.
 
 */

enum NT_MainScreen: Int {
    
    // MARK: - Cases:
    
    case first
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventh
    case eighth
    case ninth
    case tenth
    
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
        case .sixth: return "Sixth"
        case .seventh: return "Seventh"
        case .eighth: return "Eighth"
        case .ninth: return "Ninth"
        case .tenth: return "Tenth"
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
        case .sixth: return Icons.sixCircle
        case .seventh: return Icons.sevenCircle
        case .eighth: return Icons.eightCircle
        case .ninth: return Icons.nineCircle
        case .tenth: return Icons.tenCircle
        }
    }
}

// MARK: - Identifiable:

extension NT_MainScreen: Identifiable {  }

// MARK: - CaseIterable:

extension NT_MainScreen: CaseIterable {  }

// MARK: - Equatable:

extension NT_MainScreen: Equatable {  }

// MARK: - Hashable:

extension NT_MainScreen: Hashable {  }
