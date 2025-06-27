//
//  ProfileTwoView.swift
//  Native
//

import SwiftUI

struct ProfileTwoView: View {
    
    // MARK: - Properties:
    
    /// Account to display the details for:
    @State var account: NT_ProfileAccount? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .localizedNavigationTitle(title: "Profile")
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: toolbarIconSymbolVariant,
                font: toolbarFont,
                style: toolbarStyle,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarButton(
                title: "Share",
                icon: Icons.squareAndArrowUp,
                iconSymbolVariant: toolbarIconSymbolVariant,
                font: toolbarFont,
                style: toolbarStyle,
                action: share
            )
            .animation(
                .default,
                value: account
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension ProfileTwoView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isNoAccount {
            noData
        } else {
            accountPosts
        }
    }
}

// MARK: - Empty states:

private extension ProfileTwoView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var noData: some View {
        noDataContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noDataContent: some View {
        EmptyStateView(
            title: "No Data",
            subtitle: "We don't have any data to display here."
        )
    }
}

// MARK: - Account and posts:

private extension ProfileTwoView {
    private var accountPosts: some View {
        VStack(
            alignment: .leading,
            spacing: 24
        ) {
            accountPostsContent
        }
    }
    
    @ViewBuilder
    private var accountPostsContent: some View {
        accountContent
        DividerView()
        posts
    }
    
    @ViewBuilder
    private var accountContent: some View {
        if let account {
            ProfileTwoAccountView(account: account)
        }
    }
    
    @ViewBuilder
    private var posts: some View {
        if let account {
            ProfileTwoPostsView(account: account)
        }
    }
}

// MARK: - Preview:

#Preview {
    ProfileTwoView()
}
