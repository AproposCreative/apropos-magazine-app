//
//  MainSixStory+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSixStoryView {
    
    // MARK: - Computed properties:
    
    /// Image of the story to display:
    var image: Image {
        .init(story.image)
    }
}
