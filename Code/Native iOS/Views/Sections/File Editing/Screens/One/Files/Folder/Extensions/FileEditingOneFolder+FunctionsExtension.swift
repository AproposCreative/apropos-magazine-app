//
//  FileEditingOneFolder+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension FileEditingOneFolderView {
    
    // MARK: - Functions:
    
    /// Returns the identifier of the given file:
    func identifier(_ file: NT_DesignToolFile) -> String {
        file.id
    }
    
    /// Returns the title of the given file:
    func title(_ file: NT_DesignToolFile) -> String {
        file.title
    }
    
    /// Returns the time interval since the file was last saved as a string:
    func timeIntervalSinceLastSaved(_ file: NT_DesignToolFile) -> String {
        "\(file.timeIntervalSinceLastSaved) ago"
    }
    
    /// Returns the thumbnail of the given file:
    func thumbnail(_ file: NT_DesignToolFile) -> Image {
        .init(file.thumbnail)
    }
}
