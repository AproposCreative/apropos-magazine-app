//
//  FileEditingOneFilesView.swift
//  Native
//

import SwiftUI

struct FileEditingOneFilesView: View {
    
    // MARK: - Properties:
    
    /// An actual section to display the files for if applicable:
    let section: NT_DesignToolSection?
    
    /// An actual folder to display the files for if applicable:
    let folder: NT_DesignToolFolder?
    
    /// An actual tag to display the files for if applicable:
    let tag: NT_DesignToolTag?
    
    init(
        section: NT_DesignToolSection?,
        folder: NT_DesignToolFolder?,
        tag: NT_DesignToolTag?
    ) {
        
        /// Properties initialization:
        self.section = section
        self.folder = folder
        self.tag = tag
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
            .toolbar {
                settingsToolbar
            }
            .animation(
                .default,
                value: folders
            )
    }
}

// MARK: - Scroll:

private extension FileEditingOneFilesView {
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
            noFiles
        } else {
            foldersContent
        }
    }
}

// MARK: - No files:

private extension FileEditingOneFilesView {
    private var noFiles: some View {
        noFilesContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noFilesContent: some View {
        EmptyStateView(
            title: "No Files",
            subtitle: "Just add a file and it will appear here."
        )
    }
}

// MARK: - Folders:

private extension FileEditingOneFilesView {
    private var foldersContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 24
        ) {
            foldersItem
        }
    }
    
    private var foldersItem: some View {
        ForEach(
            folders,
            content: folder
        )
    }
    
    private func folder(_ folder: NT_DesignToolFolder) -> some View {
        FileEditingOneFolderView(
            folder: folder,
            folders: folders
        )
    }
}

// MARK: - Settings toolbar:

private extension FileEditingOneFilesView {
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            settingsMenu
        }
    }
    
    private var settingsMenu: some View {
        Menu {
            settingsMenuContent
        } label: {
            settingsMenuLabel
        }
    }
    
    @ViewBuilder
    private var settingsMenuContent: some View {
        newFileButton
        filterButton
        generateButton
    }
    
    private var settingsMenuLabel: some View {
        LabelView(
            icon: Icons.ellipsisCircle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconSize: settingsIconSize,
            title: "Settings",
            style: .iconOnly
        )
    }
}

// MARK: - Buttons:

private extension FileEditingOneFilesView {
    private var newFileButton: some View {
        ButtonView(
            title: "New File",
            titleFont: buttonFont,
            icon: Icons.plusCircle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newFile
        )
    }
    
    private var filterButton: some View {
        ButtonView(
            title: "Filter",
            titleFont: buttonFont,
            icon: Icons.lineThreeHorizontalDecreaseCircle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: filter
        )
    }
    
    private var generateButton: some View {
        ButtonView(
            title: "Generate",
            titleFont: buttonFont,
            icon: Icons.sparkles,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: generate
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingOneFilesView(
        section: .example.first,
        folder: nil,
        tag: nil
    )
    .navigationStack()
}
