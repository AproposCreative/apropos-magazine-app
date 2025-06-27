//
//  PaywallEightFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallEightFeaturesView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .contentBackground(
                verticalPadding: 0,
                horizontalPadding: 0
            )
    }
}

// MARK: - Item:

private extension PaywallEightFeaturesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            featuresContent
        }
    }
}

// MARK: - Features:

private extension PaywallEightFeaturesView {
    private var featuresContent: some View {
        ForEach(
            features,
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(feature),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: title(feature),
            subtitle: subtitle(feature),
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallEightFeaturesView()
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
