//
//  NT_BudgetCategoryFilter.swift
//  Native
//

import SwiftUI

enum NT_BudgetCategoryFilter: Int {
    
    // MARK: - Cases:
    
    case housing
    case groceries
    case transportation
    case shopping
    case entertainment
    case miscellaneous
    case investments
    case withdrawals
    case travel
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .housing: return .init(localized: "Housing")
        case .groceries: return .init(localized: "Groceries")
        case .transportation: return .init(localized: "Transportation")
        case .shopping: return .init(localized: "Shopping")
        case .entertainment: return .init(localized: "Entertainment")
        case .miscellaneous: return .init(localized: "Miscellaneous")
        case .investments: return .init(localized: "Investments")
        case .withdrawals: return .init(localized: "Withdrawals")
        case .travel: return .init(localized: "Travel")
        }
    }
    
    /// Color of the filter:
    var color: Color {
        switch self {
        case .housing: return .blue
        case .groceries: return .orange
        case .transportation: return .purple
        case .shopping: return .pink
        case .entertainment: return .green
        case .miscellaneous: return .gray
        case .investments: return .green
        case .withdrawals: return .indigo
        case .travel: return .blue
        }
    }
    
    /// Starting color of the gradient of the filter:
    var gradientStart: Color {
        switch self {
        case .housing: return .blueGradientStart
        case .groceries: return .orangeGradientStart
        case .transportation: return .purpleGradientStart
        case .shopping: return .pinkGradientStart
        case .entertainment: return .greenGradientStart
        case .miscellaneous: return .grayGradientStart
        case .investments: return .greenGradientStart
        case .withdrawals: return .indigoGradientStart
        case .travel: return .blueGradientStart
        }
    }
    
    /// Ending color of the gradient of the filter:
    var gradientEnd: Color {
        switch self {
        case .housing: return .blueGradientEnd
        case .groceries: return .orangeGradientEnd
        case .transportation: return .purpleGradientEnd
        case .shopping: return .pinkGradientEnd
        case .entertainment: return .greenGradientEnd
        case .miscellaneous: return .grayGradientEnd
        case .investments: return .greenGradientEnd
        case .withdrawals: return .indigoGradientEnd
        case .travel: return .blueGradientEnd
        }
    }
    
    /// Icon of the filter:
    var icon: String {
        switch self {
        case .housing: return Icons.house
        case .groceries: return Icons.bag
        case .transportation: return Icons.car
        case .shopping: return Icons.cart
        case .entertainment: return Icons.popcorn
        case .miscellaneous: return Icons.rectangleStack
        case .investments: return Icons.chartLineUptrendXYAxis
        case .withdrawals: return Icons.dollarsign
        case .travel: return Icons.airplane
        }
    }
}

// MARK: - Identifiable:

extension NT_BudgetCategoryFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_BudgetCategoryFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_BudgetCategoryFilter: Equatable {  }

// MARK: - Hashable:

extension NT_BudgetCategoryFilter: Hashable {  }
