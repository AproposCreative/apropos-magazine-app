//
//  OnboardingTwelveView.swift
//  Native
//

import SwiftUI

struct OnboardingTwelveView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Feature that is currently shown:
    @State var currentFeature: NT_Feature? = .latestTechnologies
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .animation(
                .default,
                value: currentFeature
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension OnboardingTwelveView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension OnboardingTwelveView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .top,
                48
            )
            .safeAreaPadding(
                .bottom,
                32
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension OnboardingTwelveView {
    private var featuresContent: some View {
        featuresItem
            .accessibilityElement(children: .combine)
    }
    
    private var featuresItem: some View {
        VStack(
            alignment: .center,
            spacing: 48
        ) {
            featuresItemContent
        }
    }
    
    @ViewBuilder
    private var featuresItemContent: some View {
        imagesScroll
        titleSubtitle
    }
}

// MARK: - Images:

private extension OnboardingTwelveView {
    private var imagesScroll: some View {
        imagesScrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .horizontal,
                32
            )
            .safeAreaPadding(
                .horizontal,
                horizontalPadding
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
    
    private var imagesScrollContent: some View {
        ScrollView(.horizontal) {
            imagesScrollItem
        }
    }
    
    private var imagesScrollItem: some View {
        images
            .scrollTargetLayout()
    }
    
    private var images: some View {
        HStack(
            alignment: .center,
            spacing: 16
        ) {
            imagesContent
        }
    }
    
    private var imagesContent: some View {
        ForEach(
            features,
            content: imageContent
        )
    }
    
    private func imageContent(_ feature: NT_Feature) -> some View {
        imageItem(feature)
            .containerRelativeFrame(.horizontal)
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(feature)
    }
    
    private func imageItem(_ feature: NT_Feature) -> some View {
        ImageBackgroundView(
            image: image(feature),
            height: 224,
            alignment: imageAlignment(feature),
            isFullWidth: true,
            cornerRadius: 16
        )
    }
}

// MARK: - Title and subtitle:

private extension OnboardingTwelveView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            title: title,
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: subtitle,
            subtitleFont: .body,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 12,
            horizontalPadding: horizontalPadding
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingTwelveView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        pagination
        getStartedButton
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentFeature,
            all: features
        )
    }
    
    private var getStartedButton: some View {
        ButtonView(
            title: getStartedTitle,
            action: getStarted
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingTwelveView()
}
