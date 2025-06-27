//
//  MainNineContent+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainNineContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the folders, as well as an array of the drives to display are both empty:
    var isEmpty: Bool {
        searchFolders.isEmpty && searchDrives.isEmpty
    }
    
    /// An array of the folders that are filtered by the search text that is inputed by the user:
    var searchFolders: [NT_Folder] {
        folders.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the drives that are filtered by the search text that is inputed by the user:
    var searchDrives: [NT_Drive] {
        drives.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Font of the buttons that are placed in the toolbar:
    var toolbarFont: Font {
        .body
    }
    
    /// Font of the buttons that are placed on this view:
    var buttonFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are placed on this view:
    var buttonIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Style of the buttons that are placed in the toolbar:
    var toolbarStyle: NT_LabelStyle {
        .iconOnly
    }
    
    /// Style of the buttons that are placed on this view:
    var buttonStyle: NT_LabelStyle {
        .titleAndIcon
    }
    
    /// Size of the icon of the 'Settings' menu:
    var settingsIconSize: NT_IconSize {
        .custom(
            font: toolbarFont,
            nonBackgroundFont: toolbarFont,
            frame: 22,
            cornerRadius: 0,
            cornerStyle: .continuous
        )
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the folders and the drives by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
