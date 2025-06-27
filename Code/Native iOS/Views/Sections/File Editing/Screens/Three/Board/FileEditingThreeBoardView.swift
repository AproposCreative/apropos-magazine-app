//
//  FileEditingThreeBoardView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeBoardView: View {
    
    // MARK: - Properties:
    
    /// Current location where the user has tapped on the canvas if applicable:
    @State var currentLocation: CGPoint? = nil
    
    /// An actual board to display:
    let board: NT_WhiteboardBoard
    
    init(board: NT_WhiteboardBoard) {
        
        /// Properties initialization:
        self.board = board
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(
                title: title,
                isLocalized: false,
                displayMode: .inline
            )
            .toolbarButton(
                title: "Share",
                icon: Icons.squareAndArrowUp,
                iconSymbolVariant: buttonIconSymbolVariant,
                font: buttonFont,
                style: buttonStyle,
                action: share
            )
            .toolbar {
                editToolbar
            }
            .toolbarBackgroundVisibility(
                .visible,
                for: .bottomBar
            )
            .animation(
                .default,
                value: notes
            )
    }
}

// MARK: - Item:

private extension FileEditingThreeBoardView {
    private var item: some View {
        GeometryReader { proxy in
            scroll(forProxy: proxy)
        }
    }
}

// MARK: - Scroll:

private extension FileEditingThreeBoardView {
    private func scroll(forProxy proxy: GeometryProxy) -> some View {
        scrollContent(forProxy: proxy)
            .scrollIndicators(.hidden)
            .background {
                FileEditingThreeBoardGridLinesView(proxy: proxy)
            }
    }
    
    private func scrollContent(forProxy proxy: GeometryProxy) -> some View {
        ScrollView(
            [
                .vertical,
                .horizontal
            ]
        ) {
            canvas(forProxy: proxy)
        }
    }
}

// MARK: - Canvas:

private extension FileEditingThreeBoardView {
    private func canvas(forProxy proxy: GeometryProxy) -> some View {
        canvasContent(forProxy: proxy)
            .frame(
                width: canvasWidth(forProxy: proxy),
                height: canvasHeight(forProxy: proxy),
                alignment: .topLeading
            )
            .onTapGesture(perform: updateCurrenLocation)
            .accessibilityLabel("Canvas with notes")
    }
    
    private func canvasContent(forProxy proxy: GeometryProxy) -> some View {
        Canvas(renderer: canvasRenderer) {
            notesContent
        }
    }
}

// MARK: - Notes:

private extension FileEditingThreeBoardView {
    private var notesContent: some View {
        ForEach(
            notes,
            content: note
        )
    }
    
    private func note(_ note: NT_WhiteboardNote) -> some View {
        FileEditingThreeBoardNoteView(
            note: note,
            frame: noteFrame,
            currentLocation: currentLocation
        )
    }
}

// MARK: - Edit toolbar:

private extension FileEditingThreeBoardView {
    private var editToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            editToolbarContent
        }
    }
    
    @ViewBuilder
    private var editToolbarContent: some View {
        newTextButton
        Spacer()
        newNoteButton
        Spacer()
        newShapeButton
        Spacer()
        newImageButton
        Spacer()
        newConnectionButton
    }
}

// MARK: - Buttons:

private extension FileEditingThreeBoardView {
    private var newTextButton: some View {
        ButtonView(
            title: "New Text",
            icon: Icons.textformat,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newText
        )
    }
    
    private var newNoteButton: some View {
        ButtonView(
            title: "New Note",
            icon: Icons.squareTextSquare,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newNote
        )
    }
    
    private var newShapeButton: some View {
        ButtonView(
            title: "New Shape",
            icon: Icons.rectangleOnRectangle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newShape
        )
    }
    
    private var newImageButton: some View {
        ButtonView(
            title: "New Image",
            icon: Icons.photoOnRectangle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newImage
        )
    }
    
    private var newConnectionButton: some View {
        ButtonView(
            title: "New Connection",
            icon: Icons.arrowTriangleSwap,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newConnection
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingThreeBoardView(board: .example.first!)
        .navigationStack()
}
