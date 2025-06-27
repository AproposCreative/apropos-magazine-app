//
//  NT_Transaction.swift
//  Native
//

import Foundation

struct NT_Transaction {
    
    // MARK: - Properties:
    
    /// Identifier of the transaction:
    let id: String
    
    /// Title of the transaction:
    let title: String
    
    /// Notes of the transaction:
    let notes: String
    
    /// URL of the transaction as a string:
    let url: String
    
    /// Amount of the transaction:
    let amount: Double
    
    /// Type of the transaction:
    let type: NT_TransactionType
    
    /// Status of the transaction:
    let status: NT_TransactionStatus
    
    /// Date when the transaction occurred:
    let date: Date
    
    /// Time when the transaction occurred:
    let time: Date
    
    /// Recurrence of the transaction:
    let recurrence: NT_TransactionRecurrence
    
    /// 'Bool' value indicating whether or nor the transaction is pinned:
    let isPinned: Bool
    
    /// An array of the attachments that are part of the transaction:
    let attachments: [NT_TransactionAttachment]
    
    /// Category that the transaction is a part of:
    let category: NT_TransactionsCategory
    
    init(
        id: String,
        title: String,
        notes: String,
        url: String,
        amount: Double,
        type: NT_TransactionType,
        status: NT_TransactionStatus,
        date: Date,
        time: Date,
        recurrence: NT_TransactionRecurrence,
        isPinned: Bool,
        attachments: [NT_TransactionAttachment],
        account: String,
        category: NT_TransactionsCategory
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.notes = notes
        self.url = url
        self.amount = amount
        self.type = type
        self.status = status
        self.date = date
        self.time = time
        self.recurrence = recurrence
        self.isPinned = isPinned
        self.attachments = attachments
        self.category = category
    }
}

// MARK: - Identifiable:

extension NT_Transaction: Identifiable {  }

// MARK: - Equatable:

extension NT_Transaction: Equatable {  }

// MARK: - Hashable:

extension NT_Transaction: Hashable {  }

// MARK: - Example:

extension NT_Transaction {
    
    // MARK: - Computed properties:
    
    /// An array of the example transactions:
    static var example: [NT_Transaction] {
        [
            .init(
                id: "Item.1",
                title: "Weekly Groceries",
                notes: "Purchased a variety of different groceries for the upcoming week.",
                url: "",
                amount: 135.0,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 17
                ),
                time: .dateWithComponents(
                    withHour: 9,
                    withMinute: 45
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .groceries
            ),
            .init(
                id: "Item.2",
                title: "Mortgage for February",
                notes: "",
                url: "",
                amount: 550.00,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 16
                ),
                time: .dateWithComponents(
                    withHour: 12,
                    withMinute: 1
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .housing
            ),
            .init(
                id: "Item.3",
                title: "Car Insurance",
                notes: "",
                url: "",
                amount: 350.00,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 12
                ),
                time: .dateWithComponents(
                    withHour: 7,
                    withMinute: 36
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .transportation
            ),
            .init(
                id: "Item.4",
                title: "Utilities",
                notes: "",
                url: "",
                amount: 104.78,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 10
                ),
                time: .dateWithComponents(
                    withHour: 17,
                    withMinute: 44
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .utilities
            ),
            .init(
                id: "Item.5",
                title: "Cinema Tickets",
                notes: "",
                url: "",
                amount: 18.50,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 9
                ),
                time: .dateWithComponents(
                    withHour: 18,
                    withMinute: 25
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .entertainment
            ),
            .init(
                id: "Item.6",
                title: "Phone Bill",
                notes: "",
                url: "",
                amount: 25.97,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 7
                ),
                time: .dateWithComponents(
                    withHour: 8,
                    withMinute: 54
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .subscriptions
            ),
            .init(
                id: "Item.7",
                title: "Plane Tickets",
                notes: "",
                url: "",
                amount: 2872.34,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 4
                ),
                time: .dateWithComponents(
                    withHour: 20,
                    withMinute: 6
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .travel
            ),
            .init(
                id: "Item.8",
                title: "Clothing",
                notes: "",
                url: "",
                amount: 325.0,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 1
                ),
                time: .dateWithComponents(
                    withHour: 15,
                    withMinute: 26
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .shopping
            ),
            .init(
                id: "Item.9",
                title: "Cash Withdrawal",
                notes: "",
                url: "",
                amount: 250.0,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 1,
                    withDay: 29
                ),
                time: .dateWithComponents(
                    withHour: 13,
                    withMinute: 59
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .miscellaneous
            ),
            .init(
                id: "Item.10",
                title: "Monthly Investments",
                notes: "",
                url: "",
                amount: 5786.98,
                type: .expense,
                status: .cleared,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 1,
                    withDay: 26
                ),
                time: .dateWithComponents(
                    withHour: 10,
                    withMinute: 52
                ),
                recurrence: .none,
                isPinned: false,
                attachments: [],
                account: "Item.1",
                category: .investing
            )
        ]
    }
}
