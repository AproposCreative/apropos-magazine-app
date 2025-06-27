//
//  OnboardingSixView.swift
//  Native
//

import SwiftUI

struct OnboardingSixView: View {
    
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

private extension OnboardingSixView {
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

private extension OnboardingSixView {
    private var scroll: some View {
        ScrollView {
            featuresScroll
        }
    }
}

// MARK: - Features scroll:

private extension OnboardingSixView {
    private var featuresScroll: some View {
        featuresScrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .top,
                48
            )
            .safeAreaPadding(
                .horizontal,
                16
            )
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

private extension OnboardingSixView {
    private var featuresContent: some View {
        HStack(
            alignment: .top,
            spacing: 32
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
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(feature)
    }
    
    private func featureContent(_ feature: NT_Feature) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: image(feature),
            imageAlignment: imageAlignment(feature),
            title: title(feature),
            subtitle: subtitle(feature)
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingSixView {
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
    OnboardingSixView()
}
