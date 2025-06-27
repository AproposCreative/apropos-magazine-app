//
//  NT_Account.swift
//  Native
//

import SwiftUI

struct NT_TransactionsAccount {
    
    // MARK: - Properties:
    
    /// Identifier of the account:
    let id: String
    
    /// Title of the account:
    let title: String
    
    /// Number of account:
    let number: String
    
    /// Color of the account:
    let color: Color
    
    /// Starting color of the gradient of the account if applicable:
    let gradientStart: Color
    
    /// Ending color of the gradient of the account if applicable:
    let gradientEnd: Color
    
    /// Icon of the account:
    let icon: String
    
    /// Amount of the account:
    let amount: Double
    
    /// An array of the transactions of the account:
    let transactions: [NT_Transaction]
    
    init(
        id: String,
        title: String,
        number: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        amount: Double,
        transactions: [NT_Transaction]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.number = number
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.amount = amount
        self.transactions = transactions
    }
}

// MARK: - Identifiable:

extension NT_TransactionsAccount: Identifiable {  }

// MARK: - Equatable:

extension NT_TransactionsAccount: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionsAccount: Hashable {  }

// MARK: - Example:

extension NT_TransactionsAccount {
    
    // MARK: - Computed properties:
    
    /// An array of the example accounts:
    static var example: [NT_TransactionsAccount] {
        [
            .init(
                id: "Item.1",
                title: "Checking",
                number: "900-648-073",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.buildingColumns,
                amount: 20891.50,
                transactions: NT_Transaction.example
            ),
            .init(
                id: "Item.2",
                title: "Savings",
                number: "547-089-001",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.buildingColumns,
                amount: 4865.23,
                transactions: NT_Transaction.example
            ),
            .init(
                id: "Item.3",
                title: "Credit Card",
                number: "020-000-961",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.creditcard,
                amount: 502.77,
                transactions: NT_Transaction.example
            ),
            .init(
                id: "Item.4",
                title: "Mortgage",
                number: "332-001-708",
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.house,
                amount: 196433.81,
                transactions: NT_Transaction.example
            )
        ]
    }
}
