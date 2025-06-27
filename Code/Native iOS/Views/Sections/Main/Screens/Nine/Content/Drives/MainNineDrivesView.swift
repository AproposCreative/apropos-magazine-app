//
//  MainNineDrivesView.swift
//  Native
//

import SwiftUI

struct MainNineDrivesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the drives to display:
    let drives: [NT_Drive]
    
    init(drives: [NT_Drive]) {
        
        /// Properties initialization:
        self.drives = drives
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

private extension MainNineDrivesView {
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
        SectionHeaderView(title: "My Drives")
        drivesContent
    }
}

// MARK: - Drives:

private extension MainNineDrivesView {
    private var drivesContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            drivesItem
        }
    }
    
    private var drivesItem: some View {
        ForEach(
            drives,
            content: drive
        )
    }
    
    private func drive(_ drive: NT_Drive) -> some View {
        NavigationLink(value: drive) {
            folderLabel(drive)
        }
    }
    
    private func folderLabel(_ drive: NT_Drive) -> some View {
        IconBackgroundTitleValueSubtitleProgressIconView(
            icon: Icons.externaldrive,
            iconBackgroundColor: color(drive),
            iconBackgroundGradientStart: gradientStart(drive),
            iconBackgroundGradientEnd: gradientEnd(drive),
            title: title(drive),
            value: capacityString(drive),
            subtitle: filesCount(drive),
            progressValue: usedCapacityValue(drive),
            progressTotal: capacityValue(drive),
            isShowingProgressValueTitle: true,
            progressValueTitle: usedCapacityString(drive),
            progressColor: color(drive),
            secondIconFrame: secondIconFrame
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainNineDrivesView(drives: NT_Drive.example)
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
    .navigationDestination(for: NT_Drive.self) { drive in
        PlaceholderView(title: drive.title)
    }
    .navigationStack()
}
