//
//  SettingsFiveBannerView.swift
//  Native
//

import SwiftUI

struct SettingsFiveBannerView: View {
    
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
        banner
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(.zero))
            .padding(
                .horizontal,
                16
            )
    }
}

// MARK: - Banner:

private extension SettingsFiveBannerView {
    private var banner: some View {
        BannerView(
            isShowing: isShowing,
            icon: Icons.bolt,
            isIconColorGradient: true,
            iconBackgroundColor: primaryColor,
            isIconBackgroundColorGradient: false,
            title: "Upgrade to Pro",
            titleColor: primaryColor,
            subtitle: "Take advantage of all of the amazing features that we offer!",
            subtitleColor: secondaryColor,
            dismissButtonColor: tertiaryColor,
            dismissFrame: dismissFrame,
            isBackgroundColorGradient: true,
            dismissAction: dismiss
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        SettingsFiveBannerView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Settings")
    .navigationStack()
}
