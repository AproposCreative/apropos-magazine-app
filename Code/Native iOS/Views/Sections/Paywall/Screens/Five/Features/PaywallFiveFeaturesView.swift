//
//  PaywallFiveFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallFiveFeaturesView: View {
    
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

private extension PaywallFiveFeaturesView {
    private var featuresContent: some View {
        ForEach(
            features,
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(feature),
            isShowingIconBackground: false,
            title: title(feature),
            subtitle: subtitle(feature),
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallFiveFeaturesView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Image(.paywall5).ignoresSafeArea())
    .environment(
        \.colorScheme,
         .dark
    )
}
