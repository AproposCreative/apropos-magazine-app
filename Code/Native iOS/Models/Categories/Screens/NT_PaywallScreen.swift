//
//  NT_PaywallScreen.swift
//  Native
//

import Foundation

/*
 
 NOTE: Paywall screen model that is used for the different paywall screens.
 
 */

enum NT_PaywallScreen: Int {
    
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
    case eleventh
    case twelfth
    case thirteenth
    case fourteenth
    case fifteenth
    
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
        case .eleventh: return "Eleventh"
        case .twelfth: return "Twelfth"
        case .thirteenth: return "Thirteenth"
        case .fourteenth: return "Fourteenth"
        case .fifteenth: return "Fifteenth"
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
        case .eleventh: return Icons.elevenCircle
        case .twelfth: return Icons.twelveCircle
        case .thirteenth: return Icons.thirteenCircle
        case .fourteenth: return Icons.fourteenCircle
        case .fifteenth: return Icons.fifteenCircle
        }
    }
}

// MARK: - Identifiable:

extension NT_PaywallScreen: Identifiable {  }

// MARK: - CaseIterable:

extension NT_PaywallScreen: CaseIterable {  }

// MARK: - Equatable:

extension NT_PaywallScreen: Equatable {  }

// MARK: - Hashable:

extension NT_PaywallScreen: Hashable {  }
