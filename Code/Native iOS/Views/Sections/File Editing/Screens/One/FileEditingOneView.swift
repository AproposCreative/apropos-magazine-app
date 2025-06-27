//
//  FileEditingOneView.swift
//  Native
//

import SwiftUI

struct FileEditingOneView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections to display:
    @State var sections: [NT_DesignToolSection] = []
    
    /// An array of the folders to display:
    @State var folders: [NT_DesignToolFolder] = []
    
    /// An array of the tags to display:
    @State var tags: [NT_DesignToolTag] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the sections, folders, and tags by that is inputed by the user:
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .navigationDestination(
                for: NT_DesignToolSection.self,
                destination: files
            )
            .navigationDestination(
                for: NT_DesignToolFolder.self,
                destination: files
            )
            .navigationDestination(
                for: NT_DesignToolTag.self,
                destination: files
            )
            .animation(
                .default,
                value: searchSections
            )
            .animation(
                .default,
                value: searchFolders
            )
            .animation(
                .default,
                value: searchTags
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

private extension FileEditingOneView {
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

private extension FileEditingOneView {
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
        FileEditingOneSectionsView(sections: searchSections)
        FileEditingOneFoldersView(folders: searchFolders)
        FileEditingOneTagsView(tags: searchTags)
    }
}

// MARK: - Files:

private extension FileEditingOneView {
    private func files(_ section: NT_DesignToolSection) -> some View {
        filesContent(forSection: section)
    }
    
    private func files(_ folder: NT_DesignToolFolder) -> some View {
        filesContent(forFolder: folder)
    }
    
    private func files(_ tag: NT_DesignToolTag) -> some View {
        filesContent(forTag: tag)
    }
    
    private func filesContent(
        forSection section: NT_DesignToolSection? = nil,
        forFolder folder: NT_DesignToolFolder? = nil,
        forTag tag: NT_DesignToolTag? = nil
    ) -> some View {
        FileEditingOneFilesView(
            section: section,
            folder: folder,
            tag: tag
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingOneView()
}
