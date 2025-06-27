//
//  FileEditingFive+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension FileEditingFiveView {
    
    // MARK: - Functions:
    
    /// Lets the user add a new image:
    func newImage() {
        
        /*
         
         NOTE: You can add your own logic for adding a new image here.
         
         */
        
    }
    
    /// Lets the user annotate the image:
    func annotate() {
        
        /*
         
         NOTE: You can add your own logic for annotating the image here.
         
         */
        
    }
    
    /// Lets the user crop the image:
    func crop() {
        
        /*
         
         NOTE: You can add your own logic for cropping the image here.
         
         */
        
    }
    
    /// Lets the users rotate the image to the left:
    func rotateLeft() {
        
        /// Updating the angle of the rotation of the image by subtracting the ninety degrees from it to rotate the image to the left:
        rotationAngle += -.init(degrees: 90)
    }
    
    /// Lets the users rotate the image to the right:
    func rotateRight() {
        
        /// Updating the angle of the rotation of the image by adding the ninety degrees to it to rotate the image to the right:
        rotationAngle += .init(degrees: 90)
    }
}
