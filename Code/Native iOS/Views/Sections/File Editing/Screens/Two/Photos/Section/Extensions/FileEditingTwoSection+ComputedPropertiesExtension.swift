//
//  FileEditingTwoSection+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingTwoSectionView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !photos.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the section is featured:
    var isFeatured: Bool {
        section.isFeatured
    }
    
    /// An array of the photos that are part of the section to display:
    var photos: [NT_PhotoEditorPhoto] {
        section.photos
    }
    
    /// An array of the columns to display the photos in the grid:
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
    
    /// Title of the section:
    var title: String {
        section.title
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Padding around the content of each of the photos:
    var photoPadding: Double {
        12
    }
    
    /// Width that each of the images that is displayed on this view should have:
    var imageWidth: Double {
        128
    }
    
    /// Height of the image of each of the photos that is based on whether or not the section that the photos are part of is currently featured:
    var imageHeight: CGFloat? {
        (
            isFeatured
            || shouldMoveContent
        ) ? 168 : 112
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected, as well as whether or not the section contains the featured photos:
    private var gridItemMinWidth: Double {
        (
            isFeatured
            || shouldMoveContent
        ) ? 200 : imageWidth
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected, as well as whether or not the section contains the featured photos:
    private var gridItemMaxWidth: Double {
        (
            isFeatured
            || shouldMoveContent
        ) ? 400 : 200
    }
}
