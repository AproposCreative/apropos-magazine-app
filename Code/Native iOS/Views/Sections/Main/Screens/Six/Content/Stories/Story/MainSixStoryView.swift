//
//  MainSixStoryView.swift
//  Native
//

import SwiftUI

struct MainSixStoryView: View {
    
    // MARK: - Properties:
    
    /// An actual story to display:
    let story: NT_Story
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    init(story: NT_Story) {
        
        /// Properties initialization:
        self.story = story
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        imageContent
            .toolbarButton(
                title: "Done",
                color: .primary,
                action: dismiss.callAsFunction
            )
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Image:

private extension MainSixStoryView {
    private var imageContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
            .accessibilityLabel("Story image")
    }
}

// MARK: - Preview:

#Preview {
    MainSixStoryView(story: .example.first!)
}
