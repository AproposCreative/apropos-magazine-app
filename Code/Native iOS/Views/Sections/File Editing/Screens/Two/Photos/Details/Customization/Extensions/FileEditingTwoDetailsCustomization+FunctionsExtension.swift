//
//  FileEditingTwoDetailsCustomization+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension FileEditingTwoDetailsCustomizationView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given resolution:
    func title(_ resolution: NT_ImageResolution) -> LocalizedStringKey {
        .init(resolution.title)
    }
    
    /// Returns the title of the given aspect ratio:
    func title(_ aspectRatio: NT_ImageAspectRatio) -> LocalizedStringKey {
        .init(aspectRatio.title)
    }
    
    /// Returns the title of the given grid:
    func title(_ grid: NT_ImageGrid) -> LocalizedStringKey {
        .init(grid.title)
    }
}
