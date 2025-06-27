//
//  MainFourView.swift
//  Native
//

import SwiftUI

struct MainFourView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections with the news to display:
    @State var sections: [NT_NewsSection] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .localizedNavigationTitle(title: "News")
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: toolbarFont,
                style: toolbarStyle,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarButton(
                title: "New Article",
                icon: Icons.plusCircle,
                font: toolbarFont,
                style: toolbarStyle,
                action: newArticle
            )
            .animation(
                .default,
                value: sections
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

private extension MainFourView {
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
            noNews
        } else {
            MainFourSectionsView(sections: sections)
        }
    }
}

// MARK: - Empty states:

private extension MainFourView {
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
    
    private var noNews: some View {
        noNewsContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noNewsContent: some View {
        EmptyStateView(
            title: "No News",
            subtitle: "We don't have any news to display here."
        )
    }
}

// MARK: - Preview:

#Preview {
    MainFourView()
}
