//
//  FileEditingOneFoldersView.swift
//  Native
//

import SwiftUI

struct FileEditingOneFoldersView: View {
    
    // MARK: - Properties:
    
    /// An array of the folders to display:
    let folders: [NT_DesignToolFolder]
    
    init(folders: [NT_DesignToolFolder]) {
        
        /// Properties initialization:
        self.folders = folders
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
    
    @ViewBuilder
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension FileEditingOneFoldersView {
    private var item: some View {
        Section("Folders") {
            foldersContent
        }
    }
}

// MARK: - Folders:

private extension FileEditingOneFoldersView {
    private var foldersContent: some View {
        ForEach(
            folders,
            content: folder
        )
    }
    
    private func folder(_ folder: NT_DesignToolFolder) -> some View {
        NavigationLink(value: folder) {
            folderLabel(folder)
        }
    }
    
    private func folderLabel(_ folder: NT_DesignToolFolder) -> some View {
        LabelView(
            icon: icon(folder),
            title: title(folder),
            isShowingBadge: true,
            badge: filesCount(folder),
            isBadgeLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingOneFoldersView(folders: NT_DesignToolFolder.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(
        title: "AppLayouts",
        isLocalized: false
    )
    .navigationDestination(for: NT_DesignToolFolder.self) { folder in
        PlaceholderView(title: folder.title)
    }
    .navigationStack()
}
