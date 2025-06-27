//
//  PaywallTwelveAdditionalFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallTwelveAdditionalFeaturesView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension PaywallTwelveAdditionalFeaturesView {
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
            subtitle: ""
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallTwelveAdditionalFeaturesView()
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
