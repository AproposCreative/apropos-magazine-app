//
//  MainOneBannerView.swift
//  Native
//

import SwiftUI

struct MainOneBannerView: View {
    
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
            icon: Icons.gift,
            iconBackgroundGradientStart: .orangeGradientStart,
            iconBackgroundGradientEnd: .orangeGradientEnd,
            title: "Upgrade to Pro",
            subtitle: "Level up your banking experience with the Pro.",
            dismissFrame: dismissFrame,
            dismissAction: dismiss
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainOneBannerView()
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
