//
//  MainSixContentView.swift
//  Native
//

import SwiftUI

struct MainSixContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the stories to display:
    @State var stories: [NT_Story] = []
    
    /// An array of the posts to display:
    @State var posts: [NT_Post] = []
    
    /// An array of the accounts to display:
    @State var accounts: [NT_Account] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .overlay {
                loading
            }
            .overlay {
                nothingHere
            }
            .localizedNavigationTitle(title: "Recent")
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarAvatar(
                type: .image,
                image: avatarImage
            )
            .navigationDestination(
                for: NT_Account.self,
                destination: account
            )
            .animation(
                .default,
                value: stories
            )
            .animation(
                .default,
                value: posts
            )
            .animation(
                .default,
                value: accounts
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

// MARK: - Empty states:

private extension MainSixContentView {
    private var loading: some View {
        loadingContent
            .opacity(loadingOpacity)
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var nothingHere: some View {
        nothingHereContent
            .opacity(nothingHereOpacity)
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - List:

private extension MainSixContentView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        MainSixStoriesView(stories: stories)
        MainSixPostsForYouView(posts: posts)
        MainSixAccountsToFollowView(accounts: accounts)
    }
}

// MARK: - Account:

private extension MainSixContentView {
    private func account(_ account: NT_Account) -> some View {
        PlaceholderView(title: name(account))
    }
}

// MARK: - Preview:

#Preview {
    MainSixContentView()
}
