//
//  MainSevenBannerView.swift
//  Native
//

import SwiftUI

struct MainSevenBannerView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the banner should be shown at all:
    @State var isShowing: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        BannerView(
            isShowing: isShowing,
            icon: Icons.percent,
            isIconColorGradient: true,
            iconBackgroundColor: primaryColor,
            isIconBackgroundColorGradient: false,
            title: "Summer Sale",
            titleColor: primaryColor,
            subtitle: "Save more than 50% on our most popular products.",
            subtitleColor: secondaryColor,
            dismissButtonColor: tertiaryColor,
            dismissFrame: dismissFrame,
            buttons: buttons,
            isBackgroundColorGradient: true,
            dismissAction: dismiss
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainSevenBannerView()
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
