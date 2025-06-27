//
//  FileEditingThreeView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections to display:
    @State var sections: [NT_WhiteboardSection] = []
    
    /// An array of the boards of the user to display:
    @State var userBoards: [NT_WhiteboardBoard] = []
    
    /// An array of the boards of the team to display:
    @State var teamBoards: [NT_WhiteboardBoard] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the sections and the boards by that is inputed by the user:
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
            .localizedNavigationTitle(
                title: "AppLayouts",
                isLocalized: false
            )
            .toolbarButton(
                title: "New Board",
                icon: Icons.plusCircle,
                font: .body,
                style: .iconOnly,
                action: newBoard
            )
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .navigationDestination(
                for: NT_WhiteboardSection.self,
                destination: FileEditingThreeSectionBoardsView.init
            )
            .animation(
                .default,
                value: searchSections
            )
            .animation(
                .default,
                value: searchUserBoards
            )
            .animation(
                .default,
                value: searchTeamBoards
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

private extension FileEditingThreeView {
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

private extension FileEditingThreeView {
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
        FileEditingThreeSectionsView(sections: searchSections)
        userBoardsContent
        teamBoardsContent
    }
}

// MARK: - Boards:

private extension FileEditingThreeView {
    private var userBoardsContent: some View {
        FileEditingThreeBoardsView(
            boards: searchUserBoards,
            title: "My Boards"
        )
    }
    
    private var teamBoardsContent: some View {
        FileEditingThreeBoardsView(
            boards: searchTeamBoards,
            title: "Team Boards"
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingThreeView()
}
