//
//  PaywallFourteenFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallFourteenFeaturesView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .padding(
                .horizontal,
                16
            )
    }
}

// MARK: - Item:

private extension PaywallFourteenFeaturesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension PaywallFourteenFeaturesView {
    private var featuresContent: some View {
        ForEach(
            features,
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: Icons.checkmarkCircle,
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .thirtyTwoPixels,
            title: subtitle(feature),
            isShowingSubtitle: false,
            subtitle: "",
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallFourteenFeaturesView()
    }
    .safeAreaPadding(
        .top,
        16
    )
    .safeAreaPadding(
        .bottom,
        32
    )
}
