//
//  MainEightTopicsView.swift
//  Native
//

import SwiftUI

struct MainEightTopicsView: View {
    
    // MARK: - Properties:
    
    /// An array of the topics to display:
    let topics: [NT_BlogTopic]
    
    init(topics: [NT_BlogTopic]) {
        
        /// Properties initialization:
        self.topics = topics
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
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension MainEightTopicsView {
    private var item: some View {
        Section("Topics") {
            topicsContent
        }
    }
}

// MARK: - Topics:

private extension MainEightTopicsView {
    private var topicsContent: some View {
        ForEach(
            topics,
            content: topic
        )
    }
    
    private func topic(_ topic: NT_BlogTopic) -> some View {
        NavigationLink(value: topic) {
            topicLabel(topic)
        }
    }
    
    private func topicLabel(_ topic: NT_BlogTopic) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(topic),
            iconColor: color(topic),
            iconGradientStart: gradientStart(topic),
            iconGradientEnd: gradientEnd(topic),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(topic),
            isShowingSubtitle: false,
            subtitle: "",
            isShowingBadge: true,
            badge: articlesCount(topic),
            verticalAlignment: .center,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainEightTopicsView(topics: NT_BlogTopic.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Blog")
    .navigationDestination(for: NT_BlogTopic.self) { topic in
        PlaceholderView(title: topic.title)
    }
    .navigationStack()
}
