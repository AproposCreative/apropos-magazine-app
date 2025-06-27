//
//  ProfileOneDetailsView.swift
//  Native
//

import SwiftUI

struct ProfileOneDetailsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the banner should be shown at all:
    @State var isShowingBanner: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension ProfileOneDetailsView {
    @ViewBuilder
    private var item: some View {
        user
        banner
        statsContent
    }
}

// MARK: - User:

private extension ProfileOneDetailsView {
    private var user: some View {
        ImageBackgroundTitleSubtitleBadgeView(
            image: image, 
            title: "John Smith",
            subtitle: "@john.smith_123",
            badgeTitle: "Pro",
            isShowingBadgeBorder: true,
            verticalAlignment: .top
        )
    }
}

// MARK: - Banner:

private extension ProfileOneDetailsView {
    private var banner: some View {
        BannerView(
            isShowing: isShowingBanner,
            icon: Icons.bolt,
            iconBackgroundGradientStart: .orangeGradientStart,
            iconBackgroundGradientEnd: .orangeGradientEnd,
            title: "Supercharge Your Workflow",
            subtitle: "Explore our latest blog post to level up your tasks management.",
            dismissFrame: dismissFrame,
            buttons: bannerButtons,
            dismissAction: dismissBanner
        )
    }
}

// MARK: - Stats:

private extension ProfileOneDetailsView {
    private var statsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            statsItem
        }
    }
    
    private var statsItem: some View {
        ForEach(
            stats,
            content: stat
        )
    }
    
    private func stat(_ stat: NT_ProfileTaskStat) -> some View {
        TitleSubtitleView(
            title: value(stat),
            titleFont: .subheadline.bold(),
            titleAlignment: .center,
            subtitle: title(stat),
            subtitleFont: .footnote,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 2,
            maxWidth: .infinity,
            maxWidthAlignment: .center,
            verticalPadding: statPadding,
            horizontalPadding: statPadding,
            maxHeight: .infinity,
            isShowingBackground: true,
            cornerRadius: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileOneDetailsView()
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
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
