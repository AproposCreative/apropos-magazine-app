//
//  FileEditingOneFolders+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingOneFoldersView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given folder:
    func title(_ folder: NT_DesignToolFolder) -> String {
        folder.title
    }
    
    /// Returns the count of the files that are part of the given folder as a string:
    func filesCount(_ folder: NT_DesignToolFolder) -> String {
        folder.filesCount.formatted()
    }
    
    /// Returns the icon of the given folder:
    func icon(_ folder: NT_DesignToolFolder) -> String {
        folder.icon
    }
}
