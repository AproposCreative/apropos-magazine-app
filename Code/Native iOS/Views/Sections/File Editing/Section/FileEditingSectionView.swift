//
//  FileEditingSectionView.swift
//  Native
//

import SwiftUI

struct FileEditingSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_FileEditingScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("File Editing")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension FileEditingSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension FileEditingSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_FileEditingScreen) -> some View {
        FileEditingSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension FileEditingSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_FileEditingScreen) -> some View {
        switch screen {
        case .first: FileEditingOneView()
        case .second: FileEditingTwoView()
        case .third: FileEditingThreeView()
        case .fourth: FileEditingFourView(file: .example.first!)
        case .fifth: FileEditingFiveView(photo: .example.first!)
        }
    }
}

// MARK: - Preview:

#Preview {
    FileEditingSectionView()
}
