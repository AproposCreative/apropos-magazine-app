//
//  PaywallTenFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallTenFeaturesView: View {
    
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
        item
            .contentBackground(backgroundColor: .init(.secondarySystemBackground))
    }
}

// MARK: - Item:

private extension PaywallTenFeaturesView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        pagination
    }
}

// MARK: - Scroll:

private extension PaywallTenFeaturesView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        scrollItemContent
            .scrollTargetLayout()
    }
    
    private var scrollItemContent: some View {
        HStack(
            alignment: .top,
            spacing: 16
        ) {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension PaywallTenFeaturesView {
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
        IconBackgroundTitleSubtitleView(
            icon: icon(feature),
            iconBackgroundGradientStart: gradientStart(feature),
            iconBackgroundGradientEnd: gradientEnd(feature),
            iconSize: .sixtyFourPixels,
            title: title(feature),
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: subtitle(feature),
            subtitleFont: .body,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 12,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            spacing: 24,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Pagination:

private extension PaywallTenFeaturesView {
    private var pagination: some View {
        PaginationView(
            current: $currentFeature,
            all: features
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentFeature: NT_Feature? = .latestTechnologies
    
    ScrollView {
        PaywallTenFeaturesView(
            features: .init(NT_Feature.allCases.prefix(4)),
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
}
