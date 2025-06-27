//
//  SortAndFilterThreeCategories+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension SortAndFilterThreeCategoriesView {
    
    // MARK: - Computed properties:
    
    /// An array of the budget category filters to select from:
    var budgetCategoryFilters: [NT_BudgetCategoryFilter] {
        NT_BudgetCategoryFilter.allCases
    }
    
    /// An array of the columns to display the budget category filters in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: gridItemMinWidth,
                    maximum: gridItemMaxWidth
                ),
                spacing: spacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        8
    }
    
    /// Padding around the content of the view:
    var padding: Double {
        8
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMinWidth: Double {
        shouldMoveContent ? 200 : 96
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 144
    }
}
