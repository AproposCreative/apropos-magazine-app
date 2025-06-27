//
//  MainThreeView.swift
//  Native
//

import SwiftUI

struct MainThreeView: View {
    
    // MARK: - Properties:
    
    /// An array of the messages to display:
    @State var messages: [NT_Message] = []
    
    /// An array of the groups with the messages to display:
    @State var groups: [NT_MessagesGroup] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the messages and the groups with the messages by that is inputed by the user:
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
            .localizedNavigationTitle(title: "Messages")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbarButton(
                title: "New Message",
                icon: Icons.plusCircle,
                font: .body,
                style: .iconOnly,
                placement: .cancellationAction,
                action: newMessage
            )
            .toolbarAvatar(indicatorBorderColor: .init(.systemGroupedBackground))
            .navigationDestination(
                for: NT_Message.self,
                destination: message
            )
            .navigationDestination(
                for: NT_MessagesGroup.self,
                destination: group
            )
            .animation(
                .default,
                value: searchMessages
            )
            .animation(
                .default,
                value: searchGroups
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

private extension MainThreeView {
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

private extension MainThreeView {
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
        MainThreeRecentView(messages: searchMessages)
        MainThreeMyGroupsView(groups: searchGroups)
    }
}

// MARK: - Message and group:

private extension MainThreeView {
    private func message(_ message: NT_Message) -> some View {
        PlaceholderView(title: content(message))
    }
    
    private func group(_ group: NT_MessagesGroup) -> some View {
        PlaceholderView(title: title(group))
    }
}

// MARK: - Preview:

#Preview {
    MainThreeView()
}
