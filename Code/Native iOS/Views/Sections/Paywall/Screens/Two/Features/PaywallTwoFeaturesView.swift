//
//  PaywallTwoFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallTwoFeaturesView: View {
    
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

private extension PaywallTwoFeaturesView {
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
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallTwoFeaturesView()
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
