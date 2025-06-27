//
//  OnboardingEightView.swift
//  Native
//

import SwiftUI

struct OnboardingEightView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Private properties:
    
    /// Feature that is currently shown:
    @State private var currentFeature: NT_Feature? = .latestTechnologies
    
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

private extension OnboardingEightView {
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

private extension OnboardingEightView {
    private var scroll: some View {
        ScrollView {
            featuresScroll
        }
    }
}

// MARK: - Features scroll:

private extension OnboardingEightView {
    private var featuresScroll: some View {
        featuresScrollContent
            .ignoresSafeArea()
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .bottom,
                32
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
    
    private var featuresScrollContent: some View {
        ScrollView(.horizontal) {
            featuresScrollItem
        }
    }
    
    private var featuresScrollItem: some View {
        featuresContent
            .scrollTargetLayout()
    }
}

// MARK: - Features:

private extension OnboardingEightView {
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
        ImageBackgroundTitleSubtitleView(
            image: image(feature),
            imageHeight: 344,
            imageAlignment: .top,
            imageCornerRadius: 0,
            title: title(feature),
            subtitle: subtitle(feature),
            titleSubtitleHorizontalPadding: 16
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingEightView {
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
            title: "Get Started",
            action: getStarted
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingEightView()
}
