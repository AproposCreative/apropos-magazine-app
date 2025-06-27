//
//  NT_TransactionsCategory.swift
//  Native
//

import SwiftUI

enum NT_TransactionsCategory: Int {
    
    // MARK: - Cases:
    
    case housing
    case groceries
    case transportation
    case utilities
    case entertainment
    case shopping
    case travel
    case subscriptions
    case investing
    case miscellaneous
    
    // MARK: - Computed properties:
    
    /// Identifier of the category:
    var id: Int {
        rawValue
    }
    
    /// Title of the category:
    var title: String {
        switch self {
        case .housing: return "Housing"
        case .groceries: return "Groceries"
        case .transportation: return "Transportation"
        case .utilities: return "Utilities"
        case .entertainment: return "Entertainment"
        case .shopping: return "Shopping"
        case .travel: return "Travel"
        case .subscriptions: return "Subscriptions"
        case .investing: return "Investing"
        case .miscellaneous: return "Miscellaneous"
        }
    }
    
    /// Color of the category:
    var color: Color {
        switch self {
        case .housing: return .orange
        case .groceries: return .green
        case .transportation: return .indigo
        case .utilities: return .gray
        case .entertainment: return .pink
        case .shopping: return .purple
        case .travel: return .blue
        case .subscriptions: return .yellow
        case .investing: return .green
        case .miscellaneous: return .gray
        }
    }
    
    /// Starting color of the gradient of the category if applicable:
    var gradientStart: Color {
        switch self {
        case .housing: return .orangeGradientStart
        case .groceries: return .greenGradientStart
        case .transportation: return .indigoGradientStart
        case .utilities: return .grayGradientStart
        case .entertainment: return .pinkGradientStart
        case .shopping: return .purpleGradientStart
        case .travel: return .blueGradientStart
        case .subscriptions: return .yellowGradientStart
        case .investing: return .greenGradientStart
        case .miscellaneous: return .grayGradientStart
        }
    }
    
    /// Ending color of the gradient of the category if applicable:
    var gradientEnd: Color {
        switch self {
        case .housing: return .orangeGradientEnd
        case .groceries: return .greenGradientEnd
        case .transportation: return .indigoGradientEnd
        case .utilities: return .grayGradientEnd
        case .entertainment: return .pinkGradientEnd
        case .shopping: return .purpleGradientEnd
        case .travel: return .blueGradientEnd
        case .subscriptions: return .yellowGradientEnd
        case .investing: return .greenGradientEnd
        case .miscellaneous: return .grayGradientEnd
        }
    }
    
    /// Icon of the category:
    var icon: String {
        switch self {
        case .housing: return Icons.house
        case .groceries: return Icons.bag
        case .transportation: return Icons.car
        case .utilities: return Icons.gearshape
        case .entertainment: return Icons.tv
        case .shopping: return Icons.cart
        case .travel: return Icons.airplane
        case .subscriptions: return Icons.repeatIcon
        case .investing: return Icons.chartLineUptrendXYAxis
        case .miscellaneous: return Icons.docText
        }
    }
}

// MARK: - Identifiable:

extension NT_TransactionsCategory: Identifiable {  }

// MARK: - CaseIterable:

extension NT_TransactionsCategory: CaseIterable {  }

// MARK: - Equatable:

extension NT_TransactionsCategory: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionsCategory: Hashable {  }
