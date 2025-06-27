//
//  MainSixStories+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSixStoriesView {
    
    // MARK: - Functions:
    
    /// Returns the username of the account that the given story was posted by:
    func username(_ story: NT_Story) -> String {
        account(story).username
    }
    
    /// Returns the accessibility label of the given story:
    func accessibilityLabel(_ story: NT_Story) -> String {
        "\(username(story)) story"
    }
    
    /// Returns the color of the given story:
    func color(_ story: NT_Story) -> Color {
        story.color.opacity(opacity(story))
    }
    
    /// Returns the starting color of the gradient of the given story:
    func gradientStart(_ story: NT_Story) -> Color {
        story.gradientStart.opacity(opacity(story))
    }
    
    /// Returns the ending color of the gradient of the given story:
    func gradientEnd(_ story: NT_Story) -> Color {
        story.gradientEnd.opacity(opacity(story))
    }
    
    /// Returns the image of the account that the given story was posted by:
    func image(_ story: NT_Story) -> Image {
        .init(account(story).image)
    }
    
    /// Lets the user view the given story:
    func view(_ story: NT_Story) {
        
        /// Showing the given story by updating the 'currentStory' property with the given story:
        currentStory = story
    }
    
    /// Lets the user add a new story:
    func newStory() {
        
        /*
         
         NOTE: You can add your own logic for adding a new story here.
         
         */
        
    }
    
    // MARK: - Private functions:
    
    /// Returns the account that the given store was posted by:
    private func account(_ story: NT_Story) -> NT_Account {
        story.account
    }
    
    /// Returns the opacity of the color of the given story:
    private func opacity(_ story: NT_Story) -> Double {
        story.isSeen ? 0.24 : 1
    }
}
