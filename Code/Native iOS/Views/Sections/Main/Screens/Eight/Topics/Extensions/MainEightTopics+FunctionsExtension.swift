//
//  MainEightTopics+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainEightTopicsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given topic:
    func title(_ topic: NT_BlogTopic) -> String {
        topic.title
    }
    
    /// Returns the count of the articles that are part of the given topic as a string:
    func articlesCount(_ topic: NT_BlogTopic) -> String {
        topic.articlesCount.formatted()
    }
    
    /// Returns the color of the given topic:
    func color(_ topic: NT_BlogTopic) -> Color {
        topic.color
    }
    
    /// Returns the starting color of the gradient of the given topic:
    func gradientStart(_ topic: NT_BlogTopic) -> Color {
        topic.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given topic:
    func gradientEnd(_ topic: NT_BlogTopic) -> Color {
        topic.gradientEnd
    }
    
    /// Returns the icon of the given topic:
    func icon(_ topic: NT_BlogTopic) -> String {
        topic.icon
    }
}
