//
//  FileEditingOneFolder+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingOneFolderView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !files.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the divider should be shown which is only applicable if the folder isn't the last folder that is displayed in an array:
    var isShowingDivider: Bool {
        folders.filter { !$0.files.isEmpty }.last != folder
    }
    
    /// An array of the files that are part of the folder to display:
    var files: [NT_DesignToolFile] {
        folder.files
    }
    
    /// An array of the columns to display the files in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: imageWidth,
                    maximum: gridItemMaxWidth
                ),
                spacing: spacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Title of the folder:
    var title: String {
        folder.title
    }
    
    /// Count of the files that are part of the folder as a string:
    var filesCount: String {
        "\(folder.filesCount) files"
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Width that each of the images that are displayed on the view should have that is based on the size of the dynamic type that is currently selected:
    var imageWidth: Double {
        shouldMoveContent ? 200 : 128
    }
    
    /// Height that each of the images that are displayed on the view should have that is based on the size of the dynamic type that is currently selected:
    var imageHeight: Double {
        shouldMoveContent ? 224 : 172
    }
    
    /// Size of the frame of the icon that is displayed in the header of the view that is based on the size of the dynamic type that is currently selected:
    var headerIconFrame: CGFloat? {
        shouldMoveContent ? nil : 25
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 200
    }
}
