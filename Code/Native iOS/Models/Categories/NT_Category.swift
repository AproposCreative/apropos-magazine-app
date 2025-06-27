//
//  NT_Category.swift
//  Native
//

import Foundation

/*
 
 NOTE: Category model is used for the different screens categories, such as onboarding, paywall, etc.
 
 */

enum NT_Category: Int {
    
    // MARK: - Cases:
    
    case onboarding
    case signUp
    case login
    case passwordReset
    case paywall
    case emptyState
    case main
    case productDetails
    case dataVisualization
    case fileEditing
    case sortAndFilter
    case profile
    case account
    case settings
    case terms
    
    // MARK: - Computed properties:
    
    /// Identifier of the category:
    var id: Int {
        rawValue
    }
    
    /// Title of the category:
    var title: String {
        switch self {
        case .onboarding: return "Onboarding"
        case .signUp: return "Sign Up"
        case .login: return "Login"
        case .passwordReset: return "Password Reset"
        case .paywall: return "Paywall"
        case .emptyState: return "Empty State"
        case .main: return "Main"
        case .productDetails: return "Product Details"
        case .dataVisualization: return "Data Visualization"
        case .fileEditing: return "File Editing"
        case .sortAndFilter: return "Sort and Filter"
        case .profile: return "Profile"
        case .account: return "Account"
        case .settings: return "Settings"
        case .terms: return "Terms"
        }
    }
    
    /// Icon of the category:
    var icon: String {
        switch self {
        case .onboarding: return Icons.rectangleStack
        case .signUp: return Icons.plusCircle
        case .login: return Icons.arrowForwardCircle
        case .passwordReset: return Icons.lock
        case .paywall: return Icons.creditcard
        case .emptyState: return Icons.tray
        case .main: return Icons.house
        case .productDetails: return Icons.docRichtext
        case .dataVisualization: return Icons.chartPie
        case .fileEditing: return Icons.docText
        case .sortAndFilter: return Icons.lineThreeHorizontalDecreaseCircle
        case .profile: return Icons.personCropCircle
        case .account: return Icons.person
        case .settings: return Icons.gearshape
        case .terms: return Icons.docPlaintext
        }
    }
}

// MARK: - Identifiable

extension NT_Category: Identifiable {  }

// MARK: - CaseIterable

extension NT_Category: CaseIterable {  }

// MARK: - Equatable:

extension NT_Category: Equatable {  }

// MARK: - Hashable

extension NT_Category: Hashable {  }
