//
//  NT_Performance.swift
//  Native
//

import Foundation

struct NT_Performance {
    
    // MARK: - Properties:
    
    /// Identifier of the performance item:
    let id: String
    
    /// An array of the data of the performance item:
    let data: [NT_PerformanceData]
    
    init(
        id: String,
        data: [NT_PerformanceData]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.data = data
    }
}

// MARK: - Identifiable:

extension NT_Performance: Identifiable {  }

// MARK: - Equatable:

extension NT_Performance: Equatable {  }

// MARK: - Hashable:

extension NT_Performance: Hashable {  }

// MARK: - Example:

extension NT_Performance {
    
    // MARK: - Computed properties:
    
    /// An array of the example performance items:
    static var example: [NT_Performance] {
        [
            .init(
                id: "Item.1",
                data: NT_PerformanceData.example
            ),
            .init(
                id: "Item.2",
                data: NT_PerformanceData.example
            ),
            .init(
                id: "Item.3",
                data: NT_PerformanceData.example
            )
        ]
    }
}
