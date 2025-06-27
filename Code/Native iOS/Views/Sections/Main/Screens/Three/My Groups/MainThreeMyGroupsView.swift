//
//  MainThreeMyGroupsView.swift
//  Native
//

import SwiftUI

struct MainThreeMyGroupsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the groups with the messages to display:
    let groups: [NT_MessagesGroup]
    
    init(groups: [NT_MessagesGroup]) {
        
        /// Properties initialization:
        self.groups = groups
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

private extension MainThreeMyGroupsView {
    private var item: some View {
        Section("My Groups") {
            groupsContent
        }
    }
}

// MARK: - Groups:

private extension MainThreeMyGroupsView {
    private var groupsContent: some View {
        ForEach(
            groups,
            content: group
        )
    }
    
    private func group(_ group: NT_MessagesGroup) -> some View {
        NavigationLink(value: group) {
            groupLabel(group)
        }
    }
    
    private func groupLabel(_ group: NT_MessagesGroup) -> some View {
        AvatarTitleValueSubtitleView(
            avatarType: .icon,
            avatarIcon: icon(group),
            avatarColor: color(group),
            avatarGradientStart: gradientStart(group),
            avatarGradientEnd: gradientEnd(group),
            isShowingAvatarIndicator: isRead(group),
            avatarIndicatorBorderColor: avatarIndicatorBorderColor,
            avatarIndicatorAccessibilityLabel: avatarIndicatorAccessibilityLabel(group),
            title: title(group),
            titleLineLimit: titleLineLimit,
            value: latestMessageTimeIntervalSinceSent(group),
            subtitle: latestMessageContent(group),
            subtitleLineLimit: subtitleLineLimit,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainThreeMyGroupsView(groups: NT_MessagesGroup.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Messages")
    .navigationDestination(for: NT_Message.self) { message in
        PlaceholderView(title: message.content)
    }
    .navigationStack()
}
