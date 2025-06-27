//
//  FileEditingThreeSectionBoardsView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeSectionBoardsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An actual section to display the boards for:
    let section: NT_WhiteboardSection
    
    // MARK: - Private properties:
    
    /// Namespace that is needed for the zoom transition:
    @Namespace private var namespace
    
    init(section: NT_WhiteboardSection) {
        
        /// Properties initialization:
        self.section = section
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
    }
}

// MARK: - Scroll:

private extension FileEditingThreeSectionBoardsView {
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
        if isEmpty {
            noBoards
        } else {
            boardsContent
        }
    }
}

// MARK: - No boards:

private extension FileEditingThreeSectionBoardsView {
    private var noBoards: some View {
        noBoardsContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noBoardsContent: some View {
        EmptyStateView(
            title: "No Boards",
            subtitle: "Just add a board and it will appear here."
        )
    }
}

// MARK: - Boards:

private extension FileEditingThreeSectionBoardsView {
    private var boardsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            boardsItem
        }
    }
    
    private var boardsItem: some View {
        ForEach(
            boards,
            content: board
        )
    }
    
    private func board(_ board: NT_WhiteboardBoard) -> some View {
        boardContent(board)
            .matchedTransitionSource(
                id: identifier(board),
                in: namespace
            )
    }
    
    private func boardContent(_ board: NT_WhiteboardBoard) -> some View {
        NavigationLink {
            boardItem(board)
        } label: {
            boardLabel(board)
        }
    }
    
    private func boardItem(_ board: NT_WhiteboardBoard) -> some View {
        FileEditingThreeBoardView(board: board)
            .navigationTransition(
                .zoom(
                    sourceID: identifier(board),
                    in: namespace
                )
            )
    }
    
    private func boardLabel(_ board: NT_WhiteboardBoard) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(board),
            title: title(board),
            isShowingSubtitle: false,
            subtitle: "",
            alignment: .vertical,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingThreeSectionBoardsView(section: .example.first!)
        .navigationStack()
}
