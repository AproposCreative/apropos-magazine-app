//
//  FileEditingTwoPhotos+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingTwoPhotosView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the sections with the photos to display is empty:
    var isEmpty: Bool {
        sections.isEmpty
    }
    
    /// An array of the sections with the photos that are part of the category to display:
    var sections: [NT_PhotoEditorSection] {
        category.sections.filter { !$0.photos.isEmpty }
    }
    
    /// Title of the category:
    var title: String {
        category.title
    }
}
