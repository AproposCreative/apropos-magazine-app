//
//  MainOneBanner+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainOneBannerView {
    
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
}
