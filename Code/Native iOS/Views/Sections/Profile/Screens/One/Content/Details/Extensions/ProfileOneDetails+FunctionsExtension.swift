//
//  ProfileOneDetails+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProfileOneDetailsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given stat:
    func title(_ stat: NT_ProfileTaskStat) -> String {
        stat.title
    }
    
    /// Returns the value of the given stat as a string:
    func value(_ stat: NT_ProfileTaskStat) -> String {
        stat.value.formatted()
    }
    
    /// Dismisses the banner:
    func dismissBanner() {
        
        /// Firstly adding an animation before dismissing the banner:
        withAnimation {
            
            /// Then dismissing the banner by setting the 'isShowingBanner' property to 'false':
            isShowingBanner = false
        }
        
        /// Lastly triggering the soft haptic feedback indicating that the banner was dismissed:
        HapticFeedbacks.soft()
    }
    
    /// Shows the screen with the latest blog post:
    func showLatestBlogPost() {
        
        /*
         
         NOTE: You can add your own logic for showing the latest blog post here.
         
         */
        
    }
}
