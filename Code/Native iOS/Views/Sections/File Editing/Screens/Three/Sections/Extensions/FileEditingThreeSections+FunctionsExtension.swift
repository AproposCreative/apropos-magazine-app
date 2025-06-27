//
//  FileEditingThreeSections+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingThreeSectionsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given section:
    func title(_ section: NT_WhiteboardSection) -> String {
        section.title
    }
    
    /// Returns the count of the boards that are part of the given section as a string:
    func boardsCount(_ section: NT_WhiteboardSection) -> String {
        section.boardsCount.formatted()
    }
    
    /// Returns the icon of the given section:
    func icon(_ section: NT_WhiteboardSection) -> String {
        section.icon
    }
}
