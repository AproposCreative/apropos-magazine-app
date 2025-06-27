//
//  FileEditingTwoDetails+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingTwoDetailsView {
    
    // MARK: - Functions:
    
    /// Lets the user create a new photo based on the photo that is currently selected:
    func create() {
        
        /// Showing the photo editor for the newly created photo by setting the 'isPhotoEditorPresented' property to 'true':
        isPhotoEditorPresented = true
    }
}
