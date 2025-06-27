//
//  MainOneContentView.swift
//  Native
//

import SwiftUI

struct MainOneContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the accounts to display:
    @State var accounts: [NT_TransactionsAccount] = []
    
    /// An array of the bars to display in the chart:
    @State var bars: [NT_ChartBar] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(backgroundColor)
            .localizedNavigationTitle(title: "Dashboard")
            .toolbarAvatar(indicatorBorderColor: backgroundColor)
            .navigationDestination(
                for: NT_TransactionsAccount.self,
                destination: account
            )
            .animation(
                .default,
                value: accounts
            )
            .animation(
                .default,
                value: bars
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

private extension MainOneContentView {
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
        } else if isEmpty {
            nothingHere
        } else {
            bannerAccountsSummary
        }
    }
}

// MARK: - Empty states:

private extension MainOneContentView {
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
    
    private var nothingHere: some View {
        nothingHereContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - Banner, accounts, and summary:

private extension MainOneContentView {
    private var bannerAccountsSummary: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            bannerAccountsSummaryContent
        }
    }
    
    @ViewBuilder
    private var bannerAccountsSummaryContent: some View {
        MainOneBannerView()
        MainOneAccountsView(accounts: accounts)
        MainOneSummaryView(bars: bars)
    }
}

// MARK: - Account:

private extension MainOneContentView {
    private func account(_ account: NT_TransactionsAccount) -> some View {
        PlaceholderView(title: title(account))
    }
}

// MARK: - Preview:

#Preview {
    MainOneContentView()
}
