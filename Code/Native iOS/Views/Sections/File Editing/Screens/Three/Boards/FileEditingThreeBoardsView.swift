//
//  FileEditingThreeBoardsView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeBoardsView: View {
    
    // MARK: - Properties:
    
    /// An array of the boards to display:
    let boards: [NT_WhiteboardBoard]
    
    /// Title of the view:
    let title: LocalizedStringKey
    
    init(
        boards: [NT_WhiteboardBoard],
        title: LocalizedStringKey
    ) {
        
        /// Properties initialization:
        self.boards = boards
        self.title = title
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension FileEditingThreeBoardsView {
    private var item: some View {
        Section(title) {
            boardsContent
        }
    }
}

// MARK: - Boards:

private extension FileEditingThreeBoardsView {
    private var boardsContent: some View {
        ForEach(
            boards,
            content: board
        )
    }
    
    private func board(_ board: NT_WhiteboardBoard) -> some View {
        NavigationLink {
            FileEditingThreeBoardView(board: board)
        } label: {
            boardLabel(board)
        }
    }
    
    private func boardLabel(_ board: NT_WhiteboardBoard) -> some View {
        LabelView(
            icon: icon(board),
            title: title(board)
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingThreeBoardsView(
            boards: NT_WhiteboardBoard.example,
            title: "My Boards"
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(
        title: "AppLayouts",
        isLocalized: false
    )
    .navigationDestination(for: NT_WhiteboardBoard.self) { board in
        PlaceholderView(title: board.title)
    }
    .navigationStack()
}
