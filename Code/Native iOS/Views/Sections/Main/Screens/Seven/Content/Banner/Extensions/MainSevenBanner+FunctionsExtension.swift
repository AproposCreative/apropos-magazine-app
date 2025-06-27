//
//  MainSevenBanner+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSevenBannerView {
    
    // MARK: - Functions:
    
    /// Dismisses the banner:
    func dismiss() {
        
        /// Firstly adding an animation before dismissing the banner:
        withAnimation {
            
            /// Then dismissing the banner by setting the 'isShowing' property to 'false':
            isShowing = false
        }
        
        /// Lastly triggering the soft haptic feedback indicating that the banner was dismissed:
        HapticFeedbacks.soft()
    }
    
    /// Shows the products screen:
    func showProducts() {
        
        /*
         
         NOTE: You can add your own logic for showing the products here.
         
         */
        
    }
}
