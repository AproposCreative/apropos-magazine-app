//
//  SettingsFourBannerView.swift
//  Native
//

import SwiftUI

struct SettingsFourBannerView: View {
    
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
            .listRowInsets(.init(.zero))
    }
}

// MARK: - Banner:

private extension SettingsFourBannerView {
    private var banner: some View {
        BannerView(
            isShowing: isShowing,
            icon: Icons.bolt,
            title: "Upgrade to Pro",
            subtitle: "Take advantage of all of the amazing features that we offer!",
            dismissFrame: dismissFrame,
            isShowingBackground: false,
            cornerRadius: 0,
            dismissAction: dismiss
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        SettingsFourBannerView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Settings")
    .navigationStack()
}
