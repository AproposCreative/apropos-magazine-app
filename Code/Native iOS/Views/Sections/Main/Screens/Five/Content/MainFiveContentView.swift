//
//  MainFiveContentView.swift
//  Native
//

import SwiftUI

struct MainFiveContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the tasks to display:
    @State var tasks: [NT_Task] = []
    
    /// An array of the comments to display:
    @State var comments: [NT_Comment] = []
    
    /// An array of the projects to display:
    @State var projects: [NT_Project] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the tasks, comments, and the projects by that is inputed by the user:
    @State var searchText: String = ""
    
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
            .localizedNavigationTitle(title: "Overview")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarAvatar(indicatorBorderColor: .init(.systemGroupedBackground))
            .navigationDestination(
                for: NT_Comment.self,
                destination: comment
            )
            .navigationDestination(
                for: NT_Project.self,
                destination: project
            )
            .animation(
                .default,
                value: searchTasks
            )
            .animation(
                .default,
                value: searchComments
            )
            .animation(
                .default,
                value: searchProjects
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

private extension MainFiveContentView {
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

private extension MainFiveContentView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        MainFiveTodayView(tasks: searchTasks)
        MainFiveCommentsView(comments: searchComments)
        MainFiveProjectsView(projects: searchProjects)
    }
}

// MARK: - Comment and project:

private extension MainFiveContentView {
    private func comment(_ comment: NT_Comment) -> some View {
        PlaceholderView(title: content(comment))
    }
    
    private func project(_ project: NT_Project) -> some View {
        PlaceholderView(title: title(project))
    }
}

// MARK: - Preview:

#Preview {
    MainFiveContentView()
}
