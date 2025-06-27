//
//  NT_UnpaidInvoice.swift
//  Native
//

import Foundation

struct NT_UnpaidInvoice {
    
    // MARK: - Properties:
    
    /// Identifier of the invoice:
    let id: String
    
    /// Amount of the invoice:
    let amount: Double
    
    /// Category of the invoice:
    let category: NT_ExpenseCategory
    
    init(
        id: String,
        amount: Double,
        category: NT_ExpenseCategory
    ) {
        
        /// Properties initialization:
        self.id = id
        self.amount = amount
        self.category = category
    }
}

// MARK: - Identifiable:

extension NT_UnpaidInvoice: Identifiable {  }

// MARK: - Equatable:

extension NT_UnpaidInvoice: Equatable {  }

// MARK: - Hashable:

extension NT_UnpaidInvoice: Hashable {  }

// MARK: - Example:

extension NT_UnpaidInvoice {
    
    // MARK: - Computed properties:
    
    /// An array of the example invoices:
    static var example: [NT_UnpaidInvoice] {
        [
            .init(
                id: "Item.1",
                amount: 15000.0,
                category: .example1.first { $0.id == "Item.1" }!
            ),
            .init(
                id: "Item.2",
                amount: 43500.0,
                category: .example1.first { $0.id == "Item.3" }!
            ),
            .init(
                id: "Item.3",
                amount: 10703.01,
                category: .example1.first { $0.id == "Item.4" }!
            ),
            .init(
                id: "Item.4",
                amount: 17500.0,
                category: .example1.first { $0.id == "Item.5" }!
            ),
            .init(
                id: "Item.5",
                amount: 12500.0,
                category: .example1.first { $0.id == "Item.6" }!
            ),
            .init(
                id: "Item.6",
                amount: 7500.0,
                category: .example1.first { $0.id == "Item.7" }!
            ),
            .init(
                id: "Item.7",
                amount: 7500.0,
                category: .example1.first { $0.id == "Item.8" }!
            ),
            .init(
                id: "Item.8",
                amount: 42500.0,
                category: .example1.first { $0.id == "Item.9" }!
            )
        ]
    }
}
