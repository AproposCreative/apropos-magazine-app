//
//  FileEditingTwoSection+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension FileEditingTwoSectionView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given photo:
    func title(_ photo: NT_PhotoEditorPhoto) -> String {
        photo.title
    }
    
    /// Returns the image of the given photo:
    func image(_ photo: NT_PhotoEditorPhoto) -> Image {
        .init(photo.image)
    }
    
    /// Lets the user select the given photo:
    func select(_ photo: NT_PhotoEditorPhoto) {
        
        /// Selecting the given photo by updating the 'selectedPhoto' property with the given photo:
        selectedPhoto = photo
    }
}
