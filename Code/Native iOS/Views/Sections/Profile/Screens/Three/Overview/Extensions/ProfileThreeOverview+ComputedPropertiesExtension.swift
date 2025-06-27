//
//  ProfileThreeOverview+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileThreeOverviewView {
    
    // MARK: - Computed properties:
    
    /// An array of the stats to display:
    var stats: [NT_ProfileTaskStat] {
        NT_ProfileTaskStat.example
    }
    
    /// An array of the columns to display the stats in the grid:
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
        12
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMinWidth: Double {
        shouldMoveContent ? 200 : 128
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 200
    }
}
