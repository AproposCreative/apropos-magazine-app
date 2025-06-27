//
//  PaywallTwelveMainFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallTwelveMainFeaturesView: View {
    
    // MARK: - Private properties:
    
    /// Feature that is currently shown:
    @Binding private var currentFeature: NT_Feature?
    
    /// An array of the features to display:
    private let features: [NT_Feature]
    
    init(
        features: [NT_Feature],
        currentFeature: Binding<NT_Feature?>
    ) {
        
        /// Properties initialization:
        self.features = features
        _currentFeature = currentFeature
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
}

// MARK: - Scroll:

private extension PaywallTwelveMainFeaturesView {
    private var scroll: some View {
        ScrollView(.horizontal) {
            scrollContent
        }
    }
    
    private var scrollContent: some View {
        scrollItem
            .scrollTargetLayout()
    }
    
    private var scrollItem: some View {
        HStack(
            alignment: .top,
            spacing: 32
        ) {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension PaywallTwelveMainFeaturesView {
    private var featuresContent: some View {
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
            imageAlignment: imageAlignment(feature),
            title: title(feature),
            titleAlignment: .leading,
            subtitle: subtitle(feature),
            subtitleAlignment: .leading,
            titleSubtitleAlignment: .leading,
            titleSubtitleMaxWidthAlignment: .leading,
            horizontalAlignment: .leading
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentFeature: NT_Feature? = .latestTechnologies
    
    ScrollView {
        PaywallTwelveMainFeaturesView(
            features: .init(NT_Feature.allCases.prefix(3)),
            currentFeature: $currentFeature
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
}
