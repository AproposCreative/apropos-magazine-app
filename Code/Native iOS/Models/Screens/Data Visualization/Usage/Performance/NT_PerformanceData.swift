//
//  NT_PerformanceData.swift
//  Native
//

import Foundation

struct NT_PerformanceData {
    
    // MARK: - Properties:
    
    /// Identifier of the data:
    let id: String
    
    /// Title of the data:
    let title: String
    
    /// Title of the value of the data:
    let valueTitle: String
    
    /// Value of the data:
    let value: Double
    
    init(
        id: String,
        title: String,
        valueTitle: String,
        value: Double
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.valueTitle = valueTitle
        self.value = value
    }
}

// MARK: - Identifiable:

extension NT_PerformanceData: Identifiable {  }

// MARK: - Equatable:

extension NT_PerformanceData: Equatable {  }

// MARK: - Hashable:

extension NT_PerformanceData: Hashable {  }

// MARK: - Example:

extension NT_PerformanceData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_PerformanceData] {
        [
            .init(
                id: "Item.1",
                title: "Item - 1",
                valueTitle: "Item - 1",
                value: 1.0
            ),
            .init(
                id: "Item.2",
                title: "Item - 2",
                valueTitle: "Item - 2",
                value: 0.9
            ),
            .init(
                id: "Item.3",
                title: "Item - 3",
                valueTitle: "Item - 3",
                value: 0.8
            ),
            .init(
                id: "Item.4",
                title: "Item - 4",
                valueTitle: "Item - 4",
                value: 0.7
            ),
            .init(
                id: "Item.5",
                title: "Item - 5",
                valueTitle: "Item - 5",
                value: 0.6
            ),
            .init(
                id: "Item.6",
                title: "Item - 6",
                valueTitle: "Item - 6",
                value: 0.5
            ),
            .init(
                id: "Item.7",
                title: "Item - 7",
                valueTitle: "Item - 7",
                value: 0.4
            ),
            .init(
                id: "Item.8",
                title: "Item - 8",
                valueTitle: "Item - 8",
                value: 0.3
            ),
            .init(
                id: "Item.9",
                title: "Item - 9",
                valueTitle: "Item - 9",
                value: 0.2
            ),
            .init(
                id: "Item.10",
                title: "Item - 10",
                valueTitle: "Item - 10",
                value: 0.1
            )
        ]
    }
}
