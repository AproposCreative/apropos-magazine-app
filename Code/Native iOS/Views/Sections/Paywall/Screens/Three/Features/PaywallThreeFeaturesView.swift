//
//  PaywallThreeFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallThreeFeaturesView: View {
    
    // MARK: - Private properties:
    
    /// Feature that is currently shown:
    @Binding private var currentFeature: NT_Feature?
    
    init(currentFeature: Binding<NT_Feature?>) {
        
        /// Properties initialization:
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

private extension PaywallThreeFeaturesView {
    private var scroll: some View {
        ScrollView(.horizontal) {
            scrollContent
        }
    }
    
    private var scrollContent: some View {
        featuresContent
            .scrollTargetLayout()
    }
}

// MARK: - Features:

private extension PaywallThreeFeaturesView {
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
            imageAlignment: imageAlignment(feature),
            imageCornerRadius: 0,
            title: title(feature),
            subtitle: subtitle(feature),
            titleSubtitleHorizontalPadding: 16
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentFeature: NT_Feature? = .latestTechnologies
    
    PaywallThreeFeaturesView(currentFeature: $currentFeature)
}
