//
//  PaywallOneFeaturesView.swift
//  Native
//

import SwiftUI

struct PaywallOneFeaturesView: View {
    
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

private extension PaywallOneFeaturesView {
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
            subtitle: subtitle(feature)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallOneFeaturesView()
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
