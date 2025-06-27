//
//  MainOneAccounts+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainOneAccountsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given account:
    func title(_ account: NT_TransactionsAccount) -> String {
        account.title
    }
    
    /// Returns the number of the given account:
    func number(_ account: NT_TransactionsAccount) -> String {
        account.number
    }
    
    /// Returns the color of the given account:
    func color(_ account: NT_TransactionsAccount) -> Color {
        account.color
    }
    
    /// Returns the starting color of the gradient of the given account if applicable:
    func gradientStart(_ account: NT_TransactionsAccount) -> Color {
        account.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given account if applicable:
    func gradientEnd(_ account: NT_TransactionsAccount) -> Color {
        account.gradientEnd
    }
    
    /// Returns the icon of the given account:
    func icon(_ account: NT_TransactionsAccount) -> String {
        account.icon
    }
    
    /// Returns the amount of the given account as a string:
    func amount(_ account: NT_TransactionsAccount) -> String {
        account.amount.formatted(.currency(code: "USD"))
    }
}
