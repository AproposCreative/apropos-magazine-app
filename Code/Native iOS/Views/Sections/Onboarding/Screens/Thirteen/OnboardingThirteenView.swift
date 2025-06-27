//
//  OnboardingThirteenView.swift
//  Native
//

import SwiftUI

struct OnboardingThirteenView: View {
    
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
            .background(backgroundGradient)
            .animation(
                .default,
                value: currentFeature
            )
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Item:

private extension OnboardingThirteenView {
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

private extension OnboardingThirteenView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .top,
                24
            )
            .safeAreaPadding(
                .bottom,
                32
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        featuresContent
            .scrollTargetLayout()
    }
}

// MARK: - Features:

private extension OnboardingThirteenView {
    private var featuresContent: some View {
        HStack(
            alignment: .top,
            spacing: 0
        ) {
            featuresItem
        }
    }
    
    private var featuresItem: some View {
        ForEach(
            features,
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        featureContent(feature)
            .containerRelativeFrame(.horizontal)
            .id(feature)
    }
    
    private func featureContent(_ feature: NT_Feature) -> some View {
        ScrollView {
            featureItem(feature)
        }
    }
    
    private func featureItem(_ feature: NT_Feature) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: image(feature),
            isImageResizable: false,
            isImageClipped: false,
            imageHeight: 432,
            isImageFullWidth: true,
            isShowingImageBackground: false,
            imageCornerRadius: 0,
            title: title(feature),
            titleAlignment: .leading,
            subtitle: subtitle(feature),
            subtitleAlignment: .leading,
            subtitleColor: .primary.opacity(0.8),
            titleSubtitleAlignment: .leading,
            titleSubtitleHorizontalPadding: 16,
            horizontalAlignment: .leading
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingThirteenView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        getStartedButton
        pagination
    }
    
    private var getStartedButton: some View {
        ButtonView(
            title: getStartedTitle,
            titleColor: .blueSystem,
            backgroundColor: .white,
            isBackgroundColorGradient: false,
            action: getStarted
        )
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentFeature,
            all: features,
            color: .white,
            isColorGradient: false
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingThirteenView()
}
