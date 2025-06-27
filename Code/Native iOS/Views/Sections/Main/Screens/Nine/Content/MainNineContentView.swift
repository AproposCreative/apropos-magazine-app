//
//  MainNineContentView.swift
//  Native
//

import SwiftUI

struct MainNineContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the folders to display:
    @State var folders: [NT_Folder] = []
    
    /// An array of the drives to display:
    @State var drives: [NT_Drive] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the folders and the drives by that is inputed by the user:
    @State var searchText: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Folders")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbar {
                settingsToolbar
            }
            .toolbarButton(
                title: "New Folder",
                icon: Icons.plusCircle,
                font: toolbarFont,
                style: toolbarStyle,
                action: newFolder
            )
            .navigationDestination(
                for: NT_Folder.self,
                destination: folder
            )
            .navigationDestination(
                for: NT_Drive.self,
                destination: drive
            )
            .animation(
                .default,
                value: searchFolders
            )
            .animation(
                .default,
                value: searchDrives
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

// MARK: - Scroll:

private extension MainNineContentView {
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
        if isFetching {
            loading
        } else if isEmpty {
            nothingHere
        } else {
            foldersDrives
        }
    }
}

// MARK: - Empty states:

private extension MainNineContentView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
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
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - Folders and drives:

private extension MainNineContentView {
    private var foldersDrives: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            foldersDrivesContent
        }
    }
    
    @ViewBuilder
    private var foldersDrivesContent: some View {
        MainNineFoldersView(folders: searchFolders)
        MainNineDrivesView(drives: searchDrives)
    }
}

// MARK: - Settings toolbar:

private extension MainNineContentView {
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
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
    
    private var settingsMenuLabel: some View {
        LabelView(
            icon: Icons.ellipsisCircle,
            iconSymbolVariant: .none,
            iconSize: settingsIconSize,
            title: "Settings",
            style: .iconOnly
        )
    }
    
    @ViewBuilder
    private var settingsMenuContent: some View {
        editButton
        filterButton
        settingsButton
    }
}

// MARK: - Buttons:

private extension MainNineContentView {
    private var editButton: some View {
        ButtonView(
            title: "Edit",
            titleFont: buttonFont,
            icon: Icons.pencil,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: edit
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
    
    private var settingsButton: some View {
        ButtonView(
            title: "Settings",
            titleFont: buttonFont,
            icon: Icons.gearshape,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: showSettings
        )
    }
}

// MARK: - Folder and drive:

private extension MainNineContentView {
    private func folder(_ folder: NT_Folder) -> some View {
        PlaceholderView(title: title(folder))
    }
    
    private func drive(_ drive: NT_Drive) -> some View {
        PlaceholderView(title: title(drive))
    }
}

// MARK: - Preview:

#Preview {
    MainNineContentView()
}
