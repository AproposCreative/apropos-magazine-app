//
//  FileEditingOneSections+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingOneSectionsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given section:
    func title(_ section: NT_DesignToolSection) -> String {
        section.title
    }
    
    /// Returns the count of the files that are part of the given section as a string:
    func filesCount(_ section: NT_DesignToolSection) -> String {
        section.filesCount.formatted()
    }
    
    /// Returns the icon of the given section:
    func icon(_ section: NT_DesignToolSection) -> String {
        section.icon
    }
}
