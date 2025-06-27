//
//  MainNineFolders+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainNineFoldersView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given folder:
    func title(_ folder: NT_Folder) -> String {
        folder.title
    }
    
    /// Returns the count of the files that are part of the given folder as a string:
    func filesCount(_ folder: NT_Folder) -> String {
        "\(folder.filesCount) files"
    }
    
    /// Returns the color of the given folder:
    func color(_ folder: NT_Folder) -> Color {
        folder.color
    }
    
    /// Returns the starting color of the gradient of the given folder:
    func gradientStart(_ folder: NT_Folder) -> Color {
        folder.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given folder:
    func gradientEnd(_ folder: NT_Folder) -> Color {
        folder.gradientEnd
    }
}
