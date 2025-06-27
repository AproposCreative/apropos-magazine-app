//
//  MainNineFoldersView.swift
//  Native
//

import SwiftUI

struct MainNineFoldersView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the folders to display:
    let folders: [NT_Folder]
    
    init(folders: [NT_Folder]) {
        
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
            item
        }
    }
}

// MARK: - Item:

private extension MainNineFoldersView {
    private var item: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            foldersContent
        }
    }
}

// MARK: - Folders:

private extension MainNineFoldersView {
    private var foldersContent: some View {
        ForEach(
            folders,
            content: folder
        )
    }
    
    private func folder(_ folder: NT_Folder) -> some View {
        NavigationLink(value: folder) {
            folderLabel(folder)
        }
    }
    
    private func folderLabel(_ folder: NT_Folder) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: Icons.folder,
            iconColor: color(folder),
            iconGradientStart: gradientStart(folder),
            iconGradientEnd: gradientEnd(folder),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: title(folder),
            subtitle: filesCount(folder),
            alignment: .vertical,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainNineFoldersView(folders: NT_Folder.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Folders")
    .navigationDestination(for: NT_Folder.self) { folder in
        PlaceholderView(title: folder.title)
    }
    .navigationStack()
}
