//
//  FileEditingOneFolderView.swift
//  Native
//

import SwiftUI

struct FileEditingOneFolderView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An actual folder to display:
    let folder: NT_DesignToolFolder
    
    /// An array of all of the folders to display that is needed to show the divider of the view correctly:
    let folders: [NT_DesignToolFolder]
    
    // MARK: - Private properties:
    
    /// Namespace that is needed for the zoom transition:
    @Namespace private var namespace
    
    init(
        folder: NT_DesignToolFolder,
        folders: [NT_DesignToolFolder]
    ) {
        
        /// Properties initialization:
        self.folder = folder
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

private extension FileEditingOneFolderView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        filesContent
        divider
    }
}

// MARK: - Header:

private extension FileEditingOneFolderView {
    private var header: some View {
        NavigationLink(value: folder) {
            headerLabel
        }
    }
    
    private var headerLabel: some View {
        SectionHeaderView(
            title: title,
            isTitleLocalized: false,
            titleMaxWidth: nil,
            isShowingIcon: true,
            iconFrame: headerIconFrame,
            isShowingSubtitle: true,
            subtitle: filesCount
        )
    }
}

// MARK: - Files:

private extension FileEditingOneFolderView {
    private var filesContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            filesItem
        }
    }
    
    private var filesItem: some View {
        ForEach(
            files,
            content: file
        )
    }
    
    private func file(_ file: NT_DesignToolFile) -> some View {
        fileContent(file)
            .matchedTransitionSource(
                id: identifier(file),
                in: namespace
            )
    }
    
    private func fileContent(_ file: NT_DesignToolFile) -> some View {
        NavigationLink {
            fileItem(file)
        } label: {
            fileLabel(file)
        }
    }
    
    private func fileItem(_ file: NT_DesignToolFile) -> some View {
        fileItemContent(file)
            .navigationTransition(
                .zoom(
                    sourceID: identifier(file),
                    in: namespace
                )
            )
    }
    
    private func fileItemContent(_ file: NT_DesignToolFile) -> some View {
        FileEditingFourView(
            file: file,
            isEmbeddingIntoNavigationStack: false
        )
    }
    
    private func fileLabel(_ file: NT_DesignToolFile) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: thumbnail(file),
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageCornerRadius: 16,
            title: title(file),
            titleFont: .headline,
            subtitle: timeIntervalSinceLastSaved(file),
            isSubtitleLocalized: false,
            subtitleFont: .subheadline,
            titleSubtitleSpacing: 4,
            spacing: 12,
            maxHeight: .infinity
        )
    }
}

// MARK: - Divider:

private extension FileEditingOneFolderView {
    @ViewBuilder
    private var divider: some View {
        if isShowingDivider {
            DividerView()
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        FileEditingOneFolderView(
            folder: .example.first!,
            folders: NT_DesignToolFolder.example
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Recent")
    .navigationDestination(for: NT_DesignToolFolder.self) { folder in
        PlaceholderView(title: folder.title)
    }
    .navigationStack()
}
