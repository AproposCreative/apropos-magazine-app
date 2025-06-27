//
//  MainSixStoriesView.swift
//  Native
//

import SwiftUI

struct MainSixStoriesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Story that is currently shown (Can be 'nil' or no story at all):
    @State var currentStory: NT_Story? = nil
    
    /// An array of the stories to display:
    let stories: [NT_Story]
    
    init(stories: [NT_Story]) {
        
        /// Properties initialization:
        self.stories = stories
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        scroll
            .listRowInsets(.init(.zero))
            .fullScreenCover(
                item: $currentStory,
                content: MainSixStoryView.init
            )
    }
}

// MARK: - Scroll:

private extension MainSixStoriesView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .vertical,
                12
            )
            .safeAreaPadding(
                .trailing,
                32
            )
            .safeAreaPadding(
                .leading,
                16
            )
            .scrollTargetBehavior(.viewAligned)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        storiesContent
            .scrollTargetLayout()
    }
}

// MARK: - Stories:

private extension MainSixStoriesView {
    private var storiesContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: 12
        ) {
            storiesItem
        }
    }
    
    @ViewBuilder
    private var storiesItem: some View {
        newStoryButton
        storiesItemContent
    }
    
    private var storiesItemContent: some View {
        ForEach(
            stories,
            content: story
        )
    }
    
    private func story(_ story: NT_Story) -> some View {
        storyContent(story)
            .buttonStyle(.plain)
    }
    
    private func storyContent(_ story: NT_Story) -> some View {
        Button {
            view(story)
        } label: {
            storyLabel(story)
        }
    }
    
    private func storyLabel(_ story: NT_Story) -> some View {
        storyLabelContent(story)
            .frame(
                width: storyWidth,
                alignment: .center
            )
            .accessibilityLabel(accessibilityLabel(story))
    }
    
    private func storyLabelContent(_ story: NT_Story) -> some View {
        ImageBackgroundBorderTitleView(
            image: image(story),
            imageBorderGradientStart: gradientStart(story),
            imageBorderGradientEnd: gradientEnd(story),
            title: username(story)
        )
    }
}

// MARK: - New story button:

private extension MainSixStoriesView {
    private var newStoryButton: some View {
        newStoryButtonContent
            .buttonStyle(.plain)
            .frame(
                width: storyWidth,
                alignment: .center
            )
    }
    
    private var newStoryButtonContent: some View {
        Button {
            newStory()
        } label: {
            newStoryButtonLabel
        }
    }
    
    private var newStoryButtonLabel: some View {
        IconBackgroundBorderTitleView(
            icon: Icons.plusCircle,
            title: "My Story"
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainSixStoriesView(stories: NT_Story.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Recent")
    .navigationStack()
}
