//
//  FileEditingOneTags+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingOneTagsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given tag:
    func title(_ tag: NT_DesignToolTag) -> String {
        tag.title
    }
    
    /// Returns the count of the files that are part of the given tag as a string:
    func filesCount(_ tag: NT_DesignToolTag) -> String {
        tag.filesCount.formatted()
    }
    
    /// Returns the icon of the given tag:
    func icon(_ tag: NT_DesignToolTag) -> String {
        tag.icon
    }
}
