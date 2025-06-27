//
//  MainSevenProducts+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSevenProductsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !products.isEmpty
    }
    
    /// An array of the columns to display the products in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: 304,
                    maximum: 600
                ),
                spacing: spacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Height of each of the images of the products that is based on the size of the dynamic type that is currently selected:
    var imageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 304 : 200
    }
}
