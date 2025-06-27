//
//  NT_ComparisonRow.swift
//  Native
//

import Foundation

struct NT_ComparisonRow {
    
    // MARK: - Properties:
    
    /// Identifier of the row for the comparison:
    let id: String
    
    /// Title of the row for the comparison:
    let title: String
    
    /// 'Bool' value indicating whether or not the title of the row for the comparison should be localized:
    let isTitleLocalized: Bool
    
    /// An array of the items of the row to compare:
    let items: [NT_ComparisonRowItem]
    
    init(
        id: String,
        title: String,
        isTitleLocalized: Bool,
        items: [NT_ComparisonRowItem]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.items = items
    }
}

// MARK: - Identifiable:

extension NT_ComparisonRow: Identifiable {  }

// MARK: - Equatable:

extension NT_ComparisonRow: Equatable {  }

// MARK: - Hashable:

extension NT_ComparisonRow: Hashable {  }

// MARK: - Example:

extension NT_ComparisonRow {
    
    // MARK: - Computed properties:
    
    /// An example for the comparison:
    static var example: [NT_ComparisonRow] {
        [
            .init(
                id: "Header.1.1",
                title: "Feature",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Header.1.2",
                        type: .header(
                            title: "Free",
                            isTitleLocalized: true
                        )
                    ),
                    .init(
                        id: "Header.1.3",
                        type: .header(
                            title: "Pro",
                            isTitleLocalized: true
                        )
                    )
                ]
            ),
            .init(
                id: "Feature.1.1",
                title: "Latest Technologies",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.1.2",
                        type: .included
                    ),
                    .init(
                        id: "Feature.1.3",
                        type: .included
                    )
                ]
            ),
            .init(
                id: "Feature.2.1",
                title: "Native Design",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.2.2",
                        type: .excluded
                    ),
                    .init(
                        id: "Feature.2.3",
                        type: .included
                    )
                ]
            ),
            .init(
                id: "Feature.3.1",
                title: "Reusable Components",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.3.2",
                        type: .excluded
                    ),
                    .init(
                        id: "Feature.3.3",
                        type: .included
                    )
                ]
            ),
            .init(
                id: "Feature.4.1",
                title: "Global Styleguide",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.4.2",
                        type: .excluded
                    ),
                    .init(
                        id: "Feature.4.3",
                        type: .included
                    )
                ]
            ),
            .init(
                id: "Feature.5.1",
                title: "Fully Accessible",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.5.2",
                        type: .excluded
                    ),
                    .init(
                        id: "Feature.5.3",
                        type: .included
                    )
                ]
            ),
            .init(
                id: "Feature.6.1",
                title: "Scalable Source Code",
                isTitleLocalized: true,
                items: [
                    .init(
                        id: "Feature.6.2",
                        type: .excluded
                    ),
                    .init(
                        id: "Feature.6.3",
                        type: .included
                    )
                ]
            )
        ]
    }
}
