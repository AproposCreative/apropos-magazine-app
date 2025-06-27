//
//  FileEditingOneFiles+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingOneFilesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the folders or an array of the files of each of the folders to display are empty:
    var isEmpty: Bool {
        folders.isEmpty || folders.allSatisfy { $0.files.isEmpty }
    }
    
    /// An array of the folders with the files to display:
    var folders: [NT_DesignToolFolder] {
        NT_DesignToolFolder.example
    }
    
    /// Title of the view:
    var title: String {
        if let section {
            return section.title
        } else if let folder {
            return folder.title
        } else if let tag {
            return tag.title
        } else {
            return ""
        }
    }
    
    /// Font of the buttons that are placed on this view:
    var buttonFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are placed on this view:
    var buttonIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Size of the icon of the 'Settings' menu:
    var settingsIconSize: NT_IconSize {
        .custom(
            font: buttonFont,
            nonBackgroundFont: buttonFont,
            frame: 22,
            cornerRadius: 0,
            cornerStyle: .continuous
        )
    }
    
    /// Style of the buttons that are placed on this view:
    var buttonStyle: NT_LabelStyle {
        .titleAndIcon
    }
}
