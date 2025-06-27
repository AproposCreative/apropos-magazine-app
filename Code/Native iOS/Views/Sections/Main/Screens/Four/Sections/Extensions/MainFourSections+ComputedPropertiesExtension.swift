//
//  MainFourSections+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainFourSectionsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !sections.isEmpty
    }
    
    /// An array of the columns to display the articles in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: 304,
                    maximum: 600
                ),
                spacing: sectionSpacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Spacing between the content of the section with the news:
    var sectionSpacing: Double {
        16
    }
    
    /// Height of the image that is based on the size of the dynamic type that is currently selected:
    var imageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 600 : 400
    }
}
